/**
 * TCRoof › Master Plan sheet (Master_Plan_ประปา_เฟส3-4_ลิงก์แผนรายโครงการ): the sheet's own script.
 *
 * - `TCRoof › ดึงข้อมูลตอนนี้` (and every 5 minutes): reads the app's jobs and daily reports from Firestore and writes
 *   the `TCRoof` tab's blue columns, which the Master Plan reads (`% MP ในแอป TCRoof`, `แก้ล่าสุดในแอป`), and the `WBS`
 *   tab. The one thing it writes back: a `Y` typed on the `WBS` tab (or taken off a row the sheet ticked) goes to the
 *   job's `wbsTicks` first, as a `sheet` tick (`syncWBSEdits`, CHA-71).
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
    .addItem('เพิ่มสถานีที่ยังไม่มีในแอป…', 'addMissingStations')
    .addItem('ลบสถานีที่เพิ่มจากชีต…', 'removeAddedStations')
    .addItem('สร้างชีตผู้มีส่วนได้ส่วนเสีย', 'createStakeholderTab')
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

    var jobs = firestoreQuery('jobs', ['projectName', 'code', 'capacityKW', 'kind', 'status', 'stationDocs', 'scheduleInput',
                                       'scheduleActual', 'iecState', 'scheduleWBS', 'wbsTicks', 'externals']).map(jobSummary);
    // what was typed on the WBS tab since the last pull goes to the app before the tab is written again
    var wbs = syncWBSEdits(book, jobs);
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
    writeUnmatched(tab, c1 + 2, first, unmatchedJobs(jobs, matches, stats));
    writeAppTab(book, appTabRows(jobs, matches, rows, stats), logs.length);
    writeWBSTab(book, wbsTabRows(rows, matches), wbs);
    var risks = syncRisks(book, rows, matches);
    var people = syncStakeholders(book, rows, matches);

    var found = matches.filter(function (m, i) { return m.job && String(ids[i] || '').trim(); }).length;
    var stations = ids.filter(function (id) { return String(id || '').trim(); }).length;
    var line = 'สำเร็จ: จับคู่ ' + found + ' / ' + stations + ' สถานี, งานในแอป ' + jobs.length + ', รายงานประจำวัน ' + logs.length;
    if (risks) line += ', ' + risks;
    if (people) line += ', ' + people;
    if (wbs.written || wbs.refusals.length) line += ', WBS ส่งเข้าแอป ' + wbs.written + ' งาน' + (wbs.refusals.length ? ' ไม่รับ ' + wbs.refusals.length + ' แถว (ดูชีต WBS)' : '');
    // the app's days are Bangkok's: a sheet in another time zone shows them a day early
    var tz = book.getSpreadsheetTimeZone();
    if (tz !== 'Asia/Bangkok') line += ' | ⚠ เขตเวลาของชีตเป็น ' + tz + ' วันที่จะเลื่อน: ไฟล์ › การตั้งค่า › เขตเวลา เลือก (GMT+07:00) Bangkok';
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

/**
 * `_app`: every job Firestore holds, one row each (`appTabRows`), rewritten every pull, so what the app has can be read
 * from the sheet alone. Made hidden the first time.
 */
function writeAppTab(book, list, logCount) {
  var sheet = book.getSheetByName('_app');
  if (!sheet) { sheet = book.insertSheet('_app', book.getNumSheets()); sheet.hideSheet(); }
  sheet.clearContents();
  sheet.getRange(1, 1).setValue('งานทั้งหมดใน Firebase (' + project() + ') ดึงโดยสคริปต์ทุกรอบ ห้ามแก้ไข');
  sheet.getRange(2, 1, 1, 2).setValues([['ดึงล่าสุด', new Date()]]);
  sheet.getRange(2, 3, 1, 2).setValues([['งาน ' + list.length, 'รายงานประจำวัน ' + logCount]]);
  sheet.getRange(3, 1, 1, APP_TAB_HEADER.length).setValues([APP_TAB_HEADER]);
  if (list.length) sheet.getRange(4, 1, list.length, APP_TAB_HEADER.length).setValues(list);
}

