# Claude Code task: iPad install tracking, `ภาพรวม` tab: header buttons, waiting tone, and the 4.2 / devices / hand-over document tiles (board 21 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-overview`, then paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad-overview/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)`, tab `ภาพรวม` (`iPadInstall.dc.html`, state `menu: "ov"`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** the station, dates, %, counts, paper names. They are listed in `assets/sample-data.json`. Never hard-code them.

## What exists (v1 and v2 are built)

- `docs/ui/install-tracking-ipad` (v1) and `docs/ui/install-tracking-ipad-v2` (v2) are implemented in `TCRoof/Views/Install/Tracking/`:
  - `InstallTrackingPage` (header, tab bar, KPI strip)
  - `+Progress` (Gantt / S-curve)
  - `+Site` (`เอกสารโครงการ` grid, the tile sheet, the site panel)
  - `InstallPageData+Site.swift` (`DocTile`, `DocItem`, `Tone`, `docTiles`, `packageTile`, `demoTiles`)
- **The Gantt card, the S-curve, the KPI strip's layout, the `ต้องดำเนินการ` sheet and the site panel did not change.** Pixel diffs against v2 differ only where this list says. Do not touch them.
- **This task changes only the overview's differences** (§ Change list).

## Scope

- **In scope:** iPad regular width, the install tracking page's header and `ภาพรวม` tab only.
- **Not in this task. Each one has its own branch, so leave it alone:**
  - The tab bar. The board shows 8 items, including `ตั้งค่าโครงการ` and an in-page `คำขอรายสัปดาห์`. Those belong to other branches: `design/install-tracking-ipad-weekly-request`, and the project settings feature. Keep today's 7 items.
  - The `รายงานประจำวัน` and `แผนก่อสร้าง` tabs.
  - The iPhone page (`+Phone*.swift`).
- **Do not touch:**
  - `StationDocs` rules or catalog JSON
  - `StationDocsScreen`
  - `JobDevicesView`'s behaviour
  - stored fields of any model
  - `firestore.rules`
- **Data rule (same as v1 / v2):** show only what has a source. Hide what has none and list it in your report. `-installDemo YES` may show the board's values (`demoTiles`), for screenshots only.

**Before editing:** use the code-review-graph tools (per `CLAUDE.md`). If the server is not available, use grep.
- Read `InstallTrackingPage.swift` (`header`, `headerButton`), `InstallTrackingPage+Site.swift` (`ink`, `fill`, the grid, the tile sheet) and `InstallPageData+Site.swift` (`docTiles`, `packageTile`, `paperItems`, the devices tile, `demoTiles`).
- Read `StationDocs` (`Package`, `progress`, `papers`, `state`, `Kind.origin`), `JobDevicesView` and `InstallTrackingUITests`.
- Run `tests_for` on what you touch.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/01` (@2x) |
| `states/01-overview-gantt.png` | `ภาพรวม`, Gantt. Header: `ผู้ช่วย AI` (white filled) + `รายงานสำรวจ` (outlined) |
| `states/02-overview-scurve.png` | `ภาพรวม`, S-Curve (unchanged from v2; for reference) |
| `states/03-actions-sheet.png` | `ต้องดำเนินการ` sheet (unchanged; reference) |
| `states/04-overview-scrolled-end.png` | The overview's end: the `เอกสารโครงการ` grid with `4.2 ขนานไฟ (กฟภ.)`, `ส่งมอบงาน 1/4 ฉบับ` and a purple `Material Approval` |
| `states/05-doc-grid-connection.png` | The `4.2 ขนานไฟ (กฟภ.)` tile's sheet: the station's 11 papers with code, origin line and status pill |
| `states/06-doc-handover.png` | The `ส่งมอบงาน` tile's sheet: 4 papers, chip `1/4 ฉบับ`, the due date in the sub line |
| `states/07-doc-devices.png` | The `อุปกรณ์ที่ติดตั้ง` tile's sheet: a row per device kind with installed and S/N counts and `เปิดบันทึก ›` |
| `states/08-header.png` | The header, tab bar and KPI strip, cropped |
| `iPadInstall.dc.html` + `grf.css` | Design source. Read it as text. Search for `const DOCS`, `const P =`, `const DOT`, `ผู้ช่วย AI` |
| `assets/sample-data.json` | The board's example values and the status → colour table |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Header buttons (`states/08`)
- **`ผู้ช่วย` → `ผู้ช่วย AI`**, styled as the **primary** header button:
  - `Theme.surface` fill, `Theme.primary` label, 15 pt bold, 44 pt high, radius 12.
  - Shadow `0 2 8` at 18 % navy.
  - Symbol `sparkles`.
  - Same condition as today (`permissions.can(.assistantUse)`, `job.scheduleInput != nil`).
  - Add a `primary: Bool` parameter to `headerButton`. Do not add a second function.
- **`รายงานสำรวจ (ดูอย่างเดียว)` → `รายงานสำรวจ`**:
  - Keep the lock symbol and the outlined style.
  - Set the accessibility label to `รายงานสำรวจ (ดูอย่างเดียว)`, so VoiceOver still says it's read only.
  - Update every UI test that taps this button by its old label.
- **`รายละเอียดงาน`:** the board doesn't show it, but `InstallTrackingUITests` and the page's way to the job depend on it. **Keep it** and list it under the open questions.

### 2. A `waiting` tone for documents (`states/04`, `05`, `07`)
The board now gives "waiting on someone else" its own colour: purple, `#6B4FBB` on `#EFEBFA`. Blue no longer means waiting.
- Add `case waiting` to `InstallPageData.Tone`:
  - `ink`: `Theme.planInspect`
  - `fill`: `Theme.planInspectSoft`
  - These tokens already exist. Add no hex.
