Follow docs/ui/pwa-solar-survey/CLAUDE_CODE_TASK_v2.md

The 3-tab PWA Solar Survey home (SurveyHomeView, TCRoofKit/Sources/SurveyUI/SurveyHome*.swift, JobCard.swift) is already built. Align it with the latest board: docs/ui/pwa-solar-survey/preview.png and states/*.png at 1366 × 1024.
1. Remove the sync button from the blue header. Add "ซิงก์ทั้งหมด (n)" as the first item in the ••• menu, and show a "ซิงก์ n งาน" button in the list heading when the รอซิงก์ filter box is selected. Keep the ••• menu.
2. Search placeholder "ค้นหาเลขที่ ชื่อโครงการ สถานที่…", width 330, height 46, radius 12. Title 30 pt, subtitle 15 pt.
3. Card and filter-box radius 16. Progress ring centre text 16 pt bold + 10 pt "%".
4. Card footer: orange dot + "รอซิงก์" / green ✓ + "ซิงก์แล้ว" (instead of the cloud icons).

Visual pass only: no model, sync-logic or flow changes. Vector assets are in docs/ui/pwa-solar-survey/icons (SF Symbol names in icons/README.md). Use code-review-graph first, then read the source. Finish with a summary of the files changed and any other differences you see.
