# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/pwa-maintenance-iphone/CLAUDE_CODE_TASK.md.
It is the iPhone PWA home, stage บำรุงรักษา. That overview is already built
(TCRoofKit/Sources/SurveyUI/SurveyHome+Overviews.swift, maintenanceOverview), so the task
is: (1) replace the stage pills with the segmented switch with counts (shared with
docs/ui/pwa-plan-iphone/CLAUDE_CODE_UPDATE_v2.md §1 — build it once in TCRoofUI; if it
already exists, reuse it), rename งานติดตั้ง → ติดตั้ง, and (2) verify the maintenance
overview against states/ and fix any differences. Read the task, then PhoneHome.dc.html as
text (the isMnt block and the stage switch); measure on the PDFs. Use code-review-graph
first as CLAUDE.md says. Compact width only. Build with your own -derivedDataPath, run
-screen pwa -surveyHomeTab maintenance on an iPhone simulator (DEBUG seed), save
screenshots in docs/ui/pwa-maintenance-iphone/screenshots/, compare them with states/,
then report differences and the open questions in §6.
```
