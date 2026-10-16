# Prompt for Claude Code

```
git fetch origin && git switch -c feat/daily-report-ipad origin/design/daily-report-ipad
```

```
Follow docs/ui/daily-report-ipad/CLAUDE_CODE_TASK.md.

FIRST check that TCRoof/Views/Job/RoutineReports/DailyReportScreen.swift and TCRoofKit/Sources/TCRoofCore/RoutineReport.swift
exist. If not, STOP and report.

Re-lay ONLY DailyReportScreen on iPad regular width (≥ 1000 pt) as the board's one-page layout (iPadDaily.dc.html, step 0).
Keep the model, the PDF, signing and the iPhone as they are.

1. Left column:
   a. The key plan card: A2 picture, today's lines as numbered pins in their colour, ghost "+" pins for this week's MP
      tasks (tap adds a line), select / dim, ⛶ full screen.
   b. The task tabs, then the selected task panel: MP task + weight, status pill, วัสดุ / ปัญหา / ✕ buttons,
      quick picks +10/+20/+30/+50/เสร็จ, photos + camera, and the "สถานี +x% · MP รวม / แผน / ช้ากว่า" line.
   c. Material / problem rows under the panel. The card scrolls.
2. Right column:
   a. Day switcher ‹ › and the เวลาทำงาน chip.
   b. ทีมงานวันนี้: labour tiles (คน·ชม., ทำงานได้จริง after rain), คน | เครื่องมือ tabs, rows with a count DROPDOWN
      (1–12, ลบออก), "+ เพิ่มตำแหน่ง / เครื่องมือ" dropdown.
   c. ลงนาม: reporter * and inspector signature boxes with names (existing sign sheet).
3. Bottom bar: status, บันทึกร่างตอนนี้, PDF 3 หน้า (existing preview), ส่งรายงาน (disabled with the reason).
4. Keep weather editing reachable (report where).
5. DEBUG -routineDaily onepage and -routineDailyState … (one line in CLAUDE.md).

Rules:
- Station % and behind-plan from MasterSchedule weights and location counts.
- Labour hours minus rain hours inside the working time.
- The new math lives in TCRoofCore, with tests.
- Theme tokens (5 task colours), TCButtonStyle, 44 pt.
- Don't ship the board's example images.

Steps:
1. Read the task, then iPadDaily.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test with the new tests.
4. Run on an iPad Pro 13" simulator with -screen daily -routineKeyPlan YES. Save screenshots 01, 02, 04, 06 and 08 in
   docs/ui/daily-report-ipad/screenshots/ and compare them with states/. Check that -routineDemo pdf is unchanged.
5. Commit on feat/daily-report-ipad and push it (no merge).
6. Report:
   - the differences
   - where weather went
   - what the working-hours chip does
   - the open questions
```
