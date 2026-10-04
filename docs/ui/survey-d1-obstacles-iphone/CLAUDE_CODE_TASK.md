# Claude Code task: D1 ถังน้ำใส · 2/4 สิ่งกีดขวาง on iPhone

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-obstacles-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Values in the previews (8/16, 15 points, 1.2 %, 16.80 m) are **example data**.

## Goal
Today the D1 tank page's second sub-step (`TankPageWide`, `tab == 2`, groups `obst` / `plan` + `shade…`) is a generic form: an `ObstaclesEditor` list plus the shading questions.

The board `PhoneD1Obs.dc.html` (390 × 844) redesigns it for iPhone as a **verify-on-site** flow:
- The standard tank plan already shows where the vents (`V1…V10`) and access hatches (`H1…H5`) should be, generated from the tank size preset.
- The surveyor walks the roof and marks each point `มีตรงแบบ` (present as drawn) or `ไม่มีจริง` (not there).
- Points can be moved by drag or by typed distances.
- Missing ones can be added.

Build this on compact width (`horizontalSizeClass == .compact`). The iPad tab can adopt the same model later. Keep the iPad UI working as it is now.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`):
- `TankPageWide`, `ObstaclesEditor` (`Fields.swift`), `Obstacle` (`TCRoofCore/Models.swift`), `TankPlan`, `Tank`, `Roof.Key.obstacles`, `Schema` (tank groups `obst`, `plan`, `shade*`)
- `tests_for` on `Tank` / `TankPlan` / `Schema`

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-screen.png` | First screen 390 × 844 (@3x), V9 selected |
| `states/02-full-length.png` / `.pdf` | Whole sub-step scrolled out. The PDF is **vector**; measure there. |
| `states/01-screen.pdf` | Vector first screen |
| `preview.html` + `grf.css` | Static render to inspect sizes and colours |
| `PhoneD1Obs.dc.html` | Board source |
| `svg/` + `svg/README.md` | Plan, marker symbols in all 4 states, icons, and the colour table |

## Layout (page `#F5F8FB`, margins 16, gap 12)

### Header, step line and sub-step tabs
- Same as D1 · 1/4 (`docs/ui/survey-d1-size-iphone`).
- Tab 1 `ขนาดถัง` is done: green circle with ✓ and a green connector. Tab 2 `สิ่งกีดขวาง` is current.

### Card 1 · `แปลนสิ่งกีดขวาง`
- Header chip: `ตรวจแล้ว n/N`. Orange until every point is confirmed or marked absent, then green `✓ ตรวจครบ`.
- **Segmented control** (44 high):
  - `บนหลังคา · 15 จุด` (this view)
  - `เงาบัง · 1.2%`: switches the card to the existing shading questions (`shade`, `shadeFrom`, `shadeDir`, `shadeNote`) with the computed shading %, if that value exists. Otherwise show the shading answer.
- **Plan** (326 × 296, frame radius 12):
  - tank outline and grid from `TankPlan`
  - each point drawn as a symbol + label pill (`svg/marker-*`):
    - vent: square + ring
    - hatch: hatched square
  - colour by state: unconfirmed blue `#1F6FB5`, confirmed navy `#16325C`, absent red dashed `#D9453B`, selected orange with halo `#E8851A`
  - while a point is selected or dragged:
    - a teal alignment guide (`#27A99A`) when it lines up with another point
    - a distance tag (`16.80`) from the left wall
  - north arrow rotated by the D1 azimuth
  - full-screen button bottom-right
- Hint under the plan: `แตะจุดเพื่อเลือก · ลากเพื่อย้าย`.
- Legend row (11 pt): `ยังไม่ยืนยัน` · `ยืนยันแล้ว` · `ไม่มีจริง` · `จุดที่เลือก`.
- **Gestures**:
  - tap a symbol (44 pt hit area) to select it
  - drag to move it, snapping to 0.05 m and to other points' rows and columns
  - pinch / full screen to zoom

### Card 2 · `จุด <id> · <kind name>` (the selected point)
- Header chip: `ย้ายแล้ว` when the point moved from its standard position, `ตามแบบ` otherwise.
- **Point picker**: a horizontal row of chips (`‹` `V9` `H3` `H4` `H5` `›`):
  - current point is a solid orange chip; unconfirmed points are dashed blue
  - `‹` `›` step through the points that still need checking
  - each chip 44 pt high
- **`สถานะ *`**: two large choice buttons:
  - `มีตรงแบบ`: mint when on
  - `ไม่มีจริง`: danger tint when on
- **`ห่างผนังซ้าย`** / **`ห่างผนังบน`**: number fields in metres, 2 decimals, with a number-pad icon. Editing them moves the point. Use the number pad popover if the component library has it.
- **Info line** (mint box with `info.circle`): live checks, for example `แนวเดียวกับ V10 · ไม่ทับจุดอื่น`. Show a warning in orange when the point overlaps another one or falls outside the tank.
- **`เพิ่ม / แก้ไข`** (aside `กรณีไม่มีในแบบ`), 2 × 2 buttons:
  - `+ ช่องระบาย`: add a vent at the plan centre, selected
  - `+ ช่องลงถัง`: add a hatch
  - `ทำซ้ำเป็นแถว`: repeat the selected point along its row at the standard spacing; ask the count and spacing
  - `ลบจุดนี้`: destructive, with confirmation; only for points added on site. Standard points use `ไม่มีจริง` instead.

### Bottom bar
- `บันทึก` + `‹` `›` 72 × 53.
- VoiceOver: `ก่อนหน้า D1 1/4 ขนาดถัง`, `ถัดไป D1 3/4 จัดแผง`.

## Data
- Keep using `Obstacle` in `Roof.Key.obstacles` so the PDF/Excel export and `TankPlan` drawing keep working. Add what the flow needs, with backward-compatible decoding like the existing `init(from:)`:
  - `kind`: add `vent` and `hatch`. Empty still means a generic obstacle.
  - `status`: `""` unverified / `ok` / `absent`
  - `origin`: `standard` / `added`
  - the standard position, to detect `ย้ายแล้ว`
- **Standard points**: generate them from the tank preset in `TankPlan` / `Tank`. The 40 × 40 m preset gives 10 vents and 5 hatches as on the board. Put the layout table in TCRoofCore, with unit tests.
  - Generate on first open, when the obstacle list is empty.
  - When the tank size changes, keep the existing confirmation (`ตำแหน่งสิ่งกีดขวางเดิมอาจอยู่นอกแปลน`).
- **Completion**: the sub-step is complete when every standard point has a status. The `ตรวจแล้ว n/N` chip and the top `ยังขาด` line follow that.
- Absent points stay in the data with `status = absent`. Exports leave them out of the layout but list them as `ไม่มีจริง` where the report lists obstacles.

## Rules
- Thai text exactly as in the previews.
- Colours from `Theme` / `Home`; no new hex literals in views.
- Touch targets ≥ 44 pt.
- iPad stays as it is now.
- Don't change export layouts beyond honouring `status`.

## Done when
- `xcodebuild` builds the app and TCRoofKit, and tests pass (add tests for standard-point generation, status completion and backward-compatible decoding).
- On an iPhone 16 simulator, D1 · สิ่งกีดขวาง matches `states/01` and `states/02`.
- Selecting, dragging, typing distances, `มีตรงแบบ` / `ไม่มีจริง`, add, repeat-row and delete all work.
- Summary of files changed, model changes, and the remaining differences from the board.
