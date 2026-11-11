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

/**
 * The app's jobs no row took, for the list beside the tab (so their ids can go in a row's yellow cell): PWA jobs first,
 * then by name. Each as [id, name, kind, kWp, station code, has a plan, daily reports].
 */
function unmatchedJobs(jobs, matches, stats) {
  var taken = {};
  matches.forEach(function (m) { if (m.job) taken[m.job.id] = true; });
  return jobs.filter(function (j) { return !taken[j.id]; })
    .sort(function (a, b) { return (a.kind === 'pwa' ? 0 : 1) - (b.kind === 'pwa' ? 0 : 1) || a.name.localeCompare(b.name); })
    .map(function (j) {
      var s = (stats || {})[j.id];
      return [j.id, j.name, j.kind === 'pwa' ? 'งาน PWA' : j.kind === 'home' ? 'งานบ้าน' : j.kind, j.kWp || '',
              j.codes.join(', '), j.doc && j.doc.scheduleInput ? 'มี' : '', s ? s.count : 0];
    });
}

/** Every app job as one row of the `_app` tab, the header first: PWA jobs first, then by name. */
var APP_TAB_HEADER = ['id', 'ชื่องานในแอป', 'ประเภท', 'สถานะ', 'รหัสงาน', 'รหัสสถานี', 'kWp', 'แผน MP', '% MP',
                      'IEC', 'รายงานประจำวัน', 'ลงนามแล้ว', 'รายงานล่าสุด', 'แก้ล่าสุด', 'แถวในชีต'];

function appTabRows(jobs, matches, rows, stats) {
  var rowOf = {};
  matches.forEach(function (m, i) { if (m.job) rowOf[m.job.id] = String(rows[i].code || '').trim(); });
  var status = { interested: 'ลูกค้าสนใจติดตั้ง', confirmed: 'ลูกค้ายืนยันติดตั้ง', installing: 'กำลังติดตั้ง', completed: 'ติดตั้งเสร็จ' };
  return jobs.slice()
    .sort(function (a, b) { return (a.kind === 'pwa' ? 0 : 1) - (b.kind === 'pwa' ? 0 : 1) || a.name.localeCompare(b.name); })
    .map(function (j) {
      var d = j.doc || {}, s = (stats || {})[j.id];
      var p = progress(d.scheduleInput, d.scheduleActual);
      var station = (parseJSON(d.stationDocs) || {}).code || '';
      var updated = d.updated;
      if (s && s.updated && (!updated || s.updated > updated)) updated = s.updated;
      return [j.id, j.name, j.kind === 'pwa' ? 'งาน PWA' : j.kind === 'home' ? 'งานบ้าน' : (j.kind || ''),
              status[d.status] || d.status || '', d.code || '', station, j.kWp || '', p ? 'มี' : '', p ? p.pct : '',
              iecLabel(d.iecState), s ? s.count : 0, s ? s.signed : 0, s && s.last ? s.last : '', updated || '',
              rowOf[j.id] || ''];
    });
}

/**
 * A new PWA job for a station row, as the app's job document (`Job.Record`, TCRoof/Sync/CloudRecords.swift): the
 * station's code as the job's code (so the sheet and `MPTemplates.best` find it by code), its name, `กปภ.สาขา<branch>`
 * as the customer, its kWp, no dates yet (1970, `Job.unscheduled`), `ลูกค้ายืนยันติดตั้ง`, team TCR01. Firestore REST
 * fields; the app fills the rest the first time a team device saves it.
 */
function newJobFields(row, now) {
  var branch = String(row.branch || '').trim();
  if (branch && !/^(กปภ|การประปา)/.test(branch)) branch = 'กปภ.สาขา' + branch;
  var name = String(row.name || '').trim();
  var str = function (v) { return { stringValue: String(v) }; };
  var int = function (v) { return { integerValue: String(Math.round(v)) }; };
  return {
    code: str(String(row.code || '').trim()),
    projectName: str(name),
    customerName: str(branch || name),
    province: str(''),
    capacityKW: { doubleValue: Number(row.kWp) || 0 },
    team: str('TCR01'),
    status: str('confirmed'),
    surveyDate: int(0),
    installStart: int(0),
    createdAt: int(now.getTime()),
    installDays: int(1),
    kind: str('pwa')
  };
}

