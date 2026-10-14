# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/pwa-plan-ipad/CLAUDE_CODE_TASK.md.

PWAPlanPhoneView is built for iPhone (one pane at a time). On iPad, the PWA home's "แผนงาน" currently pushes that
same iPhone page. Build the iPad layout by REUSING the iPhone pieces (calendarCard, schedule/agendaRow, curveCard,
ganttCard, dueGroup/dueRow, open(_:station:), PWAPlanBoard). Change ONLY this, on iPad (regular width) only:

1. Frame:
   - The plan shows inside the PWA home's frame: header "โครงการ PWA", nav "โครงการ | แผนงาน | บำรุงรักษา" with แผนงาน
     selected (no filter button), and the dock visible with โครงการ selected.
   - No back button and no "แผนงาน PWA" header.
   - Host it as an in-page segment (preferred) or as a pushed page with the same frame, and report which.
2. Left column, 440 pt: a framed "ตารางงาน" card (white, #DDE4ED, r16).
   - Inside: the calendar in a soft #F8FAFC panel (week/month toggle, day strip or month grid), then the agenda.
   - Agenda rows are soft #F8FAFC, r12.
   - The card ends 116 pt above the bottom. Only the agenda scrolls.
3. Right column (scrolls, 130 pt bottom padding):
   - "แผน MP" + "Master Plan · n สถานี".
   - The S-curve card at FULL width, chart 170 pt, labels not stretched.
   - Below it, two equal cards: "รายสถานี" (gantt) | "กำหนดส่ง" (framed, rows soft #F8FAFC r12).
4. No bottom gradient fade on this page.
   - No schedule or deadline filter buttons (not on the board; report).

Do not touch:
- the iPhone plan page
- PWAPlanBoard logic
- the PWA home's โครงการ and บำรุงรักษา views
- the screens rows open, data models

Steps:
1. Read the task, then iPadPwaPlan.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPad Pro 13" simulator (landscape) with
   -surveyHomeTab plan -pwaPlanDemo YES -pwaPlanToday 2026-10-12.
4. Save screenshots of states 01, 02, 05 and 07 in docs/ui/pwa-plan-ipad/screenshots/ and compare them with states/.
5. Report:
   - the differences
   - the hosting choice
   - that iPhone is unchanged
   - the open questions
```
