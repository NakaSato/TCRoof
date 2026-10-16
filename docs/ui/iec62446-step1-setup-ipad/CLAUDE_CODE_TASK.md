# Claude Code task: IEC 62446 test, step 1/7 `ตั้งค่าระบบ` on iPad (SLD + string list) (board 15 ต.ค. 2569)

> **How to use:** check out the branch `design/iec62446-step1-setup-ipad`, open Claude Code in the repo, and paste `PROMPT.md`,
> or type `Follow docs/ui/iec62446-step1-setup-ipad/CLAUDE_CODE_TASK.md`.
> Implement on a **new feature branch** cut from this one (e.g. `feat/iec62446-step1-setup-ipad`), commit there, and push it.

- **Board:** `iPad · IEC 62446 · 1/7 ตั้งค่าระบบ (แบบ SLD · รายการสตริง)` (`iPadIECStep1.dc.html`, 1366 × 1024 pt, landscape).
  - The same board file drives all 7 steps (`step` state).
  - **This task is step 1 only.**
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** the Praek Nam Daeng station, Growatt models, S/Ns, 16 modules, 570 Wp, 34.3 °C, file names. Never hardcode it.
  - The station sample is `docs/forms/iec62446-pwa/sample-praek-nam-daeng.json`.

## Prerequisite: check this first
- The IEC test feature was started from `docs/ui/iec62446-test`. On the owner's Mac it lives in **files that may not be in git yet**:
  - `TCRoof/Views/Install/IEC/` (`IECTestScreen`, `IECSetupSheet`, `IECStringGrid`, `IECStringEntry`, `IECPhotos`, `IECPerformancePage`, `IECShared`)
  - `TCRoofKit/Sources/TCRoofCore/IECReport.swift`, `IECReport+Form.swift`
- **Before writing code, check that these exist in your checkout.**
  - **If they are missing, stop and report.** The owner must push them first. Do **not** recreate a second `IECReport` model from scratch.
  - If they exist, this task **replaces `IECSetupSheet`** (a system `Form`) with the step-1 page below and keeps `IECReport` as the data.

## Scope: change only this list
1. A full-page **step 1** of the IEC wizard on iPad. It is the first page of the test flow, and it is where `IECTestScreen`'s `ตั้งค่า` / `ตั้งค่าการทดสอบ` goes.
   - **Frame:** header, `1/7` progress bar, two columns, bottom bar.
   - **Left column:** SLD diagram card, test date / tester, test conditions, instruments.
   - **Right column:** string list per inverter, with add, delete and S/N.
2. **The `เพิ่มอินเวอร์เตอร์` sheet** (`states/03`) and **the delete confirmation** (`states/04`).
3. **Rules:**
   - string slots = MPPT × 2
   - used / `SPARE`
   - modules per string
   - totals
   - the Excel cells each field fills (from `docs/forms/iec62446-pwa/excel-cell-map.json` / `docs/specs/iec62446-excel-export-swift.md`)

**Do not touch:**
- steps 2–7 (their own boards will come as separate hand-offs). `ถัดไป` goes to the existing next screen (`IECStringGrid`, phase before), and the button keeps the board's label.
- the iPhone
- the Excel exporter's cell map (use it, don't change it)
- `IECReport` stored fields: add optional ones only, decoded with `decodeIfPresent`
- the install tracking page

**Before editing:** use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep.
- Look at: `IECReport` (inverters, string slots, module, record/instruments), `IECSetupSheet`, `IECTestScreen`, `IECStringGrid`, `IECShared` (`IECHeader`, `IECHeaderButton`)
- Look at: the Excel export spec, and `TCCountSegments` / the stepper and toggle components in `TCRoofUI`
- Then run `tests_for` on what you touch.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01` (@2x) |
| `states/01-setup-inv1.png` | Step 1, `Inverter 1` (125 kW, 10 MPPT, 16/20 strings) |
| `states/02-setup-inv2.png` | `Inverter 2` tab (60 kW, 6 MPPT, 8/12) |
| `states/03-add-inverter.png` | The `เพิ่มอินเวอร์เตอร์` sheet: model list, S/N + scan, MPPT from the model, modules per string, required photos |
| `states/04-delete-inverter.png` | `ลบ INV1 ?` confirmation with what will be removed |
| `states/05-sn-edit.png` | The S/N field in edit mode |
| `states/06-string-set-spare.png` | A string slot switched off → `SPARE`, totals updated |
| `iPadIECStep1.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule (`INVB0`, `AIM`, `NS`, `mkStrs`, `conds`, `tools`, `totals`) |
| `assets/iec/inv-125k.jpg` · `sld-inv1.png` · `sld-inv2.png` | The board's example inverter photo and SLD pages, for rendering only, **not for the app bundle** |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. Frame (`states/01`)
- **Header**, blue gradient, bottom radius 15:
  - `IEC 62446 · ตั้งค่าระบบ`, 22 pt bold
  - station line: `<station> · <kWp> kWp`, 15 pt
  - use `IECHeader`
