// node --test tools/master-plan-sheet
// fixtures/plans.json is the app's own output: P3-001's imported plan and an in-app ≥ 200 kVA plan, encoded by Swift's
// JSONEncoder as the app stores them, with the points, % and finish days the app works out (`Actual.done`, `Input.weight`).
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('./Core.js');
const plans = require('./fixtures/plans.json');

test('progress matches the app on its own encoded plans', () => {
  for (const [name, p] of Object.entries(plans)) {
    const got = core.progress(p.scheduleInput, p.scheduleActual);
    assert.ok(got, name);
    assert.equal(got.pct, p.pct, `${name} %`);
    for (const t of core.TASKS) assert.equal(got.points[t.code], p.points[t.code], `${name} ${t.code}`);
  }
});

test('finish days: install when every 2.x is done, IEC 3.1, COD 1.7', () => {
  const app = plans['app-plan'];
  const got = core.progress(app.scheduleInput, app.scheduleActual);
  // the last 2.x to finish is 2.9, on 20 Oct (Bangkok midnight)
  assert.equal(got.finInstall.toISOString(), app.finished.monitoring.replace('Z', '.000Z'));
  assert.equal(got.finCOD, null, '1.7 has 0.5 of 1 point: not finished');
  assert.equal(got.finIEC, null);
  const p3 = core.progress(plans['P3-001'].scheduleInput, plans['P3-001'].scheduleActual);
  assert.equal(p3.finInstall.toISOString(), plans['P3-001'].finished.monitoring.replace('Z', '.000Z'));
  assert.equal(p3.finIEC.toISOString(), plans['P3-001'].finished.preCommissioning.replace('Z', '.000Z'));
  assert.equal(p3.finCOD, null, 'P3-001 has 1.7 done without its day: none shown');
});

test('a plan of standard weights sums to 100 both ways', () => {
  for (const over of [false, true]) {
    const sum = core.TASKS.reduce((s, t) => s + core.taskWeight({ over200kVA: over }, t), 0);
    assert.equal(sum, 100);
  }
  assert.equal(core.progress(null, null), null);
  assert.equal(core.progress('not json', '{}'), null);
});

test('Swift dates are seconds since 2001, the records\' are milliseconds since 1970', () => {
  assert.equal(core.swiftDate(0).toISOString(), '2001-01-01T00:00:00.000Z');
  assert.equal(core.millisDate(1761498000000).toISOString(), '2025-10-26T17:00:00.000Z');
  assert.equal(core.millisDate(0), null);
  assert.equal(core.swiftDate(null), null);
});

test('Firestore REST values decode', () => {
  const docs = core.fsDocuments([
    { document: { name: 'projects/p/databases/(default)/documents/jobs/J1', updateTime: '2026-10-27T05:00:00Z',
                  fields: { projectName: { stringValue: 'สถานี' }, capacityKW: { doubleValue: 163.02 },
                            mpNumber: { integerValue: '37' }, externals: { arrayValue: { values: [{ stringValue: 'a@x' }] } },
                            gone: { nullValue: null } } } },
    { readTime: '2026-10-27T05:00:01Z' }
  ]);
  assert.equal(docs.length, 1);
  assert.deepEqual({ ...docs[0], updated: docs[0].updated.toISOString() },
    { id: 'J1', updated: '2026-10-27T05:00:00.000Z', projectName: 'สถานี', capacityKW: 163.02, mpNumber: 37, externals: ['a@x'], gone: null });
});

