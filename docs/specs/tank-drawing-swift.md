# D1 ถังน้ำใส — tank drawing and survey flow, Swift feature spec (iPad + iPhone)

**Status:** Updated 2026-10-01 to match the D1 design in the TCRoof canvas (five pages: `iPadD1` ขนาดถัง, `iPadD1Obs` สิ่งกีดขวาง, `iPadD1Layout` จัดแผง, `iPadD1Shade` เงาบัง, `iPadD1Photo` ภาพถ่าย)
**Design rules and drawing standard:** [`auto-drawing.md`](auto-drawing.md) §5–§7
**Types and code detail:** [`auto-drawing-swift.md`](auto-drawing-swift.md) §8 Tank, §9 UI, §10 PDF, §11 tests
**Mounting layout algorithm (step 3):** `tank-mounting-layout.md` on branch `spec/tank-mounting-layout`. This spec gives only the D1 behaviour and the numbers the design uses.
**Older visual reference:** `img/tank_pwa.png` (64 × 40), `img/tank_40x40.png` (40 × 40), `prototype/tank-layout.html`. Still valid for the plan's drawing style.
**Targets:** `TCRoofKit` in the TCRoof app, iOS 17+, iPad and iPhone
**New dependencies:** none

## What changed from the 2026-09-29 draft

| Draft | Now (D1 design) |
|---|---|
| tank size from `spansX` / `spansY` typed as `16@4` | pick a **standard tank** (40 × 40, 64 × 40, 30 × 30, 20 × 20) which fills size and column grid, or **custom width × length** (`tankWidth`, `tankLength`) |
| round tank (`tankDiameter`) in the form | not in the D1 design; `tankDiameter` stays optional in the model for later |
| `tankType` (ชนิดถัง) | removed from the page (existing answers are kept) |
| `tankAboveGround` always asked | asked only when `tankPos` = กึ่งฝัง; บนดิน = height, ฝังดิน = 0 |
| `surface` free text | `roofSurface` choice: คอนกรีต / คอนกรีตเคลือบกันซึม / ดินปลูกหญ้า / หินกรวด |
| no orientation | `tankAzimuth`: the direction wall A faces, measured with the iPad compass and camera; the plan and N arrow rotate by it |
| vents placed by tapping bay cells, hatches by wall + distance | openings come **pre-placed from the standard tank's drawing**; the surveyor confirms each one (ตรงแบบ / ไม่มีจริง), drags it if it moved, or edits its distances from the walls; can add, duplicate as a row, delete, undo |
| ladders, pipes, `ventStyle`, section marks as inputs | not in the D1 design v1 (kinds stay in the model; old data still draws) |
| usable area (green raster, m² ÷ 6 = kWp) | replaced by the real **panel layout** in step 3: tables, posts, cut columns, panel count, kWp, energy |
| one page with a drawing card | five steps on one D1 page, each with a done state |

## 1. The D1 page

The page has five step tabs across the top. Each tab shows its number, which becomes ✓ when done, its name, and a one-line status under the name:

| # | Tab | Status line when done | Status when not done |
|---|---|---|---|
| 1 | ขนาดถัง | size, e.g. `40 × 40 ม. · เสร็จ` | `ยังไม่เสร็จ` (orange) |
| 2 | สิ่งกีดขวาง | `{n} จุด · เสร็จ` | same |
| 3 | จัดแผง | `{panels} แผง · {kWp} kWp · เสร็จ` | same |
| 4 | เงาบัง | `สูญเสีย {x}% · เสร็จ` | same |
| 5 | ภาพถ่าย | `บังคับ {k}/9` | same |

- A step is marked done when the surveyor presses its `ถัดไป · … ›` button.
- Each step also has `‹ …` to go back.
- The tabs can be tapped in any order.

