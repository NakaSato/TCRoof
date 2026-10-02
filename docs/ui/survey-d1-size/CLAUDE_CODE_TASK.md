# Claude Code task: D1 Clear water tank, sub-step 1/4 "ขนาดถัง" (tank size), wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-size/CLAUDE_CODE_TASK.md`

## Goal
D1 (`ModuleType.tank`, sheet "บ่อน้ำใส") is still drawn by the generic `groupPage`. Give it a designed wide page on iPad landscape. The page is split into **4 sub-steps**, shown as a tab bar:
1. `ขนาดถัง`
2. `สิ่งกีดขวาง · เงาบัง`
3. `จัดแผง`
4. `ภาพถ่าย`

**This task builds the page shell, the tab bar and sub-step 1 only.** Sub-steps 2–4 arrive in later handoffs. Until then, tabs 2–4 show the existing generic groups for those fields (`obst`; the `เงาบัง` group; the `ภาพถ่าย` group), inside the same shell.

`iPadD1.dc.html` holds the design for all four sub-steps. Read only the sub-step 1 markup and logic (`tab === 1`, `renderVals`), plus the compass modal (`azm`).

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of:
- `ModuleType.tank`, `Schema.planFields(tank:)`, and the `ข้อมูลถัง` group
- `tankType`, `tankPos`, `tankHeight`, `surface`, `soilDepth`, `spansX`, `spansY`
- `Sketch.plan(_:tank:)`, `parseSpans`, `SiteModels` (tank width × length)
- `Progress` (`case .tank`)
- the PDF section (`ReportLayout+Sections.swift`, around `ความสูงของถังน้ำใส`)
- the Excel export (`ExcelExporter.swift`: D16, J16)
- `RoofPageWide` / `RoofPageWide+Plan.swift`, whose plan drawing and span editing this page should reuse