- **Progress:** `1/7` on the left and the step name `ตั้งค่าระบบ` on the right, 15 pt.
  - 7 capsules, 8 pt high; current = primary gradient, others grey.
  - The step names, for the label and later steps: 1 ตั้งค่าระบบ · 2 ก่อนออน · แรงดัน / กระแส · 3 … (read `B3`/step titles in the board script).
- **Body:** two columns, 24 pt margins.
  - left 420 pt (scrolls)
  - right, the rest: one white card, radius 16
- **Bottom bar**, white with a top shadow, 53 pt buttons, as `grf.css`'s compact bar:
  - **left:** status icon + text, e.g. `แนบแบบ SLD และตั้งรายการสตริงแล้ว · ยังไม่ได้กรอกวันที่ ผู้ทดสอบ และ S/N เครื่องมือ`. The text is built from what's missing.
  - `บันทึกร่างตอนนี้`, outlined
  - `‹ กลับ` with the sub label `งานติดตั้ง`, outlined: pops back to where the test was opened
  - `ถัดไป 2/7` with the sub label `ก่อนออน · แรงดัน / กระแส ›`, primary
  - **`ถัดไป` is enabled only when step 1 is complete:** SLD attached, date, tester, ≥ 1 inverter with ≥ 1 used string. Otherwise it is disabled and the status text says what's missing.

## 2. Left column (`states/01`, `05`)
- **Status banner**, orange soft fill, radius 12:
  - title `ระบบยังไม่ออน · ตั้งค่าก่อนเริ่มวัด`
  - sub line: the cells it fills, `แนบแบบ SLD และตรวจรายการสตริง · เติม E5, O5, แถว 8–9`
- **`Diagram` card:**
  - **Preview:** the attached SLD page (PDF first page or photo), 16:10, with chips `หน้า n/m · Inverter k` and `แตะเพื่อดูเต็มจอ · ซูมได้`. Tapping it opens it full screen with zoom.
  - **File row:** `PDF` tag, file name (one line), `v<n> · <date · time>`. Re-uploading keeps the old versions, and a `ประวัติ n ครั้ง` link shows them.
  - **Buttons:**
    - `ดูแบบ` (outlined)
    - `อัปโหลด PDF` (outlined): a file importer for PDF or image, which you can also photograph
    - `อ่านรายการสตริง` (primary): reads the inverter / string count from the SLD **if a reader exists. If not, show it disabled and report it (open question 1).**
  - Store the SLD as a job attachment in the job's IEC folder.
- **`วันที่ทดสอบ *` and `ผู้ทดสอบ *`:** two fields side by side (dashed border when empty). Date picker; the tester name defaults to the signed-in user.
- **`สภาพการทดสอบ`:**
  - three tiles: `อากาศ · E29` °C, `แสง · E30` W/m², `เวลา · AA30` น.
  - right label: `ก่อนออน · INV 01 ลิงก์ไปทุกแผ่น`. The values are entered once and linked to every inverter's sheet, as the Excel spec says.
  - Fill the values from the weather station or manual entry, as the existing IEC code does.
- **`เครื่องมือวัด (S/N)`:** rows `แคลมป์มิเตอร์ · เครื่องวัดฉนวน (IR) · เครื่องวัดแสง · กล้องความร้อน`.
  - Each row shows the value or `ยังไม่ระบุ`, plus a `สแกน` link (camera / barcode).
  - Right label: `ฟอร์มเดิมไม่มี · แนะนำให้เก็บ`. These are **new optional fields** that the Excel form doesn't have; keep them in `IECReport`.
  - If the tools register (`ToolsView` / `InstrumentStore`) has these instruments, offer them as a picker.

## 3. Right column: `รายการสตริง (String list)` (`states/01`, `02`, `05`, `06`)
- **Inverter tabs**, one per inverter, equal width, 54 pt, radius 12:
  - `Inverter n` 17 pt bold + `<kW> kW`, and on the right `used/slots สตริง`
  - selected = 2 pt primary border
  - the last tab is a dashed `+ เพิ่มอินเวอร์เตอร์`, which opens section 4
- **Inverter row:**
  - photo thumbnail
  - `รุ่นอินเวอร์เตอร์` + model, 17 pt bold
  - the `S/N` field (`states/05`: 2 pt primary border while editing)
  - `สแกนป้าย` (primary, camera icon): reads the S/N from a nameplate photo. Use the photo text reader (`DeviceCaps` / Vision) the survey already uses for nameplates. If none fits, open the camera and let the user type.
  - a red-outlined delete button → section 5
- **String grid:** two columns of MPPT groups, `MPPT n` label 13 pt, two string rows per MPPT.
  - Slots = **MPPT × 2** (125 kW 10 MPPT → 20, 60 kW 6 MPPT → 12).
  - **A used row:** `String k` 16 pt bold · a stepper `− n +` (modules per string) · `<n × module Wp> Wp` · a toggle (on).
  - **An unused row:** grey text, the `SPARE` chip, `ไม่มีสตริง`, toggle off.
  - Toggling updates the totals immediately.