- **Use `.waiting`** where a paper or tile is submitted and waits on an outside party:
  - In `paperItems`, the statuses that are neither ready, nor missing, nor not-needed (today `.info`), for example submitted or awaiting approval.
  - A tile whose papers are all submitted but not all approved.
  - Keep `.info` for things the team is working on (for example `ร่างพร้อมแล้ว`, an IEC test in progress).
- Check the grid's dot and the sheet's pill both read the tone. The board's tile dot is a 9 pt circle in the tone's ink.

### 3. `4.2 ขนานไฟ (กฟภ.)` tile (`states/04`, `05`)
- Rename the grid-connection tile `ขออนุญาตขนานไฟ` → `4.2 ขนานไฟ (กฟภ.)`. The number is the PWA submission's section, as in `StationDocsScreen`. If the package has a section number in `StationDocs`, take it from there; don't type `4.2`.
- **The tile's `about` (the sheet's sub line):** `ชุดยื่น กปภ. ของสถานีนี้ | <state>`.
  - `<state>` is `ยื่นครบแล้ว รอ กฟภ. นัดตรวจ` when every paper is ready and the package is not approved yet.
  - Otherwise it is `กำหนด <d>`, or nothing when there's no due date.
- **Chip:** `ครบ n/m` when complete (already so).
- **Sheet rows:**
  - Each paper is a row: code (`4.2-01` …, the kind's own code when it has one, otherwise its order in the package), name, origin line (`Kind.origin.title`, as today), status pill.
  - The sheet's sub line may wrap to 2 lines (`states/05`), so don't truncate it.

### 4. `ส่งมอบงาน` tile (`states/04`, `06`)
- **Chip when not complete:** `<ready>/<total> ฉบับ` (`1/4 ฉบับ`), tone by due date as today (`.warn` within 7 days, `.danger` when late).
  - The due date moves out of the chip into the sub line: `ชุดส่งมอบ กปภ. ของสถานีนี้ | กำหนดส่งมอบ <d/M/yyyy>`.
  - Apply the same chip rule to every `packageTile` (commissioning too), so the grid reads one way.
- **Sheet rows:** the hand-over package's papers, as `paperItems` gives them today, with a code (`HO-01` …) like §3.
  - The `รายงาน IEC 62446` paper's row opens the IEC test (`.iec`) when the station has a test.
  - Other rows open `StationDocsScreen` (`.docs`), as today.

### 5. `อุปกรณ์ที่ติดตั้ง` tile (`states/07`)
- **Today** the tile lists scanned kinds (`สแกน n`). **The board** lists every device kind the station needs. Each row has:
  - a code (`EQ-PV`, `EQ-INV`, `EQ-MTR`, `EQ-RSD`)
  - a title with its size where known (`แผงโซลาร์ (PV) | 570 W`)
  - a detail line `ติดตั้ง a/b | S/N c/b`
  - a status pill: `ขาด S/N n` (warn), `รอติดตั้ง` (waiting), `ยังไม่ถึง` (idle), `ครบ` (ok)
  - a `เปิดบันทึก ›` button (44 pt, `TCButtonStyle` primary) that pushes `JobDevicesView(job:)`
- **Tile chip:** `S/N ขาด n` summed over the kinds, or `ครบ` when nothing is missing. Its tone is warn while anything is missing.
- **Sources:**
  - `c` is the scanned count per `DeviceKind` (`job.devices`).
  - `b` (the planned count) only where a field already holds it, for example the panel count and inverter count from the survey / IEC set-up.
  - `a` (installed) only if a source exists.
  - **Where `b` or `a` has no source, drop that part of the line** (show `S/N c` only). List what's missing in the report. Don't invent counts.
- Add a `Route` case for the devices screen only if `.detail` can't reach it. Prefer a new `case devices` that pushes `JobDevicesView`.

### 6. `-installDemo YES`
- Update `demoTiles` so the demo grid matches `states/04` and the three sheets match `states/05`–`07`, from `assets/sample-data.json`. Nothing is saved.

### 7. Tests and CLAUDE.md
- **`InstallTrackingUITests`:** add one step. On `-installDemo YES`, tap the `4.2 ขนานไฟ (กฟภ.)` tile and expect its sheet with 11 rows; tap `อุปกรณ์ที่ติดตั้ง`, then `เปิดบันทึก ›` pushes the device list, and back returns.
- **A unit test, if** the chip / tone rules of §2–§4 move into a pure function (preferred: `InstallPageData.packageChip(progress:due:today:)`). Test complete, due within 7 days, late, and waiting.
- **`CLAUDE.md`:** in the `InstallTrackingUITests` paragraph, add the new step in one sentence.

## Rules
- Colours from `Theme` only (`planInspect`, `planInspectSoft`, `success*`, `warning*`, `inkMuted`, `hairline`). No hex in views, no `Color.white`.
- Hit areas ≥ 44 pt. Buttons use `TCButtonStyle`.
- Split each card and sheet row into its own computed property or view (Debug type-check limits).
- Old job JSON must still decode. No stored field changes.
- Keep `docTiles`' order: `Daily Report`, `Weekly Report`, … `4.2 ขนานไฟ (กฟภ.)`, `อุปกรณ์ที่ติดตั้ง`, `ส่งมอบงาน`.

## Check list
- [ ] `swift test` in `TCRoofKit` passes.
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, run in the background.
- [ ] `InstallTrackingUITests` passes on an iPad simulator.
- [ ] Screenshots `01`, `04`–`08` saved to `screenshots/`:
  ```
  -screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES
  ```
  For the sheets, add `-installSheet grid|devices|handover`. For the end, add `-installScrollEnd YES`.
- [ ] Each item in the change list ticked in your report, with what was hidden for lack of a source.

## Open questions (report, don't decide)
1. `รายละเอียดงาน` is not on the board's header. Keep it, move it into a `…` menu, or drop it?
2. Does `StationDocs` carry the section number (`4.1`, `4.2`, `4.3`) per package? If not, should the title be `ขนานไฟ (กฟภ.)` without it?
3. The planned count per device kind (`b`) and the installed count (`a`): which fields hold them today, and which kinds have none?
4. Should `.waiting` also apply to the `ต้องดำเนินการ` sheet's rows and the KPI strip, or only to documents?
5. The board's KPI reads `5 เรื่อง` because more papers are due. The formula is unchanged (`due documents + open problems`). Confirm that the hand-over papers count as due within 7 days.
