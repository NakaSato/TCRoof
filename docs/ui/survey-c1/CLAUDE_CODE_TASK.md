# Claude Code task: C1 Roof plan + structure, one-screen wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-c1/CLAUDE_CODE_TASK.md`

## Goal
The C roof module (`ModuleType.roof`, "หลังคา (แปลนและโครงสร้าง)") is still drawn by the generic `groupPage`, in four groups that scroll: แปลนหลังคา / โครงสร้าง / รูปแบบหลังคา / ภาพถ่าย. Build one designed wide page for iPad landscape that fits **on one screen with no scrolling**, like the A2/B1–B5 wide pages:

- **Left:** an interactive roof plan (grid, spans, posts, skylights, PV layout, keep-out zones) above a true-scale section A-A that changes with the frame type.
- **Right:** roof info, the member sizes 1–7, and the photo checklist.

### Reference files in this folder
| File | What it is |
|---|---|
| `preview.png` | default state, 1366 × 1024 (span popover open on grid 3–4) |
| `states/01…17-*.png` | every state; listed in "States" below |
| `preview.html` | static render of the default state |
| `iPadC1.dc.html` | **design source**: all markup, plus all drawing math and interaction logic in the `<script>` `renderVals()`. Treat it as the executable spec: plan geometry, section geometry, PV packing, member lists and defaults are all there. |
| `icons/members/*.svg` | the 21 member thumbnails (3 frame families × 7); `icons/members/INDEX.md` maps file → frame → number → name |
| `icons/profiles/*.svg` | the section-profile glyphs shown before each size (C, 2C, □, tube, wood, RC, T2, none, other) |
| `icons/photo-*.svg`, `icons/ui-*.svg` | photo slot icons (same set as `docs/ui/photo-picker`) |

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of the roof fields below, especially in:
- `Sketch.swift` (plan drawing from `spansX` / `spansY`)
- `SiteModels.swift` (A2 building models read the roof size)
- `Progress.swift`
- the PDF `ReportLayout+*` roof pages
- `ExcelExporter` (sheet "หลังคาทั่วไป R")
- `StructureSizes.swift` and `MemberPicker.swift`
- `Fields.swift` (`.plan`, `.diagram`, `.member`, `.obstacles`)

Read the source before editing.

## Existing data: do not change ids, labels or Excel cells
From `Schema.planFields(tank: false)` and `modules[.roof]`:

| Field id | Type | Use on the new page |
|---|---|---|
| `panelsBefore` | number (แผง) | "จำนวนแผง" box in the roof-info card |
| `panelsCut` | number, optional | not shown (keep it) |
| `spansX`, `spansY` | text "1.5,4,4,4,4,1.5" | the plan grid spans (x = 1…n, y = A…). Edited in the span popover and written back as the same comma string. |
| `sheetDir` | choice แนวนอน / แนวตั้ง, optional | see "ridge direction" below |
| `obst` | `.obstacles`, optional | skylights, keep-out zones and roof objects (see below) |
| `plan` | `.plan(tank: false)` | the plan itself |
| `planPhoto` | photo, optional | "ถ่ายแบบร่าง" button (hand-drawn sketch that replaces the auto plan) |
| `diag` | `.diagram` | replaced by the section A-A on this page |
| `comp1`…`comp7` | `.member(component:)` "size @spacing" | the 7 member rows (see mapping) |
| `roofShape` | choice + other | "รูปแบบหลังคา" dropdown |
| `roofMaterial` | choice + other | "วัสดุมุง" dropdown |
| `roofStructure` | choice ไม้ / โครงเหล็ก | "วัสดุโครงสร้าง" segmented control |
| `aerialPhoto` | photo | photo slot "มุมสูง ภาพรวม" |
| `generalPhotos` | photos (max 3), optional | photo slots "ด้านหน้า", "ด้านข้าง", "แผ่นมุง ระยะใกล้" |
| `structPhotos` | photos (max 4) | photo slots "ใต้หลังคา โครง", "ใต้หลังคา จุดต่อ" |

