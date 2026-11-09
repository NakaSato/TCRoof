// `npm test` in functions/. The Monitoring poll (CHA-93) against a fake Growatt.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  bangkokDayText, bangkokMonthStart, GrowattClient, GrowattFailure, growattURL, health, joinEnergy, pairings, parseSettings,
  plantTime, stationDoc, zoneOffsetMinutes,
} from './growatt';
import { archiveStation, checkTokenRequest, detailDue, detailMinutes, due, isManager, pickDetail, pollStation, Previous, Reader, readFleet } from './monitoring';

const SERVER = '0B9D3C2E-1F4A-4E57-9C1D-2A3B4C5D6E7F';
const OTHER = '1B9D3C2E-1F4A-4E57-9C1D-2A3B4C5D6E7F';
const ok = (data: unknown) => JSON.stringify({ error_code: 0, error_msg: '', data });
// 14:00 in Bangkok, 9 Nov 2026
const NOW = new Date('2026-11-09T07:00:00Z');

test('the settings are read as the app writes them, with its defaults', () => {
  const s = parseSettings(JSON.stringify({
    servers: [{ id: SERVER.toLowerCase(), name: 'a', url: 'https://openapi.growatt.com/v1/', tokenSuffix: '3f2a' }, { id: OTHER, url: 'https://x.growatt.com/v1/' }],
    pollMinutes: 3, pairings: { A: '101', B: ' 202 ', C: 'abc', D: '303' }, pairingServers: { D: OTHER.toLowerCase() },
  }));
  assert.ok(s);
  assert.equal(s.pollMinutes, 5);
  assert.equal(s.archiveNightly, true);
  assert.equal(s.loggerOfflineMinutes, 30);
  const p = pairings(s);
  assert.deepEqual(p.map((x) => [x.stationID, x.plantID, x.server.id]), [['A', 101, SERVER], ['B', 202, SERVER], ['D', 303, OTHER]]);
  assert.equal(parseSettings('not json'), null);
  assert.deepEqual(pairings(parseSettings('{"pairings":{"A":"1"}}')!), [], 'no server, nothing to read');
});

test('a token goes to Growatt over https only', () => {
  assert.equal(growattURL('https://openapi.growatt.com/v1')?.toString(), 'https://openapi.growatt.com/v1/');
  assert.ok(growattURL('https://test.growatt.com/v1/'));
  assert.equal(growattURL('http://openapi.growatt.com/v1/'), null);
  assert.equal(growattURL('https://growatt.com.evil.io/v1/'), null);
  assert.equal(growattURL('nonsense'), null);
  assert.equal(stationDoc('a/b'), 'a_b');
});

test('days and zones are the app\'s', () => {
  assert.equal(bangkokDayText(NOW), '2026-11-09');
  assert.equal(bangkokDayText(new Date('2026-11-09T17:30:00Z')), '2026-11-10', 'after midnight in Bangkok');
  assert.equal(bangkokDayText(NOW, 29), '2026-10-11');
  assert.equal(bangkokMonthStart(NOW, 11), '2025-12-01');
  assert.equal(zoneOffsetMinutes('GMT+7'), 420);
  assert.equal(zoneOffsetMinutes('UTC+07:00'), 420);
  assert.equal(zoneOffsetMinutes('GMT-3'), -180);
  assert.equal(zoneOffsetMinutes(''), 480);
  assert.equal(plantTime('2026-11-09 13:55:00', 420)?.toISOString(), '2026-11-09T06:55:00.000Z');
  assert.equal(plantTime('2026-11-09 13:55', 420)?.toISOString(), '2026-11-09T06:55:00.000Z');
  assert.equal(plantTime('2026-13-09 13:55', 420), null);
});

test('health: offline past the logger threshold, else in alarm on a faulted or lost inverter', () => {
  const data = (t: string) => ({ last_update_time: t, timezone: 'GMT+7', current_power: '12.5' });
  const devices = (...rows: object[]) => ({ devices: rows });
  assert.equal(health(data('2026-11-09 13:55:00'), devices({ device_sn: 'a', type: 1, status: 1 }), NOW, 30).health, 'normal');
  assert.equal(health(data('2026-11-09 13:00:00'), null, NOW, 30).health, 'offline');
  assert.equal(health({}, null, NOW, 30).health, 'offline', 'never reported');
  const h = health(data('2026-11-09 13:55:00'), devices(
    { device_sn: 'a', type: 1, status: 3 }, { device_sn: 'b', type: 1, status: '-1' }, { device_sn: 'c', lost: 'true' },
    { device_sn: 'meter', type: 3, status: 3 }), NOW, 30);
  assert.deepEqual([h.health, h.faults], ['alarm', 3]);
});