/** The rows to create jobs for: a station code and name, nothing in the yellow cell, and no job of the app's found. */
function rowsToCreate(rows, matches) {
  return rows.filter(function (r, i) {
    return /^P\d+-\d+$/.test(String(r.code || '').trim()) && String(r.name || '').trim() && !String(r.override || '').trim()
      && !matches[i].job && matches[i].how === 'ไม่พบงานในแอป';
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

// MARK: the risk register (CHA-81): `ทะเบียนความเสี่ยง` copied into `config/risks` for the app, read only

/**
 * The station codes a risk's `ขอบเขต` touches, from the Master Plan rows (`id`, `contractor`, `pk2_required`); null
 * for every station. `ผรม. S` is contractor S's stations, `สถานี > 200 kVA` the ones that need พค.2; `ทั้งเฟส`,
 * `ทุก ผรม.`, `รายเขต`, `รายสถานี`, `รายวิศวกร` and anything else touch every station.
 */
function riskStations(scope, stations) {
  var text = String(scope === null || scope === undefined ? '' : scope).trim();
  var ids = function (keep) {
    return (stations || []).filter(function (s) { return String(s.id || '').trim() && keep(s); })
      .map(function (s) { return String(s.id).trim(); });
  };
  if (/200\s*kVA/i.test(text)) return ids(function (s) { return isY(s.pk2_required); });
  var m = /^ผรม\.?\s*(\S+)$/.exec(text);
  if (m && m[1] !== 'ทุก') {
    var who = m[1].toUpperCase();
    return ids(function (s) { return String(s.contractor || '').trim().toUpperCase() === who; });
  }
  return null;
}

/**
 * `config/risks`' JSON: every row of `ทะเบียนความเสี่ยง` with an id, in the sheet's order, its stations as app job
 * ids (`jobByCode`: station code → Firestore job id; a station not paired with a job is left out). The app's
 * `RiskRegister.decode` reads it. `bangkokDay` formats a date cell (the sheet passes Utilities.formatDate).
 */
function riskRegister(rows, stations, jobByCode, bangkokDay) {
  var num = function (v) { return typeof v === 'number' && isFinite(v) ? v : null; };
  var str = function (v) { return v === null || v === undefined ? '' : String(v).trim(); };
  var risks = (rows || []).filter(function (r) { return str(r.id); }).map(function (r) {
    var codes = riskStations(r.scope, stations);
    var jobs = codes === null ? null : codes.map(function (c) { return jobByCode[c]; }).filter(Boolean)
      .filter(function (j, i, a) { return a.indexOf(j) === i; });
    var out = {
      id: str(r.id), title: str(r.risk), category: str(r.cat), cause: str(r.cause), scope: str(r.scope), wbs: str(r.wbs),
      kri: str(r.kri), kriValue: num(r.kri_v), kriThreshold: num(r.kri_t), warn: str(r.warn) === '⚠',
      probability: num(r.p), impact: num(r.i), score: num(r.score), level: str(r.level),
      impactDays: num(r.days), reserveDays: num(r.res), strategy: str(r.strat), response: str(r.resp), owner: str(r.owner),
      status: str(r.status) || 'เปิด',
      reviewed: r.rev instanceof Date && bangkokDay ? bangkokDay(r.rev) : (str(r.rev) || null)
    };
    if (jobs !== null) out.jobs = jobs;
    return out;
  });
  return JSON.stringify({ risks: risks });
}

// MARK: the WBS tab (CHA-71): the plans' sub-tasks, and a `Y` typed there written to the app as a `sheet` tick

/** Bangkok is UTC+7 all year. */
var BANGKOK_MS = 7 * 3600 * 1000;

/** Bangkok's day `yyyy-MM-dd` → a Swift date (seconds since 2001) at that day's Bangkok midnight, as the app's ticks. */
function bangkokDayToSwift(day) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day || ''));
  if (!m) return null;
  return (Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) - BANGKOK_MS) / 1000 - SWIFT_EPOCH;
}

/** A Swift date → its Bangkok day `yyyy-MM-dd`; '' for none. */
function swiftToBangkokDay(v) {
  var d = swiftDate(v);
  return d ? new Date(d.getTime() + BANGKOK_MS).toISOString().slice(0, 10) : '';
}

/**
 * A date cell as Bangkok's day `yyyy-MM-dd`: a Date (Apps Script gives one at the sheet's midnight; the sheet is in
 * Bangkok, README), `yyyy-MM-dd`, or `d/m/yyyy` (a Buddhist year, over 2400, taken back 543). '' for an empty cell,
 * null for text it can't read.
 */
function sheetDay(v) {
  if (v === null || v === undefined || v === '') return '';
  if (v instanceof Date) return isNaN(v.getTime()) ? null : new Date(v.getTime() + BANGKOK_MS).toISOString().slice(0, 10);
  var s = String(v).trim();
  if (!s) return '';
  var iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s), dmy = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/.exec(s);
  var y, mo, d;
  if (iso) { y = +iso[1]; mo = +iso[2]; d = +iso[3]; } else if (dmy) { d = +dmy[1]; mo = +dmy[2]; y = +dmy[3]; } else return null;
  if (y < 100) y += 2000;
  if (y > 2400) y -= 543;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  var t = new Date(Date.UTC(y, mo - 1, d));
  if (t.getUTCDate() !== d) return null;
  return t.toISOString().slice(0, 10);
}

