# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/install-tracking-ipad/CLAUDE_CODE_TASK.md.

InstallTrackingView is a placeholder ("อยู่ระหว่างพัฒนา"). Build the iPad install tracking page for ONE project from
the board iPadInstall.dc.html, iPad (regular width) only. Work in four phases, and stop and report with screenshots
after each one:

A. Frame:
   - Header: back, project name, sub line, "รายงานสำรวจ (ดูอย่างเดียว)" button.
   - The 7-tab bar.
   - The 5-cell KPI strip.
   - The dock stays visible.
   - Route install-mode cards and installing PWA stations here on iPad (report what goes where).
B. ภาพรวม card:
   - Gantt with the day axis, today line, step rows, expandable sub-tasks, plan/actual/forecast/overrun bars.
   - The Gantt | S-Curve switch.
   - The step sheet: cause chips, checklist, photos, "ยืนยันเสร็จขั้นนี้", updating the install progress.
C. The rest of ภาพรวม: เอกสารโครงการ tiles + item sheets, the site panel tabs, and the actions sheet from the KPI.
D. รายงานประจำวัน tab: KPI row, report table from DailyReportListView data (buttons open DailyReportScreen), and the
   four cards under it.

Rules:
- Tabs คำขอรายสัปดาห์ / ทดสอบ IEC / เอกสาร / แผนก่อสร้าง only LINK to the existing screens.
- Show only what has a data source. Hide weather, milestones, instalments, RFI/NCR/CO, labour, safety, PPC, SPI, cause
  etc. when there is no model, and list them.
- -installDemo YES may seed the board's example data, for screenshots only.

Do not touch:
- the iPhone
- the existing report/test/docs/schedule screens
- the PWA home
- stored model fields

Steps:
1. Read the task, then iPadInstall.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPad Pro 13" simulator (landscape).
4. After each phase, save screenshots in docs/ui/install-tracking-ipad/screenshots/
   (A: 01 · B: 02, 03 · C: 08 · D: 05) and compare them with states/.
5. Report:
   - the differences
   - the routing
   - the plan source used (InstallInfo steps vs the MP plan)
   - every element hidden for lack of data
   - the open questions
```
