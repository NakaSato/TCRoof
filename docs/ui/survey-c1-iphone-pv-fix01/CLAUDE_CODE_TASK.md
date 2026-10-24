# Task: iPhone · C1 หลังคา `จัดแผง` fix 01: what PR #170 left out (board 24 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/survey-c1-iphone-pv-fix01`, then paste `PROMPT.md`, or type
> `Follow docs/ui/survey-c1-iphone-pv-fix01/CLAUDE_CODE_TASK.md`

- **Board:** `iPhoneC1.dc.html` (390 × 844), the same board as the first hand-off (`design/survey-c1-iphone-pv`), unchanged since.
  - Read it as text and search for `isPair`, `pgT`, `pvRows`, `pvWalkT` and `pva0`.
  - Its script is a toy layout for the states only. **Don't port it.**
- **Everything on the board is example data** (`assets/sample-data.json`). Never hard-code it.

## Where this sits

PR #170 (`602c7c7`, `f6a9a41`) built items 1, 4 and 5 of the first hand-off and part of item 3:
- the switch above the plan, the count tag, `แก้แผง · จัดแผงใหม่ · CAD`
- the edge stepper (`edgeStepper`: `setEave` + `setVerge`)
- `02` / `03` and the closed `ตั้งค่าและรายละเอียดเพิ่มเติม`
- `PhoneRoofPVUITests`

Its commit says: *"Landscape pairs and the ridge walkway width are not built yet."* This task is only those, plus two board details `02` still misses.

## Scope: only this

**In scope:**
- `TCRoofCore/RoofPV` (`RoofMount.Choice`, `RoofMountLayout`, `RoofMountStandard`, quantities and clamps where pairs change them)
- `RoofPlan` (pair numbers, walkway width)
- `RoofPageWide+PhonePV.swift` and `mountRidgeWalkway` / `mountAccessSide`
- the iPad cards only so the new choices show there too