test('the client only GETs, sends the token and waits out 10012', async () => {
  const seen: { url: string; headers: Record<string, string> }[] = [];
  const answers = [JSON.stringify({ error_code: 10012, error_msg: 'error_frequently_access' }), ok({ today_energy: 1 })];
  const waits: number[] = [];
  const c = new GrowattClient(new URL('https://openapi.growatt.com/v1/'), 'tok', async (url, init) => {
    seen.push({ url, headers: init.headers });
    return { ok: true, status: 200, text: async () => answers.shift()! };
  }, async (ms) => { waits.push(ms); });
  assert.equal(JSON.parse(await c.data(42)).data.today_energy, 1);
  assert.equal(seen[0].url, 'https://openapi.growatt.com/v1/plant/data?plant_id=42');
  assert.equal(seen[0].headers.token, 'tok');
  assert.deepEqual(waits, [6000]);

  const refused = new GrowattClient(new URL('https://openapi.growatt.com/v1/'), 'bad', async () =>
    ({ ok: true, status: 200, text: async () => JSON.stringify({ error_code: 10011, error_msg: 'error_permission_denied' }) }));
  await assert.rejects(refused.data(1), (e: GrowattFailure) => e.code === '10011' && e.message.includes('token'));
});

/** A Growatt that answers every call for plant 7, counting them; `fail` names calls that fail. */
function fakeGrowatt(fail: Set<string> = new Set()) {
  const calls: string[] = [];
  const answer = (name: string, data: unknown) => {
    calls.push(name);
    if (fail.has(name.split(' ')[0])) return Promise.reject(new GrowattFailure('10011', 'Growatt ไม่อนุญาต (token ไม่ถูกต้อง)'));
    return Promise.resolve(ok(data));
  };
  const api: Reader = {
    data: () => answer('data', { last_update_time: '2026-11-09 13:55:00', timezone: 'GMT+7', current_power: 10, today_energy: 300 }),
    power: (_, date) => answer(`power ${date}`, { powers: [{ time: `${date} 13:55`, power: 10_000 }] }),
    devices: () => answer('devices', { devices: [{ device_sn: 'INV1', type: 1, status: 1 }] }),
    energy: (_, start, end, unit) => answer(`energy ${unit} ${start} ${end}`, { energys: [{ date: start, energy: 100 }] }),
    plants: (page) => answer(`plants ${page}`, { plants: [{ plant_id: 7, current_power: '10' }] }),
  };
  return { api, calls };
}

const PAIR = { stationID: 'S1', plantID: 7, server: { id: SERVER, url: 'https://openapi.growatt.com/v1/' } };

test('a station is read once a poll, and its history once a Bangkok day', async () => {
  const g = fakeGrowatt();
  const first = await pollStation(g.api, PAIR, undefined, NOW, 30);
  assert.deepEqual(g.calls, ['data', 'power 2026-11-09', 'devices', 'power 2026-11-08',
    'energy day 2026-10-11 2026-10-17', 'energy day 2026-10-18 2026-10-24', 'energy day 2026-10-25 2026-10-31',
    'energy day 2026-11-01 2026-11-07', 'energy day 2026-11-08 2026-11-08', 'energy month 2025-12-01 2026-11-09']);
  const f = first.fields;
  assert.equal(f.historyDay, '2026-11-09');
  assert.equal(f.health, 'normal');
  assert.equal(f.failure, null);
  assert.equal(f.readAt, NOW);
  assert.equal(JSON.parse(f.days as string).data.energys.length, 5, 'the day chunks joined');
  assert.equal(first.replace, false);

  const g2 = fakeGrowatt();
  const later = new Date(NOW.getTime() + 5 * 60_000);
  const second = await pollStation(g2.api, PAIR, { plantID: 7, attemptedAt: NOW, historyDay: '2026-11-09' }, later, 30);
  assert.deepEqual(g2.calls, ['data', 'power 2026-11-09', 'devices']);
  assert.equal(second.fields.days, undefined, 'the history kept from before');
});

