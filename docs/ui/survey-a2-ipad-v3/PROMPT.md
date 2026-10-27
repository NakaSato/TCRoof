# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-a2-ipad-v3 && git checkout -b feat/survey-a2-ipad-v3

Follow docs/ui/survey-a2-ipad-v3/CLAUDE_CODE_TASK.md.

Scope: only the iPad (regular width) layout of A2 ภาพสถานที่ติดตั้ง in SitePageWide as drawn in iPadA2.dc.html:
the symbol rail on the left (the palette moved out of the side column), the picture at today's width, the
narrower side column (sources one per row, "LIST ในภาพ" in one column, hints under the titles, notes filling the
rest), and the new full-screen bar (ออกจากเต็มจอ pill left, title centred, อาคารในโครงการ · n/N toggle right) with
the picture fitted to the height and the building panel closed by default, floating on the right when opened or
while a card is armed. Work through the change list in §4 in order, and nothing else: no iPhone page or iPhone
full-screen changes, no changes to how symbols, shapes, models, tools, undo, layers or SiteSync behave, no schema,
storage, PDF, Excel or DXF changes, no other pages. Reuse paletteButton / arm / ToolIcon and the existing panel;
don't fork their logic.

Start with the code-review-graph tools as CLAUDE.md says, then read SitePageWide (padBody, pictureWidth,
rightColumn, heading, the sections, paletteButton), SitePageWide+Full (padFull, fullHeader, fullPicture,
modelPanel, panelOpen), SitePageWide+Toolbar and SiteMarksEditor before writing code.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme, hit areas
≥ 44 pt, split each card and bar into its own computed property.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/ (plus one iPhone A2 and one iPhone full screen to
show they are unchanged), the change list ticked, and answers to §6's open questions in your report. Commit on
feat/survey-a2-ipad-v3 and push it.
```