test('rows find their jobs: override, code, name, name + kWp; never one job for two rows', () => {
  const job = (id, name, kWp, code, kind = 'pwa') =>
    core.jobSummary({ id, projectName: name, capacityKW: kWp, kind, stationDocs: code ? JSON.stringify({ code }) : undefined });
  const jobs = [
    job('A', 'สถานีผลิตน้ำบ้านนา', 88.92, 'P3-005'),
    job('B', 'สถานีผลิต-จ่ายน้ำ สำนักงานขลุง', 101.46),
    job('C1', 'สถานีผลิตน้ำศูนย์ราชการ', 136.8),
    job('C2', 'สถานีผลิตน้ำศูนย์ราชการ', 400.14),
    job('D', 'สถานีผลิตน้ำนายาง', 164.16),
    job('H', 'สถานีผลิตน้ำนายาง', 0, null, 'home'),
    job('E', 'โรงกรองน้ำหนองคาย', 150.48),
    job('X', 'สถานีจ่ายน้ำบ้านแหลม', 291.27)
  ];
  const rows = [
    { code: 'P3-005', name: 'ชื่ออื่น', kWp: 88.92 },
    { code: 'P4-017', name: 'สถานีผลิต-จ่ายน้ำ สำนักงานขลุง', kWp: 101.46 },
    { code: 'P4-001', name: 'สถานีผลิตน้ำศูนย์ราชการ', kWp: 136.8 },
    { code: 'P4-031', name: 'สถานีผลิตน้ำศูนย์ราชการ', kWp: 400.14 },
    { code: 'P4-044', name: 'สถานีผลิตน้ำนายาง', kWp: 164.16 },
    { code: 'P3-030', name: 'โรงกรองน้ำหนองคาย', kWp: 150.48 },
    { code: 'P9-999', name: 'โรงกรองน้ำหนองคาย', kWp: 150.48 },
    { code: 'P4-043', name: 'อื่น', kWp: 1, override: 'X' },
    { code: 'P4-055', name: 'ไม่มี', kWp: 1 },
    { code: 'P4-052', name: 'ไม่มี', kWp: 1, override: 'nope' }
  ];
  const got = core.matchRows(rows, jobs).map(m => [m.job && m.job.id, m.how]);
  assert.deepEqual(got, [
    ['A', 'รหัส'],
    ['B', 'ชื่อ'],
    ['C1', 'ชื่อ + kWp'],
    ['C2', 'ชื่อ + kWp'],
    ['D', 'ชื่อ'],
    [null, 'งานเดียวกันหลายแถว: ใส่รหัสงานเอง'],
    [null, 'งานเดียวกันหลายแถว: ใส่รหัสงานเอง'],
    ['X', 'กำหนดเอง'],
    [null, 'ไม่พบงานในแอป'],
    [null, 'ไม่พบงาน nope']
  ]);
});

test('daily reports per job and the TCRoof row', () => {
  const stats = core.logStats([
    { jobID: 'J', date: 1761498000000, engineerSignedAt: 1761500000000, updated: new Date('2026-10-26T10:00:00Z') },
    { jobID: 'J', date: 1761584400000, updated: new Date('2026-10-27T10:00:00Z') },
    { jobID: null, date: 1 }
  ]);
  assert.equal(stats.J.count, 2);
  assert.equal(stats.J.signed, 1);
  assert.equal(stats.J.last.toISOString(), '2025-10-27T17:00:00.000Z');

  const p = plans['P3-001'];
  const job = core.jobSummary({ id: 'J', projectName: 'สถานี', capacityKW: 163.02, kind: 'pwa', iecState: 'sent',
                                scheduleInput: p.scheduleInput, scheduleActual: p.scheduleActual, updated: new Date('2026-10-25T00:00:00Z') });
  const row = core.tabRow({ job, how: 'รหัส' }, stats);
  assert.equal(row.job, 'J');
  assert.equal(row.pct, 97.5);
  assert.equal(row['t2.1'], 20);
  assert.equal(row.iec_state, 'ส่งผลแล้ว รอปิด');
  assert.equal(row.logs, 2);
  assert.equal(row.log_signed, 1);
  assert.equal(row.updated.toISOString(), '2026-10-27T10:00:00.000Z', 'a later daily report is the latest edit');

  const none = core.tabRow({ job: core.jobSummary({ id: 'K', projectName: 'x' }), how: 'ชื่อ' }, {});
  assert.equal(none.how, 'ชื่อ (ยังไม่มีแผน MP)');
  assert.equal(none.pct, '');
  assert.equal(none.logs, 0);
  const missing = core.tabRow({ job: null, how: 'ไม่พบงานในแอป' }, {});
  assert.equal(missing.job, '');
  assert.equal(missing.how, 'ไม่พบงานในแอป');
});

