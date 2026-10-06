Follow docs/ui/tcroof-survey-list-iphone/CLAUDE_CODE_TASK.md

Give the iPhone survey list (SurveyListView, root of the สำรวจ tab in PhoneTabs) the compact design from docs/ui/tcroof-survey-list-iphone. Compact width only; the iPad survey list must stay pixel-identical. Add compact variants instead of changing the shared SurveyJobCard / QueueFilterBar / JobCard.

1. **Header.** A gradient header (headerGradient, bottom radius 15) replaces TCNavBar and its breadcrumbs:
   - title สำรวจหน้างาน
   - subtitle นัดสำรวจ n งาน, or ผลการค้นหา n งาน while searching
   - a 44 pt history button (white 16 %, r12) that opens SurveyHistoryView
   - a back chevron only when the list is pushed, hidden on the tab root
2. **Filter.** A segmented control replaces the gradient capsules:
   - 7 วัน / 30 วัน / ทั้งหมด (DateWindow)
   - 44 pt high, track #EEF2F7 r10
   - selected segment white r8 with a soft shadow, navy 700; unselected #5B6B82
3. **Search field.**
   - 44 pt, r12, 1 pt #DDE4ED border (2 pt #1F6FB5 when focused)
   - leading magnifyingglass, placeholder ค้นหาชื่อลูกค้า หรือรหัสโครงการ
   - a 32 pt ✕ clear button with a 44 pt hit area
   - ค้นหาล่าสุด chips (last 4 queries, AppStorage) while focused and empty
   - an active query searches all jobs and ignores the date window, as on the board
4. **Compact card.**
   - **Body** (opens JobDetailView):
     - row 1: project 16 bold + a team-code pill (TCR03, team colour on 10 % tint)
     - row 2: code · bolt · kW in 13 muted
     - row 3: calendar + RelativeDay label bold 14 (primary today), province on the right
     - no status chip, customer, divider, short date or chevron
     - today's card has a 1 pt primary border
   - **Progress box**, replacing the teal button (opens SurveyFormView):
     - min 44, r10, progressBox / progressBoxIdle fill
     - ยังไม่เริ่ม·เริ่มสำรวจ / ทำต่อ·<next group> / สำรวจครบ·ดูแบบสำรวจ, then the percent and a chevron
     - 4 segments, 5 pt (stepDone / primary / borderSubtle)
     - reuse SurveyCardProgress; add fields with tests if needed
5. **Layout.**
   - one column, padding 8/16, gap 10, background #F3F6FA
   - the last card clears the FAB and the tab bar
   - empty state is the line ไม่พบงานสำรวจ
   - FAB and tab bar unchanged from v2

No hex in views: use Theme tokens and add any missing ones (segmentTrack) with dark values. Thai UI text exactly as in the previews; touch targets ≥ 44 pt. Use code-review-graph first, then read the source. Work on a new branch feat/iphone-survey-list.

Build, run on an iPhone 16 simulator with -homeTab survey, and compare with states/*.png (measure in the PDFs). Finish with a summary: the files changed, tokens and components added, the search-scope change, and answers to the open questions.
