# SVG: D1 ถังน้ำใส · 2/4 สิ่งกีดขวาง (iPhone)

These are vector exports from `PhoneD1Obs.dc.html` at display size. Computed styles are inlined.

| File | Where | Build with |
|---|---|---|
| `obstacle-plan-40x40.svg` | Card 1 plan (326 × 296): tank outline, grid A–K × 1–11, 10 vents V1–V10, 5 hatches H1–H5, alignment guide, distance tag `16.80`, north arrow | Draw in code from `TankPlan` + the obstacle list (not an image) |
| `marker-vent-{unconfirmed,confirmed,absent,selected}.svg` | Vent symbol: 12 pt square + 3 pt ring | Same shapes in SwiftUI `Canvas` / `Path` |
| `marker-hatch-{…}.svg` | Hatch / tank access: 12 pt square with 45° hatch | Same shapes in SwiftUI `Canvas` / `Path` |
| `plan-expand.svg` | Full-screen button on the plan | `arrow.down.left.and.arrow.up.right` |
| `number-pad.svg` | Trailing icon in the distance fields (opens the number pad) | `keyboard` / custom number pad |
| `info.svg` | Info line `แนวเดียวกับ V10 · ไม่ทับจุดอื่น` | `info.circle` |
| `chevron-left.svg`, `chevron-right.svg` | Bottom bar ‹ › | `chevron.left` / `chevron.right` |

## Marker state colours
Each marker also has a 20 × 12 label pill (`V9`, `H3`) filled with the same colour.

| State | Stroke | Style |
|---|---|---|
| Unconfirmed `ยังไม่ยืนยัน` | `#1F6FB5` | Solid on the plan; the legend draws it dashed. Pick one and say which. |
| Confirmed `ยืนยันแล้ว` | `#16325C` | Solid |
| Absent `ไม่มีจริง` | `#D9453B` | Dashed 3/2 |
| Selected `จุดที่เลือก` | `#E8851A` | Halo: 22 pt rounded square, fill `rgba(232,133,26,.18)` |

The alignment guide line is teal `#27A99A`, 1 pt.
