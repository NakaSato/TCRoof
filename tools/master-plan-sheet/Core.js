/**
 * TCRoof › Master Plan sheet: the calculations, with no Apps Script or Google API in them, so they run in the sheet's
 * script and under Node's test runner alike (`node --test tools/master-plan-sheet`).
 *
 * What the app keeps in Firestore (TCRoof/Sync/CloudRecords.swift):
 * - `jobs/<id>`: `projectName`, `code`, `capacityKW`, `kind` (`pwa` / `home`), `stationDocs` (JSON of
 *   `StationDocs.Station`, whose optional `code` is the station's `P3-001`), `scheduleInput` / `scheduleActual` (JSON of
 *   `MasterSchedule.Input` / `Actual`), `iecState` (`open`, `sent`, `closed`).
 * - `installLogs/<id>`: one per daily report, `jobID`, `date` and `engineerSignedAt` in milliseconds since 1970.
 * The JSON is Swift's `JSONEncoder` default: a date is seconds since 1 January 2001 (UTC).
 */

/** Seconds from 1970 to 2001-01-01T00:00:00Z: Swift's `Date` reference. */
var SWIFT_EPOCH = 978307200;

/** The 18 MP tasks (`MasterSchedule.Task`): raw value, code, part and standard weight (`weight(over200kVA:)`). */
var TASKS = [
  { raw: 'kickoff', code: '1.1', w: [0.5, 0.5] },
  { raw: 'engineering', code: '1.2', w: [1, 1] },
  { raw: 'siteHandover', code: '1.3', w: [0.5, 0.5] },
  { raw: 'buildingPermit', code: '1.4', w: [1.5, 1] },
  { raw: 'pk2', code: '1.5', w: [0, 1] },
  { raw: 'cop', code: '1.6', w: [0, 0] },
  { raw: 'gridConnection', code: '1.7', w: [1.5, 1] },
  { raw: 'structure', code: '2.1', w: [20, 20] },
  { raw: 'dcSide', code: '2.2', w: [10, 10] },
  { raw: 'panels', code: '2.3', w: [20, 20] },
  { raw: 'fireSwitch', code: '2.4', w: [2.5, 2.5] },
  { raw: 'inverter', code: '2.5', w: [15, 15] },
  { raw: 'acSide', code: '2.6', w: [10, 10] },
  { raw: 'controlCabinet', code: '2.7', w: [5, 5] },
  { raw: 'zeroExport', code: '2.8', w: [5, 5] },
  { raw: 'monitoring', code: '2.9', w: [2.5, 2.5] },
  { raw: 'preCommissioning', code: '3.1', w: [2.5, 2.5] },
  { raw: 'training', code: '3.2', w: [2.5, 2.5] }
];

/** A Swift date (seconds since 2001) as a JS Date; null for none. */
function swiftDate(v) {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number') return new Date((SWIFT_EPOCH + v) * 1000);
  var d = new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

/** Milliseconds since 1970 (the records' own dates) as a JS Date; null for none or 0. */
function millisDate(v) {
  var n = Number(v);
  return v === null || v === undefined || !n ? null : new Date(n);
}

function parseJSON(s) {
  if (typeof s !== 'string' || !s) return null;
  try { return JSON.parse(s); } catch (e) { return null; }
}

/** A task's weight in the plan (`Input.weight`): the imported workbook's when it has one, else the standard one. */
function taskWeight(input, task) {
  if (input.fixed) {
    var f = input.fixed[task.raw];
    return f && typeof f.weight === 'number' ? f.weight : 0;
  }
  return task.w[input.over200kVA ? 1 : 0];
}

/**
 * The MP plan's progress as the sheet shows it: each task's points done (never past its weight), the % of the whole
 * plan, and the days the install (every 2.x task with a weight), IEC (3.1) and grid connection (1.7) finished.
 * Null when the job has no plan.
 */
function progress(inputJSON, actualJSON) {
  var input = typeof inputJSON === 'string' ? parseJSON(inputJSON) : inputJSON;
  if (!input) return null;
  var actual = (typeof actualJSON === 'string' ? parseJSON(actualJSON) : actualJSON) || {};
  var points = actual.points || {}, finished = actual.finished || {};
  var out = { points: {}, pct: 0, finInstall: null, finIEC: null, finCOD: null };
  var total = 0, done = 0, installDone = true, installLast = null, anyInstall = false;
  TASKS.forEach(function (t) {
    var w = taskWeight(input, t);
    var weeks = points[t.raw] || {};
    var sum = 0;
    Object.keys(weeks).forEach(function (k) { sum += Number(weeks[k]) || 0; });
    var d = Math.max(0, Math.min(sum, w));
    out.points[t.code] = round(d, 2);
    total += w; done += d;
    var complete = w > 0 && d >= w - 1e-6;
    var end = complete ? swiftDate(finished[t.raw]) : null;
    if (t.code.charAt(0) === '2' && w > 0) {
      anyInstall = true;
      if (!end) installDone = false;
      else if (!installLast || end > installLast) installLast = end;
    }
    if (t.code === '3.1') out.finIEC = end;
    if (t.code === '1.7') out.finCOD = end;
  });
  out.pct = total > 0 ? round(done / total * 100, 1) : 0;
  out.finInstall = anyInstall && installDone ? installLast : null;
  return out;
}

function round(v, n) {
  var k = Math.pow(10, n);
  return Math.round(v * k) / k;
}

/** One Firestore REST value as plain JS. */
function fsValue(v) {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fsValue);
  if ('mapValue' in v) return fsFields(v.mapValue.fields || {});
  return null;
}

