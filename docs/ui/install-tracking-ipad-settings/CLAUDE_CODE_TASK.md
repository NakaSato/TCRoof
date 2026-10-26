# iPad install tracking · `ตั้งค่าโครงการ` tab

Board: `iPadInstallSettings.dc.html` (open it in a browser next to `grf.css`). States at 2732 × 2048 (@2x of 1366 × 1024)
are in `states/`, `preview.png` is state 01 at 1 ×. Example values are in `assets/sample-data.json`: they are
examples, never hard-code them.

## 1. Goal

The iPad install tracking page (`InstallTrackingPage`) gets an in-page tab `ตั้งค่าโครงการ` (gear icon, the last item
of the tab bar) with the iPadOS Settings layout: the station card and the category list on the left, only the chosen
category on the right. It shows and edits what this one station keeps. The iPhone already has the same content behind
its header gear (`InstallTrackingPage+PhoneSettings.swift`, `SettingsCategory`); the iPad tab reads the same job data
and calls the same editors and mutations.

## 2. Scope

Do only the change list in §5. Out of scope, do not touch:

- The iPhone settings page and its look (`InstallTrackingPage+PhoneSettings.swift` may only gain shared helpers that
  the iPhone keeps using unchanged; the iPhone still shows its four categories).
- Other tabs of the page, the header, the dock, the job screen, `JobAccessCard`, `RoutineSettingsSheet`,
  `StationFactsSheet` (call them, don't restyle them).
- Firestore rules, `CloudSync` behaviour, the PDF and Excel layouts.
- The board's `ผู้ติดต่อหน้างาน` and `ขั้นสูง` categories, the `วันส่งคำขอรายสัปดาห์` and `เกณฑ์ความต้านทานฉนวน` rows and
  the `ผู้รับเหมากรอกผลได้` switch: nothing stores them today (§7). Leave them out, as the iPhone does.

## 3. Read first

`InstallTrackingPage.swift` (`Tab`, the tab bar items, `Route`, `Debug`), `InstallTrackingPage+PhoneSettings.swift`
(rows, `weekdaysSummary`, `teamPage`, `routinePage`, `connectionPage`, `referencePage`), `InstallTrackingPage+Phone.swift`
(how `.access`, `.routine` and `.station` open), `JobAccessCard` (add / remove / supervisor), `RoutineSettingsSheet`,
`StationFactsSheet`, `RoutineReport.Settings` (`contractName`, `employer`, `contractor`, `workStart`, `workEnd`,
`workingWeekdays`, `inspector`), `StationDocs.Station` / `Context` (`sellsPower`, `over200kVA`), `IECReport.instruments`,
and how `Job.weeklySentJSON` was added (`Models.swift`, `RoutineReportSupport.swift`, `CloudRecords.swift`): the
pattern for §5 item 6.

## 4. Layout (1366 × 1024, landscape)

- Below the tab bar, one rounded panel to the dock, the same panel the other tabs use.
- Left column ≈ 330 pt: the station card (initials tile, station name, `ตั้งค่าเฉพาะโครงการนี้`, a chip `ซิงก์แล้ว` /
  `ยังไม่บันทึก`), then one inset list of categories: outline icon tile (tint at ~8 % fill, ~35 % border), title, a
  trailing summary (`3 คน`, `4 แบบ`, `จ – ส`, `Zero Export`), chevron. The selected row has the light primary fill and
  a 3 pt leading bar. A category with unsaved edits shows an orange dot before its chevron.
- Right column: a head card (icon tile, title, note, the same sync chip), then the category's sections as inset grouped
  lists (section title, rows ≥ 60 pt, footer note under the card). Row kinds:
  - value row: label + hint left, value right in primary bold, chevron when it opens an editor;
  - picker row: label + hint left, 2–3 outlined segment buttons (selected: primary border 2 pt, light fill);
  - person row: avatar initial, name, email, role chip, chevron;
  - action row: outlined `+ …` button;
  - read-only row: value with a lock glyph, no chevron.
- Sheets are centred form sheets with `ยกเลิก | <title> | เสร็จ`.
- Unsaved bar (state 10): floats above the dock, `แก้ไข n รายการ · ยังไม่บันทึก`, the categories touched,
  `ยกเลิกการแก้` and `บันทึก`.

## 5. Change list (in order)

1. **Tab.** Add `case settings` to `InstallTrackingPage.Tab` and its tab bar item `ตั้งค่าโครงการ` (gear) after
   `แผนก่อสร้าง`. It changes the page in place (no push). `-installTab settings` opens it on iPad; add
   `-installSettings team|header|drawings|routine|connection|reference` to pick the category on iPad (the iPhone keeps
   its four values). Default category: `team`.
2. **Category list + head card** (`InstallTrackingPage+PadSettings.swift`, new). Categories on iPad: `team`, `header`,
   `drawings`, `routine`, `connection`, `reference`. Either add the new cases to `SettingsCategory` and keep the iPhone's
   explicit list of four, or add an iPad-only enum; the iPhone must look and behave as before. Trailing summaries come
   from the job (people count, drawing count, `weekdaysSummary`, connection).
3. **Team** (state 01, 13): same sections, footers and permission checks as the iPhone's `teamPage` (supervisor,
   `ทีมงานของเรา`, `ผู้รับเหมา`). `+` buttons open `JobAccessCard` in a sheet as the iPhone's `.access` does. A person row
   opens the person sheet (state 13): avatar, name, email, role, `ส่งอีเมล` (mailto) and, with the same permission
   `JobAccessCard` checks, `นำออกจากงานนี้` through the same mutation it uses (`externals` / `teamMembers` /
   `supervisorEmail`), asking first.
