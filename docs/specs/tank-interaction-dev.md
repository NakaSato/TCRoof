# Tank auto-drawing — interaction dev spec

**Status:** Ready for development, 2026-09-29
**Scope:** how the tank drawing editor behaves on iPad and iPhone, step by step, precise enough to implement and test.
**Reads with:** [`tank-drawing-swift.md`](tank-drawing-swift.md) (feature, layouts per device),
[`auto-drawing-swift.md`](auto-drawing-swift.md) §8–§11 (types: `TankInput`, `TankGeometry`, `TankDrawings`, `Obstacle` fields).
**Reference build:** `prototype/tank-layout.html` (open in any browser). **Demo:** `img/tank_demo.mp4` (24 steps),
regenerated with `node prototype/tank-demo.js <outDir>` (Playwright).

| Type sizes → drawing appears | Tap bays → vents | Wall tap → pick opening | Section 1–1 / 2–2 |
|---|---|---|---|
| ![](img/tank_demo_002.png) | ![](img/tank_demo_008.png) | ![](img/tank_demo_011.png) | ![](img/tank_demo_022.png) |

---

## 1. Screen parts

| Part | Content | Notes |
|---|---|---|
| Input sheet | presets (sample only in the prototype), spans X/Y, height, above ground, vent style, hatch/ladder/pipe rows, section positions, assumed values | In the app these are the D1 fields; no presets |
| Tool strip | mode (ช่องระบาย / ที่ผนัง / เลือก), undo, redo, zoom − / % / + / พอดี, view (แปลน / รูปตัด), layer toggle พื้นที่ติดแผง | Always visible above the drawing |
| Inspector | hint for the current mode, or the fields of the selected opening | One line on iPad; bottom sheet on iPhone |
| Messages | warnings (red), one-time hints (blue) | Never modal |
| Drawing | plan or sections on white paper | Zoom and pan inside its own scroll area |
| Summary | size, roof area, counts, usable m², kWp | Updates with every edit |
| Footer | assumed values, "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง" | |

## 2. State

```swift
enum TankEditMode { case vent, wall, select }
enum TankView { case plan, section }

@Observable final class TankEditorModel {
    var module: SurveyModule                  // the only persistent state (D1 values + obst rows)
    var mode: TankEditMode = .vent
    var view: TankView = .plan
    var zoom: CGFloat = 1                     // 1 = fit width; range 0.5 … 6
    var showUsable = true
    var selection: OpeningRef?                // (kind, index) into obst rows of that kind
    var wallMenu: WallPoint?                  // open "ที่ผนัง" menu, or nil
    var drag: DragState?                      // active drag of a wall opening
    private(set) var geometry: TankGeometry?  // rebuilt off-main, 150 ms debounce
    let undo: UndoManager
}
struct WallPoint { var edge: WallEdge; var along: Double }        // along rounded to 0.05 m
struct DragState { var ref: OpeningRef; var before: Values; var moved: Bool }
```

Rules:

- `geometry` is derived only; never edit it. Every edit writes `module.values` and schedules a rebuild.
- Changing `mode` closes the wall menu; leaving `.select` clears `selection`.
- Switching to `.section` keeps mode and selection but the drawing is read-only.

## 3. Coordinate pipeline

```
view point (pt) ──► content point: + scroll offset, ÷ zoom-fit scale
                 ──► sketch point: SketchView fit inverse (auto-drawing-swift §9.2)
                 ──► metres: DrawingTransform.metres(_:)          (x from the left wall, y from the top wall)
pxPerMetre = transform.k × (on-screen scale)                     used for every tolerance below
```

## 4. Behaviour by mode

### 4.1 ช่องระบาย (vent)

1. Tap → metres `(x, y)`. Find the bay **from the coordinates**, by binary search over the span edges
   (`Spans.edges(spansX)`, `Spans.edges(spansY)`). Do **not** hit-test drawn shapes: leader lines and symbols lie
   on top of bays (this blocked taps in the first prototype).
2. Outside the grid → ignore.
3. Bay shorter side on screen `< 28 pt` and `zoom < 6` → zoom in around the tap to make the bay ≥ 32 pt, show the
   hint "ช่องเล็กเกินไปสำหรับนิ้ว จึงซูมเข้าให้ก่อน แตะอีกครั้งเพื่อวางช่องระบาย" once per session, and stop.