// MARK: the WBS tab (CHA-71)

var WBS_FIRST_ROW = 4;

/** A tab's rows from `WBS_FIRST_ROW`, `width` columns; [] for none. */
function sheetRows(sheet, width) {
  if (!sheet || sheet.getLastRow() < WBS_FIRST_ROW) return [];
  return sheet.getRange(WBS_FIRST_ROW, 1, sheet.getLastRow() - WBS_FIRST_ROW + 1, width).getValues();
}

/**
 * The `WBS` tab's changes since the last pull (against the hidden `_wbs` snapshot) written into the jobs' `wbsTicks`
 * as `sheet` ticks, only for a team member (`members/<email>`, not external, not suspended): `wbsSheetChanges`. Each
 * changed job gets one commit of `wbsTicks` and `wbsTicksBy` (the editor) and nothing else; `jobs` are updated in
 * place, so the tab written after shows them. Returns { written, refusals }.
 */
function syncWBSEdits(book, jobs) {
  var tab = book.getSheetByName('WBS'), snap = book.getSheetByName('_wbs');
  if (!tab || !snap) return { written: 0, refusals: [] };
  var current = wbsCells(sheetRows(tab, WBS_TAB_HEADER.length), true);
  var snapshot = wbsCells(sheetRows(snap, 4), false);
  var byId = {}, appTicks = {};
  jobs.forEach(function (j) { byId[j.id] = j; appTicks[j.id] = parseJSON(j.doc.wbsTicks) || {}; });
  var members = {};
  var isTeam = function (email) {
    if (!(email in members)) {
      var m = firestoreGet('members/' + email);
      members[email] = !!m && m.role !== 'external' && m.suspended !== true;
    }
    return members[email];
  };
  var editor = '';
  try { editor = Session.getEffectiveUser().getEmail(); } catch (e) {}
  var today = Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM-dd');
  var r = wbsSheetChanges(snapshot, current, appTicks, editor, isTeam, today);
  var base = 'projects/' + project() + '/databases/(default)/documents/jobs/';
  r.writes.forEach(function (w) {
    if (!byId[w.jobId]) return;
    firestoreCall(':commit', { writes: [{
      update: { name: base + w.jobId, fields: { wbsTicks: { stringValue: w.json }, wbsTicksBy: { stringValue: w.by } } },
      updateMask: { fieldPaths: ['wbsTicks', 'wbsTicksBy'] },
      currentDocument: { exists: true }
    }] }, 'jobs/' + w.jobId);
    byId[w.jobId].doc.wbsTicks = w.json;
  });
  return { written: r.writes.length, refusals: r.refusals };
}

/**
 * `WBS`: every tickable sub-task of the paired PWA stations (`wbsTabRows`), rewritten every pull from the app, with
 * the rows the last pull refused flagged in `แก้โดย`'s place; `_wbs` (hidden) keeps what it showed, so the next pull
 * sees what was typed since. Made the first time.
 */
