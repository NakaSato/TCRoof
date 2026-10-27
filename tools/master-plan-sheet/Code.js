/**
 * TCRoof › Master Plan sheet (Master_Plan_ประปา_เฟส3-4_ลิงก์แผนรายโครงการ): the sheet's own script.
 *
 * - `TCRoof › ดึงข้อมูลตอนนี้` (and every 5 minutes): reads the app's jobs and daily reports from Firestore and writes
 *   the `TCRoof` tab's blue columns, which the Master Plan reads (`% MP ในแอป TCRoof`, `แก้ล่าสุดในแอป`). Read only: the
 *   sheet never writes to the app.
 * - `TCRoof › บันทึกประวัติตอนนี้` (and Mondays 08:00): adds this week's rows to `ประวัติรายสัปดาห์` and one to
 *   `ประวัติสรุป`.
 * Columns are found through the `_keys` sheet, so the tabs' layout can move. Set-up: README.md beside this file.
 * Calculations are in Core.js.
 */

var DEFAULT_PROJECT = 'tcroof-1564c';

function onOpen() {
  SpreadsheetApp.getUi().createMenu('TCRoof')
    .addItem('ดึงข้อมูลตอนนี้', 'pullFromApp')
    .addItem('บันทึกประวัติตอนนี้', 'snapshotNow')
    .addSeparator()
    .addItem('เปิดงานอัตโนมัติ (ดึงทุก 5 นาที, ประวัติวันจันทร์ 08:00)', 'installTriggers')
    .addItem('ปิดงานอัตโนมัติ', 'removeTriggers')
    .addItem('ตั้งค่าโปรเจกต์ Firebase…', 'setProject')
    .addToUi();
}

// MARK: pull from the app

function pullFromApp() {
  var lock = LockService.getDocumentLock();
  if (!lock.tryLock(1000)) return; // a run is still going
  var book = SpreadsheetApp.getActive();
  var tab = book.getSheetByName('TCRoof');
  try {
    var keys = sheetKeys(book, 'TCRoof');
    var first = keys.id.first, last = keys.id.last, n = last - first + 1;
    var read = function (k) { return tab.getRange(first, keys[k].col, n, 1).getValues().map(function (r) { return r[0]; }); };
    var ids = read('id'), names = read('name'), kwps = read('kwp'), overrides = read('override');
    var rows = ids.map(function (id, i) { return { code: id, name: names[i], kWp: kwps[i], override: overrides[i] }; });

    var jobs = firestoreQuery('jobs', ['projectName', 'code', 'capacityKW', 'kind', 'stationDocs', 'scheduleInput',
                                       'scheduleActual', 'iecState']).map(jobSummary);
    var logs = firestoreQuery('installLogs', ['jobID', 'date', 'engineerSignedAt'],
                              { unaryFilter: { field: { fieldPath: 'report' }, op: 'IS_NOT_NULL' } });
    var stats = logStats(logs);
    var matches = matchRows(rows, jobs);

    // the blue columns, written as one block; whatever lies between them (the yellow override) is kept as it is
    var written = ['job', 'jobname', 'how', 'updated', 'pct'].concat(TASKS.map(function (t) { return 't' + t.code; }))
      .concat(['fin_install', 'fin_iec', 'fin_cod', 'iec_state', 'logs', 'log_last', 'log_signed'])
      .filter(function (k) { return keys[k]; });
    var cols = written.map(function (k) { return keys[k].col; });
    var c0 = Math.min.apply(null, cols), c1 = Math.max.apply(null, cols);
    var block = tab.getRange(first, c0, n, c1 - c0 + 1);
    var values = block.getValues();
    matches.forEach(function (m, i) {
      var row = tabRow(m, stats);
      if (!String(ids[i] || '').trim()) return;
      written.forEach(function (k) { values[i][keys[k].col - c0] = row[k]; });
    });
    block.setValues(values);

    var found = matches.filter(function (m, i) { return m.job && String(ids[i] || '').trim(); }).length;
    var stations = ids.filter(function (id) { return String(id || '').trim(); }).length;
    var line = 'สำเร็จ: จับคู่ ' + found + ' / ' + stations + ' สถานี, งานในแอป ' + jobs.length + ', รายงานประจำวัน ' + logs.length;
    tab.getRange('B3').setValue(new Date());
    tab.getRange('B4').setValue(line);
    report('ดึงจาก TCRoof', line);
  } catch (e) {
    tab.getRange('B4').setValue('ผิดพลาด: ' + e.message);
    report('ดึงจาก TCRoof', 'ผิดพลาด: ' + e.message);
    throw e;
  } finally {
    lock.releaseLock();
  }
}