4. Otherwise toggle `Obstacle(kind: .vent, cell: GridCell(row:col:))`: remove it if that cell has one, else append.
   One undo step. Haptic `.selection`.
5. Vent style (กล่อง / กากบาท) is a module value; changing it is one undo step and redraws all vents.

### 4.2 ที่ผนัง (wall)

1. Tap → metres. Distance to each wall: top `y`, bottom `H − y`, left `x`, right `W − x`. Take the smallest.
2. Accept when `−2·tol ≤ distance ≤ tol`, `tol = 18 pt ÷ pxPerMetre` (a little outside the wall is allowed).
3. `along` = the tap's x (top/bottom) or y (left/right), clamped to `[0, wall length]`, rounded to **0.05 m**.
4. Show the menu at the tap: title "ผนังบน · ระยะ 10.15 ม.", buttons **+ ช่องลงถัง**, **+ บันไดขึ้นถัง**,
   **+ ท่อผ่านผนัง**, **ยกเลิก**. iPad: popover; iPhone: confirmation dialog anchored to the tap.
5. Choosing a type appends `Obstacle(kind:, edge:, along:)` (pipe: `diameter` empty, type ท่อน้ำใส), selects it,
   switches to **เลือก** mode and opens the inspector. One undo step.

### 4.3 เลือก (select)

1. Tap on a hatch, ladder or pipe symbol (hit area = symbol + 6 pt) → select it and open the inspector.
   Tap on empty paper → clear the selection.
2. Drag a selected (or just touched) wall opening: the finger's x (top/bottom) or y (left/right) in metres,
   clamped and rounded to 0.05 m, becomes `along` live. The opening never leaves its wall.
3. The whole drag is **one** undo step (store `before` at touch-down; register only if `moved`).
4. Vents are not dragged; they are toggled in vent mode.

### 4.4 Inspector (selected opening)

| Field | Control | Notes |
|---|---|---|
| title | ช่องลงถัง / บันไดขึ้นถัง / pipe type name | |
| ผนัง | picker top / bottom / left / right | keeps `along`, clamped to the new wall |
| ระยะตามผนัง (ม.) | decimal field | beyond the wall → clamped, warning "… เกินความยาวผนัง … ใช้ …" |
| Ø (มม.) | decimal field, pipes only | |
| ลบ | destructive button | one undo step |
| เสร็จ | clears the selection | |

Typing in a field is one undo step per focus (first change registers, later keystrokes merge).

### 4.5 Undo

- `UndoManager` with snapshots of `module.values` (small: tens of obstacles). Buttons ↶ ↷ enabled from
  `canUndo` / `canRedo`; iPad keyboard ⌘Z / ⇧⌘Z; iPhone also supports shake-to-undo (system default).
- Undo/redo clears the selection and closes the wall menu.

### 4.6 Zoom and pan

| Input | Result |
|---|---|
| pinch (both), ⌘+ / ⌘− (iPad keyboard), ⌘ + scroll wheel (pointer) | zoom × about the gesture centre, 0.5…6 |
| double tap | toggle 1 (fit) ↔ 2 at the tap |
| พอดี / ⌘0 | zoom 1 |
| one-finger drag on empty paper | pan (in select mode a drag that starts on an opening moves the opening instead) |

The zoom centre stays under the finger: new scroll = (old scroll + p) × new/old − p.

### 4.7 Keyboard (iPad)

⌫ deletes the selection · Esc closes the menu, then clears the selection · ⌘Z / ⇧⌘Z · ⌘+ / ⌘− / ⌘0.

## 5. Drawing rules the demo fixed

- **Labels:** right-side labels (vents per row, top/bottom/right hatches, right ladders, right pipes) stack in a
  column 80 pt right of the wall; left-side ones 70 pt left. Minimum 17 pt between labels. The same label text
  within 16 pt of the previous one shares it (one text, two leaders), as on the กปภ. sheet.
- **Vent rows:** one leader per row of vents, from the right-most vent.
- **Bays:** each bay is a dashed rectangle inset by half a beam (0.15 m), like the sheet.
- **Section marks:** circle with the number and a filled view-direction triangle on top; 1–1 top and bottom,
  2–2 left and right, just outside the wall.