function writeWBSTab(book, list, result) {
  var tab = book.getSheetByName('WBS');
  if (!tab) tab = book.insertSheet('WBS', book.getNumSheets());
  var snap = book.getSheetByName('_wbs');
  if (!snap) { snap = book.insertSheet('_wbs', book.getNumSheets()); snap.hideSheet(); }
  var refused = {};
  (result.refusals || []).forEach(function (x) { refused[x.jobId + '|' + x.code] = x.why; });
  tab.clearContents();
  tab.getRange(1, 1).setValue('งานย่อย WBS ในแอป TCRoof: ใส่ Y (และวันที่เสร็จ) ในคอลัมน์ F / G แล้วรอดึงรอบถัดไป (ทุก 5 นาที) '
    + 'นับเข้าแผน MP ทันทีในชื่อผู้แก้ | เอา Y ออกได้เฉพาะแถวที่ติ๊กจาก Google Sheet | แถวอื่นแก้ในแอป');
  tab.getRange(2, 1, 1, 2).setValues([['ดึงล่าสุด', new Date()]]);
  tab.getRange(2, 3).setValue((result.written ? 'ส่งเข้าแอป ' + result.written + ' งาน' : '')
    + ((result.refusals || []).length ? ' ไม่รับ ' + result.refusals.length + ' แถว: ดูคอลัมน์ J' : ''));
  tab.getRange(3, 1, 1, WBS_TAB_HEADER.length).setValues([WBS_TAB_HEADER]);
  var values = list.map(function (r) {
    var v = r.slice();
    // a date as the sheet's own (Bangkok) midnight, so it reads back as the same day
    if (v[6]) { var p = v[6].split('-'); v[6] = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])); }
    var why = refused[r[1] + '|' + r[2]];
    if (why) v[9] = 'ไม่รับ: ' + why;
    return v;
  });
  if (values.length) {
    tab.getRange(WBS_FIRST_ROW, 1, values.length, WBS_TAB_HEADER.length).setValues(values);
    tab.getRange(WBS_FIRST_ROW, 7, values.length, 1).setNumberFormat('yyyy-mm-dd');
  }
  snap.clearContents();
  var rows = wbsSnapshotRows(list);
  if (rows.length) snap.getRange(WBS_FIRST_ROW, 1, rows.length, 4).setValues(rows);
}

/**
 * The edit trigger (`installTriggers`): an edit of `เสร็จ (Y)` or `วันที่เสร็จ` on the `WBS` tab notes who made it in
 * `แก้โดย`, so the next pull writes the tick in their name rather than the timers' account. Google gives the editor's
 * email only when the account allows it; without one the pull uses the timers' account.
 */
function onWBSEdit(e) {
  var range = e && e.range;
  if (!range || range.getSheet().getName() !== 'WBS') return;
  var c0 = range.getColumn(), c1 = c0 + range.getNumColumns() - 1;
  if (c1 < 6 || c0 > 7 || range.getLastRow() < WBS_FIRST_ROW) return;
  var email = '';
  try { email = (e.user && e.user.getEmail()) || Session.getActiveUser().getEmail(); } catch (err) {}
  var top = Math.max(range.getRow(), WBS_FIRST_ROW), n = range.getLastRow() - top + 1;
  range.getSheet().getRange(top, 10, n, 1).setValues(Array.apply(null, Array(n)).map(function () { return [email]; }));
}

/** The app's jobs no station row took, as a list right of the tab's columns (rewritten every pull). */
function writeUnmatched(tab, col, first, list) {
  var width = 7, top = first - 2;
  var old = Math.max(tab.getLastRow() - top + 1, 2);
  tab.getRange(top, col, old, width).clearContent();
  tab.getRange(top, col).setValue('งานในแอปที่ยังไม่จับคู่ ' + list.length + ' งาน: ใส่ id ในช่องเหลือง ‘กำหนดงานในแอปเอง’ ของแถวสถานีนั้น');
  tab.getRange(top + 1, col, 1, width).setValues([['id', 'ชื่องานในแอป', 'ประเภท', 'kWp', 'รหัสสถานี', 'แผน MP', 'รายงานประจำวัน']]);
  if (list.length) tab.getRange(top + 2, col, list.length, width).setValues(list);
}

function project() {
  return PropertiesService.getScriptProperties().getProperty('FIREBASE_PROJECT') || DEFAULT_PROJECT;
}

/** The documents of a collection, with only `fields` (a projection keeps the large JSON out). */
function firestoreQuery(collection, fields, where) {
  var query = { from: [{ collectionId: collection }], select: { fields: fields.map(function (f) { return { fieldPath: f }; }) } };
  if (where) query.where = where;
  return fsDocuments(firestoreCall(':runQuery', { structuredQuery: query }, collection));
}

