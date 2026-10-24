# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-c1-iphone-pv-fix01 && git checkout -b feat/survey-c1-iphone-pv-fix01

Follow docs/ui/survey-c1-iphone-pv-fix01/CLAUDE_CODE_TASK.md.

Scope: only what PR #170 left out of the iPhone C1 จัดแผง tab. Work through change list items 1–5 in order, and
nothing else:
1. landscape pairs in the core: Choice.landscapePairs / pairGap (RoofMountStandard.pairGap default), laid out by
   RoofMountLayout, whole pairs only, quantities per pair
2. pairs in the UI: วางชิดกัน | วางคู่ 2 แผ่น and the pair-gap stepper (iPhone 02 and iPad mountFixing), and the pairs
   numbered on the plan
3. Choice.ridgeWalkwayWidth: the ridge setback from it, never narrower than RoofWalkway.band, a width stepper under the
   ridge walkway switch
4. 02's รุ่นแผง from the catalog (name, size, Voc) and the iPhone roof access block ด้านซ้าย | ด้านขวา with its note
5. DEBUG -surveyC1 pvland2 | pvpairs | pvaccessleft, one CLAUDE.md sentence, PhoneRoofPVUITests extended

Leave alone:
- what PR #170 built, beyond the lines the task names
- the structure tab
- the PDF and Excel layouts
- RoofWalkway's detail dimensions
- field ids and Excel cells
- the RoofDXF golden files: an old job must give the same file
No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read RoofMountC1 (Choice), RoofMountLayout,
RoofMountStandard, RoofWalkway, RoofMountQuantities, RoofMountClamps, RoofPlan, RoofPageWide+PhonePV and
RoofPageWide+Mount (mountFixing, mountRidgeWalkway, mountAccessSide) before writing code.

Rules:
- The board's numbers are examples (assets/sample-data.json); never hard-code them.
- New Choice keys are optional (decodeIfPresent) and enter digest only when set.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle, RoofSegments.

When done:
- run swift test in TCRoofKit (golden files unchanged)
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run PhoneRoofPVUITests, PhoneRoofFitUITests and RoofRulesUITests on an iPhone simulator
- save screenshots named like states/ to screenshots/
- tick the change list and answer the four open questions in your report

Commit and push feat/survey-c1-iphone-pv-fix01. Do not merge.
```
