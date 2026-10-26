# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-weekly-request

Follow docs/ui/install-tracking-ipad-weekly-request/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's คำขอรายสัปดาห์ tab, moved from a pushed screen into the page as the R1
request form drawn in iPadInstall.dc.html (menu "wq"). Work through the change list in §5 in order, and nothing else:
no refactors, renames or restyles outside it, no iPhone changes, no PDF layout changes, no Firestore rule changes.
The only model change is the two optional fields in §5 item 2 (PlanLine.days, WeeklyRequest.crewOff), decoded with
decodeIfPresent defaults.

Start with the code-review-graph tools as CLAUDE.md says, then read InstallTrackingPage, WeeklyRequestScreen,
RoutineReport (WeeklyRequest, PlanLine, requestDraft) and RoutineReportPages.request before writing code. Reuse the
existing send / send back / approve / reopen paths and isEditable(external:); do not change their behaviour.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme, hit areas ≥ 44 pt,
split each card into its own computed property.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on this branch.
```