**Layout on iPad landscape:**
- Left: the drawing for the step, a 610 pt square plan.
- Right: the step's panel, styled like the `ข้อมูลถัง` panel.
- Bottom bar, as on the other pages:
  - autosave time
  - one status line, e.g. `ขาโครงสร้างไม่ชนสิ่งกีดขวาง · ยังขาดภาพบังคับ 3 ภาพ`
  - `บันทึกร่างตอนนี้`
  - `‹ ก่อนหน้า 11/13 C1 …`
  - `ถัดไป 13/13 E1 สรุปผลและลงนาม ›`

**Plan drawing (all steps):**
- กปภ. style: double wall, dashed column grid, dimensions, openings with IDs (`V1…`, `H1…`).
- A north arrow rotated by `tankAzimuth`.
- Walls named A (top) and 1… along the sides, as on the standard drawing.

### Step 1 — ขนาดถัง

Panel `ข้อมูลถัง`:

| Control | Field | Behaviour |
|---|---|---|
| `ขนาดถัง *` dropdown | `tankTemplate` | Picks a standard tank or custom, see the table below. Choosing a template writes `tankWidth`, `tankLength`, `spansX`, `spansY` and seeds the openings (step 2) if the job has none. `+ กำหนดขนาดเอง (กว้าง × ยาว)` shows two number fields. |
| `ความสูงถัง (ม.) *` | `tankHeight` | stepper 0.10, min 1.00 (design default 4.50) |
| `ตำแหน่งถัง *` | `tankPos` | บนดิน / ฝังดิน / กึ่งฝัง (existing field) |
| `ส่วนพ้นดิน (ม.)` | `tankAboveGround` | stepper 0.10, clamped to 0…height. Enabled only for กึ่งฝัง, and shows the derived value otherwise. |
| `ผิวหลังคา *` | `roofSurface` | dropdown of the four surfaces |
| `ดินกลบลึก (ม.)` | `soilDepth` | stepper 0.05 (existing field) |
| `ทิศของถัง` | `tankAzimuth`, `tankAzimuthSource` | shows `ผนังบน (แนว A) หันไปทิศ {az}° {direction name}` and a small N rose; button `วัดด้วย iPad` (see below); source line `วัดด้วยเข็มทิศ iPad · ±3° · {date time} · แปลนและลูกศร N หมุนตามค่านี้` |

Standard tanks. Areas and capacities are shown in the dropdown and on the plan.

| `tankTemplate` | Label | Size | Column grid | Roof area |
|---|---|---|---|---|
| `t40` | กปภ. มาตรฐาน | 40 × 40 m | `10@4` × `10@4` (9 × 9 columns) | 1,600 m² |
| `t64` | กปภ. ขนาดใหญ่ | 64 × 40 m | `16@4` × `10@4` | 2,560 m² |
| `t30` | กปภ. ขนาดกลาง | 30 × 30 m | `6@5` × `6@5` | 900 m² |
| `t20` | สถานีขนาดเล็ก | 20 × 20 m | `5@4` × `5@4` | 400 m² |
| `custom` | กำหนดขนาดเอง | `tankWidth` × `tankLength` | `spansX` / `spansY` if typed, else one bay | W × L |

The template grids above are taken from the design. Confirm them against the กปภ. standard drawings (open question 1).

**Measuring direction (`วัดด้วย iPad`):**
1. A 960 × 720 pt sheet opens with the live camera.
2. The prompt reads `เล็งแนวผนัง A` / `ยืนที่มุม A-1 · ให้เส้นเหลืองทับขอบผนังที่วิ่งไปมุม A-…`.
3. A yellow guide line and the live compass heading are shown.
4. The surveyor stands at corner A-1 and aims along wall A.
5. `บันทึก` stores `tankAzimuth = heading − 90°` (the outward normal of wall A), rounded to whole degrees, with the time in `tankAzimuthSource`.
- Accuracy is shown as ±3°.
- A manual override is allowed by typing the degrees.
- Use `CLLocationManager` heading with `trueHeading` when available, else magnetic heading, and store which one was used.