- **Side dimensions:** per-bay values and the total as horizontal text, left of the chain.
- **Usable area:** 0.25 m raster sampled at cell centres, merged into runs per row; a cell is free when it is at least
  the edge setback from every wall, outside every vent/hatch box grown by the opening clearance, and outside every
  pipe circle (clearance + Ø/2). Ladders don't reduce it.

## 6. Sections

- 1–1 cuts at `sectionX` (default: half of Σ spansX) and shows the tank across **Σ spansY**; 2–2 cuts at
  `sectionY` (default: half of Σ spansY) and shows it across **Σ spansX**.
- Ground line: above ground → at the base; `tankAboveGround = 0` → at the roof plus 0.50 m soil cover (assumed);
  in between → at `H − above`, with "พ้นดิน x.xx" dimension. Soil hatched below the ground line.
- Wall and slab 0.30 m (assumed); columns at inner grid lines.
- Footer line: setting + "ปริมาตรภายนอกโดยประมาณ … ม³".
- No height → "ใส่ความสูงถังเพื่อวาดรูปตัด" instead of the drawing.

## 7. Messages

| When | Text | Style |
|---|---|---|
| spans missing | ใส่ ช่วงเสาแนวยาว และ ช่วงเสาแนวกว้าง เพื่อวาดผัง | drawing placeholder |
| along empty | ช่องลงถัง (ผนังบน): ยังไม่ได้ใส่ระยะ | red, list |
| along > wall | … ระยะ 45 เกินความยาวผนัง 40.00 ม. ใช้ 40.00 | red, list |
| vent outside grid (spans shortened) | ช่องระบายแถว r คอลัมน์ c อยู่นอกตาราง จึงไม่วาด | red, list; the row stays saved |
| above > height | ส่วนพ้นดินสูงกว่าถัง | red |
| auto-zoom | ช่องเล็กเกินไปสำหรับนิ้ว … | blue, once, 4 s |

## 8. Numbers to hold (cell-centre raster, 0.25 m)

| Case | Roof | Usable | kWp (÷6) |
|---|---|---|---|
| กปภ. 40 × 40, 12 cross vents, 6 hatches, 3 ladders | 1,600 m² | **1,367 m²** | ≈ 228 |
| กปภ. 64 × 40, 20 box vents, 8 hatches, 6 pipes | 2,560 m² | **2,229 m²** | ≈ 372 |

Both sit inside the ±10 m² tolerance of the unit tests in `auto-drawing-swift.md` §11 (1,363 / 2,222). Use the
cell-centre rule in Swift so iOS and the prototype give the same number.

## 9. UI test script (XCUITest, mirrors the demo)

1. New D1 section, blank. Expect the missing message.
2. Type `10@4`, `10@4`, `4.5`. Expect the plan and "1,600" roof area.
3. Vent mode: tap bays (0,0) (0,4) (0,5) (0,9) (9,0) (9,9). Expect 6 vents and the usable area to drop.
4. Vent style กากบาท. Expect cross symbols.
5. Wall mode: tap the top wall at 10.2 m. Expect the menu titled "ผนังบน · ระยะ 10.20 ม." (±0.05).
6. Choose ช่องลงถัง. Expect mode = เลือก and the inspector showing 10.2.
7. Drag the hatch right by about 4 m. Expect along ≈ 14.2 and one undo step.
8. Undo. Expect along back to 10.2.
9. Wall mode, left wall at 6.4 m → บันไดขึ้นถัง. Expect "บันได 1".
10. Above ground 1.5 → view รูปตัด. Expect two sections with "พ้นดิน 1.50".
11. Rotate (iPhone) and zoom 3× then tap a bay: the same bay toggles.

## 10. Done when

- [ ] Every step of §9 passes on an iPad and an iPhone simulator.
- [ ] Taps on leader lines or symbols still hit the bay underneath (vent mode).
- [ ] A drag is one undo step; typing a number is one undo step per field focus.
- [ ] The 40 × 40 and 64 × 40 samples show 1,367 m² and 2,229 m².
- [ ] No main-thread stall while typing spans on the 64 × 40 tank (geometry off-main, 150 ms debounce).
