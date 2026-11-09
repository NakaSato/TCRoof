// The Monitoring poll's steps (CHA-93), apart from Firestore and the schedule (index.ts), so monitoring.test.ts runs
// them against a fake Growatt. What one station's poll reads follows the app's `MonitoringFeed.read`: each poll
// `plant/data`, today's `plant/power` and `device/list`; once a Bangkok day yesterday's `plant/power` and
// `plant/energy` by day (30 days) and by month (12 months).
import { bangkokDayText, bangkokMonthStart, DAY_CHUNKS, failureMessage, GrowattFailure, health, joinEnergy, Pairing } from './growatt';

/** The calls a station's poll makes; `GrowattClient` in the function, a fake in the tests. */
export type Reader = {
  data(plantID: number): Promise<string>;
  power(plantID: number, date: string): Promise<string>;
  devices(plantID: number): Promise<string>;
  energy(plantID: number, start: string, end: string, unit: 'day' | 'month'): Promise<string>;
};

/** `monitoring/{station}` as the poll last left it (the fields it decides by). */
export type Previous = { plantID?: number; attemptedAt?: Date; historyDay?: string } | undefined;

/** Whether the station is due: never read, paired with another plant since, or last tried a poll ago or more. */
export function due(previous: Previous, plantID: number, now: Date, pollMinutes: number): boolean {
  if (!previous?.attemptedAt || previous.plantID !== plantID) return true;
  // a minute's slack, since the schedule's runs aren't exactly 5 minutes apart
  return now.getTime() - previous.attemptedAt.getTime() >= (pollMinutes - 1) * 60_000;
}

export type Poll = {
  /** Fields to merge into `monitoring/{station}`; a part whose call failed is left out, so the last one stays. */
  fields: Record<string, unknown>;
  /** True when the document is for another plant than before and is written whole. */
  replace: boolean;
};

/**
 * One station's read. The answers are kept as Growatt's text (`data`, `power`, …) for the app's own parsing; `readAt`
 * is when `plant/data` last came back, which the iPads judge freshness by. `health`, `faults` and `lastReading` say
 * whether the station is in trouble with every iPad closed.
 */
export async function pollStation(api: Reader, p: Pairing, previous: Previous, now: Date, offlineAfterMinutes: number): Promise<Poll> {
  const replace = previous?.plantID !== undefined && previous.plantID !== p.plantID;
  const fields: Record<string, unknown> = { stationID: p.stationID, plantID: p.plantID, serverID: p.server.id, attemptedAt: now };
  let failure: GrowattFailure | null = null;
  async function call(f: () => Promise<string>): Promise<string | null> {
    try { return await f(); } catch (e) {
      failure ??= e instanceof GrowattFailure ? e : new GrowattFailure('bad', failureMessage('bad'));
      return null;
    }
  }
  const data = await call(() => api.data(p.plantID));
  if (data === null) {
    // a token refused or Growatt unreachable: the other calls would fail the same way
    return { fields: { ...fields, failure: failureOf(failure) }, replace };
  }
  fields.data = data;
  fields.readAt = now;
  const power = await call(() => api.power(p.plantID, bangkokDayText(now)));
  if (power !== null) fields.power = power;
  const devices = await call(() => api.devices(p.plantID));
  if (devices !== null) fields.devices = devices;

  const today = bangkokDayText(now);
  if (replace || previous?.historyDay !== today) {
    const yesterday = await call(() => api.power(p.plantID, bangkokDayText(now, 1)));
    const chunks: string[] = [];
    for (const [from, to] of DAY_CHUNKS) {
      const t = await call(() => api.energy(p.plantID, bangkokDayText(now, from), bangkokDayText(now, to), 'day'));
      if (t === null) break;
      chunks.push(t);
    }
    const months = await call(() => api.energy(p.plantID, bangkokMonthStart(now, 11), today, 'month'));
    if (yesterday !== null) fields.yesterdayPower = yesterday;
    const days = chunks.length === DAY_CHUNKS.length ? joinEnergy(chunks) : null;
    if (days !== null) fields.days = days;
    if (months !== null) fields.months = months;
    // read whole: not again today; else the next poll tries again
    if (yesterday !== null && days !== null && months !== null) fields.historyDay = today;
  }

  const h = health(JSON.parse(data).data, devices === null ? null : JSON.parse(devices).data, now, offlineAfterMinutes);
  fields.health = h.health;
  fields.faults = h.faults;
  fields.lastReading = h.lastReading;
  fields.failure = failureOf(failure);
  return { fields, replace };
}

const failureOf = (f: GrowattFailure | null) => (f ? { code: f.code, message: f.message } : null);

/** Days the nightly archive keeps catching up on, so a night it missed is filled the next. */
export const ARCHIVE_DAYS = 7;

/**
 * `plant/power` of each of the last `ARCHIVE_DAYS` Bangkok days not archived yet (`have`), oldest first. Growatt keeps
 * the 5-minute readings about 95 days; these copies are kept for good. A day that fails is tried again the next night.
 */
export async function archiveStation(api: Reader, p: Pairing, have: Set<string>, now: Date): Promise<{ date: string; power: string }[]> {
  const out: { date: string; power: string }[] = [];
  for (let back = ARCHIVE_DAYS; back >= 1; back--) {
    const date = bangkokDayText(now, back);
    if (have.has(date)) continue;
    try { out.push({ date, power: await api.power(p.plantID, date) }); } catch (e) {
      // a token refused or Growatt unreachable: the other days would fail the same way
      if (e instanceof GrowattFailure && (e.code === '10011' || e.code === 'offline')) break;
    }
  }
  return out;
}

/** The archive's document id for a station's day. */
export const archiveDoc = (stationDocID: string, date: string) => `${stationDocID}_${date}`;

export type TokenRequest = { serverID: string; token: string };

/** `monitoringToken`'s request: a server id (a UUID, as the app writes it) and a token, or '' to remove it. */
export function checkTokenRequest(data: unknown): TokenRequest | { message: string } {
  const d = (typeof data === 'object' && data !== null ? data : {}) as Record<string, unknown>;
  const serverID = typeof d.serverID === 'string' ? d.serverID.trim().toUpperCase() : '';
  const token = typeof d.token === 'string' ? d.token.trim() : null;
  if (!/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/.test(serverID)) return { message: 'ไม่รู้จักบัญชีนี้' };
  if (token === null || token.length > 200 || /\s/.test(token)) return { message: 'Token ไม่ถูกต้อง' };
  return { serverID, token };
}

/** Only managers and the Maintainer set a token, as only they save ตั้งค่า Monitoring. */
export function isManager(member: { role?: unknown; suspended?: unknown } | undefined): boolean {
  return !!member && member.suspended !== true && (member.role === 'manager' || member.role === 'maintainer');
}