### Step 2 — สิ่งกีดขวาง

The plan shows every opening. Style shows its status:

| Status (`status`) | Label | Drawn |
|---|---|---|
| `pending` | จากแบบ ยังไม่ยืนยัน | dashed blue, 75 % opacity, blue ID tag |
| `ok` | ตรงแบบ | solid black |
| `moved` | ย้ายแล้ว | solid black (set automatically when dragged or its distances are edited) |
| `absent` | ไม่มีจริง | dashed red, 40 % opacity; ignored by the layout |

- **Legend and undo:** the legend `สัญลักษณ์` (จากแบบ ยังไม่ยืนยัน / ยืนยันแล้ว / ไม่มีจริง) and `↶ เลิกทำ` sit in a column to the right of the plan.
- **Selection:** the selected opening has an orange 3 pt border and an orange tag.
- **Drag:**
  - While dragging, a loupe follows the finger with the distances, e.g. `ซ้าย 16.80 · บน 16.40 ม.`.
  - Positions snap to 0.05 m and stay inside the walls.
  - One drag is one undo step. Undo keeps the last 30 steps.
- **Sizes:** vent 1.45 m, hatch 1.15 m (from the standard drawing; shown as ค่าสมมติ in the plan notes).

Panel `ข้อมูลสิ่งกีดขวาง`:
- **Progress:** `ตรวจแล้ว {n}/{m}` with a green / red / grey bar, and `ยังไม่ตรวจ {k} จุด`.
- **Selected opening:**
  - `‹` `{ID}` `{type name}` `›`. The arrows jump to the previous / next pending opening.
  - `สถานะ *`: `มีตรงแบบ` / `ไม่มีจริง`, with the current status text.
  - Distances from the **nearest** walls: `ห่างผนังซ้าย|ขวา (ม.)` and `ห่างผนังบน|ล่าง (ม.)`, steppers of 0.05.
  - A check line: `✓ ไม่ทับสิ่งกีดขวางอื่น`, or `⚠ ใกล้ {ID} น้อยกว่า 0.50 ม.`.
- **`เพิ่ม / แก้ไข`** (aside `กรณีไม่มีในแบบ`):
  - `+ ช่องระบาย` / `+ ช่องลงถัง`: adds one near the centre with the next free ID, status `moved`, and selects it.
  - `⧉ ทำซ้ำเป็นแถว`:
    - direction `→ แนวนอน` / `↓ แนวตั้ง`
    - `จำนวนเพิ่ม (จุด)` 1–20
    - `ระยะห่าง (ม.)`: min 1.50, step 0.50, default 4.00
    - `สร้าง {n} จุด` / `ยกเลิก`
  - `ลบจุดนี้`
- **Seeding:** when a template is chosen and the job has no openings, the template's openings are added as `pending`. The 40 × 40 design seeds V1–V10 and H1–H6. Each template needs its own list (open question 2).

### Step 3 — จัดแผง (panel layout)

The step places PV tables on the roof automatically. The full algorithm is in `tank-mounting-layout.md`.

**Plan:**
- Tables: blue, gridded by panel.
- Posts: black dots. A post that had to shift is orange, with its original spot as a red dashed square.
- Cut columns and openings.
- A slope arrow per row, and `ลาดลง {direction}`.
- Legend `สัญลักษณ์`: โต๊ะแผง / เสา / ฐาน / เสาเลื่อนหลบ (เมื่อชน) / ช่องตัดหลบขา / สิ่งกีดขวาง / ทิศลาดลงของแผง.

**Rules used by the design prototype.** These are the design's numbers; the mounting spec holds the team standard.