### New fields
All optional, `when: { _ in false }`, so the roof section's completion counts as before. Old JSON must decode (`decodeIfPresent` with defaults).

| New id | Type | Default | Meaning |
|---|---|---|---|
| `frameType` | text enum `p` / `n` / `w` / `c` / `r` | `p` | ชนิดโครงหลังคา: ถัก Pratt / ปกติ / ถัก Warren / ขื่อรัด (rafter + tie) / จันทันถัก (rafter truss + T2) |
| `ridgeDir` | text enum `h` / `v` | derived from `sheetDir` (sheets run across the ridge: `sheetDir` แนวตั้ง → ridge `h`), else `h` | แนวสันหลังคา นอน / ตั้ง. **Also write `sheetDir` back** (ridge `h` → `แนวตั้ง`, `v` → `แนวนอน`) so Sketch, PDF and Excel keep working. **Verify this convention against `Sketch.swift` before relying on it; if `sheetDir` means the ridge there, map 1:1.** |
| `trussBays` | number | auto = max(2, round(half-span / 1.0)) | panels per half truss (section stepper "ช่อง/ข้าง n × w ม.") |
| `postGrid` | per frame type, set of "i,j" toggles | the frame's default posts | posts added or removed in "แก้เสา" mode |
| `pvOrientation` | `p` / `l` | `p` | PV layout preview: portrait / landscape modules |
| `photoAngles` | the 6-angle checklist state | derived from photos | only if needed to know which slot a `generalPhotos` / `structPhotos` item fills (see Photos) |

Skylights and keep-out zones go into the existing **`obst`** obstacles value, extended if needed:
- **skylight**: rect in plan metres, plus `canCover: Bool` (วางทับได้ / ห้ามวางทับ)
- **keep-out**: rect in plan metres

If `obst`'s current model can't hold these, add optional properties with defaults. Never change the meaning of existing obstacle entries.

### Member rows 1–7 → `comp1`…`comp7`
The schema labels stay **แป จันทัน อเส ขื่อ ค้ำยัน เชิงชาย ดั้ง**; Excel and PDF use them. The page shows a **display name per frame type** (from `iPadC1.dc.html`, the `M` array) but always stores row *n* in `comp<n>`:

| Row | Schema label | Pratt / ปกติ / Warren | ขื่อรัด (`c`) | จันทันถัก + T2 (`r`) |
|---|---|---|---|---|
| 1 | แป | แป | แป | แป |
| 2 | จันทัน | คอร์ดบน | จันทัน | คอร์ดบน |
| 3 | อเส | คอร์ดล่าง | ขื่อรัด | คอร์ดล่าง |
| 4 | ขื่อ | ตัวตั้ง | อเส | ตัวทแยง |
| 5 | ค้ำยัน | ตัวทแยง | ตัวค้ำ | T2 รับจันทัน |
| 6 | เชิงชาย | เชิงชาย | เชิงชาย | เชิงชาย |
| 7 | ดั้ง | เสากลาง | เสากลาง | เสา |

**Flag this mapping in your summary.** The truss names don't match the schema names one-to-one, for example คอร์ดล่าง is stored in the `อเส` slot. If you find Excel/PDF readers that depend on the semantic meaning, stop and list them rather than silently re-labelling.

Size lists and defaults per frame type are in the design's `M` array: first entry `-` (ไม่มี / ไม่ใช้), then the sizes; the default index is `m[2] + 1`. Merge them with `StructureSizes` (recommended first, full catalogue in a submenu). Keep the stored format **`size @spacing`** that `MemberPicker` uses. The design row shows the size only; keep the spacing editable in the picker.

