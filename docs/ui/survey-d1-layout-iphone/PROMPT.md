Follow docs/ui/survey-d1-layout-iphone/CLAUDE_CODE_TASK.md

Build D1 Clear-water tank (ถังน้ำใส) · sub-step 3/4 Panel layout (`จัดแผง`) for iPhone (horizontalSizeClass == .compact), replacing today's placeholder form (panelsBefore / panelsCut / planPhoto). Match docs/ui/survey-d1-layout-iphone/states/01-screen.png and states/02-full-length.png. Keep the iPad UI working.

1. Header, step line and sub-step tabs as in D1 1/4 and 2/4 (tabs 1–2 done with ✓, tab 3 current).
2. Card 1 Panel arrangement (`การวางผังแผง`, aside `ตามแบบ B1-C3 · เอียง 15°`):
   - segmented control `เลื่อนผัง` (drag the whole layout) / `แก้แผง` (tap a panel to toggle it, long-press to remove a table)
   - plan drawn in code: blue panel tables (#2B4FD8), gaps at obstacles and clearance, teal row guides, slope tag `↓ ลาดลงใต้`, north arrow, full-screen button
   - caption `แผงโมโน 570 W · แตะแผงเพื่อแก้`
   - buttons `จัดแผงใหม่` (re-layout, confirm if edited) and `หาผังแผงมากสุด` (search for the max-panel layout)
3. Card 2 Summary · materials (`สรุป · วัสดุโครงสร้าง`):
   - chip `416 แผง · 237.1 kWp`
   - rows: panels, total kWp, rows · tables, posts + front frames, foundation points, rail length (4 rails), Mid / End clamp, Rail clamp, cross bracing
4. Card 3 Pre-checks (`ตรวจสอบก่อนไปต่อ`, chip `✓ 3/3`):
   - clearance above vent beams (panels may cover)
   - tank edge to panel edge ≥ 1.00 m
   - full 6 × 2 / short 3–5-column table counts
   - link button `ดูแบบ B1-C3 · ภาพตัดโต๊ะแผง · ฐานเสา`
5. Bottom bar `บันทึก` (save) + ‹ › with VoiceOver step names.

Logic: add a pure, unit-tested TankLayout in TCRoofCore.
- Input: tank size, 1.00 m clearance, the obstacles from 2/4 (skip absent ones; vents that panels may cover don't block), 570 W portrait module, full 6 × 2 and short 3–5-column tables, tilt 15°, offset.
- Output: tables and panels, kWp, BOM quantities and the 3 checks; the max search runs over a 0.05 m offset grid and both orientations.
- Save the offset and manual edits, and set panelsBefore to the panel count.
- The sub-step is complete when the layout exists and all checks pass.
- Reuse the C1 PV-layout code if it exists. Mark any BOM rule assumptions with TODO.

Keep all Thai UI labels exactly as written (English in brackets is only a gloss); colours from Theme/Home; touch targets ≥ 44 pt. Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/iphone-d1-layout. Build, run the tests, try every interaction on an iPhone 16 simulator, and finish with a summary of files changed, the BOM assumptions and any remaining differences from the board.
