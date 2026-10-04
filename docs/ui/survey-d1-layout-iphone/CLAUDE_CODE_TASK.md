# Claude Code task: D1 ถังน้ำใส · 3/4 จัดแผง (panel layout) on iPhone

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-layout-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels and must stay in Thai; the English in brackets is only a gloss. Numbers in the previews (416 panels, 237.1 kWp, 985 m, B1-C3, 15°) are **example data**.

## Goal
In `TankPageWide`, sub-step 3 is still the generic placeholder form. The code comments say "the section's generic groups until their designs arrive", and `formFields` case 3 only has `panelsBefore`, `panelsCut` and `planPhoto`.

The board `PhoneD1Layout.dc.html` (390 × 844) is that design for iPhone:
1. An automatic **PV panel layout** on the tank roof. It respects the obstacles confirmed in sub-step 2 and the edge clearance.
2. A **bill of materials** summary.
3. **Pre-checks** that must pass before going on.

Build it on compact width (`horizontalSizeClass == .compact`). Put the layout logic in TCRoofCore so the iPad tab and the PDF report can use it later. Keep the iPad UI working.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`):
- `TankPageWide` (`formFields`, `steps`), `TankPlan`, `Tank`, `Obstacle` and `Roof.Key.obstacles`
- `Schema` tank fields `panelsBefore` / `panelsCut` / `planPhoto`
- `PanelsPageWide` (module spec), and any existing C1 PV-layout code (`docs/ui/survey-c1`, `iPadC1`)
- `tests_for` on `Tank` / `TankPlan`

Reuse an existing layout routine if C1 already has one.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-screen.png` | First screen 390 × 844 (@3x) |
| `states/02-full-length.png` / `.pdf` | Whole sub-step scrolled out (vector PDF; measure here) |
| `states/01-screen.pdf` | Vector first screen |
| `preview.html` + `grf.css` | Static render to inspect sizes and colours |
| `PhoneD1Layout.dc.html` | Board source |
| `svg/` + `svg/README.md` | Plan drawing, icons and the drawing styles |

## Layout (page `#F5F8FB`, margins 16, gap 12)

### Header, step line and sub-step tabs
- Same as D1 1/4 and 2/4 (`docs/ui/survey-d1-size-iphone`, `…-obstacles-iphone`).
- Tabs 1 and 2 show green ✓ with green connectors; tab 3 `จัดแผง` (panel layout) is current.

### Card 1 · `การวางผังแผง` (panel arrangement)
- **Header aside:** `ตามแบบ B1-C3 · เอียง 15°` (per drawing B1-C3 · tilt 15°): the standard drawing reference and the tilt.
- **Segmented control (44 high):** two edit modes.
  - `เลื่อนผัง` (move layout): drag the whole layout and snap it to the grid. Clearance is kept.
  - `แก้แผง` (edit panels): tap a panel to toggle it off/on, and long-press a table to remove the whole table.
- **Plan** (326 × 296, frame radius 12):
  - tank outline and grid from `TankPlan`
  - panel tables in blue `#2B4FD8`
  - empty slots where obstacles or clearance block them
  - teal row guides
  - slope tag `↓ ลาดลงใต้` (slopes down to the south)
  - north arrow rotated by the D1 azimuth
  - full-screen button
  - Styles are in `svg/README.md`.
- **Caption:** `แผงโมโน 570 W · แตะแผงเพื่อแก้` (mono 570 W module · tap a panel to edit).
- **Two buttons (44+ high):**
  - `จัดแผงใหม่` (re-layout): outline. Resets to the automatic layout and asks for confirmation if there are manual edits.
  - `หาผังแผงมากสุด` (find max-panel layout): mint primary. Tries offsets and orientations and keeps the layout with the most panels.

### Card 2 · `สรุป · วัสดุโครงสร้าง` (summary · structure materials)
- **Header chip:** `416 แผง · 237.1 kWp`, green.
- **Key/value rows** (label grey 15 pt left, value navy bold right, 1 pt hairline):