test('the phase summary', () => {
  const d = (s) => new Date(s);
  const s = core.phaseSummary([
    { id: 'P3-001', kwp: 100, pct: 0.5, tc_pct: 40, ms_done: 3, ms_tot: 7, cod_delay: 5, p_cod: d('2027-01-10') },
    { id: 'P3-002', kwp: 300, pct: 0.1, tc_pct: 20, ms_done: 1, ms_tot: 7, cod_delay: -2, p_cod: d('2027-02-01') },
    { id: '', kwp: 999 }
  ], d('2027-01-25'), [
    { id: 'R1', level: 'สูง', warn: '⚠', status: 'เปิด' },
    { id: 'R2', level: 'สูง', warn: '', status: 'ปิด' },
    { id: 'R3', level: 'กลาง', warn: '⚠', status: 'เฝ้าระวัง' }
  ], [{ st: 'P3-001', stat: 'รออนุมัติ' }, { st: 'P3-002', stat: 'อนุมัติ' }, { st: '', stat: 'รออนุมัติ' }]);
  assert.equal(s.cod_phase.toISOString(), d('2027-02-01').toISOString());
  assert.equal(s.cod_move, 7);
  assert.equal(s.pct_kwp, 0.2);
  assert.equal(s.tc_pct_kwp, 25);
  assert.deepEqual([s.ms_done, s.ms_tot, s.late, s.risk_high, s.kri_warn, s.cr_pending], [4, 14, 1, 1, 2, 1]);
});

test('the app jobs no row took, PWA first', () => {
  const j = (id, name, kind, code) => core.jobSummary({ id, projectName: name, kind, capacityKW: 10,
                                                       stationDocs: code ? JSON.stringify({ code }) : undefined });
  const jobs = [j('H', 'บ้านคุณ ก', 'home'), j('B', 'ข สถานี', 'pwa'), j('T', 'ก สถานี', 'pwa', 'P3-001'), j('A', 'ทดสอบ', 'pwa')];
  const list = core.unmatchedJobs(jobs, [{ job: jobs[3], how: 'ชื่อ' }, { job: null, how: 'ไม่พบงานในแอป' }], { B: { count: 3 } });
  assert.deepEqual(list.map(r => r[0]), ['T', 'B', 'H']);
  assert.deepEqual(list[1], ['B', 'ข สถานี', 'งาน PWA', 10, '', '', 3]);
  assert.equal(list[0][4], 'P3-001');
  assert.equal(list[2][2], 'งานบ้าน');
});

test('a new station job is the app\'s job document, and only unmatched station rows make one', () => {
  const now = new Date('2026-10-27T06:00:00Z');
  const f = core.newJobFields({ code: ' P3-005 ', name: 'สถานีผลิตน้ำบ้านนา', kWp: 88.92, branch: 'บ้านนา' }, now);
  // every non-optional field of Job.Record, in the type the app decodes
  assert.deepEqual(Object.keys(f).sort(), ['capacityKW', 'code', 'createdAt', 'customerName', 'installDays', 'installStart', 'kind',
    'projectName', 'province', 'status', 'surveyDate', 'team']);
  assert.deepEqual(f.code, { stringValue: 'P3-005' });
  assert.deepEqual(f.customerName, { stringValue: 'กปภ.สาขาบ้านนา' });
  assert.deepEqual(f.capacityKW, { doubleValue: 88.92 });
  assert.deepEqual(f.createdAt, { integerValue: String(now.getTime()) });
  assert.deepEqual(f.installStart, { integerValue: '0' });
  assert.deepEqual([f.team, f.status, f.kind], [{ stringValue: 'TCR01' }, { stringValue: 'confirmed' }, { stringValue: 'pwa' }]);
  assert.equal(core.newJobFields({ code: 'P3-001', name: 'x', kWp: 1, branch: 'กปภ.สาขาชัยบาดาล' }, now).customerName.stringValue, 'กปภ.สาขาชัยบาดาล');
  assert.equal(core.newJobFields({ code: 'P3-001', name: 'x', kWp: '' }, now).customerName.stringValue, 'x');
  // the job is found by its code on the next pull
  const job = core.jobSummary({ id: 'N', projectName: 'สถานีผลิตน้ำบ้านนา', code: 'P3-005', kind: 'pwa' });
  assert.deepEqual(core.matchRows([{ code: 'P3-005', name: 'อื่น' }], [job]).map(m => m.how), ['รหัส']);

  const rows = [{ code: 'P3-005', name: 'ก' }, { code: 'P3-006', name: 'ข', override: 'X' }, { code: 'P3-007', name: 'ค' },
                { code: '', name: 'ว่าง' }, { code: 'P3-008', name: 'ง' }];
  const matches = [{ job: null, how: 'ไม่พบงานในแอป' }, { job: null, how: 'ไม่พบงาน X' }, { job: job, how: 'ชื่อ' },
                   { job: null, how: 'ไม่พบงานในแอป' }, { job: null, how: 'ชื่อซ้ำ 2 งาน: ใส่รหัสงานเอง' }];
  assert.deepEqual(core.rowsToCreate(rows, matches).map(r => r.code), ['P3-005']);
});