- **Totals strip:**
  - `สตริงที่ใช้ used / slots ช่อง`
  - `แผงรวม n แผง`
  - `กำลังติดตั้ง (AA9) n Wp`, which is Σ modules × module Wp
- **Excel:** each inverter is its sheet pair `INV nn-ก่อน / -หลัง`. Model / S/N → the cells in the cell map (O5 …), strings → rows 8–9.
  - **Follow `excel-cell-map.json`.** Do not invent cells, and report any field without a cell.

## 4. `เพิ่มอินเวอร์เตอร์` sheet (`states/03`)
- **Modal**, 1100 pt wide, radius 24.
- **Header:** chip `INVn` (next number), `เพิ่มอินเวอร์เตอร์`, `ข้อมูลจากป้ายพิกัด`, close.
- **`รุ่นอินเวอร์เตอร์ *`:** a 2-column list of radio cards. Each card: photo, model 17 pt bold, `<kW> kW · <MPPT> MPPT · <inputs> ช่อง`.
  - The catalogue: **use the app's equipment catalogue (`EquipmentCatalog`) if it has inverters with MPPT counts; otherwise the board's `AIM` list is the example.** Report which you used.
- **Three fields:**
  - `S/N` (type, or `สแกนป้าย`; note `ใส่ภายหลังได้`; the cell `O5 · แผ่น INV nn`)
  - `MPPT`, read-only from the model (`n MPPT · 2n ช่อง DC input`)
  - `แผงต่อสตริง`, a stepper, with `<Wp> Wp ต่อสตริง`
- **Info box:** `เพิ่มแท็บ INVn ในรายการสตริง (ทุกช่องเริ่มเป็นสตริง n แผง แล้วตั้ง SPARE ช่องที่ไม่ได้ใช้) · Excel เพิ่มแผ่น INV nn-ก่อน และ INV nn-หลัง ที่ลิงก์หัวเรื่องจาก INV 01`.
- **`รูปอินเวอร์เตอร์ *`:** five photo slots.
  - **required** (orange dashed): `ด้านหน้า`, `ด้านข้าง · ป้าย S/N`
  - optional: `ด้านข้างอีกด้าน`, `ด้านหลัง`, `ด้านล่าง · ขั้วต่อสาย`
- **Buttons:** `ยกเลิก`, and the primary button.
  - The primary button is disabled with the text `ถ่ายรูปด้านหน้าและป้าย S/N ก่อน` until both required photos exist; then it reads `เพิ่ม INVn`.
- **On add:** a new tab with every slot used at the chosen modules per string, then selected.

## 5. Delete confirmation (`states/04`)
- **Modal:** red trash icon, `ลบ INVn ?`, and `INVn · <model> · S/N <sn> จะถูกนำออกจากงานนี้`.
- **The bullet list:** strings and measured values (with photos) removed; Excel loses `INV nn-ก่อน / -หลัง` and the rest renumber; `ลบแล้วกู้คืนได้จาก "ประวัติการแก้ไข" ของงาน`.
  - **Only promise the restore if the job keeps an edit history** (review lock / REV). Otherwise drop that line and report it.
- **Buttons:** `ยกเลิก` and the red `ลบ INVn`. Deleting the last inverter is not allowed (the button is disabled).

## DEBUG
- `-screen iec -iecStep 1` opens step 1 on the first installing job.
- `-iecDemo praek` seeds `docs/forms/iec62446-pwa/sample-praek-nam-daeng.json`, or the existing `iec-demo-praek-nam-daeng.json`.
- `-iecSheet add|delete|sn` opens the sheets.
- Add them to CLAUDE.md.

## Check
- [ ] The prerequisite files exist (or you stopped and reported).
- [ ] Build with your own `-derivedDataPath`. Run `swift build` + `swift test` in `TCRoofKit/` (add tests for: slots = MPPT × 2, the totals, the add / delete renumbering, and old `IECReport` JSON still decoding).
- [ ] Run on an iPad Pro 13" simulator, landscape. Compare with `states/01`–`06` and note any difference larger than 4 pt.
- [ ] `ถัดไป` is enabled only when complete. The bottom status text names what's missing.
- [ ] The Excel export still fills the same cells, and new inverters add their sheet pair.
- [ ] Simulator screenshots 01, 03, 04 and 06 are in `docs/ui/iec62446-step1-setup-ipad/screenshots/`.
- [ ] Commit on your feature branch and push it. Do not merge to `main`.

## Open questions (report, don't decide)
1. `อ่านรายการสตริง`: is there a way to read strings from the SLD PDF? If not, should it stay hidden until there is?
2. The inverter catalogue: `EquipmentCatalog` or a new list? And who maintains MPPT counts?
3. Instrument S/Ns are not in the original Excel form. Should they go into the Word report only?
4. Is a delete restorable (edit history), or final?
