# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-a3-ipad-v3 && git checkout -b feat/survey-a3-ipad-v3

Follow docs/ui/survey-a3-ipad-v3/CLAUDE_CODE_TASK.md.

Scope: only the iPad A3 หม้อแปลง · MDB page (ElectricalPageWide and its +Cards / +A2 files) as drawn in
iPadA3.dc.html, which means:
- the compact A2 ใส่จากภาพ A2 button and no subtitle;
- TX size picks fill the empty V / vector group / %Z with standard values and show the In แรงต่ำ hint;
- the nameplate fields as menus with an อื่น ๆ way out;
- the MDP main breaker's AT / AF (อัตโนมัติ) / Icu menus with + เพิ่ม, and ยี่ห้อ split from รุ่น;
- tappable CB ลูกย่อย rows opening the existing breaker editor as the board's popover;
- the 0.4 kV meter with no transformer;
- the bottom line.
Work through the change list in §4 in order, and nothing else:
- no iPhone A3, SLD page, SiteSync rule or other page changes;
- no changed schema ids, labels or Excel cells;
- new model fields optional with decodeIfPresent;
- reuse A3Input / the existing breaker editor / kvaSizes / plateText; don't fork their logic.

Start with the code-review-graph tools as CLAUDE.md says, then read the files in §3, and find every reader of
Transformer, Board.brand, Breaker and meterKV before changing any data. If §4.6's LV-only storage reaches beyond the
readers listed in §3, build the UI only and report the readers.

The board's lists and standard values are examples to confirm (assets/sample-data.json, §6). Keep them in one
place, never inline in views. Colours from Theme, hit areas ≥ 44 pt, each card / menu field / popover its own
computed property.

When done:
- swift test in TCRoofKit;
- the xcodebuild app build with your own -derivedDataPath (in the background);
- simulator screenshots named like states/ saved to screenshots/ (plus one iPhone A3 to show it is unchanged);
- the change list ticked, and answers to §6's open questions in your report.
Commit on feat/survey-a3-ipad-v3 and push it.
```