test('the _app tab lists every job, its plan, reports and the row it pairs with', () => {
  const p = plans['P3-001'];
  const a = core.jobSummary({ id: 'A', projectName: 'สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล', kind: 'pwa', status: 'confirmed', code: 'TCR2569-12345',
                              capacityKW: 163.02, stationDocs: JSON.stringify({ code: 'P3-001' }), iecState: 'open',
                              scheduleInput: p.scheduleInput, scheduleActual: p.scheduleActual, updated: new Date('2026-10-27T01:00:00Z') });
  const h = core.jobSummary({ id: 'H', projectName: 'Google', kind: 'home', status: 'interested', code: 'TCR2569-1', capacityKW: 15 });
  const rows = [{ code: 'P3-001', name: 'x' }];
  const matches = core.matchRows(rows, [a, h]);
  const out = core.appTabRows([h, a], matches, rows, { A: { count: 2, signed: 1, last: new Date('2026-10-26T17:00:00Z'), updated: null } });
  assert.equal(out.length, 2);
  assert.equal(out[0].length, core.APP_TAB_HEADER.length);
  assert.deepEqual(out[0].slice(0, 12), ['A', 'สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล', 'งาน PWA', 'ลูกค้ายืนยันติดตั้ง', 'TCR2569-12345', 'P3-001',
                                         163.02, 'มี', 97.5, 'กำลังทดสอบ', 2, 1]);
  assert.equal(out[0][14], 'P3-001', 'paired with the P3-001 row');
  assert.deepEqual(out[1].slice(0, 9), ['H', 'Google', 'งานบ้าน', 'ลูกค้าสนใจติดตั้ง', 'TCR2569-1', '', 15, '', '']);
  assert.equal(out[1][14], '');
});

// MARK: the WBS tab (CHA-71)

const wbsItems = [
  { code: '2.1', title: 'ติดตั้งโครงสร้าง', weight: 20, level: 1 },
  { code: '2.1.1', title: '    ยึดขาจับ', weight: 8, level: 2 },
  { code: '2.1.2', title: '    ติดตั้ง Rail', weight: 12, level: 2 },
  { code: '2.1.2.1', title: 'ฐานราก', weight: 4.8, level: 3 },
  { code: '2.1.2.2', title: 'โครงเหล็ก', weight: 7.2, level: 3 },
  { code: '2.1.3', title: '    ทางเดิน (ไม่เกี่ยวกับสถานีนี้)', weight: 0, level: 2 },
  { code: '0.1.1', title: '    แผนบริหารโครงการ', weight: 0, level: 2 }
];
const day7 = core.bangkokDayToSwift('2026-12-07');

test('Bangkok days and Swift dates', () => {
  // Bangkok midnight of 7 Dec 2026 is 6 Dec 17:00 UTC
  assert.equal(new Date((core.SWIFT_EPOCH + day7) * 1000).toISOString(), '2026-12-06T17:00:00.000Z');
  assert.equal(core.swiftToBangkokDay(day7), '2026-12-07');
  assert.equal(core.swiftToBangkokDay(day7 + 23 * 3600), '2026-12-07');
  assert.equal(core.sheetDay(new Date('2026-12-06T17:00:00Z')), '2026-12-07', 'a sheet Date at Bangkok midnight');
  assert.equal(core.sheetDay('7/12/2569'), '2026-12-07', 'a Buddhist year');
  assert.equal(core.sheetDay('2026-12-07'), '2026-12-07');
  assert.equal(core.sheetDay(''), '');
  assert.equal(core.sheetDay('พรุ่งนี้'), null);
  assert.equal(core.sheetDay('31/2/2026'), null);
  assert.ok(core.isY('y') && core.isY(true) && core.isY(' Y ') && !core.isY('') && !core.isY('N'));
});