| Label | Example value | Meaning |
|---|---|---|
| `แผง 570 W` | `416` | panels |
| `กำลังรวม` | `237.1 kWp` | total DC power = panels × module W |
| `แถว · โต๊ะแผง` | `7 · 40` | rows · tables |
| `เสา + โครงหน้า` | `224` | posts + front frames |
| `ฐานราก` | `224 จุด` | foundation points |
| `ราง (4 เส้น)` | `985 ม.` | rail length, 4 rails per table |
| `Mid / End clamp` | `672 / 320` | |
| `Rail clamp` | `448` | |
| `ค้ำยันไขว้` | `40 ชุด` | cross bracing sets, one per table |

- These come from the layout (tables × per-table quantities). Keep the per-table quantity rules in one TCRoofCore table with unit tests.
- If the company's BOM rules differ, leave a clear `TODO` with the assumption.

### Card 3 · `ตรวจสอบก่อนไปต่อ` (check before continuing)
- **Header chip:** `✓ 3/3` when all pass; orange `n/3` otherwise.
- **Check rows** (green ✓ circle, or orange ! when failing): title 14.5 bold, value line 13 grey.

| Check | Example | Meaning |
|---|---|---|
| `ใต้คานเหนือปล่อง (แผงทับได้)` | `0.00 ม.` | clearance above the vent beams; panels may cover |
| `ขอบถังถึงขอบแผง ≥ 1.00 ม.` | `1.00 ม.` | tank edge to panel edge ≥ 1.00 m |
| `โต๊ะเต็ม 6 × 2 / โต๊ะสั้น 3–5 คอลัมน์` | `23 / 17` | full tables are 6 columns × 2 rows; short tables are 3–5 columns; the value is the count of each |

- **Link button (outline, 44 high):** `ดูแบบ B1-C3 · ภาพตัดโต๊ะแผง · ฐานเสา` (view drawing B1-C3 · table section · post base). Opens the standard drawing (PDF in the app bundle if one exists; otherwise a placeholder).

### Bottom bar
- `บันทึก` (save) + ‹ › 72 × 53.
- VoiceOver: `ก่อนหน้า D1 2/4 สิ่งกีดขวาง`, `ถัดไป D1 4/4 ภาพถ่าย`.

## Data and logic (TCRoofCore)
- New `TankLayout`:
  - **Input:** tank size, edge clearance (default 1.00 m), the obstacles from 2/4 (ignore `absent`; vents marked "panels may cover" don't block), module size and power (default 570 W mono, portrait, from the module spec if one exists), table types (full 6 × 2; short 3–5 columns × 2), tilt 15°, row pitch, and an offset.
  - **Output:** placed tables and panels, counts, rows, kWp, the BOM quantities, and the three check results.
  - Pure, deterministic and unit-tested. `หาผังแผงมากสุด` searches offsets on a 0.05 m grid and both module orientations, and keeps the maximum.
- **Save to the tank module values:**
  - the chosen offset/orientation
  - manual on/off panel edits
  - `panelsBefore` = panel count, so the existing completion, export and step status keep working
- **Completion:** the sub-step is complete when the layout exists and all three checks pass.

## Rules
- Thai UI labels exactly as in the previews.
- Colours from `Theme` / `Home`; no new hex literals in views.
- Touch targets ≥ 44 pt.
- iPad keeps working.
- Don't change export layouts except that they now read the computed count.

## Done when
- `xcodebuild` builds the app and TCRoofKit, and tests pass. Add tests for `TankLayout` counts on the 40 × 40 preset, clearance, obstacle avoidance, the max search and the BOM.
- On an iPhone 16 simulator, D1 · จัดแผง matches `states/01` and `states/02`.
- Both edit modes, `จัดแผงใหม่`, `หาผังแผงมากสุด` and the checks all work.
- Summary of files changed, the assumptions in the BOM rules, and the remaining differences from the board.
