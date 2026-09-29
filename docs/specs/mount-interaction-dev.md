# Mounting layout on the tank — interaction dev spec

**Status:** Ready for development, 2026-09-29
**Feature:** [`tank-mounting-layout.md`](tank-mounting-layout.md) (standard, algorithm, quantities, drawings)
**Reference build:** `prototype/mount-layout.html` (open in a browser). **Demo:** `img/mount_demo.mp4` (21 steps),
regenerated with `NODE_PATH=<global node_modules> node prototype/mount-demo.js <outDir>` (Playwright).
**Where it lives in the app:** a third tab **โครงสร้าง** in the tank editor, next to แปลน and รูปตัด
([`tank-interaction-dev.md`](tank-interaction-dev.md)).

| Auto layout on open | Tap a vent: fits under | Tap a vent: too low | Best layout found |
|---|---|---|---|
| ![](img/mount_demo_000.png) | ![](img/mount_demo_001.png) | ![](img/mount_demo_002.png) | ![](img/mount_demo_009.png) |

| Tap a table | Section of that row | Remove modules for a walkway | North on the right |
|---|---|---|---|
| ![](img/mount_demo_010.png) | ![](img/mount_demo_011.png) | ![](img/mount_demo_016.png) | ![](img/mount_demo_019.png) |

---

## 1. Principle

The layout is **computed**, never drawn by hand. The user changes a few inputs (row offset, column offset, north,
vent height, the structure standard) and may **remove** modules; everything else — tables, posts, rails, clamps,
quantities — follows. There is no dragging of tables or posts: a post that must move is moved by the rules, and a
post the rules cannot place is shown red with the reason.

## 2. Screen parts

| Part | Content |
|---|---|
| Controls (left column on iPad, a sheet on iPhone) | north of the tank plan, vent height, row offset slider, column offset slider, **หาผังที่ได้แผงมากที่สุด**, the structure standard (collapsed by default) with **คืนค่ามาตรฐาน** |
| Tool strip | mode: **ดูรายละเอียด** / **เอาแผงออก / ใส่คืน** · undo · view: **แปลน** / **รูปตัดแถวที่เลือก** |
| Info line | what was tapped and why (pills: green = OK, red = problem); or the mode hint |
| Drawing | the plan (tank, openings, modules, rails, rafters, posts, clamps, lugs, north arrow) or the row section |
| Quantities | modules, kWp, tables, posts/footings, rail m, rail clamps, X braces, posts to check; each with a **delta** (green +, red −) against the state before the last change |
| Notes | one red line per post pair that could not be placed |

## 3. State

```swift
@Observable final class MountEditorModel {
    var rowOffset: Double = 0          // m, 0 … pitch, rows move north
    var colOffset: Double = 0          // m, 0 … moduleW, columns move east
    var north: PlanNorth = .top        // stored on the tank module (D1 planNorth)
    var ventHeight: Double = 1.00      // stored on the tank module (D1 ventHeight)
    var standard: MountStandard        // from settings; edits here are per job (stored on the module)
    var removed: Set<SlotRef> = []     // (row, column) removed by the user
    var mode: MountMode = .inspect     // .inspect, .remove
    var view: MountView = .plan        // .plan, .rowSection
    var selection: MountSelection?     // .table(row, firstColumn) | .vent(index) | .post(row, x, line)
    private(set) var layout: MountLayout
    private(set) var previous: MountQuantities?   // for the deltas
    let undo: UndoManager
}
```

Stored per job: `rowOffset`, `colOffset`, `removed`, and the standard if the user changed it here. The layout
itself is always recomputed.

**`removed` is cleared** whenever the grid it refers to changes: row or column offset, north, the standard, or the
tank spans/openings. The info line says so once ("ผังเปลี่ยน จึงล้างแผงที่เอาออกเอง"), and undo brings it back.

## 4. Interactions

### 4.1 Open the tab

Compute with the stored offsets. First time for a tank: run **best layout** (§4.4) automatically and store its
offsets, so the first view is already the best one.

### 4.2 ดูรายละเอียด (inspect) — tap targets, in this order

| Tap on | Result in the info line | Drawing |
|---|---|---|
| a post (hit radius 8 pt) | row, x (m), footing type; red pill "ชนช่องเปิด" + "ลองเลื่อนแนวแผงหรือกด หาผังที่ได้แผงมากที่สุด" when flagged | orange ring |
| a vent (box + 3 pt) | row above it, lowest panel height over it, required height (vent + 0.10); green "วางแผงคร่อมได้" or red "ต่ำไป จึงเว้นแผงเหนือช่องนี้"; if no row covers it: "ไม่มีแผงเหนือช่องนี้" | orange outline |
| a module slot in a table | table: modules (kWp), length, post pairs and max spacing, green "เลื่อนเสาหลบช่องเปิด n คู่", red "เสาชน n คู่", button **ดูรูปตัดแถวนี้** | table modules tinted |
| an empty slot (blocked) | red pill with the reason: "ช่องลงถัง: เว้นให้เข้าถึงได้", "ช่องระบาย: ใต้แผงสูง 0.85 ม. ต่ำกว่า 1.10 ม.", "เอาออกเอง" | — |
| empty paper | clear the selection | — |