test('the tab lists the rows the app ticks, with each tick and its source', () => {
  assert.deepEqual(core.wbsTickable(wbsItems).map((i) => i.code), ['2.1.1', '2.1.2.1', '2.1.2.2', '0.1.1']);
  const ticks = { '2.1.1': { by: 'con@vendor.test', at: day7 }, '2.1.2.1': { by: 'pm@tcroof.test', at: day7, source: 'daily' } };
  const job = { id: 'J1', name: 'สถานี A', codes: ['P3-001'], kind: 'pwa',
                doc: { scheduleWBS: JSON.stringify(wbsItems), wbsTicks: JSON.stringify(ticks), externals: ['con@vendor.test'] } };
  const home = { id: 'H1', name: 'บ้าน', codes: [], kind: 'home', doc: { scheduleWBS: JSON.stringify(wbsItems) } };
  const rows = core.wbsTabRows([{ code: 'P3-001' }, { code: 'P3-002' }, { code: 'X' }], [{ job }, { job }, { job: home }]);
  assert.equal(rows.length, 4, 'one job listed once, a home job not at all');
  assert.deepEqual(rows[0], ['P3-001', 'J1', '2.1.1', 'ยึดขาจับ', 8, 'Y', '2026-12-07', 'ผู้รับเหมาติ๊ก', 'con@vendor.test', '']);
  assert.equal(rows[1][7], 'รายงานประจำวัน');
  assert.deepEqual(rows[2].slice(5, 9), ['', '', '', '']);
  assert.equal(core.WBS_TAB_HEADER.length, rows[0].length);
  // what the snapshot keeps reads back as the tab does
  assert.deepEqual(core.wbsCells(core.wbsSnapshotRows(rows), false).J1['2.1.1'], { y: true, day: '2026-12-07', editor: '' });
  assert.deepEqual(core.wbsCells(rows, true).J1['2.1.1'], { y: true, day: '2026-12-07', editor: '' });
  // `แก้โดย` is an email from the edit trigger, or the pull's own note of a refusal, which names no one
  const noted = rows.map((r) => r.slice());
  noted[0][9] = 'ไม่รับ: ผู้แก้ไม่ใช่ทีมงาน'; noted[1][9] = 'bee@tcroof.test';
  const cells = core.wbsCells(noted, true);
  assert.equal(cells.J1['2.1.1'].editor, '');
  assert.equal(cells.J1['2.1.2.1'].editor, 'bee@tcroof.test');
});

test('a tick at a credit step under 100 shows its percent, not Y, and a Y over it is refused (CHA-84)', () => {
  assert.equal(core.wbsMark(undefined), '');
  assert.equal(core.wbsMark({ by: 'a', at: day7 }), 'Y');
  assert.equal(core.wbsMark({ by: 'a', at: day7, percent: 50 }), '50%');
  const ticks = { '2.1.1': { by: 'eng@tcroof.test', at: day7, source: 'team', percent: 50 } };
  const job = { id: 'J1', name: 'สถานี A', codes: ['P3-001'], kind: 'pwa',
                doc: { scheduleWBS: JSON.stringify(wbsItems), wbsTicks: JSON.stringify(ticks) } };
  const rows = core.wbsTabRows([{ code: 'P3-001' }], [{ job }]);
  assert.equal(rows[0][5], '50%');
  const snap = core.wbsCells(core.wbsSnapshotRows(rows), false);
  assert.equal(snap.J1['2.1.1'].y, false);
  const cur = JSON.parse(JSON.stringify(snap));
  cur.J1['2.1.1'] = { y: true, day: '2026-12-09', editor: 'bee@tcroof.test' };
  const r = core.wbsSheetChanges(snap, cur, { J1: ticks }, 'a@tcroof.test', (e) => e.endsWith('@tcroof.test'), '2026-12-10');
  assert.deepEqual(r.writes, []);
  assert.deepEqual(r.refusals.map((x) => x.code), ['2.1.1']);
});

