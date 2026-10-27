# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-a4-ipad-v2 && git checkout -b feat/survey-a4-ipad-v2

Follow docs/ui/survey-a4-ipad-v2/CLAUDE_CODE_TASK.md.

Scope: only A4 น้ำท่วม's FloodPageWide (plus FloodCheck and FloodSection's screen drawing) as drawn in
iPadA4.dc.html:
- the right column in three cards (ประวัติน้ำท่วม, ความถี่ · สาเหตุ, จุดที่ได้รับผลกระทบ) with short display labels;
- the water level as a 5 cm stepper with a typed value and a 0–200 slider;
- the new ระดับติดตั้งต่ำสุด equation row with the freeboard as an answer (optional hidden field floodFreeboard,
  default 50, so old jobs compute as before);
- the restyled section drawing on screen (the PDF keeps today's drawing behind a style parameter);
- the bottom status icon and line.
Work through the change list in §4 in order, and nothing else:
- no other pages, no shared bar changes beyond A4's status;
- no changed schema ids, labels, option values or Excel cells;
- no change to FloodCheck's pass/fail rules or the GISTDA card.

Start with the code-review-graph tools as CLAUDE.md says, then read the files in §3. Find every reader of
FloodCheck.minCm and freeboardCm (B2, B4, B5, equipHeight, the PDF) before changing them.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme, hit areas
≥ 44 pt, each card / row / tile its own computed property.

When done:
- swift test in TCRoofKit (with the new FloodCheck tests);
- the xcodebuild app build with your own -derivedDataPath (in the background);
- simulator screenshots named like states/ saved to screenshots/ (plus one iPhone A4 to show it is unchanged
  or how it shares the page);
- the change list ticked, and answers to §6's open questions in your report.
Commit on feat/survey-a4-ipad-v2 and push it.
```
