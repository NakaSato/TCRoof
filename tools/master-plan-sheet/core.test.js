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