test('a Y typed on the tab becomes a sheet tick; only a sheet tick is cleared from the sheet', () => {
  const team = (e) => e.endsWith('@tcroof.test');
  const app = { J1: { '2.1.1': { by: 'eng@tcroof.test', at: day7, source: 'team' },
                      '2.1.2.1': { by: 'pm@tcroof.test', at: day7, source: 'sheet' } } };
  const snap = { J1: { '2.1.1': { y: true, day: '2026-12-07' }, '2.1.2.1': { y: true, day: '2026-12-07' },
                       '2.1.2.2': { y: false, day: '' }, '0.1.1': { y: false, day: '' } } };
  const cur = { J1: { '2.1.1': { y: false, day: '' }, '2.1.2.1': { y: false, day: '' },
                      '2.1.2.2': { y: true, day: '', editor: '' }, '0.1.1': { y: true, day: '2026-12-09', editor: 'Bee@tcroof.test' } } };
  const r = core.wbsSheetChanges(snap, cur, app, 'owner@tcroof.test', team, '2026-12-10');
  assert.equal(r.writes.length, 1);
  const w = r.writes[0];
  assert.equal(w.jobId, 'J1');
  assert.deepEqual(Object.keys(JSON.parse(w.json)), ['0.1.1', '2.1.1', '2.1.2.2'], 'sorted, as the app writes them');
  assert.deepEqual(w.ticks['2.1.1'], app.J1['2.1.1'], "the team's tick stays");
  assert.equal(w.ticks['2.1.2.1'], undefined, "the sheet's own tick goes");
  assert.deepEqual(w.ticks['2.1.2.2'], { by: 'owner@tcroof.test', at: core.bangkokDayToSwift('2026-12-10'), source: 'sheet' });
  assert.deepEqual(w.ticks['0.1.1'], { by: 'bee@tcroof.test', at: core.bangkokDayToSwift('2026-12-09'), source: 'sheet' },
                   'in the name of who typed it, on its date');
  assert.deepEqual(r.refusals.map((x) => x.code), ['2.1.1']);
  assert.equal(app.J1['2.1.2.1'].source, 'sheet', 'the input is left as it was');
});

test('nothing typed, a Y the app has, a stranger or a bad date writes nothing', () => {
  const team = (e) => e.endsWith('@tcroof.test');
  const app = { J1: { '2.1.1': { by: 'eng@tcroof.test', at: day7, source: 'daily' } } };
  const snap = { J1: { '2.1.1': { y: false, day: '' }, '2.1.2.1': { y: false, day: '' }, '0.1.1': { y: false, day: '' } } };
  assert.deepEqual(core.wbsSheetChanges(snap, snap, app, 'a@tcroof.test', team, '2026-12-10'), { writes: [], refusals: [] });
  const cur = { J1: { '2.1.1': { y: true, day: '' }, '2.1.2.1': { y: true, day: '', editor: 'x@gmail.com' }, '0.1.1': { y: true, day: null } },
                J2: { '2.1.1': { y: true, day: '' } } };
  const r = core.wbsSheetChanges(snap, cur, app, 'a@tcroof.test', team, '2026-12-10');
  assert.deepEqual(r.writes, [], 'J2 was not listed at the last pull');
  assert.deepEqual(r.refusals.map((x) => x.code).sort(), ['0.1.1', '2.1.2.1']);
  // the sheet's tick moved to another day
  const sheetApp = { J1: { '2.1.2.1': { by: 'a@tcroof.test', at: day7, source: 'sheet' } } };
  const moved = core.wbsSheetChanges({ J1: { '2.1.2.1': { y: true, day: '2026-12-07' } } },
                                     { J1: { '2.1.2.1': { y: true, day: '2026-12-08' } } }, sheetApp, 'a@tcroof.test', team, '2026-12-10');
  assert.equal(moved.writes[0].ticks['2.1.2.1'].at, core.bangkokDayToSwift('2026-12-08'));
});

// CHA-81: the risk register copied into config/risks for the app
test('risk scope: a contractor, the พค.2 stations, else every station', () => {
  const stations = [
    { id: 'P3-001', contractor: 'S', pk2_required: 'Y' },
    { id: 'P3-002', contractor: 'c', pk2_required: '' },
    { id: '', contractor: 'S' }
  ];
  assert.deepEqual(core.riskStations('ผรม. S', stations), ['P3-001']);
  assert.deepEqual(core.riskStations('ผรม. C', stations), ['P3-002']);
  assert.deepEqual(core.riskStations('สถานี > 200 kVA', stations), ['P3-001']);
  for (const all of ['ทั้งเฟส', 'ทุก ผรม.', 'รายเขต', 'รายสถานี', 'รายวิศวกร', '', null]) {
    assert.equal(core.riskStations(all, stations), null, String(all));
  }
});