| Rule | Value |
|---|---|
| edge setback | 1.00 m |
| panel width along the row | 1.13 m, 2 panels up the slope per column, 600 Wp |
| table depth / row pitch | 4.30 m / 5.50 m |
| posts | front at 0.75 m and back at 3.55 m into the table; every 2.26 m along the row (2 columns); 0.40 m overhang at both ends; a last post within 1.0 m of the end post is dropped |
| post footprint / clearance | 0.40 m square; 0.30 m clear of any opening |
| hatch access | no panel within 0.60 m of a hatch |
| post clash | shift along the row in 0.10 m steps up to ±0.80 m; if still clashing, cut that column (the table splits; a piece shorter than 2 columns is dropped) |
| slope direction | panels face the wall side closer to south, from `tankAzimuth` |

**Panel:**
- `ภาพตัดโต๊ะแผง`: the section of one table (front and back post heights, panel angle, low side), with the low side named by direction.
- `หมายเหตุ`: generated notes, e.g. which row was cut beside which vent.
- `การวางผัง`:
  - `เลื่อนแนวแถวไปทางเหนือ {m} ม.` (step 0.10)
  - `เลื่อนแนวแผงไปทางตะวันออก {m} ม.` (step 0.05)
  - `จัดแผงใหม่`
  - `⚡ หาผังแผงมากสุด`: searches offsets north 0–5.4 m × east 0–1.1 m for the most panels; ties go to the fewest shifted posts. Afterwards it shows `✓ ผังดีที่สุด {n} แผง (+{gain})`.
- `สรุปผลการจัดแผง` (aside `พลังงานเป็นค่าประมาณ`):
  - แผง, กำลัง (kWp = panels × 0.6)
  - พลังงาน/ปี, kWh/kWp (design uses 1,452 kWh/kWp, to be replaced by a real estimate)
  - เงาแถวหน้า %
  - โต๊ะแผง, เสา / ฐาน
  - ราง (m = Σ table length × 4)
  - ช่องตัดหลบขา
  - ขาชนสิ่งกีดขวาง (must be 0)
  - อินเวอร์เตอร์ (from B2), DC/AC
- `ตรวจสอบก่อนไปต่อ`: roof load `{x} / 150 kg/m²`, maintenance walkway ≥ 0.60 m, edge setback ≥ 1.00 m, and `เสาเลื่อนหลบสิ่งกีดขวาง {n} ต้น`.

The design's default 40 × 40 sample gives 426 panels / 255.6 kWp. The optimiser finds a better north offset (5.2 m) with 4 shifted posts. Use this as a regression fixture once the mounting spec's numbers are final.

### Step 4 — เงาบัง

**Left: `จำลองเงาบัง`.**
- Shadow snapshots on the plan for 21 มี.ค., 21 มิ.ย. and 21 ธ.ค. at two times each.
- A heat map `สัดส่วนแผงที่โดนเงา รายเดือน × รายชั่วโมง`. Legend: ไม่มีเงา / เงา 25% / ≥ 50% / กลางคืน.

**Right: `สิ่งที่บังแดด`.**

| Control | Field |
|---|---|
| `มีเงาบังพื้นที่ติดตั้งหรือไม่ *` | `shade` (existing): ไม่มี / มี |
| `สิ่งที่บัง` | `shadeFrom` (existing): ต้นไม้ / อาคาร / หอถังสูง / อื่นๆ |
| `ทิศที่เงาบัง` | `shadeDir` (existing): N … NW |
| `ความสูง (ม.) *` | `shadeHeight` (new, when shaded) |
| `ห่างผนังถัง (ม.) *` | `shadeDistance` (new, when shaded) |

- **Results:**
  - `เงาแถวหน้า %`, `เงาต้นไม้ %`, `สูญเสียรวม %`
  - `MWh/ปี ที่เสียจากต้นไม้`
  - one recommendation line, e.g. trimming below 5 m removes the tree shade; it is recorded as a proposal for E1
- **Old notes:** the existing `shadeNote` stays; old jobs show their note until height and distance are entered.

### Step 5 — ภาพถ่าย

Photo groups. Required ones are counted in `บังคับ {k}/9`; a required slot that is empty has a red frame.