function fsFields(fields) {
  var o = {};
  Object.keys(fields || {}).forEach(function (k) { o[k] = fsValue(fields[k]); });
  return o;
}

/** A `runQuery` response's documents as `{ id, updated, ...fields }`. */
function fsDocuments(response) {
  return (response || []).filter(function (r) { return r.document; }).map(function (r) {
    var d = fsFields(r.document.fields);
    d.id = r.document.name.split('/').pop();
    d.updated = r.document.updateTime ? new Date(r.document.updateTime) : null;
    return d;
  });
}

/** A station name as matched: no spaces, hyphens or zero-width marks, so `สถานีผลิต-จ่ายน้ำ` meets `สถานีผลิตจ่ายน้ำ`. */
function normalizeName(s) {
  return String(s || '').replace(/[\s​\-–_.]/g, '').toLowerCase();
}

/** A job as the matcher needs it, from its Firestore document. */
function jobSummary(doc) {
  var station = parseJSON(doc.stationDocs) || {};
  var codes = [station.code, doc.code].filter(function (c) { return typeof c === 'string' && /^P\d+-\d+$/.test(c.trim()); })
    .map(function (c) { return c.trim(); });
  return { id: doc.id, name: doc.projectName || '', codes: codes, kWp: Number(doc.capacityKW) || 0, kind: doc.kind || '', doc: doc };
}

/**
 * Each sheet row's job: the one its yellow cell names (`กำหนดเอง`), else the PWA job carrying its code (`รหัส`), else
 * the one job of the same name (`ชื่อ`), with two of the same name told apart by kWp within 5 % (`ชื่อ + kWp`). A job
 * two rows would take goes to neither, so a wrong pairing never shows as fact.
 * rows: [{ code, name, kWp, override }]; jobs: jobSummary[]. Returns [{ job, how }] in the rows' order.
 */
function matchRows(rows, jobs) {
  var byId = {}, byCode = {}, byName = {};
  jobs.forEach(function (j) {
    byId[j.id] = j;
    j.codes.forEach(function (c) { (byCode[c] = byCode[c] || []).push(j); });
    var n = normalizeName(j.name);
    if (n) (byName[n] = byName[n] || []).push(j);
  });
  function pwaFirst(list) {
    var pwa = list.filter(function (j) { return j.kind === 'pwa'; });
    return pwa.length ? pwa : list;
  }
  var picks = rows.map(function (r) {
    var o = String(r.override || '').trim();
    if (o) return byId[o] ? { job: byId[o], how: 'กำหนดเอง' } : { job: null, how: 'ไม่พบงาน ' + o };
    var c = pwaFirst(byCode[String(r.code || '').trim()] || []);
    if (c.length === 1) return { job: c[0], how: 'รหัส' };
    var n = pwaFirst(byName[normalizeName(r.name)] || []);
    if (n.length === 1) return { job: n[0], how: 'ชื่อ' };
    if (n.length > 1) {
      var k = Number(r.kWp) || 0;
      var near = n.filter(function (j) { return k > 0 && j.kWp > 0 && Math.abs(j.kWp - k) <= 0.05 * k; });
      if (near.length === 1) return { job: near[0], how: 'ชื่อ + kWp' };
      return { job: null, how: 'ชื่อซ้ำ ' + n.length + ' งาน: ใส่รหัสงานเอง' };
    }
    return { job: null, how: 'ไม่พบงานในแอป' };
  });
  // a job two rows took is no one's until someone says which
  var taken = {};
  picks.forEach(function (p) { if (p.job && p.how !== 'กำหนดเอง') taken[p.job.id] = (taken[p.job.id] || 0) + 1; });
  return picks.map(function (p) {
    if (p.job && p.how !== 'กำหนดเอง' && taken[p.job.id] > 1) return { job: null, how: 'งานเดียวกันหลายแถว: ใส่รหัสงานเอง' };
    return p;
  });
}