Read the source before editing.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` / `preview.html` | default: 40 × 40 ม., กึ่งฝัง, height 4.50, exposed part 1.20, azimuth 12° |
| `states/01-size-dropdown-open.png` | the size menu: 4 presets + `+ กำหนดขนาดเอง (กว้าง × ยาว)` |
| `states/02-size-64x40.png` | 64 × 40 preset: grid 1–17 × A–K |
| `states/03-size-30x30.png` | 30 × 30 preset (6 @ 5.00) |
| `states/04-size-20x20.png` | 20 × 20 preset (5 @ 4.00) |
| `states/05-position-above-ground.png` | `บนดิน`: exposed part locked to the height (4.50, greyed) |
| `states/06-position-buried.png` | `ฝังดิน`: exposed part locked to 0.00; soil cover 0.60 |
| `states/07-roof-surface-dropdown.png` | the roof-surface menu |
| `states/08-compass-measure-modal.png` | the iPad compass modal, with the reading locked |
| `states/09-compass-saved.png` | after `บันทึกมุม`: 14° and the measured time in the source line |
| `states/10-step1-done.png` | tab 1 is complete: green check and `40 × 40 ม. · เสร็จ` |
| `iPadD1.dc.html` | design source |
| `icons/` | SVGs listed under Icons below |

## Data mapping (field ids unchanged)
| UI (Thai) | Stored as | Notes |
|---|---|---|
| `ขนาดถัง *` | `spansX`, `spansY` (existing comma strings) | A preset writes **expanded** spans, because `parseSpans` doesn't understand `n@d`. |
| `ความสูงถัง (ม.) *` | `tankHeight` (existing) | Stepper ±0.10, minimum 1.00. Stored as a plain number string, e.g. `4.5`. |
| `ส่วนพ้นดิน (ม.)` | **new optional** `tankExposed` (number, M) | See the position rules below. |
| `ตำแหน่งถัง *` | `tankPos` (existing) | Segmented: `บนดิน` / `ฝังดิน` / `กึ่งฝัง`, the exact `Schema.tankPositions` strings. |
| `ผิวหลังคา *` | `surface` (existing text) | Menu of suggestions; any text is still allowed (see below). |
| `ดินกลบลึก (ม.)` | `soilDepth` (existing, optional) | Stepper ±0.05, minimum 0. |
| `ทิศของถัง` | **new optional** `tankAzimuth` (number, degrees 0–359) | Plus optional `tankAzimuthAt` (ISO date) and `tankAzimuthSrc` (`"compass"` / `"manual"`). |
| (not shown in the design) | `tankType` (existing, required) | See "ชนิดถัง" below. |

Add the new fields to `Schema.modules[.tank]` as `optional: true` and **hidden from `groupPage`**, the same way other wide-page-only fields are hidden. Do not add them to the Excel export. The PDF may print `ทิศของถัง` only if there is already a free slot; otherwise leave the PDF unchanged.

### Size presets
| Menu label | Sub-label | spansX | spansY |
|---|---|---|---|
| `40 × 40 ม.` | `กปภ. มาตรฐาน` | 10 × `4` | 10 × `4` |
| `64 × 40 ม.` | `กปภ. ขนาดใหญ่` | 16 × `4` | 10 × `4` |
| `30 × 30 ม.` | `กปภ. ขนาดกลาง` | 6 × `5` | 6 × `5` |
| `20 × 20 ม.` | `สถานีขนาดเล็ก` | 5 × `4` | 5 × `4` |

- The 40 × 40 preset writes `spansX = "4,4,4,4,4,4,4,4,4,4"`, and so on.
- The menu shows the matching preset when the stored spans equal one exactly. Otherwise it shows `<sumX> × <sumY> ม.` with the sub-label `กำหนดเอง`. If the spans are empty, it shows the placeholder `เลือกจากรายการ`.
- `+ กำหนดขนาดเอง (กว้าง × ยาว)` opens the existing span editor from `RoofPageWide+Plan` (tap the blue dimension numbers), seeded with the current spans. Do not write a second span editor.
- Switching to a preset **replaces** the spans. If `obst` holds obstacles, first confirm with a sheet: `เปลี่ยนขนาดถัง? ตำแหน่งสิ่งกีดขวางเดิมอาจอยู่นอกแปลน`. Use a SwiftUI `confirmationDialog`, not an alert from the web layer.

### Position rules (`tankPos` drives `ส่วนพ้นดิน`)
- `บนดิน`: exposed part = the height. The stepper is disabled (greyed) and shows the height. Store `tankExposed` = `tankHeight`.
- `ฝังดิน`: exposed part = 0. The stepper is disabled. Store `0`.
- `กึ่งฝัง`: editable, ±0.10, clamped to 0…height. Default 1.20 the first time.
- When the height changes, re-clamp the exposed part.
- `ดินกลบลึก` is always editable. It is optional and doesn't depend on the position.

### Roof surface suggestions
`คอนกรีต`, `คอนกรีตเคลือบกันซึม`, `ดินปลูกหญ้า`, `หินกรวด`.
- Show them as a `Menu` with a check on the current value, plus a last item `อื่นๆ…` that turns the control into a text field.
- An old job whose `surface` holds any other text shows that text as is.

### ชนิดถัง (owner decision, flag it)
The design omits `tankType`, which is still required for completion, the PDF and Excel.
- Do **not** drop it or change its requirement.
- Put a compact `ชนิดถัง *` menu (`Schema.tankTypes`; `อื่นๆ` → `other` text) in the right panel, directly under `ขนาดถัง`, in the same field style.
- Call this out in your summary as an addition the owner should confirm.

### Tank azimuth (`ทิศของถัง`)
- The label is `ทิศของถัง`, with the aside `ผนังบน (แนว A) หันไปทิศ`. The value box shows `<az>°` plus the Thai 8-point direction name: `เหนือ`, `ตะวันออกเฉียงเหนือ`, `ตะวันออก`, `ตะวันออกเฉียงใต้`, `ใต้`, `ตะวันตกเฉียงใต้`, `ตะวันตก`, `ตะวันตกเฉียงเหนือ` (`index = round(az/45) % 8`).
- Tapping the value box allows manual entry (0–359) and sets `tankAzimuthSrc = "manual"`.
- The button `วัดด้วย iPad` (icon `d1-compass`, at least 44 pt) opens the compass modal (`states/08`). It is full screen on iPad, as a `fullScreenCover`:
  - Live camera preview (`AVCaptureSession`) with a vertical yellow guide line and the reticle `d1-aim-reticle`.
  - Header: a close button, the title `เล็งแนวผนัง A`, and the hint `ยืนที่มุม A-1 · ให้เส้นเหลืองทับขอบผนังที่วิ่งไปมุม A-17`. Name the far corner from the real grid: the last column number.
  - Top-right: the live heading pill (`CLLocationManager.headingAvailable()`; `trueHeading`, falling back to `magneticHeading`) and an accuracy chip `±n°` from `headingAccuracy`.
  - When the heading stays within ±2° for 2 s, show the locked panel: the `d1-heading-locked` icon, `ถือนิ่งครบ 2 วินาที · จับค่าแล้ว`, the formula line `แนวผนัง A <wall>° − 90° = ผนังบนหันไปทิศ`, the warning `ยืนห่างเหล็กเสริม ราวเหล็ก ท่อ ≥ 1 ม. · เกิน ±10° ให้หมุนเครื่องเป็นเลข 8`, the big result `<az>° <name>`, and the button `บันทึกมุม`.
  - Result: `az = (wallHeading − 90 + 360) % 360`.
  - When `headingAccuracy` is worse than 10° or below 0, show the warning in red and keep `บันทึกมุม` disabled.
  - On the simulator, or without a heading, show a message and a manual entry field instead of the camera.
  - Add `NSCameraUsageDescription` (it should already exist for photos) and `NSLocationWhenInUseUsageDescription` if they're missing, with Thai text.
- `บันทึกมุม` writes `tankAzimuth`, `tankAzimuthAt = now` and `tankAzimuthSrc = "compass"`.
- Source line under the field:
  - `วัดด้วยเข็มทิศ iPad · ±3° · <d/M HH:mm> · แปลนและลูกศร N หมุนตามค่านี้` for a measured value, using the real accuracy
  - `ป้อนเอง · แปลนและลูกศร N หมุนตามค่านี้` for a manual value
  - nothing when the value is empty
  - The `30/9 10:31 (ตัวอย่าง)` in the preview is an example.

## Layout (landscape, content width 1318)
Use the same shell as C1 `RoofPageWide`: the header, the 13-step progress strip with `12/13`, and the shared `cardBar` bottom bar. Use the same width source too (`min(detailSize.width, 1318 + 48) − 48`; the stacked layout below 1100 pt), so it never pushes wider than the free space.

### Sub-step tab bar
- Full width; a light `#EEF2F7` track, radius 14, height about 52 pt; four equal segments, each at least 44 pt tall.
- Each segment: a 24 pt number circle, the title (15 pt bold), and a status line (12 pt).
  - Current: white segment with a shadow; blue number circle (`d1-step-current`).
  - Done: green check circle (`d1-step-done`); status in green, e.g. `40 × 40 ม. · เสร็จ`.
  - Not done: grey number; status `ยังไม่เสร็จ` in orange.
  - Photos tab: status `บังคับ n/m`, from the required photo count in `Progress`.
