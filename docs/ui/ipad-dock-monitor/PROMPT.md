# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/ipad-dock-monitor && git checkout -b feat/ipad-dock-monitor

Follow docs/ui/ipad-dock-monitor/CLAUDE_CODE_TASK.md.

Scope: only the iPad main dock's new Monitor tab, as drawn in boards/ (between เอกสาร and เครื่องมือ). That means:
- the tab-monitor glyph asset;
- PadTab.monitor and its dock item, with a red badge counting handed-over stations in .alarm or .offline;
- a MonitorRoot that shows the existing บำรุงรักษา overview pinned to that stage, without the segment and without
  writing solarSurvey.homeTab.

Work through the change list in §5 in order, and nothing else:
- no change to the iPhone dock, the other tabs' roots or badges, or the settings sheet;
- no change to TCTabBar beyond §5 item 6;
- no fleet monitoring page (that is CHA-21), no Growatt API work, no new MaintenanceStationSummary fields.
Contractors don't get the tab.

Start with the code-review-graph tools as CLAUDE.md says. Then, before writing code, read:
PadTabs.swift, PWARoot.swift, SurveyHome.swift (the AppStorage homeTab and the segment), SurveyHome+Overviews.swift,
PWAPhoneTabs.swift (Job.maintenanceSummary), GrowattDemoFeed, TCTabBar / TCTabItem in Layout.swift and
HomeNavbarUITests. Share PWARoot's overview host rather than copying it.

The badge numbers on the boards are examples. Colours come from Theme, hit areas are ≥ 44 pt, and the glyph is a
template asset.

When done:
- run the xcodebuild app build with your own -derivedDataPath (in the background), and swift test;
- run HomeNavbarUITests on an iPad simulator;
- save dock screenshots like states/ to screenshots/;
- tick the change list;
- answer §7's open questions in your report.
Commit on feat/ipad-dock-monitor and push it.
```