/** One Firestore REST call on the database's documents (`:runQuery`, `:commit`). */
function firestoreCall(method, body, what) {
  var res = UrlFetchApp.fetch('https://firestore.googleapis.com/v1/projects/' + project() + '/databases/(default)/documents' + method, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(body),
    // the account that runs the script uses its own Google access (IAM, see README), billed to the app's project
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken(), 'x-goog-user-project': project() },
    muteHttpExceptions: true
  });
  var code = res.getResponseCode();
  if (code !== 200) {
    var msg = res.getContentText();
    try { msg = JSON.parse(msg)[0].error.message; } catch (e) { try { msg = JSON.parse(res.getContentText()).error.message; } catch (e2) {} }
    throw new Error('Firestore ' + (what || method) + ' (' + code + '): ' + msg);
  }
  return JSON.parse(res.getContentText());
}

/** One document's fields as plain JS (`members/<email>`), or null when there is none. */
function firestoreGet(path) {
  var res = UrlFetchApp.fetch('https://firestore.googleapis.com/v1/projects/' + project() + '/databases/(default)/documents/'
    + path.split('/').map(encodeURIComponent).join('/'), {
    method: 'get',
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken(), 'x-goog-user-project': project() },
    muteHttpExceptions: true
  });
  var code = res.getResponseCode();
  if (code === 404) return null;
  if (code !== 200) throw new Error('Firestore ' + path + ' (' + code + '): ' + res.getContentText().slice(0, 200));
  return fsFields(JSON.parse(res.getContentText()).fields || {});
}

// MARK: the risk register for the app (CHA-81)

/**
 * Copies `ทะเบียนความเสี่ยง` into `config/risks` (`Core.riskRegister`: each risk with the paired jobs of the stations
 * its `ขอบเขต` touches), only when it changed, so an unchanged register costs one read a pull. The app reads it, team
 * only (firestore.rules). Returns a few words for the pull's line, or '' when nothing was written; a failure here is
 * reported in that line and never stops the pull.
 */
function syncRisks(book, rows, matches) {
  try {
    var jobByCode = {};
    matches.forEach(function (m, i) {
      var code = String(rows[i].code || '').trim();
      if (m.job && code) jobByCode[code] = m.job.id;
    });
    var tz = book.getSpreadsheetTimeZone();
    var json = riskRegister(readRows(book, 'ทะเบียนความเสี่ยง'), readRows(book, 'Master Plan'), jobByCode,
                            function (d) { return Utilities.formatDate(d, tz, 'yyyy-MM-dd'); });
    var current = firestoreGet('config/risks');
    if (current && current.json === json) return '';
    firestoreCall(':commit', { writes: [{
      update: { name: 'projects/' + project() + '/databases/(default)/documents/config/risks',
                fields: { json: { stringValue: json }, updatedAt: { timestampValue: new Date().toISOString() } } }
    }] }, 'config/risks');
    return 'ทะเบียนความเสี่ยงส่งเข้าแอป ' + JSON.parse(json).risks.length + ' รายการ';
  } catch (e) {
    return '⚠ ทะเบียนความเสี่ยง: ' + e.message;
  }
}

// MARK: the stakeholder list for the app (CHA-82)

/**
 * Copies `ผู้มีส่วนได้ส่วนเสีย` into `config/stakeholders` (`Core.stakeholderList`), only when it changed, as
 * `syncRisks` does. A book without the tab yet writes nothing and says nothing (the menu's `สร้างชีตผู้มีส่วนได้ส่วนเสีย`
 * makes it). Returns a few words for the pull's line, or ''; a failure is reported there and never stops the pull.
 */
function syncStakeholders(book, rows, matches) {
  if (!book.getSheetByName(STAKEHOLDER_TAB.name)) return '';
  try {
    var jobByCode = {};
    matches.forEach(function (m, i) {
      var code = String(rows[i].code || '').trim();
      if (m.job && code) jobByCode[code] = m.job.id;
    });
    var json = stakeholderList(readRows(book, STAKEHOLDER_TAB.name), readRows(book, 'Master Plan'), jobByCode);
    var current = firestoreGet('config/stakeholders');
    if (current && current.json === json) return '';
    firestoreCall(':commit', { writes: [{
      update: { name: 'projects/' + project() + '/databases/(default)/documents/config/stakeholders',
                fields: { json: { stringValue: json }, updatedAt: { timestampValue: new Date().toISOString() } } }
    }] }, 'config/stakeholders');
    return 'ผู้มีส่วนได้ส่วนเสียส่งเข้าแอป ' + JSON.parse(json).stakeholders.length + ' ราย';
  } catch (e) {
    return '⚠ ผู้มีส่วนได้ส่วนเสีย: ' + e.message;
  }
}