- Tab 1 is done when the spans are set, plus `tankType`, `tankHeight`, `tankPos` and `surface`. The azimuth is optional.
- Store the selected tab in view state only, not in the job.

### Left card: plan drawing (flexible width)
- Draw it with **`Sketch.plan(values, tank: true)`** (the same ops as the PDF), rendered the way `RoofPageWide+Plan` renders the roof plan. Add to `Sketch.plan` only what the tank plan lacks, so the PDF benefits too:
  - grid bubbles: numbers on top (1…nX+1), letters on the left (A–K for 10 spans, as drawn; if the C1 roof plan already has a letter convention, use the same one)
  - dimension chains: each span along the bottom and the right, plus the total (`40.00`)
  - a light dashed grid and the double outline for the wall
  - the north arrow `d1-north-arrow`, top-right, **rotated by −`tankAzimuth`**; the plan itself stays with wall A on top
  - the top-right note `ผนัง ค.ส.ล. <t> · สิ่งกีดขวางระบุในขั้นที่ 2`: use `ค.ส.ล.` / `เหล็ก` / `FRP` from `tankType`; drop the thickness when it is unknown, because the `0.30` is an example
  - level tags `ระดับหลังถัง +<tankExposed>` in four quadrants; hide them when `tankExposed` is empty (the `+3.60` in the previews is an example)
  - the underlined caption `แปลนหลังคาถังน้ำใส <W> × <L> ม.`, and `หน่วย: เมตร` at the bottom-right
- Obstacles from `obst` are drawn as they already are (read-only on this tab).
- Scale to fit the card. The plan must stay fully visible at 64 × 40 (`states/02`).