/** The documents of a collection, with only `fields` (a projection keeps the large JSON out). */
function firestoreQuery(collection, fields, where) {
  var project = PropertiesService.getScriptProperties().getProperty('FIREBASE_PROJECT') || DEFAULT_PROJECT;
  var query = { from: [{ collectionId: collection }], select: { fields: fields.map(function (f) { return { fieldPath: f }; }) } };
  if (where) query.where = where;
  var res = UrlFetchApp.fetch('https://firestore.googleapis.com/v1/projects/' + project + '/databases/(default)/documents:runQuery', {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify({ structuredQuery: query }),
    // the account that runs the script reads with its own Google access (IAM, see README), billed to the app's project
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken(), 'x-goog-user-project': project },
    muteHttpExceptions: true
  });
  var code = res.getResponseCode();
  if (code !== 200) {
    var msg = res.getContentText();
    try { msg = JSON.parse(msg)[0].error.message; } catch (e) { try { msg = JSON.parse(res.getContentText()).error.message; } catch (e2) {} }
    throw new Error('Firestore ' + collection + ' (' + code + '): ' + msg);
  }
  return fsDocuments(JSON.parse(res.getContentText()));
}

// MARK: history

function snapshotNow() {
  var book = SpreadsheetApp.getActive();
  try {
    var line = snapshot(book, new Date());
    report('บันทึกประวัติ', line);
  } catch (e) {
    report('บันทึกประวัติ', 'ผิดพลาด: ' + e.message);
    throw e;
  }
}

/** The Master Plan's rows into `ประวัติรายสัปดาห์` and a phase line into `ประวัติสรุป`; a day already kept is replaced. */
function snapshot(book, now) {
  var day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  var plan = readRows(book, 'Master Plan');
  var stations = plan.filter(function (r) { return String(r.id || '').trim(); });

  var weekly = book.getSheetByName('ประวัติรายสัปดาห์'), wk = sheetKeys(book, 'ประวัติรายสัปดาห์');
  var wkNames = Object.keys(wk);
  // the history names a few columns its own way
  var from = { con: 'contractor' };
  var rows = stations.map(function (s) {
    var o = { date: day };
    wkNames.forEach(function (k) {
      var v = s[from[k] || k];
      if (k !== 'date') o[k] = v === undefined ? '' : v;
    });
    return o;
  });
  appendForDay(weekly, wk, rows, day);

  var summary = book.getSheetByName('ประวัติสรุป'), sk = sheetKeys(book, 'ประวัติสรุป');
  var previous = lastBefore(summary, sk, day);
  var risks = readRows(book, 'ทะเบียนความเสี่ยง').filter(function (r) { return r.id; });
  var changes = readRows(book, 'บันทึกการเปลี่ยนแปลง');
  var line = phaseSummary(stations, previous, risks, changes);
  line.date = day;
  appendForDay(summary, sk, [line], day);
  return 'สำเร็จ: ' + rows.length + ' สถานี, ' + Utilities.formatDate(day, book.getSpreadsheetTimeZone(), 'yyyy-MM-dd');
}

/** Rows written under a history sheet's header, after removing the rows it already kept for `day`. */
function appendForDay(sheet, keys, rows, day) {
  var first = keys.date.first, dateCol = keys.date.col;
  var lastRow = sheet.getLastRow();
  if (lastRow >= first) {
    var dates = sheet.getRange(first, dateCol, lastRow - first + 1, 1).getValues();
    // from the bottom, a run of that day's rows at a time
    for (var i = dates.length - 1; i >= 0; i--) {
      if (!(dates[i][0] instanceof Date && sameDay(dates[i][0], day))) continue;
      var end = i;
      while (i > 0 && dates[i - 1][0] instanceof Date && sameDay(dates[i - 1][0], day)) i--;
      sheet.deleteRows(first + i, end - i + 1);
    }
  }
  if (!rows.length) return;
  var names = Object.keys(keys);
  var cols = names.map(function (k) { return keys[k].col; });
  var c0 = Math.min.apply(null, cols), c1 = Math.max.apply(null, cols);
  var at = Math.max(sheet.getLastRow() + 1, first);
  var values = rows.map(function (r) {
    var v = []; for (var c = c0; c <= c1; c++) v.push('');
    names.forEach(function (k) { v[keys[k].col - c0] = r[k] === undefined ? '' : r[k]; });
    return v;
  });
  sheet.getRange(at, c0, values.length, c1 - c0 + 1).setValues(values);
}

