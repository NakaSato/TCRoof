Follow docs/ui/survey-list/CLAUDE_CODE_TASK.md

Redesign the job cards on SurveyListView (TCRoof/Views/Survey/SurveyViews.swift) to match docs/ui/survey-list/preview.png and states/*.png at 1366 × 1024:
1. Title row: project name + team pill (team.color) + chevron. Then code + status pill, then customer · kW.
2. When row: `วันนี้ / พรุ่งนี้ / เมื่อวาน / อีก n วัน / n วันที่แล้ว` + HH:mm from surveyDate, plus the short date. Then the province.
3. New progress box: 4 groups (`หลังคา`, `ระบบไฟฟ้า`, `ค่าไฟ`, `รูปบังคับ`) computed from SurveyOptions.missing() on the draft. Percent = filled/11. Labels: `ยังไม่เริ่ม` / `ทำต่อ n/4` / `สำรวจครบ`.
4. Remove the arrow icon. Card body → JobDetailView; gradient button → SurveyFormView (unchanged).

Make a new SurveyJobCard and keep JobCard unchanged for the other lists. Put the progress grouping in SurveyOptions, and add unit tests for it and for the relative-day label. Thai UI text exactly as in the previews. Use code-review-graph first, then read the source. Finish with a summary of the files changed and the test results.
