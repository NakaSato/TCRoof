Follow docs/ui/plan-calendar/CLAUDE_CODE_TASK.md

Redesign PlanCalendarView (TCRoof/Views/Plan/PlanViews.swift) for iPad landscape to match docs/ui/plan-calendar/preview.png and states/*.png at 1366 × 1024, on one screen:
1. Full-height month grid (full weekday names). Install jobs are drawn as team-coloured bars (18 % tint) spanning their days, in up to 3 lanes per week, with square edges and "ต่อ ·" when a job continues across weeks. A dashed pill "นัดสำรวจ n" goes at the bottom of each day with surveys.
2. Title row: month + summary "n งานติดตั้ง · n นัดสำรวจ · n ทีมทำงาน". One segmented group: ‹ วันนี้ ›.
3. Footer: team filter chips (ทุกทีม, TCR01–04, with counts) that hide other teams' bars and day-panel rows, plus the นัดสำรวจ legend.
4. Right day panel, 360 pt: green band title "วันนี้ · …", sections งานสำรวจ / งานติดตั้ง, and a new PlanDayJobRow with a team stripe, Day d/n badge, kW · province and a team pill. Keep PlanJobRow for PlanListView.

Same data and navigation as today (jobs(on:), surveys(on:), JobDetailView, SurveyReportEditor). Vector assets are in docs/ui/plan-calendar/icons. Prefer the SF Symbols listed in icons/README.md. Put lane assignment in a pure, unit-tested helper. Thai UI text exactly as in the previews. Use code-review-graph first, then read the source. Finish with a summary of the files changed and the test results.