test('a failed read keeps the last figures and says why', async () => {
  const g = fakeGrowatt(new Set(['data']));
  const r = await pollStation(g.api, PAIR, { plantID: 7, attemptedAt: NOW, historyDay: '2026-11-09' }, NOW, 30);
  assert.deepEqual(g.calls, ['data'], 'nothing else is tried');
  assert.equal(r.fields.readAt, undefined);
  assert.equal(r.fields.data, undefined);
  assert.deepEqual(r.fields.failure, { code: '10011', message: 'Growatt ไม่อนุญาต (token ไม่ถูกต้อง)' });

  const devicesDown = await pollStation(fakeGrowatt(new Set(['devices'])).api, PAIR, { plantID: 7, attemptedAt: NOW, historyDay: '2026-11-09' }, NOW, 30);
  assert.equal(devicesDown.fields.devices, undefined);
  assert.ok(devicesDown.fields.data);
  assert.equal((devicesDown.fields.failure as { code: string }).code, '10011');

  const historyDown = await pollStation(fakeGrowatt(new Set(['energy'])).api, PAIR, undefined, NOW, 30);
  assert.equal(historyDown.fields.historyDay, undefined, 'tried again at the next poll');
});

test('a station paired with another plant starts over', async () => {
  const r = await pollStation(fakeGrowatt().api, PAIR, { plantID: 6, attemptedAt: NOW, historyDay: '2026-11-09' }, NOW, 30);
  assert.equal(r.replace, true);
  assert.equal(r.fields.historyDay, '2026-11-09', 'its history read again');
});

test('a station is due a poll after pollMinutes, never sooner', () => {
  const at = (min: number) => new Date(NOW.getTime() + min * 60_000);
  assert.equal(due(undefined, 7, NOW, 5), true);
  assert.equal(due({ plantID: 7, attemptedAt: NOW }, 7, at(2), 5), false);
  assert.equal(due({ plantID: 7, attemptedAt: NOW }, 7, at(4), 5), true, 'a minute of slack for the schedule');
  assert.equal(due({ plantID: 7, attemptedAt: NOW }, 7, at(4), 10), false);
  assert.equal(due({ plantID: 6, attemptedAt: NOW }, 7, at(1), 5), true, 'paired again');
});