## Layout (landscape 1366 × 1024, content width 1240, no scroll)
- Header: blue gradient bar "C1 หลังคา · 1 โรงกรอง" / "แบบสำรวจ NO.224 · GRF2567-23407" (module name and job number from data).
- Step row: `10/13` with the step title "แปลนและโครงสร้างหลังคา" and the 13-capsule progress bar (shared component).
- Main grid: **left 720 / right flexible**, gap 28. The left stack is the plan card (top, about 480 tall) and the section card (bottom, about 270 tall). The right stack has three cards.
- Bottom bar: shared `cardBar`, described below.

### Left card 1: roof plan (แปลนโครงหลังคา)
Draw it with `DrawOp` / `Canvas`, shared with the PDF where possible. It sits in a 580 × 446 design viewBox, uniformly scaled to fit. The drawing order and math are in `renderVals` (`P.*` layers):

1. **Grid + dimensions.**
   - Grid lines 1…n (top bubbles, r 9) and A…m (left bubbles).
   - Two dimension chains on top: overall `19.00` plus each span; same on the left (`16.00`).
   - Ticks are 45° slashes.
   - Total length = sum of `spansX`, total width = sum of `spansY`. Scale `k = min(380/Lx, 320/Ly)`, centred.
2. **Span chips.** Each span value is a tappable chip: blue underlined text, or a filled `#E3EEF8` chip with a 1.5 pt blue outline when selected. The design chip is small, so **give each one a 44 × 44 pt hit area**. Tapping opens the **span popover**:
   - Title `ระยะช่วงกริด 3-4` (or `B-C` for y), with `ช่วงที่ i จาก n` and a close button.
   - − / value (m, 2 decimals) / + in 0.5 m steps, minimum 0.5.
   - Quick chips `1.5  3  4  4.5  6`; the current value is filled mint `#9EE6D6`.
   - `แบ่งครึ่ง` (split into two halves), `ลบช่วง` (delete; disabled when it's the only span), `ถัดไป ›` (next span; after the last x it goes to y).
   - `EQ เท่ากันทั้งแนว` (equalise; disabled if already equal) and `ทุกช่วง 4.00 ม.`.
   - A footer line with the whole chain and total, e.g. `ทั้งแนว: 1.5, 4, 4, 4, 4, 1.5 · รวม 19.00 ม.`
   - Placement: x popover under the chip, clamped inside the card; y popover to the right of the left chain.
   - States: `preview.png`, `states/16-span-popover-y.png`.
3. **`+` buttons** (blue square) at the end of each chain add a span equal to the last one and select it.
4. **Ridge.** A dash-dot line through the middle, along x if `ridgeDir = h`, else along y, with the label `สันหลังคา` (`states/06-ridge-vertical.png`).
5. **Frame lines by `frameType`**:
   - Pratt / Warren / ปกติ: double lines `T1` on each inner grid line across the ridge.
   - ขื่อรัด: rafters every 1.00 m and eave beams `อเส`, labelled `จันทัน @1.00`.
   - จันทันถัก: `T1` across plus `T2` along the inner grid.
6. **Purlins.** Thin lines every 1.0 m, parallel to the ridge.
7. **Posts.** 10 pt black squares at the frame's default grid intersections. In **แก้เสา mode** (`states/02-edit-posts.png`), every intersection shows a 22-unit circle: red if it has a post (tap to remove), dashed blue if not (tap to add). Store the result in `postGrid[frameType]`. The button label is `แก้เสา (n)`, or `เสร็จ · เสา n ต้น` while editing.
8. **Slope arrows.** Two arrows per side pointing down-slope, labelled `ลาด 15°` (30° for ขื่อรัด).
9. **Section mark A-A.** A dash-dot cut line at 42% along the ridge, heavy end bars, view-direction triangles and `A` bubbles.
10. **Skylights** (`P.sky` / `P.skyNo`):
    - Blue-filled rects. Tap to toggle **วางทับได้** (blue border) / **ห้ามวางทับ** (red dashed border).
    - Defaults are two skylights at 36% and 64% along the ridge (examples). On the real page they come from `obst`; add and edit them with the obstacle editor.

The mode toggle under the plan is `โครงสร้าง | จัดแผง`, with buttons beside it:
- `โครงสร้าง` mode: `แก้เสา (n)`, `ถ่ายแบบร่าง` (`planPhoto`).
- `จัดแผง` (PV layout) mode (`states/03…05`):
  - Hide frame lines, posts, purlins, slope arrows and their labels.
  - Pack modules on each roof face. Module size comes from the global spec default; today that is **2278 × 1134 mm, 570 W** (read the equipment catalogue, don't hard-code).
  - Edge clearances: eave 0.5 m, ridge 0.3 m, gable ends 0.5 m. Gap 2 cm.
  - Rows go along the slope: horizontal depth × cos(slope).
  - Modules that hit a keep-out zone or a no-cover skylight are drawn as dashed outlines and not counted.
  - Hint text: `84 แผง · 47.9 kWp` (computed).
  - Buttons:
    - `แผงแนวตั้ง` / `แผงแนวนอน` toggles portrait / landscape (`pvOrientation`).
    - `วาดเขตห้ามติด (n)`: drag a rectangle on the plan (at least 0.3 × 0.3 m, rounded to 0.1 m) to add a keep-out zone. Zones are hatched red with the label `ห้ามติด 4.2×3.0` and a red `×` to delete. The button label becomes `เสร็จ · เขตห้าม n` while drawing (`states/04-pv-keepout.png`).
  - This count is a **preview only**. Do not overwrite `panelsBefore` with it.

Hint text under the plan, by mode:
- default: `แตะเลขสีฟ้า/แผ่นใสเพื่อแก้`
- posts: `แตะจุดตัดกริด เพิ่ม/ลบเสา`
- keep-out: `ลากเพื่อวาดเขตห้ามติด`
- PV: the panel count and kWp

### Left card 2: section A-A (รูปตัด A-A · <frame name>)
True-scale section across the ridge, fitted to the card. The geometry is in `renderVals` (`S.*`):
- **Span**: the plan width across the ridge (`16 (จากแปลน)`). **Half-span** = span / 2. **Rise** = half × tan(slope): 15°, or 30° for ขื่อรัด. **Heel**: 0.50 m for trusses, 0 for ขื่อรัด.
- **Members by frame type**:
  - Pratt: verticals + diagonals toward the centre.
  - Warren: alternating diagonals.
  - ปกติ: king post + two struts.
  - ขื่อรัด: rafters + tie at 62% height + RC supports.
  - จันทันถัก: double chord with heel depth, zig-zag web, and 4 columns.
- **Styling**:
  - Chords and columns: thick dark outline (6 / 7 px) with a light core (3.6 / 4.4 px `#D5DBE3`).
  - Webs: 3.2 px dark with a 1.3 px light core.
  - Gusset diamonds at the nodes.
  - Corrugated roof sheet line `#1F4F78` with a ridge cap.
  - Purlin C-marks on top.
  - Fascia at the eaves; base plates and break marks at the column feet.
- **Dimensions**: the bay chain `8 × 1.00 = 8.00` each side; overall `16`; overhang `ชายคา 0.70` each side; clear height `สูงใต้ขื่อ 4.00` (or `สูงถึงหัวเสา` for ขื่อรัด); rise `R 2.14`; heel `0.50`; slope arc with `15°`.
- **Callouts** ①…⑦: red circles with leader arrows pointing at members 1–7. Their positions per frame are in the `call(...)` lines. Hide the callouts that a frame doesn't have, e.g. 5 and 7 for ขื่อรัด.
- **Footer**: the title is a link `รูปตัด A-A · โครงถัก Pratt` with `หน่วย ม.`. On the right is the stepper `ช่อง/ข้าง  −  8 × 1.00 ม.  +` (2…20, writes `trussBays`) and `อัตโนมัติ`, which clears it and is disabled when already auto.
- States: `07…10` (frame types) and `17` (12 bays).

### Right card 1: ข้อมูลหลังคา * (trailing note: `ตามแผนงาน ข้อ 1–3`)
- Row 1:
  - `รูปแบบหลังคา` dropdown → `roofShape`. The design list is ทรงจั่ว / ทรงปั้นหยา / ทรงเพิงหมาแหงน / ทรงฟันเลื่อย / ทรงโค้ง / หลังคาแบน-ดาดฟ้า, each with an English sub-label.
  - `วัสดุมุง` dropdown → `roofMaterial`: เมทัลชีท / เมทัลชีทบุฉนวน / กระเบื้องลอนคู่ / กระเบื้องคอนกรีต / แผ่นโปร่งแสง / คอนกรีต (ดาดฟ้า).
  - **Map each design option to the existing `Options.roofShape` / `Options.roofMaterial` values. Anything without an exact match is stored as `อื่นๆ` plus the other-text**, so Excel stays valid. List the mapping you chose in your summary.
  - Dropdowns: white list, selected row `#E3EEF8` with ✓ (`states/12`, `states/13`).
- Row 2:
  - `จำนวนแผง` number field → `panelsBefore`, unit `แผง`.
  - `แนวสันหลังคา` segmented `นอน | ตั้ง` → `ridgeDir` (+ `sheetDir`).
  - `วัสดุโครงสร้าง` segmented `ไม้ | เหล็ก` → `roofStructure` (ไม้ / โครงเหล็ก) (`states/14`).
- Row 3: `ชนิดโครงหลังคา` segmented with 5 options: `ปกติ | ถัก Pratt | ถัก Warren | ขื่อรัด | จันทันถัก` → `frameType`.
- Segmented style: track `#EEF2F7`; the selected segment is white with a soft shadow, bold navy text. Height at least 44 pt.

### Right card 2: ขนาดชิ้นส่วน 1–7 *
- Trailing note: `ชุดมาตรฐาน · โครงถักเหล็ก 16 ม.` (frame + material + span; computed).
- Seven rows, at least 44 pt tall, each:
  - red number
  - 67 × 36 member thumbnail (`icons/members/…`; the highlighted member in red)
  - display name
  - right-aligned profile glyph (`icons/profiles/…`, chosen from the size prefix) + size text
  - a `▾` affordance
- Size text is bold when it differs from the default, and grey for `-`.
- Tap opens the **member picker popover** (`states/11-member-picker-open.png`):
  - title `2 คอร์ดบน · เลือกขนาด` with a close button
  - options with ✓ on the current one; the first option is `-  (ไม่มี / ไม่ใช้)`
  - for rows 1–4 it opens below the row, for 5–7 above
- Values are kept per frame type in the design. On the app, `comp<n>` holds **one** value. When the frame type changes, keep the stored value if it is in the new list; otherwise leave it as is and mark the row (do not wipe user data).

### Right card 3: ภาพหลังคา * — 6-angle checklist
- Header counter: `3/6 มุม · ต้องถ่ายครบทุกมุม` (red bold), or `ครบ 6 มุมที่แนะนำ ✓` (green) (`states/15`).
- Six small photo tiles in a row:
  - filled: thumbnail, done badge, clear `×` (44 pt hit)
  - empty: dashed red, camera icon + name
- Tile names: `มุมสูง ภาพรวม`, `ด้านหน้า`, `ด้านข้าง`, `ใต้หลังคา โครง`, `ใต้หลังคา จุดต่อ`, `แผ่นมุง ระยะใกล้`. Storage:
  - มุมสูง ภาพรวม → `aerialPhoto`
  - ด้านหน้า, ด้านข้าง, แผ่นมุง ระยะใกล้ → the three `generalPhotos` (max 3)
  - ใต้หลังคา โครง, ใต้หลังคา จุดต่อ → `structPhotos` items 1 and 2. `structPhotos` allows 4; keep any extra old photos and show a `+n` chip.
- Use the shared `PhotoSlot` (`docs/ui/photo-picker`) in its compact form: Upload / Camera in a small menu on tap.
- The tiles are small, so the whole tile is the hit target (at least 44 pt).

### Bottom bar
Use the shared `InfoPageBar`, with `statusText` / `statusAlert`:
- Badge: green ✓ when all 6 angles are present, orange ! otherwise.
- Status: `ยังขาดภาพหลังคา: ด้านหน้า · ด้านข้าง · แผ่นมุง ระยะใกล้` in red, or `ปิดแอปแล้วกลับมาทำต่อได้ · ครบช่องบังคับหน้านี้แล้ว`.
- The 6-angle rule is a page warning; **do not change `Progress` completion**.
- Previous: the step before (here `B5 ปุ่ม Emergency`). Next: the next roof module or step (`C1 หลังคา 2`).

## States to match (`states/`)
| File | State |
|---|---|
| `preview.png` | default, span 3–4 popover |
| `01-span-popover-closed` | nothing selected |
| `02-edit-posts` | แก้เสา mode |
| `03-pv-layout` | จัดแผง, portrait modules |
| `04-pv-keepout` | drawing keep-out zones, 2 zones |
| `05-pv-landscape` | landscape modules |
| `06-ridge-vertical` | ridge along y |
| `07-frame-normal` | โครงปกติ |
| `08-frame-warren` | ถัก Warren |
| `09-frame-rafter-tie` | ขื่อรัด (30°, no heel, RC supports) |
| `10-frame-rafter-truss-T2` | จันทันถัก + T2 (tube members) |
| `11-member-picker-open` | member 2 picker |
| `12-roof-shape-dropdown` / `13-roof-material-dropdown` | dropdowns open |
| `14-wood-structure` | ไม้ selected |
| `15-photos-complete` | 6/6 photos |
| `16-span-popover-y` | y-span popover |
| `17-section-bays-12` | section with 12 bays per side |

## Rules
- Do not change existing field ids, labels, choice strings, Excel cells or the Excel layout. New fields are optional and hidden; roof completion is unchanged.
- Old job JSON must decode. Jobs with free-text `comp<n>` values, other-text roof shapes and existing obstacles must display unchanged.
- One screen, no scroll, at 1366 × 1024 landscape. iPad portrait and iPhone keep `groupPage`. The page must never push wider than the free space (see the A4 overflow fix).
- Every control is at least 44 pt. Use enlarged hit areas for the small plan chips and post circles.
- UI text stays Thai, exactly as in the design.
- All numbers in the previews are examples and must never be hard-coded: 19.00 × 16.00, the spans, 312 panels, 84 panels / 47.9 kWp, 4.00 / 0.70 / 2.14, member sizes, the module name.
- Plan and section drawings should be `DrawOp`-based so the PDF can draw the same plan and section (replacing the old `.diagram` image) without a second implementation.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass. Add tests:
   - old roof JSON decodes
   - editing spans writes the same comma format to `spansX` / `spansY`
   - `ridgeDir` ↔ `sheetDir` round-trip
   - `comp<n>` mapping per frame type
   - the PV packing count for a known roof matches the design math, e.g. 19 × 16, Pratt, ridge `h`, portrait 2278 × 1134 → 84 without zones
   - completion is unchanged
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add `-surveyPage roof`, open it in the simulator at 1366 × 1024 and compare with `preview.png` and every file in `states/`. Flow:
   1. Edit a span with the popover (split, delete, EQ).
   2. Add a span.
   3. Toggle the ridge.
   4. Switch all 5 frame types and check the section and member names.
   5. Edit posts.
   6. Open จัดแผง, draw and delete a keep-out zone, toggle orientation.
   7. Pick a member size.
   8. Fill all 6 photos.
   9. Export the PDF and Excel and check the roof pages and the `comp1`…`comp7` cells.
4. Summarise:
   - the files changed
   - the `comp<n>` display-name mapping
   - the roofShape / roofMaterial option mapping
   - the `sheetDir` convention you confirmed
   - anything left open
