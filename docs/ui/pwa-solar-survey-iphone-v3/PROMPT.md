# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/pwa-solar-survey-iphone-v3/CLAUDE_CODE_TASK.md.

The PWA project home on iPhone (SurveyHomeView inside PWAPhoneTabs) is already built from pwa-solar-survey-iphone-v2 and
pwa-maintenance-iphone. Change ONLY these five things, on iPhone only:

1. Dock: drop the PWA module's own dock.
   - The PWA module becomes the main dock's "กปภ." stack (PhoneTabs .pwa), with the main dock showing on its root.
   - "แผนงาน" moves into the nav (item 2), and "เอกสาร" is the main dock's tab.
   - Put PWA project settings in a row of the main settings sheet for now, and report.

2. Header:
   - Title "โครงการ PWA" (22 pt). Remove the old title and subtitle.
   - Round search button, plus a new bell with an unread badge that opens notifications.
   - No "···" menu: keep its actions reachable, and report where.
   - Under the header: TCCountSegments "โครงการ | แผนงาน | บำรุงรักษา" plus an always-visible filter button. "แผนงาน" pushes PWAPlanPhoneView.
   - This replaces the stage pills.

3. Filter popover:
   - New first section "ประเภทงาน": ทั้งหมด / ติดตั้ง / บำรุงรักษา, with counts. It picks the view.
   - "สถานะงาน" and "เรียงตาม" show only for ทั้งหมด.
   - Reset also resets the type, and the active dot shows when the type is not ทั้งหมด.
   - Add "-surveyHomeType".

4. Project cards keep JobCard's layout.
   - Survey cards get a blue "สำรวจ" badge.
   - Install-phase cards get a green hard-hat "ติดตั้ง" badge.
   - Their ring and 10-segment bar are coloured by InstallOverview.pace (late red, on plan blue, done green, behind-plan pale red).
   - Next row: "กำลังทำ <task>" plus "ช้ากว่าแผน n%" or "ตามแผน".
   - Chips: plan/actual, ส่งมอบ, contractor.

5. Maintenance rows become tappable, with a "›".
   - Each row opens the closest existing station screen.
   - Do not build the station page (reference/ only), and report what it opens.

Do not touch:
- the install and maintenance overview bodies
- PWAPlanPhoneView, StationDocsScreen, the survey wizard
- the iPhone home, the iPad, or data models

Steps:
1. Read the task, then PhoneHome.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPhone simulator.
4. Save screenshots of states 01, 02, 04 and 08 in docs/ui/pwa-solar-survey-iphone-v3/screenshots/ and compare them with states/.
5. Report:
   - the differences from states/
   - what replaced PWAPhoneTabs
   - where PWA settings and the old ··· actions went
   - what a maintenance row opens
   - the open questions
```