test('the archive keeps each missing day of the last week, oldest first', async () => {
  const g = fakeGrowatt();
  const days = await archiveStation(g.api, PAIR, new Set(['2026-11-08', '2026-11-05']), NOW);
  assert.deepEqual(days.map((d) => d.date), ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-06', '2026-11-07']);
  assert.ok(g.calls.every((c) => c.startsWith('power ')));
  const refused = await archiveStation(fakeGrowatt(new Set(['power'])).api, PAIR, new Set(), NOW);
  assert.deepEqual(refused, []);
});

test('joined energy reads as one answer', () => {
  const j = JSON.parse(joinEnergy([ok({ energys: [{ date: 'a' }] }), ok({ energys: [{ date: 'b' }] })]));
  assert.deepEqual(j, { error_code: 0, error_msg: '', data: { energys: [{ date: 'a' }, { date: 'b' }] } });
});

test('a token request names a server and a token without spaces; only managers send one', () => {
  assert.deepEqual(checkTokenRequest({ serverID: SERVER.toLowerCase(), token: ' abc ' }), { serverID: SERVER, token: 'abc' });
  assert.deepEqual(checkTokenRequest({ serverID: SERVER, token: '' }), { serverID: SERVER, token: '' });
  assert.ok('message' in checkTokenRequest({ serverID: '../x', token: 'a' }));
  assert.ok('message' in checkTokenRequest({ serverID: SERVER, token: 'a b' }));
  assert.ok('message' in checkTokenRequest({ serverID: SERVER }));
  assert.equal(isManager({ role: 'manager' }), true);
  assert.equal(isManager({ role: 'maintainer' }), true);
  assert.equal(isManager({ role: 'manager', suspended: true }), false);
  assert.equal(isManager({}), false);
  assert.equal(isManager(undefined), false);
});

// MARK: the fleet and the detail's schedule

test('a healthy station\'s detail every 15 minutes, never past half the logger threshold nor under pollMinutes', () => {
  assert.equal(detailMinutes({ pollMinutes: 5, loggerOfflineMinutes: 30 }), 15);
  assert.equal(detailMinutes({ pollMinutes: 5, loggerOfflineMinutes: 20 }), 10);
  assert.equal(detailMinutes({ pollMinutes: 5, loggerOfflineMinutes: 5 }), 5);
  assert.equal(detailMinutes({ pollMinutes: 30, loggerOfflineMinutes: 60 }), 30);
  assert.equal(detailMinutes({ pollMinutes: 10, loggerOfflineMinutes: 120 }), 15);
});

test('a troubled station is read every run, a healthy one every detailMinutes', () => {
  const s = { pollMinutes: 5, loggerOfflineMinutes: 30 };
  const at = (min: number) => new Date(NOW.getTime() - min * 60_000);
  assert.equal(detailDue({ plantID: 7, attemptedAt: at(5), health: 'normal' }, 7, NOW, s), false);
  assert.equal(detailDue({ plantID: 7, attemptedAt: at(15), health: 'normal' }, 7, NOW, s), true);
  assert.equal(detailDue({ plantID: 7, attemptedAt: at(5), health: 'alarm' }, 7, NOW, s), true);
  assert.equal(detailDue({ plantID: 7, attemptedAt: at(5), health: 'offline' }, 7, NOW, s), true);
  assert.equal(detailDue(undefined, 7, NOW, s), true, 'never read');
  assert.equal(detailDue({ plantID: 6, attemptedAt: at(1), health: 'normal' }, 7, NOW, s), true, 're-paired');
});

test('the detail reads spread over the runs: troubled ones first, then the oldest, a third of the fleet a run', () => {
  const s = { pollMinutes: 5, loggerOfflineMinutes: 30 };
  const st = (id: string, min: number, health = 'normal') => ({ id, previous: { plantID: 1, attemptedAt: new Date(NOW.getTime() - min * 60_000), health } });
  const fleet = [st('a', 20), st('b', 40), st('c', 30), st('d', 25), st('e', 15), st('f', 50), st('x', 5, 'alarm')];
  const picked = pickDetail(fleet, 9, s).map((e) => e.id);
  assert.deepEqual(picked, ['x', 'f', 'b', 'c'], '9 stations: 3 healthy a run, oldest first, plus the troubled');
  assert.equal(pickDetail(fleet.slice(0, 1), 1, s).length, 1, 'at least one a run');
  // the first run after deploy: none read yet, a third of them
  const fresh = Array.from({ length: 43 }, (_, i) => ({ id: String(i), previous: undefined as Previous }));
  assert.equal(pickDetail(fresh, 43, s).length, 15);
});

test('the fleet\'s power comes from plant/list, page after page until every plant is seen', async () => {
  const pages: string[] = [];
  const rows = (from: number, n: number) => Array.from({ length: n }, (_, i) => ({ plant_id: from + i, current_power: String((from + i) / 10) }));
  const answers = [ok({ count: 150, plants: rows(1, 100) }), ok({ count: 150, plants: [...rows(101, 48), { plant_id: 149, current_power: '-1' }, { plant_id: 150 }] })];
  const api = { plants: (page: number) => { pages.push(String(page)); return Promise.resolve(answers[page - 1]); } } as unknown as Reader;
  const power = await readFleet(api, new Set([3, 120, 149, 150]));
  assert.deepEqual(pages, ['1', '2']);
  assert.equal(power.get(3), 0.3);
  assert.equal(power.get(120), 12);
  assert.equal(power.get(149), -1, 'never reported, as Growatt says');
  assert.equal(power.get(150), null, 'no power given');

  const once: string[] = [];
  const one = { plants: (page: number) => { once.push(String(page)); return Promise.resolve(answers[0]); } } as unknown as Reader;
  await readFleet(one, new Set([3]));
  assert.deepEqual(once, ['1'], 'every wanted plant on the first page: no second call');

  const down = { plants: () => Promise.reject(new GrowattFailure('10011', 'x')) } as unknown as Reader;
  assert.equal((await readFleet(down, new Set([1]))).size, 0, 'a refused list reads nothing');
});
