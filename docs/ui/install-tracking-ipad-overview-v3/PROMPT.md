# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-overview-v3 && git checkout -b feat/install-tracking-ipad-overview-v3

Follow docs/ui/install-tracking-ipad-overview-v3/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking overview's bottom row (siteRow) as drawn in iPadInstall.dc.html (menu "ov"):
a fixed 258 pt band, เอกสารโครงการ (wider, tiles in 3 columns) beside the site panel (its four stat tiles as four
rows, รายละเอียดงาน in its header). The KPI strip and the plan card stay as they are (the card still fills the height
down to the dock and the page still scrolls to the row). Work through the change list in §5 in order, and nothing else:
no changes to the plan card, other tabs, the iPhone page, the sheets, InstallPageData, models, sync or rules.

Start with the code-review-graph tools as CLAUDE.md says, then read InstallTrackingPage+Site (siteRow, card, docsCard,
docTile, sitePanel, siteInfo, siteInfoBody, kpiTile, siteRisks, siteLabour) and InstallTrackingUITests before writing
code.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme, hit areas ≥ 44 pt,
split views into computed properties.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on feat/install-tracking-ipad-overview-v3 and push it.
```
