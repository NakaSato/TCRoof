# Auto mounting layout from the tank (ผังโครงสร้างแผงบนหลังคาถัง)

**Status:** Draft for development, 2026-09-29
**Builds on:** tank drawing ([`tank-drawing-swift.md`](tank-drawing-swift.md), [`tank-interaction-dev.md`](tank-interaction-dev.md)),
types in [`auto-drawing-swift.md`](auto-drawing-swift.md) §8
**Interaction dev spec:** [`mount-interaction-dev.md`](mount-interaction-dev.md) · **Interactive prototype:** `prototype/mount-layout.html` · **Prototype:** `img/tank_mount.py` (run from `img/`) → `tank_mount_plan.png`, `tank_mount_section.png`, `tank_mount_front.png`
**Reference sheets (team standard):** `img/ref_mount_section.png`, `img/ref_mount_front.png`, `img/ref_mount_plan.png`

The surveyor already enters the tank (bays, vents, hatches, ladders). This feature places the PV mounting structure
on that roof automatically, using the team's tank-roof structure standard: rows of tables, posts, footings,
rails and clamps, avoiding openings. It then draws the plan, the side section and the front elevation, and counts the
materials. The surveyor enters nothing new except, where needed, the vent height and the plan's north.

![](img/tank_mount_plan.png)

| Side section (standard) | Front elevation of one table |
|---|---|
| ![](img/tank_mount_section.png) | ![](img/tank_mount_front.png) |

---

## 1. The structure standard (one set, editable in settings)

Taken from the reference sheets. Every value is printed under the drawing as มาตรฐาน / ค่าสมมติ.

| Key | Value | Meaning |
|---|---|---|
| `moduleL × moduleW` | 2.28 × 1.13 m, 600 W | module, portrait along the slope |
| `nSlope` | 2 | modules along the slope (slope length 4.58 m with a 0.02 m gap) |
| `hFront`, `hBack` | 1.00, 2.00 m | top of front / back post above the roof |
| `postDY` | 2.80 m | front post → back post (plan) ⇒ tilt = atan(1.00 / 2.80) = **19.7°** |
| `rowGap` | 2.70 m | back post of a row → front post of the next ⇒ row pitch **5.50 m** |
| `postDX` | ≤ 2.70 m | post spacing along the row (equal spacing per table) |
| `endOver` | 0.40 m | rail overhang past the end posts |
| `frontOver` | 0.46 m (slope) | front post → lower panel edge; the back overhang follows (1.15 m) |
| `rails` | 4 per table | rail clamps where each rail crosses a rafter |
| `footing` | 300 × 300 × 150 mm concrete, anchored to the slab | one per post |
| `edge`, `openClear` | 1.0 m, 0.5 m | same setbacks as the usable-area rule |
| `ventH`, `underClear` | 1.00 m, 0.10 m | vent height above the roof (0.40 + 0.60 on the sheet), clearance under the panels |
| `bracing` | X in every post bay, front and back lines | |

Derived: table plan depth = 4.58 × cos 19.7° = **4.31 m**; panel underside height at plan distance d north of the
front post = 1.00 + d · tan 19.7°.

## 2. Inputs

| Input | Source | New? |
|---|---|---|
| tank outline, bays | D1 `spansX`, `spansY` | no |
| vents, hatches, ladders, pipes | D1 `obst` (typed) | no |
| north of the tank plan | D1 `planNorth` (ด้านบน / ขวา / ล่าง / ซ้าย), default ด้านบน | **yes**, one choice describing the site |
| vent height | D1 `ventHeight` (ม.), default 1.00 (ค่าสมมติ) | **yes**, optional measurement |
| structure standard | settings (§1) | settings only |

Panels face the equator (south); rows run east–west. With north not at the top, the layout is computed in a rotated
frame and drawn back in the tank's frame.

## 3. Layout algorithm

All in metres, tank frame rotated so south is +y.

1. **Region:** roof inset by `edge`.
2. **Columns:** `n = ⌊(W − 2·edge + gap) / (moduleW + gap)⌋`, centred across the tank. Every row uses the same columns,
   so tables line up north–south.
3. **Rows** from the south edge: row k has its lower panel edge at `TH − edge − k·5.50`, front posts 0.43 m north of it,
   back posts 2.80 m further, upper panel edge 1.08 m beyond. Stop when the upper edge passes the north setback.