**Do not touch:**
- what PR #170 built, beyond the lines named here
- the structure tab
- the PDF and Excel layouts
- `RoofWalkway`'s detail dimensions
- field ids and Excel cells
- the `RoofDXF` golden files: an old job gives the same file

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `RoofMountC1.swift` (`Choice`, `CodingKeys`, `digest`)
- `RoofMountLayout.swift` (`Options`, the row fill and the landscape fill)
- `RoofMountStandard.swift`, `RoofWalkway.swift`, `RoofMountQuantities.swift`, `RoofMountClamps.swift`
- `RoofPlan.swift` (walkways, access, removed slots)
- `RoofPageWide+PhonePV.swift`
- `RoofPageWide+Mount.swift` (`mountFixing`, `mountRidgeWalkway`, `mountAccessSide`, `changeChoice`)
- `PhoneRoofPVUITests`

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/05` |
| `states/04-landscape-tight.png` | `แนวนอน` + `วางชิดกัน` |
| `states/05-landscape-pairs.png` | `แนวนอน` + `วางคู่ 2 แผ่น`: pairs along the row, a gap between pairs, the pairs numbered above the first row |
| `states/06-landscape-pairs-settings.png` | `การเรียงแผงแนวนอน`, its note and `ระยะเว้นระหว่างคู่` |
| `states/07-access-left-walkway.png` | Access `ด้านซ้าย`, walkway 1.00 m wide |
| `iPhoneC1.dc.html`, `grf.css`, `assets/sample-data.json` | Design source and example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Landscape pairs: core (`states/05`)
- Add two `RoofMount.Choice` fields, both encoded only when set, decoded with `decodeIfPresent` defaults, and added to `digest` only when set:
  - `landscapePairs: Bool` (default false)
  - `pairGap: Double?` (metres; nil = `RoofMountStandard.pairGap`, a new fixed value decoded with a default)
- The board shows 0.40 m. Put it in the standard, not in a view.
- Pass both through `Options`.
- **Meaning** (only with `landscape` on): in each row the modules go in pairs along the row, i.e. along the eave and ridge.
  - The two of a pair are `standard.moduleGap` apart.
  - The next pair starts `pairGap` after.
  - Rows up the slope are unchanged.
- **A run holds whole pairs:**
  - a single module left at the end of a run is dropped
  - a slot blocked by an obstacle, a walkway or a removed slot breaks its pair
  - Say in the doc comment what happens to the other half, and report it.
- **Quantities:** each pair is its own rail run when the rails run along the row. Rails, splices and end clamps follow (`RoofMountQuantities`, `RoofMountClamps`). Report what changed.
- **Tests:**
  - one face with pairs, with an exact count and positions for a given width
  - the odd module dropped
  - an obstacle breaking a pair
  - old Choice JSON decodes with `landscapePairs == false`
  - the `RoofDXF` golden files unchanged

### 2. Landscape pairs: UI and plan (`states/05`, `06`)
In `mountSettingsPhone`, under `การวางแผง`, when `landscape` is on:
- **`การเรียงแผงแนวนอน`:** a `RoofSegments` of `วางชิดกัน | วางคู่ 2 แผ่น`, 44 pt.
  - Under it a 12 pt `Theme.inkMuted` note: tight → `ทุกแถวชิดกัน`; pairs → `วางแผงเป็นคู่ตามแนวแถว แล้วเว้นระยะระหว่างคู่`.
- **With pairs:** a 52 pt row `ระยะเว้นระหว่างคู่ − 0.40 ม. +`, step 0.10 m, range 0.20–1.00 m.
  - Each change goes through `changeChoice` (an undo step).
  - A stepper at its limit is dimmed and does nothing.
  - Build it like `edgeStepper`.
- **iPad:** the same two controls in `mountFixing` when `landscape` is on.
- **Plan:** with pairs on, number the pair columns above the first row (`1, 2, 3 …`, 8.5 pt bold `Theme.primary` on a white chip), as `states/05`.
  - Draw them in `RoofPlan` as text ops tagged `pairs`, so the PDF and DXF can skip them.
  - Report whether you kept them out of the PDF.

### 3. Ridge walkway width (`states/07`)
- Add `Choice.ridgeWalkwayWidth: Double?` (metres; nil = `RoofWalkway.band`). Encode it only when set; add it to `digest` only when set.
- **Setback:** with a width, `RoofMountLayout` uses `width / 2 + 0.05` instead of `RoofWalkway.ridgeClear` for the ridge setback.
- **The team's detail keeps its size:** the 0.90 m band, grating and lifeline stay centred in the wider clear width.
- **Plan:** `RoofPlan` draws the walkway's clear width at the chosen size. The DXF does the same only if it already draws a clear outline. Golden files unchanged when the width is nil.
- **UI:** under the `ทางเดินตามสันหลังคา` switch, while it is on, a 52 pt row `ทางเดินตามสันหลังคา กว้าง − n.nn ม. +`.
  - Step 0.10 m.
  - **Minimum `RoofWalkway.band` (0.90 m)**, not the board's 0.40, so the detail always fits. Maximum 1.50 m.
  - Show it on iPhone and iPad.
- **Test:** a wider walkway moves the first row on each face down the slope by the extra half-width, and removes no module when the face has room.

### 4. `02`'s module row and roof access (`states/06`, `07`)
**`รุ่นแผง`:**
- Show the module's name from the catalog (`ModuleRules` catalog or `EquipmentCatalog`; the standard's module matched as `RoofMountYield` matches it).
- Under it: `<length> × <width> มม. · Voc <x> V · จากมาตรฐานโครงการ`.
- With no catalog match, keep today's `W | L × W ม.` line.

**`ทางขึ้นหลังคา (Roof access)`:** in place of today's compact `mountAccessSide` on iPhone:
- the label
- a full-width `RoofSegments` `ด้านซ้าย | ด้านขวา` (44 pt)
- the note `ทางขึ้นอยู่ปลายสันหลังคาด้านซ้ายหรือขวาเท่านั้น และต่อกับทางเดินตามสัน` (12 pt `Theme.inkMuted`)

Keep `accessRight`'s default. The iPad keeps its compact picker.

### 5. DEBUG, docs and test
- **New `-surveyC1` states** (with `-surveyPage roof`, iPhone):
  - `pvland2`: landscape pairs, the plan in view
  - `pvpairs`: scrolled to the pair gap
  - `pvaccessleft`: access left, walkway 1.00 m
  - They write into the demo job like the other `pv…` states.
- **CLAUDE.md:** add them to the `-surveyC1` item in one sentence, naming `landscapePairs`, `pairGap` and `ridgeWalkwayWidth`.
- **Extend `PhoneRoofPVUITests`:**
  - pick `แนวนอน` → `วางคู่ 2 แผ่น`; the pair-gap row appears and `+` reads 0.50
  - the walkway width row's `−` is dimmed at 0.90
  - `ด้านซ้าย` is selected after a tap

## Rules
- Colours from `Theme`, no hex in views, no `Color.white`. Hit areas ≥ 44 pt. `TCButtonStyle`, `RoofSegments`.
- **New `Choice` keys are optional.** An old job's layout, PDF, Excel and DXF are unchanged.
- Engineering values come from the job, `RoofMountStandard`, `RoofWalkway` and the catalog, never from the board.
- Split new controls into their own computed properties.

## Check list
- [ ] `swift test` in `TCRoofKit` passes (pairs, decode and walkway tests; golden files unchanged).
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, in the background.
- [ ] `PhoneRoofPVUITests`, `PhoneRoofFitUITests` and `RoofRulesUITests` pass on an iPhone simulator.
- [ ] iPhone 16 Pro screenshots `04`–`07` in `screenshots/`, taken with `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyPage roof -surveyC1 <state>`.
- [ ] The iPad C1 (`-surveyWideA1 YES -surveyPage roof -surveyC1 pv`) shows the new controls and still lays out.

## Open questions (report, don't decide)
1. **Pair direction:** pairs along the row (as built here), or up the slope? This is still open with the designer.
2. **Gap inside a pair:** the board's note said 0.4 ซม.; the standard's `moduleGap` is 2 ซม. (the clamp). Which one is right?
3. **Walkway width:** the board allows 0.40–1.20 m with 0.60 m by default, under the team's 0.90 m detail. Can it be narrower than the detail, and what should the default be?
4. **`สตริง` tile:** what did PR #170 use for modules per string, and is that the source to keep?