/** A `เสร็จ (Y)` cell: Y (any case), ✓, TRUE or a ticked checkbox. */
function isY(v) {
  if (v === true) return true;
  var s = String(v === null || v === undefined ? '' : v).trim().toUpperCase();
  return s === 'Y' || s === '✓' || s === '✔' || s === 'TRUE';
}

/** The rows the app ticks (`parentCodes`, `notForThisStation`): no task's own line, no row with steps under it. */
function wbsTickable(items) {
  var codes = {};
  (items || []).forEach(function (i) { codes[i.code] = true; });
  var parents = {};
  (items || []).forEach(function (i) {
    var dot = String(i.code).lastIndexOf('.');
    if (dot > 0 && codes[i.code.slice(0, dot)]) parents[i.code.slice(0, dot)] = true;
  });
  return (items || []).filter(function (i) {
    var title = String(i.title || '');
    return i.code && !parents[i.code] && String(i.code).split('.').length !== 2
      && title.indexOf('(ไม่เกี่ยวกับสถานีนี้)') < 0 && title.indexOf('(ไม่ต้อง') < 0;
  });
}

var WBS_SOURCE_LABEL = { team: 'ทีมติ๊ก', daily: 'รายงานประจำวัน', sheet: 'Google Sheet', file: 'ไฟล์แผน' };

/** A tick's `ที่มา`, as the app's `WBSTick.origin`: its source, else (an older tick) a contractor's or the team's. */
function wbsSourceLabel(tick, externals) {
  if (!tick) return '';
  if (tick.source) return WBS_SOURCE_LABEL[tick.source] || tick.source;
  var by = String(tick.by || '').trim().toLowerCase();
  var con = (externals || []).some(function (e) { return String(e).trim().toLowerCase() === by; });
  return con ? 'ผู้รับเหมาติ๊ก' : 'ทีมติ๊ก';
}

/** The `WBS` tab's columns; `แก้โดย` is filled by the edit trigger (`onWBSEdit`) and read by the next pull. */
var WBS_TAB_HEADER = ['รหัสสถานี', 'งานในแอป (id)', 'WBS', 'งานย่อย', 'น้ำหนัก %', 'เสร็จ (Y)', 'วันที่เสร็จ', 'ที่มา', 'โดย', 'แก้โดย'];

/**
 * One row per tickable WBS row of each paired PWA job (`matchRows` of the station `rows`), in the stations' order:
 * [station code, job id, WBS code, title, weight, 'Y' or '', Bangkok day or '', source, by, '']. A job two rows take is
 * listed once.
 */
function wbsTabRows(rows, matches) {
  var out = [], seen = {};
  matches.forEach(function (m, i) {
    var j = m.job;
    if (!j || seen[j.id] || j.kind !== 'pwa') return;
    seen[j.id] = true;
    var d = j.doc || {};
    var items = parseJSON(d.scheduleWBS) || [], ticks = parseJSON(d.wbsTicks) || {};
    var station = String((rows[i] || {}).code || j.codes[0] || '').trim();
    wbsTickable(items).forEach(function (it) {
      var t = ticks[it.code];
      out.push([station, j.id, it.code, String(it.title || '').trim(), Number(it.weight) || 0, t ? 'Y' : '',
                t ? swiftToBangkokDay(t.at) : '', wbsSourceLabel(t, d.externals), t ? (t.by || '') : '', '']);
    });
  });
  return out;
}

/**
 * Tab rows (or `_wbs` rows: [job id, code, Y, day]) as { jobId: { code: { y, day, editor } } }. `tab` says which. The
 * tab's `แก้โดย` counts only as an email (the pull writes its refusals there too).
 */
function wbsCells(list, tab) {
  var out = {};
  (list || []).forEach(function (r) {
    var id = String((tab ? r[1] : r[0]) || '').trim(), code = String((tab ? r[2] : r[1]) || '').trim();
    if (!id || !code) return;
    var editor = tab ? String(r[9] || '').trim() : '';
    if (!/^[^\s@]+@[^\s@]+$/.test(editor)) editor = '';
    (out[id] = out[id] || {})[code] = { y: isY(tab ? r[5] : r[2]), day: sheetDay(tab ? r[6] : r[3]), editor: editor };
  });
  return out;
}

/** The `_wbs` snapshot of tab rows: [job id, code, 'Y' or '', day]. */
function wbsSnapshotRows(tabRows) {
  return tabRows.map(function (r) { return [r[1], r[2], r[5], r[6]]; });
}