### Right card: `ข้อมูลถัง` (width 330)
Top to bottom, 15 pt labels with a red `*` for required fields and asides in `Home.muted`:
1. `ขนาดถัง *` with the aside `เลือกจากรายการ`: the menu with each preset and its sub-label (`states/01`)
2. `ชนิดถัง *`: compact menu (see above)
3. Two columns: `ความสูงถัง (ม.) *` stepper | `ส่วนพ้นดิน (ม.)` stepper. Steppers are − value +, each button at least 44 × 44 pt, with the value in 16 pt bold.
4. `ตำแหน่งถัง *`: three-way segmented control; the selected segment is teal `#9FE3D3`-tinted with a teal border
5. Two columns: `ผิวหลังคา *` menu | `ดินกลบลึก (ม.)` stepper
6. `ทิศของถัง`: the value box plus `วัดด้วย iPad`, and the source line
7. At the bottom, the primary button `ถัดไป · สิ่งกีดขวาง ›`, which selects tab 2

### Bottom bar (shared `cardBar`)
- 24 pt badge: green `✓` (`d1-status-ok`) when the whole D1 module is complete, orange `!` (`d1-status-warn`) when it isn't.
- Line 1: `บันทึกอัตโนมัติ HH:mm`. Line 2: the module's status from `Progress`, e.g. `ขาโครงสร้างไม่ชนสิ่งกีดขวาง · ยังขาดภาพบังคับ 2 ภาพ` (example). If no layout check exists yet, show only the missing-photos part.
- Buttons: `บันทึกร่างตอนนี้`, previous `C1 หลังคา 2` (the real previous module), next `E1 สรุปผลและลงนาม`.

## Icons (`icons/`)
Add them to `Resources/A2Icons.xcassets` as PDF vectors and use them through `A2Icon(name:fallback:)`:

| Name | Fallback SF Symbol | Use |
|---|---|---|
| `d1-compass` | `location.north.circle` | `วัดด้วย iPad` button (template image) |
| `d1-north-arrow` | `location.north.fill` | plan N arrow; draw it as ops in `Sketch` for the PDF |
| `d1-aim-reticle` | `scope` | compass modal reticle |
| `d1-heading-locked` | `checkmark.circle` | compass locked panel |
| `d1-step-done` / `d1-step-current` | `checkmark.circle.fill` / `1.circle.fill` | tab bar |
| `d1-status-ok` / `d1-status-warn` | `checkmark.circle.fill` / `exclamationmark.circle.fill` | bottom bar badge |

`photo-done`, `photo-clear`, `ui-camera` and `ui-upload-photo` are included for tab 4; reuse the existing assets if they're already there.

## Rules
- Do not change field ids, choice strings, labels, Excel cells or the Excel layout. D1 completion counts exactly as before; the new fields are optional.
- Old job JSON must decode. A tank with empty spans shows the placeholder and an empty plan frame with the hint `เลือกขนาดถัง`. A tank with custom spans keeps them untouched until the user picks a preset.
- iPad portrait and iPhone keep `groupPage`. Route to the wide page the same way C1 does in `JobEditor.swift` (around line 257).
- Every control is at least 44 pt. UI text stays Thai, exactly as in the design.
- The job number, times, `+3.60`, `0.30`, 12°/14° and the footer texts in the previews are examples; never hard-code them.
- Heading and camera code goes behind `#if canImport(UIKit)` and `#if !targetEnvironment(simulator)` where needed, so `swift build` on macOS still passes.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass. Add tests:
   - each preset writes the expected expanded spans, and `parseSpans` round-trips them to 40 × 40 / 64 × 40 / 30 × 30 / 20 × 20
   - the preset detection: exact spans → preset; other spans → `กำหนดเอง`
   - the `tankPos` → `tankExposed` rules, including re-clamping when the height drops below the exposed part
   - `az = (wall − 90 + 360) % 360`, including wrap-around (wall 30° → 300°), and the 8-point name
   - old tank JSON (without `tankExposed`, `tankAzimuth` or `surface` from the list) decodes, and completion is unchanged
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add `-surveyPage tank`, open it in the simulator at 1366 × 1024 and compare with `preview.png` and `states/01–10`. Flow:
   1. Step through the 4 presets.
   2. Switch the position through all three.
   3. Change the height below the exposed part.
   4. Pick a surface, and enter custom text via `อื่นๆ…`.
   5. Enter the azimuth manually (the simulator has no compass) and check the N arrow rotates.
   6. Mark tab 1 complete and check the green tab.
   7. Export the PDF and check the tank plan.
4. If you have a device, test the compass modal on a real iPad.
5. Summarise the files changed, the new optional fields (`tankExposed`, `tankAzimuth*`), the added `ชนิดถัง` control (owner to confirm), and anything left open.
