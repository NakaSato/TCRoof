Follow docs/ui/tcroof-survey-home-iphone/CLAUDE_CODE_TASK.md

Rebuild the iPhone root of the สำรวจ tab (PhoneSurveyList, shown by SurveyListView at compact width) as the survey home from docs/ui/tcroof-survey-home-iphone. Apply it at compact width only; the iPad survey list must stay pixel-identical. Work on a new branch, feat/iphone-survey-home.

1. **Header.** TCGradientHeader with:
   - title สำรวจหน้างาน, 22 pt
   - subtitle `<greeting> · พุธ 30 ก.ย. 2569`; the greeting is สวัสดีตอนเช้า / ตอนบ่าย / ตอนเย็น by the hour
   - no trailing button, and a back chevron only when the screen is pushed
2. **Week card** (white, r16), under the label สัปดาห์นี้ with the date range:
   - **Day strip**: 7 days rolling from today (วันนี้ first). Each day has a 34 pt number circle: navy fill when selected, primary text for today. A 6 pt dot (Theme.survey, primary when selected) marks days with appointments.
   - **นัดถัดไป block**, only when the selected day is the next appointment's day:
     - the project name, 18 bold
     - `วันนี้ 09:30 น. · province`
     - 44 pt circle buttons that call (`tel:`) and navigate (reuse the JobViews mapsURL)
     - a meta line: the time until the appointment, and the drive distance and time (MKDirections; hidden without location access or coordinates)
   - **Agenda rows** for the day's other appointments: time, a team-colour bar, name, `ทีม · province · kW`, chevron
   - **Empty day**: the line ไม่มีนัดสำรวจในวันนี้
3. **All jobs** (label งานสำรวจทั้งหมด with `n งาน`):
   - **Search field**: PhoneSearchField with new size parameters (50 pt, r10, 16 pt, 1 pt navy at 50 %, 2 pt primary when focused), plus the existing ค้นหาล่าสุด chips
   - **Status chips** in an edge-to-edge horizontal row: ทั้งหมด, then JobStatus.shortTitle (add สนใจ / ยืนยันแล้ว / กำลังติดตั้ง / เสร็จสิ้น), each with a dot and a count. The selected chip is navy with white text.
   - **Filtering**: no DateWindow on this screen; the query is AND-ed with the status; sort by abs(days from today)
   - **List card**, one row per job:
     - a team-colour initial avatar (prefix คุณ / บริษัท / ร้าน / โรงงาน / หอพัก stripped)
     - the name, and `code · kW · province`
     - a draft progress bar with `ทำต่อ <group> · n%` (from SurveyCardProgress)
     - a status pill and a chevron
     - separators inset 68
   - **Empty**: ไม่พบงานที่ตรงกับ "q" with a query, ไม่มีงานในสถานะนี้ without
4. **Glass dock** above the tab bar, replacing the TCFab here:
   - **Primary button** (headerGradient, r17, 52 pt): `ทำแบบสำรวจต่อ · <group>` or `เริ่มสำรวจ`, with the subtitle `project · when · n%`. It opens SurveyFormView for the next job and is hidden when there is no upcoming job.
   - **Add button** (52 pt, person.badge.plus, teal): opens NewJobView.
   - The list's bottom inset clears the dock.

Put the pure logic in TCRoofCore with tests: greeting, week strip, next appointment, agenda, sort key, status counts, initial, time-until text. Use no hex in views: use Theme tokens and add any missing ones with dark values. Keep the Thai UI text exactly as in the previews; touch targets ≥ 44 pt.

Debug flags:
- add -surveyDay <0-6> and -surveyStatus <status>
- drop -surveyWindow handling here
- update the CLAUDE.md simulator list

Use code-review-graph first, then read the source. Build; run on an iPhone 16 simulator with `-screen home -homeTab survey -homeDemo YES -surveyListDraft YES`; compare with states/*.png and measure in the PDFs.

Finish with a summary:
- the files changed
- the tokens, helpers and parameters added
- the removed date filter and history button
- the remaining differences from the board
- answers to the open questions
