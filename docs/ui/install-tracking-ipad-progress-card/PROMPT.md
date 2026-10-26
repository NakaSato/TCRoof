# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-progress-card && git checkout -b feat/install-tracking-ipad-progress-card

Follow docs/ui/install-tracking-ipad-progress-card/CLAUDE_CODE_TASK.md.

Scope: only the iPad overview's ความคืบหน้าเทียบแผน card (progressCard) as drawn in iPadInstall.dc.html (menu "ov"):
add the เหตุการณ์สำคัญ milestone row and its legend item (from InstallPlan.milestones, sharing the iPhone's strip),
the weather line under the days (past days from the daily reports' weather slots, future days from an optional forecast
input filled only by the DEBUG demo), and the งวดเบิกเงิน row (from a new optional RoutineReport.Settings.billing list).
Work through the change list in §5 in order, and nothing else: no changes to the KPI strip, the documents / site row,
other tabs, the S-curve drawing, the iPhone page's look, rules or sync. The only stored change is the optional billing
list, decoded with decodeIfPresent defaults.

Start with the code-review-graph tools as CLAUDE.md says, then read InstallTrackingPage+Progress, the iPhone's
milestoneStrip in InstallTrackingPage+PhoneProgress, MilestoneDiamond, InstallPageData / InstallPlan and
RoutineReport (Daily.weather, Settings) before writing code.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme, SF Symbols for the
weather, split views into computed properties.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on feat/install-tracking-ipad-progress-card and push it.
```