test('risk register JSON: the rows with an id, their jobs, numbers or null', () => {
  const rows = [
    { id: 'R03', risk: 'ผรม. S กำลังติดตั้งไม่พอ', cat: 'ผรม.', scope: 'ผรม. S', kri: 'สถานีที่ COD ช้า', kri_v: 12, kri_t: 10,
      warn: '⚠', p: 4, i: 5, score: 20, level: 'สูง', days: 30, res: 21, resp: 'ย้ายสถานี', owner: 'PM', status: 'เปิด',
      rev: new Date(2026, 10, 1) },
    { id: 'R06', risk: 'ฝน', scope: 'ทั้งเฟส', kri: '—', kri_v: '', kri_t: '', warn: '', p: 3, i: 2, score: 6, level: 'ต่ำ', status: '' },
    { id: '', risk: 'empty row' }
  ];
  const stations = [{ id: 'P3-001', contractor: 'S' }, { id: 'P3-009', contractor: 'S' }, { id: 'P3-002', contractor: 'C' }];
  const json = core.riskRegister(rows, stations, { 'P3-001': 'job-1', 'P3-002': 'job-2' }, () => '2026-11-01');
  const got = JSON.parse(json).risks;
  assert.equal(got.length, 2);
  assert.deepEqual(got[0].jobs, ['job-1'], 'P3-009 has no app job');
  assert.equal(got[0].warn, true);
  assert.equal(got[0].score, 20);
  assert.equal(got[0].reviewed, '2026-11-01');
  assert.equal(got[1].jobs, undefined, 'every station');
  assert.equal(got[1].kriValue, null);
  assert.equal(got[1].status, 'เปิด', 'a blank status is open');
  assert.equal(json, core.riskRegister(rows, stations, { 'P3-001': 'job-1', 'P3-002': 'job-2' }, () => '2026-11-01'),
               'the same sheet gives the same text, so an unchanged register is not written again');
});

// CHA-82: the stakeholder list copied into config/stakeholders for the app
test('stakeholder list JSON: the rows with an id, their jobs, a day typed as a number', () => {
  const rows = [
    { id: 'S01', name: 'ผอ.กองแผนงาน', org: 'กปภ. เขต 5', reports: 'R3', channel: 'อีเมล', freq: 'รายสัปดาห์', due: 'ศุกร์',
      owner: 'PM', scope: 'ทั้งเฟส' },
    { id: 'S02', name: 'ผรม. S', freq: 'รายเดือน', due: 25, scope: 'ผรม. S' },
    { id: '', name: 'empty row' }
  ];
  const stations = [{ id: 'P3-001', contractor: 'S' }, { id: 'P3-009', contractor: 'S' }, { id: 'P3-002', contractor: 'C' }];
  const json = core.stakeholderList(rows, stations, { 'P3-001': 'job-1', 'P3-002': 'job-2' });
  const got = JSON.parse(json).stakeholders;
  assert.equal(got.length, 2);
  assert.equal(got[0].organisation, 'กปภ. เขต 5');
  assert.equal(got[0].frequency, 'รายสัปดาห์');
  assert.equal(got[0].jobs, undefined, 'every station');
  assert.deepEqual(got[1].jobs, ['job-1'], 'P3-009 has no app job');
  assert.equal(got[1].due, '25');
  assert.equal(got[1].note, '');
  assert.equal(json, core.stakeholderList(rows, stations, { 'P3-001': 'job-1', 'P3-002': 'job-2' }),
               'the same sheet gives the same text, so an unchanged list is not written again');
});

test('stakeholder tab: a _keys row per column, the examples as wide as the header', () => {
  const keys = core.stakeholderKeyRows();
  assert.equal(keys.length, core.STAKEHOLDER_COLUMNS.length);
  assert.deepEqual(keys[0], ['ผู้มีส่วนได้ส่วนเสีย', 'id', 'A', 4, '']);
  assert.deepEqual(keys[keys.length - 1].slice(1, 3), ['note', 'M']);
  for (const row of core.STAKEHOLDER_TAB.examples) assert.equal(row.length, core.STAKEHOLDER_COLUMNS.length);
  // the example rows read back through the same keys give stakeholders the app reads
  const read = core.STAKEHOLDER_TAB.examples.map((r) => Object.fromEntries(core.STAKEHOLDER_COLUMNS.map((c, i) => [c[0], r[i]])));
  const got = JSON.parse(core.stakeholderList(read, [], {})).stakeholders;
  assert.deepEqual(got.map((s) => [s.id, s.frequency, s.due]), [['S01', 'รายสัปดาห์', 'ศุกร์'], ['S02', 'ก่อนส่งมอบ', '3']]);
});