/** The daily reports per job: how many, the latest day, and how many the engineer signed. */
function logStats(logs) {
  var out = {};
  (logs || []).forEach(function (l) {
    if (!l.jobID) return;
    var s = out[l.jobID] = out[l.jobID] || { count: 0, last: null, signed: 0, updated: null };
    s.count += 1;
    var d = millisDate(l.date);
    if (d && (!s.last || d > s.last)) s.last = d;
    if (millisDate(l.engineerSignedAt)) s.signed += 1;
    if (l.updated && (!s.updated || l.updated > s.updated)) s.updated = l.updated;
  });
  return out;
}

/** The IEC test's hand-over state (`IECReport.LockState`) as the sheet reads it. */
function iecLabel(state) {
  return { open: 'กำลังทดสอบ', sent: 'ส่งผลแล้ว รอปิด', closed: 'ปิดการทดสอบแล้ว' }[state] || '';
}

/**
 * One row of the TCRoof tab, by its `_keys` names: what the script writes for a sheet row and its match.
 */
function tabRow(match, stats) {
  var j = match.job;
  var row = { job: '', jobname: '', how: match.how, updated: '', pct: '', fin_install: '', fin_iec: '', fin_cod: '',
              iec_state: '', logs: '', log_last: '', log_signed: '' };
  TASKS.forEach(function (t) { row['t' + t.code] = ''; });
  if (!j) return row;
  var d = j.doc, s = stats[j.id];
  row.job = j.id;
  row.jobname = j.name;
  var updated = d.updated;
  if (s && s.updated && (!updated || s.updated > updated)) updated = s.updated;
  row.updated = updated || '';
  var p = progress(d.scheduleInput, d.scheduleActual);
  if (p) {
    row.pct = p.pct;
    TASKS.forEach(function (t) { row['t' + t.code] = p.points[t.code]; });
    row.fin_install = p.finInstall || '';
    row.fin_iec = p.finIEC || '';
    row.fin_cod = p.finCOD || '';
  } else {
    row.how = match.how + ' (ยังไม่มีแผน MP)';
  }
  row.iec_state = iecLabel(d.iecState);
  row.logs = s ? s.count : 0;
  row.log_last = s && s.last ? s.last : '';
  row.log_signed = s ? s.signed : 0;
  return row;
}

/** The phase summary row of `ประวัติสรุป` from the Master Plan rows (`_keys` names) and the registers. */
function phaseSummary(stations, previousCOD, risks, changes) {
  var kw = 0, pct = 0, tc = 0, tcKw = 0, msDone = 0, msTot = 0, late = 0, cod = null;
  stations.forEach(function (s) {
    if (!s.id) return;
    var k = Number(s.kwp) || 0;
    if (typeof s.pct === 'number') { pct += s.pct * k; kw += k; }
    if (typeof s.tc_pct === 'number') { tc += s.tc_pct * k; tcKw += k; }
    msDone += Number(s.ms_done) || 0;
    msTot += Number(s.ms_tot) || 0;
    if (Number(s.cod_delay) > 0) late += 1;
    if (s.p_cod instanceof Date && (!cod || s.p_cod > cod)) cod = s.p_cod;
  });
  var move = cod && previousCOD instanceof Date ? Math.round((cod - previousCOD) / 86400000) : '';
  var open = function (r) { return r.status !== 'ปิด'; };
  return {
    cod_phase: cod || '',
    cod_move: move,
    // % งาน in the sheet is a fraction (0–1) or a percent, as its column has it: averaged as it comes
    pct_kwp: kw > 0 ? pct / kw : '',
    tc_pct_kwp: tcKw > 0 ? round(tc / tcKw, 1) : '',
    ms_done: msDone,
    ms_tot: msTot,
    late: late,
    risk_high: (risks || []).filter(function (r) { return r.level === 'สูง' && open(r); }).length,
    kri_warn: (risks || []).filter(function (r) { return r.warn === '⚠' && open(r); }).length,
    cr_pending: (changes || []).filter(function (c) { return c.st && (c.stat === 'รออนุมัติ' || c.stat === 'ขอข้อมูลเพิ่ม'); }).length
  };
}

if (typeof module !== 'undefined') {
  module.exports = { SWIFT_EPOCH: SWIFT_EPOCH, TASKS: TASKS, swiftDate: swiftDate, millisDate: millisDate, taskWeight: taskWeight,
                     progress: progress, fsDocuments: fsDocuments, fsValue: fsValue, normalizeName: normalizeName,
                     jobSummary: jobSummary, matchRows: matchRows, logStats: logStats, iecLabel: iecLabel, tabRow: tabRow,
                     phaseSummary: phaseSummary };
}