/**
 * Makes the `ผู้มีส่วนได้ส่วนเสีย` tab: title, note, header, two example rows to overwrite, and its rows in `_keys`. Does
 * nothing to a tab that already exists.
 */
function createStakeholderTab() {
  var book = SpreadsheetApp.getActive(), ui = SpreadsheetApp.getUi();
  if (book.getSheetByName(STAKEHOLDER_TAB.name)) {
    ui.alert('มีชีต ' + STAKEHOLDER_TAB.name + ' อยู่แล้ว');
    return;
  }
  var keys = book.getSheetByName('_keys');
  if (!keys) { ui.alert('ไม่พบชีต _keys'); return; }
  var sheet = book.insertSheet(STAKEHOLDER_TAB.name);
  var width = STAKEHOLDER_COLUMNS.length, header = STAKEHOLDER_TAB.first - 1;
  sheet.getRange(1, 1).setValue(STAKEHOLDER_TAB.title).setFontWeight('bold').setFontSize(14);
  sheet.getRange(2, 1).setValue(STAKEHOLDER_TAB.note).setFontColor('#666666');
  sheet.getRange(header, 1, 1, width).setValues([STAKEHOLDER_COLUMNS.map(function (c) { return c[1]; })])
    .setFontWeight('bold').setBackground('#1f3864').setFontColor('#ffffff');
  sheet.getRange(STAKEHOLDER_TAB.first, 1, STAKEHOLDER_TAB.examples.length, width).setValues(STAKEHOLDER_TAB.examples);
  sheet.setFrozenRows(header);
  sheet.autoResizeColumns(1, width);
  var add = stakeholderKeyRows();
  keys.getRange(keys.getLastRow() + 1, 1, add.length, 5).setValues(add);
  ui.alert('สร้างชีต ' + STAKEHOLDER_TAB.name + ' แล้ว: แก้แถวตัวอย่าง S01 และ S02 แล้วเพิ่มแถวได้เลย การดึงข้อมูลครั้งถัดไปจะส่งเข้าแอป');
}

// MARK: adding the stations to the app

/**
 * Creates a PWA job in Firestore for each station row no app job is (`จับคู่โดย` `ไม่พบงานในแอป`), after asking.
 * Each is a new document (never one that exists); their ids are kept so `ลบสถานีที่เพิ่มจากชีต` can take them back.
 * The app's devices receive them on their next sync.
 */
