# Task: iPad · D1 ถังน้ำใส · 2/4 สิ่งกีดขวาง · เงาบัง (board 26 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/survey-d1-obstacles-ipad`, then paste `PROMPT.md`, or type
> `Follow docs/ui/survey-d1-obstacles-ipad/CLAUDE_CODE_TASK.md`

- **Board:** `iPadD1Obs.dc.html` (1366 × 1024, landscape).
  - It is a large prototype that also carries code from the other D1 sub-steps.
  - **Read it as text only for this page.** Search for `subO`, `subS`, `gm`, `arr`, `snapOn`, `SO0`, `shPlay`, `shV`, `shRot` and `sunAt`.
- **Its script is a prototype, not a reference implementation. Don't port its maths**, in particular its sun, shade and loss numbers.
- **Everything on the board is example data** (`assets/sample-data.json`): the 40 × 40 tank, V9 at 16.80 / 16.40, T1 14 m, the 1.2 % loss. Never hard-code it.

## Where this sits

D1 sub-step 2 (`TankPageWide+Obstacles.swift`) is built:
- **iPhone:** `docs/ui/survey-d1-obstacles-iphone`.
- **iPad:** `padObstacleStep`. The plan card on the left, the point card on the right, and the `บนหลังคา | เงาบัง` segment.
- The shade simulation exists as `TankShade` (TCRoofCore). It is shown in sub-step 3's `เงาบัง | จำลองทั้งปี` card. It models what stands beside the tank as **long walls per compass direction** (`shadeFrom`, `shadeDir`, `shadeHeight`, `shadeDistance`).

This board redesigns **the iPad page of sub-step 2** in two parts:
- **Part A, `บนหลังคา`:**
  - a three-way status
  - moving a row or column of points together
  - an inline `ทำซ้ำเป็นแถว`
  - the legend, with undo under it
- **Part B, `เงาบัง`:** replaces the shading form fields with a shade simulation:
  - discrete objects around the tank (tree, building, water tower), placed on a plan
  - a month and time scrubber, plan and 3D views
  - a sun-path diagram
  - per-object yearly loss

Part B is the bigger piece. **Build A first, commit, then B**, so A can be reviewed alone.

## Scope: only this

**In scope:**
- `TankPageWide+Obstacles.swift`: the iPad (`!isPhone`) path of sub-step 2
- `TankPointsPlan.swift`
- `TankPoints` (TCRoofCore), for group moves and repeat
- `TankShade` (TCRoofCore), extended for discrete objects (B)
- new views for the shade simulation (B), in their own files under `Pages/Tank/`

**Do not touch:**
- the iPhone sub-step 2 (`phoneObstacleCards`)
- sub-steps 1, 3 and 4
- the header, step strip and bottom bar
- field ids, labels and Excel cells
- the PDF layout. The PDF keeps printing `TankShade`'s summary line; check it still reads right.
- the DXF
- `firestore.rules`

