# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/pwa-solar-survey-ipad-v3/CLAUDE_CODE_TASK.md.

The iPhone PWA home v3 is built (commit c06b723). The iPad still shows the v1 design (padPage).
Bring the iPhone v3 design to the iPad by reusing that code, not copying it.
Change ONLY these seven things, on iPad (regular width) only:

1. Dock (PadTabs):
   - Items: หน้าแรก · โครงการ(badge) · งานบ้าน · เอกสาร · เครื่องมือ · สแกน | ตั้งค่า.
   - แผนงาน and ติดตั้ง leave the dock. Keep their modules reachable, and report where.
   - Update -homeTab. The dock's look does not change.

2. The โครงการ (.pwa) stack uses the same host as PWAPhoneRoot, made size-agnostic:
   - It provides PWAOverviewHost, the bell and openPlan.

3. Header:
   - Title "โครงการ PWA", 30 pt. No subtitle and no ···; report where the ··· actions went.
   - Round search that grows left to 420 pt, plus the bell.

4. Nav row:
   - TCCountSegments "โครงการ | แผนงาน | บำรุงรักษา" plus the filter button, 63 pt margins.
   - It replaces the stage tabs, the 4 stat boxes and the list heading.

5. Filter popover on iPad: a 248 pt list.
   - Sections: ประเภทงาน / สถานะงาน (with ล้าง) / เรียงตาม.
   - The same rules as iPhone.

6. Project grid: 3 columns of the iPhone-size JobCard.
   - Survey cards and install-phase cards, as on iPhone v3. Drop the compact guard in phaseStations.
   - The floating + is 64 pt.

7. Install and maintenance overviews:
   - One wide summary card (330 | 300 | flexible), then the row filters, then rows in 3 columns.
   - Same logic as iPhone.

Do not touch:
- any iPhone path (v3 screenshots must stay identical)
- JobCard content, the overview logic, the wizard, PWAPlanPhoneView, StationDocsScreen
- PadHome, data models

Steps:
1. Read the task, then iPadHome.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPad Pro 13" simulator (landscape).
4. Save screenshots of states 01, 02, 03 and 09 in docs/ui/pwa-solar-survey-ipad-v3/screenshots/ and compare them with states/.
5. Report:
   - the differences from states/
   - the new dock targets (เอกสาร, bell)
   - where แผนงาน, the install module and the ··· actions went
   - the open questions
```
