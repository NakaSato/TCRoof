Follow docs/ui/tcroof-plan-calendar-iphone/CLAUDE_CODE_TASK.md

Give the iPhone install-team calendar (PlanCalendarView.phoneBody, root of the แผน tab in PhoneTabs) the compact v10 design from docs/ui/tcroof-plan-calendar-iphone.

**Scope.** Compact width only; the iPad padBody and its parts must stay pixel-identical. Add phone-only parts instead of editing shared ones.

1. **Header.**
   - TCGradientHeader with title ปฏิทินทีมติดตั้ง and subtitle แผนก่อสร้างและเอกสาร
   - a TCHeaderIcon("list.bullet") that opens PlanListView (label รายการแผนก่อสร้าง)
2. **Title row.**
   - month view: กันยายน 22 bold navy, then 2569 in weight 500 inkStrong
   - week view: the range, 27 ก.ย. – 3 ต.ค. / 1–7 ต.ค.
   - a วันนี้ text button (primary, 40 % opacity when already on today)
   - 44 pt ‹ › circles: one month per tap in month view, ±7 days in week view
   - replaces PlanMonthStepper on compact; keep swipe to page
3. **Controls.**
   - a 2-segment switch เดือน / สัปดาห์: 44 pt, track r12, selected white r10 with a soft shadow
   - a 44 pt team button: dot + ทุกทีม / ทีม 01–04 + chevron.down
   - the button opens a 170 pt menu with 44 pt rows (dot, label, checkmark; ทุกทีม has a 4-colour split dot)
   - remove the PlanTeamChip row; the filter applies to everything
4. **Month grid** (white card, r20).
   - weekday header อา…ส in muted 11.5
   - day numbers in 34 pt circles: selected navy fill and white; today primary text only; outside the month #C3CBD6
   - under each number, only a pink survey diamond (#D6336C, 6 pt, rotated 45°) on days with survey appointments
   - under each week, team-coloured 5 pt range lines, one lane per install job:
     - greedy interval packing, so a job keeps its lane across weeks
     - square, un-inset ends where a job continues into the previous or next week
   - put the lane logic in a testable PlanLanes type
5. **Week view.**
   - 66 pt day buttons: weekday, 36 pt number, team dots + diamond
   - one 20 pt bar per install: team at 20 % fill, team text 11/800, 4 pt solid leading edge
   - label TCR01 · project, or 01 when the bar spans ≤ 2 days
6. **Legend.** Team line swatches 01–04 (only the filtered team) plus the diamond and สำรวจ.
7. **Agenda.**
   - heading: thaiLong date 18 bold, with สำรวจ n · ติดตั้ง n · n ทีม on the right
   - rows: min 64, r14, 1 pt border, 4 pt leading rule
   - survey row: pink rule, project, นัดสำรวจ · ทีม TCR03, 09:30 น.; opens SurveyFormView
   - install row: team rule, project, งานติดตั้ง · ทีม TCR01, per-day 4 pt progress segments, วัน 2/4 over เหลือ 2 วัน; opens the job detail
   - empty: dashed box ไม่มีนัดในวันนี้

**Tokens.** No hex in views. Use Theme tokens and add the missing ones with dark values: survey #D6336C, dayOutside #C3CBD6, optionally rowSelected. Team colours come from Team.color.

**Rules.**
- Use .sarabun fonts.
- Thai UI text exactly as in the previews.
- Touch targets ≥ 44 pt.
- No model or sync changes.
- Use code-review-graph first, then read the source.
- Work on a new branch feat/iphone-plan-calendar.

**Verify.** Build, run on an iPhone 16 simulator with -homeTab plan, and compare with states/*.png (measure in the PDFs). Add PlanLanes unit tests.

**Finish** with a summary:
- the files changed
- tokens and components added
- remaining differences
- answers to the open questions
