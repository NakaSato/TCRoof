# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-a1-ipad-v2 && git checkout -b feat/survey-a1-ipad-v2

Follow docs/ui/survey-a1-ipad-v2/CLAUDE_CODE_TASK.md.

Scope: a pixel-parity pass of the iPad A1 ข้อมูลโครงการ page (InfoPageWide.padBody, its sections and
InfoPageBar.padBar) against iPadA1.dc.html and states/. The design is already built on main (see
docs/ui/survey-a1-ipad); do not redesign it. Work through the change list in §4 in order: render the states in
the simulator, compare them with states/ in a measured table, fix only rows with a visible difference, re-render.
Nothing else: no iPhone A1 changes, no SaveButton behaviour changes, no Schema.info / mapZoom / mapCrop / Excel /
PDF / completion changes, no changes to other pages or the shared header. Keep the intentional differences listed
in §2 (the "|" separators, the live GPS note, the zoom presets, the office address left out).

Start with the code-review-graph tools as CLAUDE.md says, then read InfoPageWide, InfoPageWide+Sections, A1Card,
RatioRow, inputBox, areaTile, InfoPageBar.padBar, SaveButton and JobEditor+Debug.renderInfo before changing code.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme / Home, hit
areas ≥ 44 pt.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/ (before and after), one iPhone A1 screenshot showing
it unchanged, the comparison table, and answers to §6's open questions in your report. Commit on
feat/survey-a1-ipad-v2 and push it. If nothing needs fixing, commit only the screenshots and the report.
```