No refactors or renames outside the list.

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `TankPageWide+Obstacles.swift` (`padObstacleStep`, `obstacleSegment`, `pointCard`, `statusChoice`, `pointDistances`, `pointInfo`, `pointActions`, `rowSheet`, `shadeFields`, `obstacleLegend`)
- `TankPointsPlan.swift`
- `TankPageWide+Undo.swift`
- `TankPoints`
- `TankShade` and its tests
- `TankLayout+Energy.swift`
- `Schema.swift` (the tank's shade fields)
- `ReportLayout+Sections.swift` (where the PDF reads the shade)
- `TankUndoUITests`, `TankKeyboardUITests`, `TankPhotosUITests`

Then run `tests_for` on what you touch.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/01` |
| `states/01-obstacles.png` | `บนหลังคา`: V9 selected, `ย้ายตำแหน่ง` on, distances, `ย้ายพร้อมกัน จุดเดียว`, the four action tiles, the legend and `เลิกทำ` |
| `states/02-move-row.png` · `03-move-column.png` | `ย้ายพร้อมกัน` `แถว` / `คอลัมน์`: the group highlighted on the plan, and `ระยะห่างจุด` |
| `states/04-repeat-row.png` | `ทำซ้ำแถว` open in place of the point's controls: direction, count, spacing, `ยกเลิก` / `สร้าง n จุด` |
| `states/05-shade-3d.png` | `เงาบัง`, 3D view: the tank, panels, objects and their shadows, month and time, play, the sun-path diagram, loss chips |
| `states/06-shade-plan.png` | `เงาบัง`, plan view on the site picture: objects with height tags, the selected one's gap to the tank, shadows |
| `states/07-shade-june-noon.png` | The same in June at 12:00 |
| `states/08-shade-select-building.png` | B1 selected: its chip highlighted, its gap on the plan |
| `iPadD1Obs.dc.html` + `grf.css` | Design source |
| `assets/sample-data.json` | The example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### Part A: `บนหลังคา`

**A1. Point card header and progress (`states/01`)**
- Title: `ข้อมูลสิ่งกีดขวาง`, with `ตรวจแล้ว n/m` on the right.
- Under it, a 4 pt progress bar:
  - green for checked points
  - red for `ไม่มีจริง`
  - track for the rest
- Then the existing `‹ point ›` picker, unchanged.

**A2. Three-way status (`states/01`)**
- Replace `มีตรงแบบ | ไม่มีจริง` on iPad with three 56 pt tiles, each an icon over a label:

  | Tile | Icon | Selected look | Records |
  |---|---|---|---|
  | `ตรงแบบ` | ✓ | `Theme.mint` | `TankPoints.ok` |
  | `ย้ายตำแหน่ง` | move arrows | `Theme.primarySoft` with a primary border | moved (below) |
  | `ไม่มีจริง` | ✕ | danger tint | `TankPoints.absent` |

- **`ย้ายตำแหน่ง`:** use the status `TankPoints` already gives a moved point. If there is none, it is "moved" when the point differs from its design position. It shows the distances (A3); `ตรงแบบ` and `ไม่มีจริง` hide them.
- **Keep the hardware keys** (`pointKeys`): Return = ตรงแบบ, ⌫ = ไม่มีจริง.
- Report how "moved" is stored (open question 1).

**A3. Distances (`states/01`)**
- `ห่างผนังซ้าย (ม.)` and `ห่างผนังบน (ม.)` as rows of `− [value] +`, 44 pt.
  - The step is the plan's snap step (0.05 m) unless `TankPoints` has its own.
  - The value field stays typeable (`PointDistanceField`).
  - Round tanks keep their labels.
- Under them, keep `pointInfo`'s pill: `แนวเดียวกับ V10 · ไม่ทับจุดอื่น`.

**A4. `ย้ายพร้อมกัน` (`states/01`–`03`)**
- A segment `• จุดเดียว | ↔ แถว | ↕ คอลัมน์`, 44 pt. The default is `จุดเดียว`, kept per page, not stored.
- **`แถว`:** moves every live point of the same kind whose centre is on the selected point's row (same y within the snap tolerance).
- **`คอลัมน์`:** the same for the column (same x).
- Moves by drag and by the distance steppers apply to the whole group. Each change is one undo step (`TankPageWide+Undo`).
- **With `แถว` or `คอลัมน์`:** a row `ระยะห่างจุด (ม.)  − [4.00] +` sets the even spacing between the group's points, measured from the selected one.
  - Its starting value is the group's current spacing when that is even; otherwise the most common one.
- **The plan** highlights the group (selected outline on each, the line through them).
- **Core:** put the group and spacing logic in `TankPoints` (`group(of:mode:)`, `move(group:dx:dy:)`, `respace(group:spacing:)`), with tests:
  - row and column membership
  - a move keeps relative positions
  - respacing from the selected point
  - nothing leaves the tank: clamp, and report it

**A5. `ทำซ้ำแถว` inline (`states/04`)**
- The action tile opens a panel **in place of** the status and distances. It replaces `rowSheet` on iPad; the iPhone keeps its sheet.
- **Panel:**
  - title `ทำซ้ำเป็นแถว`
  - a segment `→ แนวนอน | ↓ แนวตั้ง`
  - `จำนวนเพิ่ม (จุด)  − [3] +` (1–20)
  - `ระยะห่าง (ม.)  − [4.00] +`
  - `ยกเลิก` (secondary) and `สร้าง n จุด` (primary, the count in the label)
- Reuse the copy logic `rowSheet` already uses, and add the downward direction.
- One undo step.
- Copies that would fall outside the tank are not made; report how many were skipped.

**A6. Action tiles (`states/01`)**
- Four tiles: `+ ช่องระบาย`, `+ ช่องลงถัง`, `ทำซ้ำแถว` and `ลบจุดนี้` (red).
- Each is 56 pt, an icon over a label.
- Title above them: `เพิ่ม / แก้ไข · กรณีไม่มีในแบบ`.
- `ลบจุดนี้` only for points added on site, as today.

**A7. Plan legend and undo (`states/01`)**
- Beside the plan, at the right of the plan card (as on the board), a legend:
  - `V · ช่องระบาย`
  - `H · ช่องลงถัง`
  - `จากแบบ ยังไม่ยืนยัน` (dashed)
  - `ยืนยันแล้ว`
  - `ไม่มีจริง` (red dashed)
  - `จุดที่เลือก` (orange)
  - `แนวเดียวกัน` (teal line)
  - `เว้นระยะ 0.50 ม. (จุดที่เลือก)` (red dashed halo)
- Then the hint `กดค้างแล้วลากเพื่อย้าย · ใกล้แนวจะดูดเข้าแนวเอง`.
- Then a 44 pt `↶ เลิกทำ` (the existing undo), disabled when there is nothing to undo.
- The plan already draws the alignment line and snapping. Add the 0.50 m keep-out halo around the selected point **only if `TankPoints` has a clearance value. Don't invent 0.50**; report the source.
- **Portrait (`stacked`):** the legend goes under the plan.

### Part B: `เงาบัง`

**B1. Model: discrete shade objects (TCRoofCore)**
- **`TankShade.Item`:**
  - an id (`T1`, `B1`, `W1` …, per type)
  - a type: `tree`, `building` or `tower`
  - a position in the tank frame: metres east and south of the tank's top-left corner, so outside the tank is < 0 or > size
  - a height above the ground
  - a width: canopy, footprint or tank diameter
- **Stored** as a new hidden field `shadeItems` (JSON), optional, decoded with defaults (`when: { _ in false }`).
- **Old jobs:** a job without it keeps today's long-wall objects; derive nothing.
- **Shapes for the shadow:**

  | Type | Shape |
  |---|---|
  | tree | ellipsoid crown on a trunk |
  | building | box |
  | tower | column under a cylinder tank |

  Write each shape's assumptions in the doc comment, and report them.
- **`TankShade` runs on the items when there are any:**
  - the year's loss per item and in total
  - the heat map
  - the panels shaded at a given month and time, so the UI can draw a moment
  - Keep the row-to-row shade and the clear-sky sun from `SolarModel` as today.
- **Legacy write-back** (data rule: Excel, PDF and `Progress` keep working). When items change, write:
  - `shade` = มี
  - `shadeFrom` (the types present)
  - `shadeDir` (each item's compass direction from the tank's centre)
  - `shadeHeight` (the tallest)
  - `shadeDistance` (the nearest gap to the wall)
- **Tests:**
  - an item south of the tank shades the south rows in December and not at noon in June
  - an item north of a north-facing layout loses nothing
  - per-item losses add up to the total within rounding
  - the legacy fields are written
  - an old job decodes and gives the same result as before

**B2. The shade card, left column (`states/05`–`07`)**
- **Header row:**
  - `จำลองเงาบัง`
  - a segment `แปลน | 3 มิติ`
  - the month `‹ ธ.ค. ›` (12 months)
  - the time `‹ 15:30 ›` (30 min steps, sunrise to sunset)
  - a 48 pt play button that animates the day in 30 min steps, about 4 per second, stopping at sunset or on any other tap
- **Over the picture:**
  - a caption `21 ธ.ค. 15:30 น. · ดวงอาทิตย์สูง 27° · มุม 234°`, using the 21st of the month and the sun from `SolarModel`
  - the compass
  - a full-screen button
- **Plan view (`states/06`, `07`), on `Theme.paper`:**
  - the A2 site picture under the tank when the job has one (aspect fill, slightly desaturated), else a plain ground
  - the tank outline and its panels: the stored layout, or "no layout yet" when sub-step 3 has none
  - each item: a tree as a circle, a building as a hatched square, a tower as a circle with a dot, each with an `ID · h ม.` tag
  - the selected item's outline is orange, with its gap to the tank wall (`3.0 ม.`) on a chip
  - the shadows at the chosen moment: dark for buildings and towers, lighter for trees
  - the sun's direction as a sun marker on the picture's edge
  - legend `รับแดด · เงาต้นไม้ · เงาทึบ`
- **Drag an item to move it.** A drag ends with one undo step and a re-run of the year off the main thread, as `TankShade.current` does.
- **3D view (`states/05`):**
  - orthographic, painter's order
  - the tank as a slab with its panels, and the items with their shadows on the ground and the roof
  - a rotate button (`มองจาก ตต.เฉียงใต้`, in 8 steps) and full screen
  - Draw it with SwiftUI `Canvas` from the same geometry as the plan. **No SceneKit / RealityKit.**
- **Left toolbar `+ เพิ่ม`:**
  - `ต้นไม้`, `อาคาร` and `หอถังสูง`, each 44 pt
  - each adds an item beside the tank on the nearest free side, with the type's default height and width taken from the team's tank standard if it has one. **Otherwise ask (open question 4); don't invent defaults.**
  - the new item is selected

**B3. The right column on `เงาบัง` (`states/05`, `08`)**
- **Title:** `เส้นทางดวงอาทิตย์`.
- **A polar sun-path diagram** (N up, E right, altitude rings), drawn with `Canvas` / `Sketch`:
  - the chosen month's path, orange dots, with the current moment as a sun
  - 21 มี.ค., มิ.ย. and ธ.ค. as dotted paths
  - each item's skyline as a wedge in its type colour: green tree, grey building, blue-grey tower
  - legend under it
- **One chip per item:** colour dot, id, and `−x.x%` yearly loss, in red when above 0.
  - A tap selects the item; the selected chip has an orange border.
- **The selected item's editor**, under the chips (not drawn on the board; build it simply):
  - `สูง (ม.)`, `กว้าง (ม.)`, `ห่างผนัง (ม.)` as `− [value] +` rows
  - `ลบสิ่งบังนี้`
  - Report its layout (open question 5).
- **Segment label:** `เงาบัง · <total loss>%` from the simulation, else `เงาบัง` as today.
- **The form's shade fields** (`shadeFields`): on iPad they move under a closed `ข้อมูลในแบบฟอร์ม` row at the end, so nothing is lost.

### C. DEBUG, docs and tests
- **New `-surveyD1` states** (with `-surveyPage tank -surveyWideA1 YES`), on the example tank:
  - `obstmoverow` / `obstmovecol`: `states/02`, `03`
  - `obstrepeat`: `states/04`
  - `shade3d` / `shadeplan`: `states/05`, `06`. These seed the board's five items and select T1.
  - `shadejune`: June 12:00
  - `shadeselect`: B1 selected
- **CLAUDE.md:** add them to the `-surveyD1` item in one sentence, naming `shadeItems` and `TankShade.Item`.
- **UI test:** a new `TankShadeUITests` (iPad).
  - Open `shadeplan` and tap `3 มิติ` then `แปลน`.
  - Step the time `›`; the caption changes.
  - Tap the B1 chip; it is selected.
  - `+ ต้นไม้` adds a chip.
  - In `บนหลังคา`, `แถว` then a stepper `+` moves the row (each point's distance changes by the same step), and `เลิกทำ` puts it back.
- **Existing tests must still pass:** `TankUndoUITests`, `TankKeyboardUITests`, `TankPhotosUITests`.

## Rules
- Colours from `Theme`. No hex in views, no `Color.white`. Plans on `Theme.paper`. Hit areas ≥ 44 pt. `TCButtonStyle`.
- **The simulation runs off the main thread**; the views read its last result. Playing the day only redraws the moment.
- **Vector drawing:** `Sketch` / `Canvas`, never bitmaps of icons. The site picture is the job's own photo.
- Split each card and canvas into its own view (Debug type-check limits; the tank page already erases types in places).
- Old job JSON must still decode. New fields are optional and hidden. Existing ids, labels and Excel cells don't change.

## Check list
- [ ] `swift test` in `TCRoofKit` passes, with the `TankPoints` group / repeat tests and the `TankShade` item tests. The tank golden files are unchanged for old jobs.
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, in the background.
- [ ] `TankShadeUITests`, `TankUndoUITests`, `TankKeyboardUITests` and `TankPhotosUITests` pass on an iPad simulator.
- [ ] iPad Pro 13" landscape screenshots `01`–`08` in `screenshots/`, taken with `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage tank -surveyD1 <state>`.
- [ ] The iPhone sub-step 2 is unchanged.
- [ ] `-surveyTankPDF YES` still prints the shade line; for a job with items, it reads from them.

## Open questions (report, don't decide)
1. How is `ย้ายตำแหน่ง` stored: an explicit status, or derived from the distance to the design position? What tolerance?
2. The 0.50 m keep-out around the selected point: which standard gives it (the vent's clearance in the tank standard?)?
3. Shade objects: should they also come from A2's placed symbols (buildings, trees), so the surveyor doesn't place them twice?
4. Default heights and widths for a new tree, building or water tower: per company (tank standard), or must the surveyor always enter them?
5. The selected item's editor isn't on the board. Is a stepper card under the chips right, or a popover on the plan?
6. Should sub-step 3's `เงาบัง | จำลองทั้งปี` card switch to the same item model, or stay on the long-wall model until a later task?