/** Ticks as the app writes them (`sortedKeys`): codes in order. */
function wbsTicksJSON(ticks) {
  var o = {};
  Object.keys(ticks).sort().forEach(function (k) { o[k] = ticks[k]; });
  return JSON.stringify(o);
}

/**
 * What was typed on the `WBS` tab since the last pull, as writes to the jobs' `wbsTicks`. `snapshot` and `current` are
 * `wbsCells` (of `_wbs` and of the tab); `appTicks` { jobId: ticks } as Firestore has them now; `editor` the email to
 * write them under (a cell's own `แก้โดย` wins); `isTeam(email)` whether that account is one of the team (members, not
 * external); `today` Bangkok's day for a `Y` without a date.
 * - `Y` added: a tick `{ by, at, source: 'sheet' }`, unless the app has one already.
 * - date changed on a `Y`: the sheet's own tick moves; the app's other ticks are refused (changed in the app only).
 * - `Y` cleared: only a `sheet` tick goes; any other is refused, and stays.
 * Returns { writes: [{ jobId, by, ticks, json }], refusals: [{ jobId, code, why }] }.
 */
function wbsSheetChanges(snapshot, current, appTicks, editor, isTeam, today) {
  var writes = [], refusals = [];
  Object.keys(current || {}).sort().forEach(function (jobId) {
    var before = (snapshot || {})[jobId];
    if (!before) return; // a job the tab didn't list at the last pull: nothing typed yet
    var ticks = JSON.parse(JSON.stringify((appTicks || {})[jobId] || {})), changed = false, by = null;
    Object.keys(current[jobId]).sort().forEach(function (code) {
      var s = before[code], c = current[jobId][code];
      if (!s || (s.y === c.y && s.day === c.day)) return;
      var who = String(c.editor || editor || '').trim().toLowerCase();
      var refuse = function (why) { refusals.push({ jobId: jobId, code: code, why: why }); };
      var t = ticks[code];
      var stranger = function () { return !who || !isTeam(who) ? (refuse('ผู้แก้ไม่ใช่ทีมงาน (' + (who || 'ไม่ทราบชื่อ') + ')'), true) : false; };
      if (c.y) {
        if (c.day === null) return refuse('อ่านวันที่ไม่ได้');
        var at = bangkokDayToSwift(c.day || today);
        if (at === null) return refuse('อ่านวันที่ไม่ได้');
        if (t && t.source !== 'sheet') { if (s.y) refuse('ติ๊กมาจาก' + wbsSourceLabel(t) + ' แก้วันในแอป'); return; }
        if (t && swiftToBangkokDay(t.at) === (c.day || today)) return;
        if (t && !s.y) return; // already ticked by the sheet
        if (stranger()) return;
        ticks[code] = { by: who, at: at, source: 'sheet' };
        changed = true; by = by || who;
      } else if (s.y && t) {
        if (t.source !== 'sheet') return refuse('ติ๊กมาจาก' + wbsSourceLabel(t) + ' เอาออกได้ในแอปเท่านั้น');
        if (stranger()) return;
        delete ticks[code];
        changed = true; by = by || who;
      }
    });
    if (changed) writes.push({ jobId: jobId, by: by, ticks: ticks, json: wbsTicksJSON(ticks) });
  });
  return { writes: writes, refusals: refusals };
}

if (typeof module !== 'undefined') {
  module.exports = { SWIFT_EPOCH: SWIFT_EPOCH, TASKS: TASKS, swiftDate: swiftDate, millisDate: millisDate, taskWeight: taskWeight,
                     progress: progress, fsDocuments: fsDocuments, fsValue: fsValue, normalizeName: normalizeName,
                     jobSummary: jobSummary, matchRows: matchRows, unmatchedJobs: unmatchedJobs, appTabRows: appTabRows, APP_TAB_HEADER: APP_TAB_HEADER, newJobFields: newJobFields, rowsToCreate: rowsToCreate, logStats: logStats, iecLabel: iecLabel, tabRow: tabRow,
                     phaseSummary: phaseSummary, bangkokDayToSwift: bangkokDayToSwift, swiftToBangkokDay: swiftToBangkokDay,
                     sheetDay: sheetDay, isY: isY, wbsTickable: wbsTickable, wbsSourceLabel: wbsSourceLabel,
                     WBS_TAB_HEADER: WBS_TAB_HEADER, wbsTabRows: wbsTabRows, wbsCells: wbsCells, wbsSnapshotRows: wbsSnapshotRows,
                     wbsTicksJSON: wbsTicksJSON, wbsSheetChanges: wbsSheetChanges,
                     riskStations: riskStations, riskRegister: riskRegister };
}