/** The phase COD of the last summary kept before `day`. */
function lastBefore(sheet, keys, day) {
  var first = keys.date.first, lastRow = sheet.getLastRow();
  if (lastRow < first || !keys.cod_phase) return null;
  var dates = sheet.getRange(first, keys.date.col, lastRow - first + 1, 1).getValues();
  var cods = sheet.getRange(first, keys.cod_phase.col, lastRow - first + 1, 1).getValues();
  var best = null, cod = null;
  dates.forEach(function (r, i) {
    var d = r[0];
    if (d instanceof Date && d < day && (!best || d > best)) { best = d; cod = cods[i][0]; }
  });
  return cod instanceof Date ? cod : null;
}

// MARK: the workbook's keys

/** `_keys` for one sheet: key → { col (1-based), first, last }; `last` 0 means open-ended. */
function sheetKeys(book, sheetName) {
  var k = book.getSheetByName('_keys');
  if (!k) throw new Error('ไม่พบชีต _keys');
  var out = {};
  k.getRange(2, 1, Math.max(k.getLastRow() - 1, 1), 5).getValues().forEach(function (r) {
    if (r[0] !== sheetName || !r[1]) return;
    out[r[1]] = { col: columnNumber(r[2]), first: Number(r[3]), last: Number(r[4]) };
  });
  if (!Object.keys(out).length) throw new Error('_keys ไม่มีชีต ' + sheetName);
  return out;
}

/** A sheet's rows between its keys' first and last row, each as { key: value } (values as the sheet shows them). */
function readRows(book, sheetName) {
  var sheet = book.getSheetByName(sheetName), keys = sheetKeys(book, sheetName);
  var names = Object.keys(keys), any = keys[names[0]];
  var last = any.last || sheet.getLastRow();
  if (last < any.first) return [];
  var cols = names.map(function (k) { return keys[k].col; });
  var c0 = Math.min.apply(null, cols), c1 = Math.max.apply(null, cols);
  var values = sheet.getRange(any.first, c0, last - any.first + 1, c1 - c0 + 1).getValues();
  return values.map(function (v) {
    var o = {};
    names.forEach(function (k) { o[k] = v[keys[k].col - c0]; });
    return o;
  });
}

function columnNumber(letters) {
  var n = 0;
  String(letters).toUpperCase().split('').forEach(function (ch) { n = n * 26 + ch.charCodeAt(0) - 64; });
  return n;
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** `ตั้งค่าแจ้งเตือน`'s `ผลการทำงานล่าสุด` line for a job. */
function report(label, text) {
  var s = SpreadsheetApp.getActive().getSheetByName('ตั้งค่าแจ้งเตือน');
  if (!s) return;
  var a = s.getRange(1, 1, s.getLastRow(), 1).getValues();
  for (var i = 0; i < a.length; i++) {
    if (String(a[i][0]).trim() === label) {
      s.getRange(i + 1, 2).setValue(Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm') + ' ' + text);
      return;
    }
  }
}

// MARK: set-up

function installTriggers() {
  removeTriggers();
  ScriptApp.newTrigger('pullFromApp').timeBased().everyMinutes(5).create();
  ScriptApp.newTrigger('snapshotNow').timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(8).create();
  pullFromApp();
  SpreadsheetApp.getUi().alert('เปิดงานอัตโนมัติแล้ว: ดึงข้อมูลจากแอปทุก 5 นาที และบันทึกประวัติทุกวันจันทร์ 08:00 '
    + '(ทำงานในชื่อบัญชีที่กดเปิด)');
}

function removeTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (['pullFromApp', 'snapshotNow'].indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t);
  });
}

function setProject() {
  var ui = SpreadsheetApp.getUi();
  var props = PropertiesService.getScriptProperties();
  var r = ui.prompt('โปรเจกต์ Firebase', 'Project ID (ตอนนี้: ' + (props.getProperty('FIREBASE_PROJECT') || DEFAULT_PROJECT) + ')',
                    ui.ButtonSet.OK_CANCEL);
  if (r.getSelectedButton() !== ui.Button.OK) return;
  var id = r.getResponseText().trim();
  if (id) props.setProperty('FIREBASE_PROJECT', id); else props.deleteProperty('FIREBASE_PROJECT');
}
