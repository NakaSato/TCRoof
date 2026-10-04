# SVG: D1 ถังน้ำใส · 3/4 จัดแผง (iPhone)

Vector exports from `PhoneD1Layout.dc.html` at display size (computed styles inlined).

| File | Where | Build with |
|---|---|---|
| `panel-layout-40x40.svg` | Card 1 plan (326 × 296): tank outline + grid, panel tables, row guide lines, slope tag `↓ ลาดลงใต้` (slopes down to the south), north arrow | Draw in code from the layout result (not an image) |
| `plan-expand.svg` | Full-screen button on the plan | `arrow.up.left.and.arrow.down.right` |
| `chevron-left.svg`, `chevron-right.svg` | Bottom bar ‹ › | `chevron.left` / `chevron.right` |

## Drawing styles on the plan
| Element | Style |
|---|---|
| Panel | fill `#2B4FD8` at 85 % opacity, white 0.5 pt gap stroke (board cell 11.7 × 26 at 6 px/m ≈ portrait module) |
| Gaps left for obstacles | empty cells, outlined by the dashed grid `#C9D3DF` 3/3 |
| Row / table guide | teal `#27A99A`, 0.8 pt |
| Slope tag | pill `#1F6FB5`, white 8 pt bold text `↓ ลาดลงใต้` |
| Tank outline | navy `#16325C`, 2 pt; grid labels 1–11 / A–K in `#5B6B82` 8 pt |

The board draws a simplified number of panels (it's a sketch). The real count comes from the layout engine; the board's summary shows 416 panels.