function addMissingStations() {
  var ui = SpreadsheetApp.getUi();
  var book = SpreadsheetApp.getActive();
  var keys = sheetKeys(book, 'TCRoof'), tab = book.getSheetByName('TCRoof');
  var first = keys.id.first, n = keys.id.last - first + 1;
  var read = function (k) { return tab.getRange(first, keys[k].col, n, 1).getValues().map(function (r) { return r[0]; }); };
  var ids = read('id'), names = read('name'), kwps = read('kwp'), overrides = read('override');
  // the branch from the Master Plan, by station code
  var branches = {};
  readRows(book, 'Master Plan').forEach(function (r) { if (r.id) branches[String(r.id).trim()] = r.branch; });
  var rows = ids.map(function (id, i) {
    return { code: id, name: names[i], kWp: kwps[i], override: overrides[i], branch: branches[String(id).trim()] };
  });
  var jobs = firestoreQuery('jobs', ['projectName', 'code', 'capacityKW', 'kind', 'stationDocs']).map(jobSummary);
  var todo = rowsToCreate(rows, matchRows(rows, jobs));
  if (!todo.length) { ui.alert('ทุกสถานีมีงานในแอปแล้ว (หรือรอใส่รหัสงานในช่องเหลือง)'); return; }
  var answer = ui.alert('เพิ่มสถานีลงแอป',
    'สร้างงาน PWA ใหม่ ' + todo.length + ' สถานี ใน Firebase (' + project() + ')\n'
    + todo.slice(0, 5).map(function (r) { return r.code + ' ' + r.name; }).join('\n') + (todo.length > 5 ? '\n…' : '')
    + '\n\nทุกเครื่องของทีมจะเห็นงานเหล่านี้ในการซิงก์รอบถัดไป ลบคืนได้จากเมนู ‘ลบสถานีที่เพิ่มจากชีต’', ui.ButtonSet.YES_NO);
  if (answer !== ui.Button.YES) return;

  var now = new Date(), created = [];
  var base = 'projects/' + project() + '/databases/(default)/documents/jobs/';
  for (var i = 0; i < todo.length; i += 400) {
    var writes = todo.slice(i, i + 400).map(function (r) {
      var id = Utilities.getUuid().toUpperCase();
      created.push(id);
      return { update: { name: base + id, fields: newJobFields(r, now) }, currentDocument: { exists: false } };
    });
    firestoreCall(':commit', { writes: writes });
  }
  var props = PropertiesService.getScriptProperties();
  var kept = JSON.parse(props.getProperty('ADDED_JOBS') || '[]');
  props.setProperty('ADDED_JOBS', JSON.stringify(kept.concat(created)));
  report('ดึงจาก TCRoof', 'เพิ่มงาน PWA ' + created.length + ' สถานีลงแอปแล้ว');
  pullFromApp();
  ui.alert('เพิ่มแล้ว ' + created.length + ' สถานี', 'ดู B4 ของชีต TCRoof: สถานีเหล่านี้จับคู่ด้วยรหัสแล้ว', ui.ButtonSet.OK);
}

/** Deletes the jobs `addMissingStations` created, after asking: only those, and only the ones still there. */
function removeAddedStations() {
  var ui = SpreadsheetApp.getUi();
  var props = PropertiesService.getScriptProperties();
  var kept = JSON.parse(props.getProperty('ADDED_JOBS') || '[]');
  if (!kept.length) { ui.alert('ยังไม่มีสถานีที่เพิ่มจากชีตนี้'); return; }
  var answer = ui.alert('ลบสถานีที่เพิ่มจากชีต',
    'ลบงาน ' + kept.length + ' งานที่ชีตนี้สร้างออกจาก Firebase? งานเหล่านี้จะหายจากทุกเครื่อง รวมถึงสิ่งที่บันทึกไว้ในงาน (แผน MP, รายงาน)',
    ui.ButtonSet.YES_NO);
  if (answer !== ui.Button.YES) return;
  var base = 'projects/' + project() + '/databases/(default)/documents/jobs/';
  for (var i = 0; i < kept.length; i += 400) {
    firestoreCall(':commit', { writes: kept.slice(i, i + 400).map(function (id) { return { delete: base + id }; }) });
  }
  props.deleteProperty('ADDED_JOBS');
  report('ดึงจาก TCRoof', 'ลบงานที่เพิ่มจากชีต ' + kept.length + ' งานแล้ว');
  pullFromApp();
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
  // who typed a Y on the WBS tab, for the next pull to write the tick in their name
  ScriptApp.newTrigger('onWBSEdit').forSpreadsheet(SpreadsheetApp.getActive()).onEdit().create();
  pullFromApp();
  SpreadsheetApp.getUi().alert('เปิดงานอัตโนมัติแล้ว: ดึงข้อมูลจากแอปทุก 5 นาที และบันทึกประวัติทุกวันจันทร์ 08:00 '
    + '(ทำงานในชื่อบัญชีที่กดเปิด) | Y ในชีต WBS ส่งเข้าแอปในชื่อผู้แก้ ถ้า Google ให้อีเมลผู้แก้ ไม่งั้นในชื่อบัญชีนี้');
}

function removeTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (['pullFromApp', 'snapshotNow', 'onWBSEdit'].indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t);
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
