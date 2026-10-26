# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-c1-iphone-pv && git checkout -b feat/survey-c1-iphone-pv

Follow docs/ui/survey-c1-iphone-pv/CLAUDE_CODE_TASK.md.

Scope: only the iPhone (narrow) C1 roof page in its จัดแผง mode, and the core changes it needs. Work through change list
items 1–6 in order, and nothing else:
1. plan card: the โครงสร้าง | จัดแผง switch above the plan, the count tag on the plan, and the row
   แก้แผง · จัดแผงใหม่ · CAD under it
2. landscape pairs: Choice.landscapePairs / pairGap, laid out by RoofMountLayout, with the pair-gap stepper and the
   pairs numbered on the plan
3. ridge walkway width (Choice.ridgeWalkwayWidth, never narrower than RoofWalkway.band), one edge-distance stepper
   (setEave + setVerge), and the roof access block ด้านซ้าย | ด้านขวา
4. แก้แผง edit mode (tap a module to take it out or put it back, Choice.removed) and จัดแผงใหม่ (clear removed)
5. the iPhone tab order: 02 แผงและการวาง, 03 สรุปการจัดแผง (4 tiles), everything else under one closed disclosure;
   the section and photo cards hidden in จัดแผง
6. DEBUG -surveyC1 states, one CLAUDE.md sentence, PhoneRoofPVUITests

Leave alone:
- the โครงสร้าง tab's content
- the iPad layouts (beyond the new choices showing in their cards)
- the PDF and Excel layouts
- RoofWalkway's detail dimensions
- field ids and Excel cells
- the RoofDXF golden files: an old job must give the same file
No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read RoofPageWide (stackedColumn, roofCard,
openDebugState), RoofPageWide+Plan (planCard, planFooter), RoofPageWide+Mount (mountTab, mountSummary, mountFixing,
mountWalkway, mountAccessSide, mountTap, changeChoice), RoofMountC1 (Choice), RoofMountLayout, RoofMountStandard,
RoofWalkway and RoofPlan before writing code. Commit dcfcd18 removed the เอาแผงออก tool; item 4 brings removal back as
an edit mode on Choice.removed, by the designer's later decision.

Rules:
- The board's numbers are examples (assets/sample-data.json); never hard-code them. Engineering values come from the
  job, RoofMountStandard, RoofWalkway and the catalog.
- No modules-per-string figure without a source in the job.
- New Choice keys are optional (decodeIfPresent) and enter digest only when set.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle, RoofSegments.
- Split each new card into its own view or computed property.

When done:
- run swift test in TCRoofKit (new layout and decode tests; golden files unchanged)
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run PhoneRoofPVUITests, PhoneRoofFitUITests and RoofRulesUITests on an iPhone simulator
- save screenshots named like states/ to screenshots/
- tick the change list and answer the six open questions in your report

Commit and push feat/survey-c1-iphone-pv. Do not merge.
```