Hit-testing uses coordinates (row by y range, column by x range), not drawn shapes, as in the tank editor.

### 4.3 เอาแผงออก / ใส่คืน (remove)

- Tap a slot → toggle `removed` for that (row, column): both modules along the slope go together.
- Removed slots stay visible as red dashed outlines in this mode (hidden in inspect mode).
- A slot blocked by the rules cannot be toggled: the info line shows its reason instead.
- Tables split and re-post live; quantities show the deltas. One undo step per tap.
- Typical use (demo steps 14–17): a walkway through all rows by removing one column in every row.

### 4.4 หาผังที่ได้แผงมากที่สุด (best layout)

- Try every row offset 0 … pitch in 0.10 m steps and every column offset 0 … moduleW in 0.05 m steps (≈ 1,300
  layouts for the standard), without post placement for speed; keep the one with the most modules; ties → fewer
  red posts, then the smaller offsets.
- Apply it, clear `removed`, show "ลอง n แบบ · ดีที่สุด m แผง ที่เลื่อนแถว a ม. แผง b ม." under the button.
- On device run it off the main thread with a small progress indicator; the 40 × 40 tank takes well under a second.
- One undo step.

Prototype numbers (40 × 40): 394 modules at offsets 0 / 0 → **416 modules (249.6 kWp)** at row offset 0.30 m.

### 4.5 Sliders

- Row offset (0 … pitch) and column offset (0 … moduleW). The layout updates while dragging (throttle to one
  compute per frame); the undo step is registered at touch-down.
- Value shown next to the label in metres (0.00).

### 4.6 Standard and site inputs

- North (ด้านบน / ขวา / ล่าง / ซ้าย): the plan is shown rotated so north is up, with the note
  "แปลนหมุนให้ทิศเหนืออยู่ด้านบน"; rows always run east–west with panels facing south.
- Vent height (m): changes which vents fit under the panels.
- Standard fields (module L, W, W, front/back post heights, front–back distance, row gap, max post spacing): commit
  on end-editing; invalid (≤ 0) reverts. Derived tilt, pitch and table depth are shown under the fields.

### 4.7 Row section

- Shows the selected row (default row 1): posts with heights, rafter, modules, braces, the front–back and row-gap
  dimensions, and the first vent under that row drawn green (fits) or red (does not), with its clearance.
- Read-only; the tab switch keeps the selection.

### 4.8 Undo and deltas

- `UndoManager` with snapshots of the editor inputs (offsets, north, vent height, standard, removed).
- `previous` = the quantities before the last change; each tile shows the difference (hidden when it rounds to 0).

## 5. Devices

| | iPad (regular width) | iPhone (compact width) |
|---|---|---|
| Controls | left column 320 pt | sheet from a toolbar button "ปรับผัง" (detents: medium, large) |
| Info line | above the drawing | bottom bar, two lines max; tap to expand |
| Quantities | row of tiles under the drawing | a second tab "ปริมาณ" in the bottom sheet |
| Best layout | button in the controls | also in the toolbar menu |
| Zoom | pinch / double tap / ⌘ keys (as in the tank editor) | pinch / double tap |

## 6. Test script (XCUITest, mirrors the demo)

1. Open the 40 × 40 fixture, tab โครงสร้าง. Expect 416 modules after the automatic best layout.
2. Tap each vent; at least one shows "วางแผงคร่อมได้" and one "ต่ำไป".
3. Tap a red post; the info shows "ชนช่องเปิด".
4. Set row offset 0.0; expect 394 modules and a red delta.
5. Best layout; expect 416 again and the note with the tried count.
6. Tap a table in row 3; **ดูรูปตัดแถวนี้** shows "รูปตัดแถวที่ 3".
7. Remove mode; tap column 16 in rows 1–4; expect 8 modules fewer (4 slots × 2); undo restores the last slot.
8. Row gap 3.20; expect fewer rows. Reset the standard.
9. North = right; the note about the rotated plan appears; modules are recomputed.

## 7. Done when

- [ ] Every step of §6 passes on iPad and iPhone simulators.
- [ ] No state in which a module sits over a hatch or a too-low vent, or a post over any opening without a red flag.
- [ ] Best layout never returns fewer modules than the current layout.
- [ ] `removed` never survives a grid change silently.
- [ ] Quantities in the app equal `MountQuantities` used by the PDF/Excel BOQ.