4. **Openings per row** (each opening grown by `openClear`):
   - **hatch** overlapping the row → the module columns over it are removed (keep access).
   - **vent** overlapping the row → if the lowest panel point above it is at least `ventH + underClear`, the vent stays
     under the panels (counted as "อยู่ใต้แผงได้"); otherwise the columns over it are removed.
   - pipes and ladders are outside the roof and do not block.
5. **Tables:** each run of at least 2 free columns is one table.
6. **Posts:** per table, `nPost = ⌈(length − 2·endOver) / postDX⌉ + 1`, equally spaced. Front and back posts share a
   rafter, so they move **as a pair**. A pair whose footing (+0.30 m) touches an opening slides along the row in
   0.05 m steps up to 1.5 m; if a slide opens a bay wider than `postDX`, a pair is added in the middle. A pair that
   cannot be placed is drawn red and listed "ต้องให้วิศวกรตรวจ".
7. **Quantities** (per table, summed): modules, kWp, posts = footings, rafters, rail length (4 × table length),
   rail clamps (rails × rafters), mid clamps (2 per module joint per module row), end clamps (2 per end per module row),
   X braces (2 per bay), ground lugs (1 per table).

Prototype result on the กปภ. 40 × 40 tank: **7 rows, 13 tables, 394 modules, 236.4 kWp**, 196 posts/footings,
98 rafters, 905 m of rail, 392 rail clamps, 736 / 104 mid / end clamps, 170 braces, 13 ground lugs; 8 vents stay
under the panels; 2 post pairs near corner vents need engineering review.

## 4. Drawings

| Sheet | Content |
|---|---|
| **Plan** (A3) | tank outline and bays (light), openings, modules as blue dashed rectangles (projected), rails, rafters, posts with footings, rail clamps (green), ground lug per table (red), north arrow, legend, quantities, notes |
| **Side section** | two rows with 2.80 / 2.70 / 2.80 and the total, post heights 1.00 / 2.00, braces, the two modules, a vent under the panels with the clearance note |
| **Front elevation** | one table: posts and spacing, X bracing, 4 rails, modules, footing note |

Footer on all: "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบนพื้นหลังคาถังกับวิศวกรโครงสร้าง".

## 5. Swift

| File | Contents |
|---|---|
| `SurveyCore/Mounting/MountStandard.swift` | the §1 values (`Codable`, in `SurveySettings`), derived tilt, depth, pitch |
| `SurveyCore/Mounting/MountLayout.swift` | `MountLayout.compute(tank: TankGeometry, std: MountStandard, north: PlanNorth) -> MountLayout` with `rows`, `tables`, `posts`, `notes`, `ventsUnder` |
| `SurveyCore/Mounting/MountQuantities.swift` | the §3.7 counts; also feeds the report and Excel BOQ |
| `SurveyCore/Mounting/MountDrawings.swift` | `plan`, `section`, `front` → `Sketch` (same `DrawingKit` as the tank) |
| `SurveyUI/Tank/MountLayoutView.swift` | a third tab next to แปลน / รูปตัด in the tank editor: **โครงสร้าง**; toggles for layers; quantities panel; tap a red post to see why |

Performance: the 40 × 40 layout is a few hundred boxes; compute with the tank geometry off the main thread.

Tests: the §3 numbers for the 40 × 40 fixture; a hatch removes exactly the columns it covers; a vent under the
back half stays, one under the front edge removes columns; post pairs never sit on an opening; bay spacing never
exceeds `postDX` unless flagged; snapshot SVGs of the three sheets.

## 6. Open questions

1. Must posts land on the tank's columns or beams (4.00 m grid) rather than anywhere on the slab? If so, the post
   spacing along the row should snap to the bay grid instead of ≤ 2.70 m.
2. Is the row gap (2.70 m) fixed, or should it follow a shading rule (e.g. no shade at 9:00–15:00 on 21 December)?
3. Walkways: does the team need a maintenance path to every hatch and between tables (width?), beyond the 0.5 m clearance?
4. Vent heights: one value per tank, or per vent (box vents vs mushroom vents)?
5. Grounding: one lug per table as drawn, plus ground plates at the tank edge (detail H) — how many and where?