| Group | Slots | Field |
|---|---|---|
| ภาพมุมสูง (โดรน หรือ Google Maps) | 1 required | `aerialPhoto` (existing) |
| ผนังถัง 4 ทิศ (ใช้วางแนวรางสายไฟ) | 4 required: N / S / E / W | `sidePhotos` (existing, max raised from 3 to 4, labelled by direction) |
| หลังคาถัง (ภาพรวม + ผิวหลังคา) | 2 required | `roofPhotos` (new) |
| เงาบัง (ถ่ายจากกลางหลังคา) | 1 required | `shadePhoto` (new) |
| ทางเดินสายไฟ (จากถังถึงห้อง Inverter) | 1 required | `cablePhoto` (new) |
| สิ่งกีดขวาง (ไม่บังคับ · ผูกรหัสได้) | any | `obstPhotos` (existing). Each photo can be tagged with an opening ID (`V9`, `H1`, a range `V1–V10`, or บันได). The first one is still used for the size frame in the report. |

- **Selecting a photo** shows `ภาพที่เลือก` on the right: name, time and GPS, `หมายเหตุ`, `ถ่ายใหม่`, `ลบภาพ`, and `จุดถ่ายภาพ` (small map from the photo's GPS, `บันทึกจาก GPS`).
- **Counting:** the required photos count toward D1 completion exactly as their fields are defined. The new photo fields are optional in `Schema` until the team agrees to make them required (open question 4).

## 2. Pipeline (TCRoofCore, no UIKit)

```
SurveyModule (.tank) ─► TankInput.from(_:)      outline, grid, setting, azimuth, openings (with status), missing / assumed / warnings
                     ─► TankGeometry.compute    roof area, volume, openings in metres, clashes
                     ─► TankDrawings.roofPlan   (Sketch, DrawingTransform)   ← the transform maps drags back to metres
                        TankDrawings.section    Sketch (tank elevation)
                     ─► MountLayout.compute     tables, posts, cuts, counts (tank-mounting-layout.md)
                        MountDrawings.plan / tableSection
                     ─► ShadeModel.compute      snapshots, month × hour matrix, losses
```

- Compute off the main actor, debounced 150 ms. Keep showing the previous drawing until the new one is ready.
- A drawing is `nil` exactly when `missing` is not empty. The step then shows the missing list instead.
- The optimiser runs about 1,300 layouts. Run it as a cancellable task with a progress indicator.

## 3. iPhone (compact width)

- The five tabs become a horizontal scrolling segment row at the top.
- Each step shows the drawing full width. Its panel opens as a bottom sheet (`.presentationDetents([.height(260), .medium, .large])`).
- Dragging openings works as on iPad. The loupe sits above the finger, and the distances in the sheet update live.
- The camera sheet for direction is full screen.
- Landscape is supported; the view keeps its zoom centre on rotation.

## 4. Report and export

- **PDF (`ReportLayout.planSection`), in this order:**
  - `แปลนฝาถัง`: plan with openings and N
  - `รูปตัดถัง`
  - `ผังจัดแผง`: tables and posts, with the summary
  - `ภาพตัดโต๊ะแผง`
  - `เงาบัง`: heat map + losses
  - the photo groups
- **Page breaks:** each drawing is scaled to the content width and never split across pages. A hand sketch photo, when attached, stays first.
- **Excel:** existing cells only in v1 (size, height, position, surface, shade). The plan image is open question 5.
- **Footer on drawings:** `สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง`.

## 5. Data compatibility

- New fields are all optional:
  - `tankTemplate`, `tankWidth`, `tankLength` (same ids as the `feature/tank-size` branch)
  - `roofSurface`
  - `tankAzimuth`, `tankAzimuthSource`
  - `shadeHeight`, `shadeDistance`
  - `roofPhotos`, `shadePhoto`, `cablePhoto`
- `Obstacle` gains the optional `kind`, `status`, `fromTemplate`, `photoTag`. Old rows read as `kind = other`, `status = ok`, and draw as before.
- `surface` (text) is read into `roofSurface` when it matches one of the four choices. Otherwise it is kept as is and shown as `อื่นๆ: {text}`.
- `tankType` is no longer shown. Its answers are kept and still exported.
- `WebBackup` writes the new keys when present and keeps them on a round-trip.

## 6. Tests

| Kind | What |
|---|---|
| Unit | template → size, spans, area (the four rows in §1); `tankPos` → above-ground (บนดิน = H, ฝังดิน = 0, กึ่งฝัง = clamped value); azimuth → slope direction (az 12° → faces ใต้); seeding adds 16 pending openings on `t40` once only |
| Unit | status: drag sets `moved`; `absent` is ignored by clash checks; undo restores; duplicate-as-row makes n openings at the spacing, clamped inside the walls |
| Unit | clash line: an opening closer than 0.50 m to another reports that ID |
| Unit (mount) | post shift ±0.8 m, column cut, hatch access 0.6 m, ≥ 2 columns per table; 40 × 40 fixture panel count (§1 step 3) |
| Snapshot | `Sketch.svg()` of the plan for `t40` with the design's openings, and for `t64` |
| Performance | layout < 30 ms per run on iPhone 12; optimiser < 3 s, cancellable |
| Manual (iPad + iPhone) | go through all five steps on a 40 × 40 job; confirm, move, add and duplicate openings; undo; run the optimiser; measure direction with the camera; export PDF |

## 7. Delivery

| PR | Content |
|---|---|
| 1 | Fields (`tankTemplate`, `tankWidth/Length`, `roofSurface`, `tankAzimuth*`, shade and photo fields), templates, `Obstacle` fields, `WebBackup`, `TankInput` / `TankGeometry` / `TankDrawings` + tests |
| 2 | D1 page shell with five tabs and done states; step 1 panel; direction camera sheet |
| 3 | Step 2: statuses, drag + loupe, distances, add / duplicate / delete, undo |
| 4 | Step 3: `MountLayout` per `tank-mounting-layout.md`, plan, table section, optimiser, summary, checks |
| 5 | Step 4: shade model, snapshots, heat map, losses |
| 6 | Step 5: photo groups, tags, GPS; completion counting |
| 7 | PDF sections, iPhone layout pass |

## 8. Done when

- [ ] Picking `40 × 40 ม.` draws the plan with V1–V10 and H1–H6 pending, and the N arrow follows `tankAzimuth`.
- [ ] Every opening can be confirmed, marked absent, dragged (0.05 m snap, loupe) or edited by distance, and every change can be undone.
- [ ] Step 3 never puts a post on an opening; shifted posts show in orange, and columns that cannot be saved are cut.
- [ ] `⚡ หาผังแผงมากสุด` never returns fewer panels than the current layout.
- [ ] Step 5 counts `บังคับ {k}/9`, and the bottom bar lists what is missing.
- [ ] Old tank jobs open unchanged. The web backup keeps the new keys.
- [ ] The PDF shows plan, section, layout and shade with the summary and the ค่าสมมติ line.

## 9. Open questions

1. Confirm the four standard tanks (size, column grid, roof area) against the กปภ. drawings, and whether more sizes are needed.
2. Opening positions for each template: the design has the 40 × 40 list only. Who supplies 64 × 40, 30 × 30 and 20 × 20?
3. Vent 1.45 m and hatch 1.15 m: fixed per template, or measured per tank?
4. Should the new photo slots (roof, shade, cable route, fourth wall) become required? This changes D1 completion for old jobs.
5. Excel NO.224: is there room for the plan / layout image?
6. Energy per kWp (1,452 kWh/kWp in the design): which source (PVGIS, the team's yield table)?
7. Round tanks: still needed? If yes, the D1 size picker needs a `ถังกลม · เส้นผ่านศูนย์กลาง` option.
