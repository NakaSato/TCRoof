Follow docs/ui/survey-d1-obstacles-iphone/CLAUDE_CODE_TASK.md

Build D1 Clear-water tank (ถังน้ำใส) · sub-step 2/4 Obstacles (`สิ่งกีดขวาง`) for iPhone (horizontalSizeClass == .compact) to match docs/ui/survey-d1-obstacles-iphone/states/01-screen.png and states/02-full-length.png. It is a verify-on-site flow. Keep the iPad UI working.

1. Header, step line and sub-step tabs as in D1 1/4 (tab 1 done with ✓, tab 2 current).
2. Card 1 Obstacle plan (`แปลนสิ่งกีดขวาง`):
   - chip `ตรวจแล้ว n/N` (checked n/N)
   - segmented `บนหลังคา · 15 จุด` (on the roof · 15 points) / `เงาบัง · 1.2%` (shading) (the shading view uses the existing shade fields)
   - plan drawn in code with TankPlan: standard vents V1–V10 (square + ring) and hatches H1–H5 (hatched square) with label pills, coloured unconfirmed blue / confirmed navy / absent red dashed / selected orange with halo (svg/README.md)
   - while dragging: teal alignment guide and distance tag; snap to 0.05 m
   - tap to select (44 pt), drag to move, full-screen button, hint and legend
3. Card 2 `จุด <id> · <kind>` (selected point; chip `ย้ายแล้ว` moved / `ตามแบบ` as drawn):
   - point chips with ‹ › stepping through the unchecked points
   - status (`สถานะ *`) choice `มีตรงแบบ` (present as drawn) / `ไม่มีจริง` (not actually there)
   - distance-from-left-wall (`ห่างผนังซ้าย`) / distance-from-top-wall (`ห่างผนังบน`) number fields that move the point
   - live info line (alignment / overlap / outside)
   - `+ ช่องระบาย` (add vent), `+ ช่องลงถัง` (add hatch), `ทำซ้ำเป็นแถว` (repeat as a row), `ลบจุดนี้` (delete point) (added points only; confirm first)
4. Bottom bar `บันทึก` (save) + ‹ › with VoiceOver step names.

Data: keep Obstacle in Roof.Key.obstacles.
- Add `kind` vent/hatch, `status` (""/ok/absent), `origin` (standard/added) and the standard position, with backward-compatible decoding.
- Generate the standard points from the tank preset in TCRoofCore (40 × 40 → 10 vents + 5 hatches), with unit tests.
- The sub-step is complete when every standard point has a status.
- Exports skip absent points in the layout.

Keep all Thai UI labels exactly as written (English in brackets is only a gloss); colours from Theme/Home; touch targets ≥ 44 pt. Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/iphone-d1-obstacles. Build, run the tests, try every interaction on an iPhone 16 simulator, and finish with a summary of files changed, the model changes and any remaining differences from the board.
