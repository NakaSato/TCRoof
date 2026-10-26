# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-settings && git checkout -b feat/install-tracking-ipad-settings

Follow docs/ui/install-tracking-ipad-settings/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's new in-page tab ตั้งค่าโครงการ as drawn in iPadInstallSettings.dc.html:
the station card and category list on the left, one category on the right (ทีมและสิทธิ์, หัวเอกสาร, แบบก่อสร้าง,
รอบรายงาน, การเชื่อมต่อและ IEC, ข้อมูลอ้างอิง), the text editor, person, revision history and upload sheets, and the
unsaved-changes bar. Work through the change list in §5 in order, and nothing else: no refactors, renames or restyles
outside it, no change to how the iPhone settings look or behave, no changes to other tabs, JobAccessCard,
RoutineSettingsSheet or StationFactsSheet (call them), no Firestore rule or CloudSync behaviour changes, no PDF or
Excel changes. The only stored change is the optional Job.drawingsJSON of §5 item 6 (with StationDrawings in
TCRoofCore and its tests), decoded with decodeIfPresent defaults and synced the way weeklySentJSON is. Leave out
what §2 lists as having no stored source.

Start with the code-review-graph tools as CLAUDE.md says, then read InstallTrackingPage (Tab, the tab bar, Route,
Debug), InstallTrackingPage+PhoneSettings and +Phone, JobAccessCard, RoutineSettingsSheet, StationFactsSheet,
RoutineReport.Settings, StationDocs.Context and how Job.weeklySentJSON is stored and synced before writing code.
Reuse the iPhone's data, wording and permission checks.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme (icon tints as
named constants in one place), TCButtonStyle, hit areas ≥ 44 pt, split each card into its own computed property.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on feat/install-tracking-ipad-settings and push it.
```