4. **Header** (`หัวเอกสาร`, state 02) and **Routine** (`รอบรายงาน`, state 04): rows from `routineSettings`:
   `contractName`, `contractor` (จาก), `employer` (ถึง), `workStart – workEnd`, `inspector` (ผู้รับรายงาน), working days
   as a picker `จ – ศ | จ – ส | ทุกวัน` (Mon–Fri, Mon–Sat, all seven; any other set shows no segment selected and its
   summary). `หน่วยงาน กปภ.` shows `stationDocs.branch` read only (its editor is `StationFactsSheet`). Text rows open the
   text editor sheet (state 09). Editable only by whoever can open `RoutineSettingsSheet` today; others see values only.
   Keep a `แก้ไขทั้งหมด` action row that opens `RoutineSettingsSheet` itself (holidays, signers, roles, tools).
5. **Draft and save** (state 10): picker and text edits go into a local draft, not the job. The bar counts them, lists
   the categories, `ยกเลิกการแก้` drops the draft, `บันทึก` writes the draft once (`routineSettings`, and
   `stationDocs.sellsPower` through `Job.stationDocs`'s setter so its links run) and saves the context. Leaving the tab
   with a draft asks `บันทึก | ทิ้ง | อยู่ต่อ`. The sync chip reads `ยังไม่บันทึก` while a draft exists, else
   `ซิงก์แล้ว` (or what `CloudSync` reports for this job if it already exposes a pending state; don't add one).
6. **Drawings** (`แบบก่อสร้าง`, states 03, 11, 12). New stored data:
   - `TCRoofCore/StationDrawings.swift`: `StationDrawing { id: String, title: String, ext: String, revisions: [Revision] }`,
     `Revision { rev: String ("00", "01" …), date: Date, reason: String, by: String (email), file: String, driveID: String? }`;
     `next(after:)` gives the next two-digit rev; `latest`; Codable with `decodeIfPresent` defaults.
     Unit tests: next rev, reason required from 01, a new drawing starts at 00, old JSON without the field decodes.
   - `Job.drawingsJSON: String?` + `Job.drawings` accessor, synced like `weeklySentJSON` (CloudRecords field, nil from
     older versions keeps the device's). Check whether `firestore.rules` lists allowed job keys; if it does, stop and
     report instead of changing rules.
   - List rows (state 03): file-type tile (PDF red, DWG teal), id + title, `แก้ล่าสุด <date> · <reason>`, `REV nn` chip and
     `n revision`; tap opens the history sheet (state 11: newest first, `ล่าสุด · ใช้งาน` / `แทนที่แล้ว`, `เปิด` per rev,
     `อัปโหลด REV nn`). The upload sheet (state 12): pick a drawing or `+ แบบใหม่` (name required), file from Files or
     camera (PDF, DWG, JPG/PNG), the next REV shown, `เหตุผลการแก้ไข *` required from REV 01; `อัปโหลด REV nn` is off
     until valid. An upload appends a revision, never replaces one.
   - Files: keep them with the job's documents the way the routine reports keep their files, in a `แบบก่อสร้าง` folder,
     so the existing Drive upload carries them (`2. เอกสารระหว่างก่อสร้าง/แบบก่อสร้าง/` on the center route). If no existing
     path can carry a non-photo file, keep it on the device, store `driveID: nil` and report it (§7).
   - Who: upload for the team and managers (`permissions` as for station docs drafts, `stationDocsDrafts`); contractors
     view and open.
7. **Connection** (`การเชื่อมต่อและ IEC`, state 06): `การเชื่อมต่อ` picker `Zero Export | ขนานไฟ (ขายคืน)` on
   `stationDocs.sellsPower` (draft, §5 item 5; same permission as the iPhone's `แก้ข้อมูลสถานี`); `ขอยกเว้นใบอนุญาต กกพ.`
   from `stationContext.over200kVA` (`ต่ำกว่า 200 kVA · ไม่ต้องยื่นขอยกเว้น` / `200 kVA ขึ้นไป · ต้องยื่น พค.2`), opening
   `StationFactsSheet`; `เครื่องมือวัด` from `iecReport.instruments` (or `ยังไม่ได้ตั้งค่า`), opening the IEC test's
   step 1 (`route = .iec`). Keep the iPhone's `ชุดที่ยื่น` row.
8. **Reference** (state 07): read only, as the iPhone's `referencePage`, plus `รายงานสำรวจ` (the linked survey's docNo and
   REV, opening it as the header's `รายงานสำรวจ` button does) and `ผังตำแหน่งงาน (Key Plan)` (`ภาพ A2 จากรายงานสำรวจ` or
   `อัปโหลดแล้ว` when the station has a `Job.keyPlanTag` photo). `ประเภทงาน` shows a lock.
9. **Debug + test.** `-installSettingsState edit|dirty|history|upload|person` opens states 09–13 with `-installDemo YES`
   (in memory, nothing saved). Add `InstallSettingsUITests` (iPad): the tab opens, a category switches, a picker change
   shows the bar, `ยกเลิกการแก้` clears it, the upload button stays off until a file and reason are given (demo). Add the
   flags and the test to CLAUDE.md in the style of the other entries.

## 6. Rules

- Colours from `Theme` (icon tints as named constants in one place), `TCButtonStyle`, `Font.sarabun`, hit areas ≥ 44 pt,
  each card a separate computed property.
- Never show an edit control to a role that can't save it; the same `permissions.can(…, on: job.access)` checks as
  the existing editors.
- Old job JSON and records from older app versions still decode; only the optional `drawingsJSON` is new.
- `swift test` in `TCRoofKit`; the xcodebuild app build with your own `-derivedDataPath` (in the background); simulator
  screenshots named like `states/` saved to `screenshots/`; tick this list in your report.

## 7. Open questions (answer in the report, don't decide them in code)

1. `ผู้ติดต่อหน้างาน` (customer coordinator, site access): store on the job (team only, like `jobContacts`) or leave out?
2. `ขั้นสูง` (ย้ายกลับไปงานสำรวจ, ปิดโครงการ, ล้างแผน MP): which of these exist as actions today, and who may run them?
3. `วันส่งคำขอรายสัปดาห์` and the Weekly Report meeting day: add to `RoutineReport.Settings`, or keep the fixed rule?
4. `เกณฑ์ความต้านทานฉนวน` (≥ 1 MΩ / ≥ 40 MΩ): does the IEC check read a threshold that should be per station?
5. `ผู้รับเหมากรอกผลได้`: a per-station switch, or stays the role matrix's decision?
6. Drawing files: which Drive path carried them, and is a DWG preview needed (`เปิด` opens Quick Look today)?
7. The board's `ถึง (ผู้ว่าจ้าง)` reads `การประปาส่วนภูมิภาค`, the app's default `employer` is `การไฟฟ้าส่วนภูมิภาค`:
   should PWA stations default to the PWA?
