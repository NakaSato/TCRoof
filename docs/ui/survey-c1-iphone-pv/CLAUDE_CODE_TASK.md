# Task: iPhone · C1 หลังคา, the `จัดแผง` tab (board 24 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/survey-c1-iphone-pv`, then paste `PROMPT.md`, or type
> `Follow docs/ui/survey-c1-iphone-pv/CLAUDE_CODE_TASK.md`

- **Board:** `iPhoneC1.dc.html` (390 × 844, design canvas "iPhone · ขั้น 10/13 C1 หลังคา (แปลน + โครงสร้าง)").
  - Read it as text and search for `pvPanels`, `isPair`, `pvWalkT`, `pva0`, `pvEditGo` and `pvKpi`.
  - Its script holds a toy layout used only to draw the states. **Don't port it.** The layout stays `RoofMountLayout`.
- Thai strings in `backticks` are literal UI labels.
- **Everything on the board is example data** (โรงกรอง 19 × 16 ม., 78 แผง, 570 W, 14 แผงต่อสตริง and so on), listed in `assets/sample-data.json`. Never hard-code it.

## Where this sits

C1 is `RoofPageWide` (`TCRoofUI/Survey/Pages/Roof/`). On iPhone it is the stacked column (`narrow`, width < 600):
- `planCard` and its `planFooter`
- `sectionCard`
- `roofCard`, which holds `mountTab` in `.pv` mode
- `membersCard`
- `photosCard`

The roof PV layout itself (`RoofMountLayout`, `RoofMount.Choice`, `RoofWalkway`, `RoofPlan`) is already built. It already has:
- portrait / landscape (`Choice.landscape`)
- the ridge walkway (`walkwayRidge`) with the roof access at its left or right end (`accessRight`), drawn on the plan by `RoofPlan` (`ทางขึ้นหลังคา`)
- removed slots (`Choice.removed`, still decoded)

This task re-lays the **iPhone `จัดแผง` tab** to the board and adds three things to the layout:
- landscape pairs
- the ridge walkway's width
- one edge distance

**Note:** commit `dcfcd18` removed the `เอาแผงออก` tool. The board brings back taking modules out, as the plan's `แก้แผง` edit mode (item 4). It reuses `Choice.removed`. This is the designer's later decision; say so in the commit message.

## Scope: only this

**In scope:** the iPhone (`narrow`) layout of C1 in `.pv` mode, plus the core changes items 2–3 need.

**Do not touch:**
- the iPad layouts (`wideLayout`, and the stacked column at ≥ 600 pt), except that the new choices also work there through the existing cards
- the structure tab's content (`โครงสร้าง`): its cards, `แก้เสา (n)` / `ถ่ายแบบร่าง` / `CAD`, members and photos stay as they are
- the PDF and Excel layouts, the DXF golden files (`RoofDXF` fixtures must not change for an old job), field ids, Excel cells
- `RoofWalkway`'s detail dimensions (band, grating, lifeline, ladder)

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `RoofPageWide.swift` (`stackedColumn`, `roofCard`, `openDebugState`)
- `RoofPageWide+Plan.swift` (`planCard`, `planFooter`, `structureButtons`, `cadButton`)
- `RoofPageWide+Mount.swift` (`mountTab`, `mountSummary`, `mountFixing`, `mountWalkway`, `mountAccessSide`, `mountTap`, `standardStepper`, `changeChoice`, `undoMount`)
- `RoofMountC1.swift` (`Choice`, its `CodingKeys`, `digest`)
- `RoofMountLayout.swift` (`Options`, the row fill around line 400 and the landscape fill)
- `RoofMountStandard.swift`
- `RoofWalkway.swift`
- `RoofPlan.swift` (walkways and access)
- `PhoneRoofFitUITests`

Then run `tests_for` on what you touch.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/02` (@2x) |
| `states/01-structure.png` | The `โครงสร้าง` tab, unchanged (reference only) |
| `states/02-pv.png` | `จัดแผง`: the switch above the plan, the count tag on the plan, the ridge walkway and `ทางขึ้น` at its right end, then `แก้แผง · จัดแผงใหม่ · CAD` under the plan |
| `states/03-pv-settings.png` | `02 แผงและการวาง`: module, `การวางแผง`, edge distance, ridge walkway width, roof access |
| `states/04-landscape-tight.png` | `แนวนอน` + `วางชิดกัน` on the plan |
| `states/05-landscape-pairs.png` | `แนวนอน` + `วางคู่ 2 แผ่น` on the plan: pairs along the row with a gap between pairs, the pairs numbered |
| `states/06-landscape-pairs-settings.png` | `การเรียงแผงแนวนอน` and `ระยะเว้นระหว่างคู่` |
| `states/07-access-left-walkway.png` | Access `ด้านซ้าย`, walkway 1.00 m |
| `states/08-edit-panels.png` | `แก้แผง` on (filled, reads `เสร็จ`): 3 modules taken out (dashed), the hint line, the tag down to 75 |
| `states/09-summary.png` | `03 สรุปการจัดแผง`: four tiles |
| `iPhoneC1.dc.html` + `grf.css` | Design source |
| `assets/sample-data.json` | The example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Plan card on iPhone in `.pv` mode (`states/02`, `07`)
- Move the `โครงสร้าง | จัดแผง` switch **above** the plan (full width, 44 pt). Today it is in `planFooter` under the plan. Keep `setMode`.
  - Do it on iPhone in both modes, so the switch doesn't jump when the tab changes.
- **On the plan, `.pv` only:**
  - a tag at the top left, `<n> แผง · <kWp> kWp`, from `shownMount?.quantities` (the same numbers as the summary)
  - keep `RoofPlan`'s walkway band and `ทางขึ้นหลังคา` marker as they are
- **Under the plan, `.pv`:** one row of three buttons, 44 pt, widths about 1 : 1 : 0.8:
  - `แก้แผง` (pencil): item 4
  - `จัดแผงใหม่` (circular arrows): item 4
  - `CAD`: the existing `cadButton`
- **Today's `ย้อน` and `วาด` menu** (`mountButtons`) are not on the board:
  - keep them on iPhone as a second line under the row, `ย้อน` left and `วาด ▾` right, both 44 pt
  - report it (open question 1)
- **The plan caption:** `planCaption` stays above the switch; its `.pv` hint becomes the edit hint while editing (item 4).
- The structure tab's footer is unchanged, apart from the switch moving up.

### 2. Landscape pairs (`states/04`, `05`, `06`)
**Core (`TCRoofCore/RoofPV`):**
- Add two `RoofMount.Choice` fields, both encoded only when set, decoded with `decodeIfPresent` defaults, and added to `digest` only when set:
  - `landscapePairs: Bool` (default false)
  - `pairGap: Double?` (metres, nil = the default)
- Pass them through `Options` as `landscapePairs` and `pairGap`.
- **What it means** (only with `landscape` on): in each row the modules are set in pairs along the row, i.e. across the slope, along the eave and ridge.
  - The two modules of a pair are `standard.moduleGap` apart, as today.
  - Between one pair and the next the gap is `pairGap`.
  - So, along a row: module 1 · module 2 ‖ gap ‖ module 3 · module 4 ‖ gap ‖ …
  - Rows stay as today (up the slope).
- **A run must hold whole pairs.** A single module left over at the end of a run is dropped; a slot blocked by an obstacle breaks the pair.
  - Write the rule in the code's doc comment.
  - Report what you chose for a pair broken by an obstacle: drop both, or keep one.
- **Default gap:** the board shows 0.40 m. Add it as `RoofMountStandard.pairGap` (fixed values block, decoded with a default) rather than a literal in the view. The stepper writes `Choice.pairGap`.
- **Rails and clamps:** a pair is one rail run when the rails run along the row. The gap splits the run, so `quantities` (rails, splices, end clamps) count each pair as its own run.
  - Check `RoofMountQuantities` and `RoofMountClamps` and report what changed.
- **Tests:**
  - one face with pairs on, with an exact module count and positions for a given width
  - the last odd module dropped
  - an obstacle breaking a pair
  - an old Choice JSON without the keys decodes to `landscapePairs == false`
  - the `RoofDXF` golden files unchanged

**UI (`mountFixing`, iPhone and iPad):**
- When `landscape` is on, show `การเรียงแผงแนวนอน` with a two-option segment `วางชิดกัน | วางคู่ 2 แผ่น`.
  - Under it, a 12 pt `Theme.inkMuted` note: tight → `ทุกแถวชิดกัน`; pairs → `วางแผงเป็นคู่ตามแนวแถว แล้วเว้นระยะระหว่างคู่`.
  - Don't print the board's "0.4 ซม."; see open question 2.
- With pairs: a 52 pt row `ระยะเว้นระหว่างคู่ − 0.40 ม. +`, step 0.10 m, range 0.20–1.00 m, through `changeChoice` (an undo step). A stepper at its limit is dimmed and does nothing.
- **Plan:** with pairs on, number the pairs' columns above the first row (`1, 2, 3 …`, 8.5 pt bold `Theme.primary` on a white chip), as `states/05` does. Draw it in `RoofPlan` as text ops with a `pairs` tag so the DXF and PDF can skip it.
- **The fixing tiles:** `roof-fixing-options.json` has an `orientation` choice. Keep the tiles on iPad.
  - On iPhone `02 แผงและการวาง` uses a plain segment `แนวตั้ง | แนวนอน` as the board does.
  - Report if you would rather keep the tiles on iPhone too.

### 3. Ridge walkway width and edge distance (`states/03`, `07`)
**Ridge walkway width:**
- Add `Choice.ridgeWalkwayWidth: Double?` (metres, nil = `RoofWalkway.band`). Encode it only when set; add it to `digest` only when set.
- `RoofMountLayout` uses `width / 2 + 0.05` instead of `RoofWalkway.ridgeClear` for the ridge setback when it is set.
- **The team's detail is not resized:** the 0.90 m band, grating and lifeline stay centred in the wider clear width.
  - So the stepper's minimum is `RoofWalkway.band` (0.90 m), not the board's 0.40, and its maximum is 1.50, step 0.10.
  - The board's 0.60 default is below the detail; see open question 3.
  - Draw the walkway band on the plan at the chosen width (`RoofPlan`), and the DXF's clear-width outline too if it has one. Golden files unchanged when the width is nil.
- **UI:** `ทางเดินตามสันหลังคา กว้าง − n.nn ม. +` (52 pt row), shown while the ridge walkway is on.
  - Keep today's switch `ทางเดินตามสันหลังคา` above it.
  - The board has no switch, but a shed roof has no ridge and the switch is how the walkway is turned off; report.

**Edge distance:**
- One stepper `ระยะห่างจากขอบหลังคา − n.nn ม. +`, step 0.10, range 0.30–1.50.
- It edits the job's standard through `setStandard`, setting **both** `setEave` and `setVerge` to the value. It shows `max(setEave, setVerge)` until edited.
- `setRidge` is not touched, since the walkway sets it.
- Report this mapping (open question 5).

**Roof access:**
- Change `mountAccessSide` on iPhone to the board's block:
  - label `ทางขึ้นหลังคา (Roof access)`
  - a full-width segment `ด้านซ้าย | ด้านขวา` (44 pt)
  - the note `ทางขึ้นอยู่ปลายสันหลังคาด้านซ้ายหรือขวาเท่านั้น และต่อกับทางเดินตามสัน` (12 pt `Theme.inkMuted`)
- Keep `accessRight`'s default (false = left). The board's right is an example.

### 4. `แก้แผง` and `จัดแผงใหม่` (`states/08`)
**`แก้แผง`** toggles an edit mode (`@State var editModules`):
- **On:** the button is filled `Theme.primary` with `Theme.onPrimary` text reading `เสร็จ`.
- **Plan taps** (`mountTap`): a tap on a module slot takes it out (`Choice.removed` += its `SlotRef`) or puts a removed one back, through `changeChoice`, so each tap is an undo step.
  - A removed slot draws dashed, as `RoofPlan` already draws `removedByUser`; check it does on screen.
  - Taps on areas and obstacles keep selecting them.
- **Hint** under the row (12 pt `Theme.primary`): `แตะแผงบนแปลนเพื่อเอาออกหรือใส่กลับ · เอาออกแล้ว <n> แผ่น`.
- **Off:** taps select as today.
- **The numbers:** the tag on the plan, `03 สรุปการจัดแผง` and the report all count without removed slots. They already do through the layout; check.
- **Switching tabs** leaves edit mode.

**`จัดแผงใหม่`** clears `Choice.removed` and leaves edit mode, as one undo step.
- It does **not** run `หาผังที่ได้แผงมากที่สุด`.
- It is disabled when nothing is removed.

### 5. iPhone `จัดแผง` tab order (`states/03`, `06`, `09`)
**Hide on iPhone in `.pv` mode:** `sectionCard` and `photosCard`. The board shows only the plan and the two cards below; the structure tab still shows them.

**`02 แผงและการวาง`**, numbered headers as the board draws them (24 pt `Theme.primary` number, a hairline, a 16 pt bold title, a status pill on the right):
1. `รุ่นแผง`: a read-only row with the standard's module, its size and its Voc from the module catalog, and the source `จากมาตรฐานโครงการ`. A tap opens the existing standard editor if there is one on iPhone, else nothing.
2. `การวางแผง`: `แนวตั้ง | แนวนอน`.
3. `การเรียงแผงแนวนอน` and `ระยะเว้นระหว่างคู่` (item 2).
4. `ระยะห่างจากขอบหลังคา` (item 3).
5. `ทางเดินตามสันหลังคา` and its width (item 3).
6. `ทางขึ้นหลังคา (Roof access)` (item 3).

The status pill is `✓ ครบ` when the layout has modules, else `ยังไม่มีแผง`.

**`03 สรุปการจัดแผง`:** four tiles in two columns (`Theme.segmentTrack` or `track`, radius 12). They replace today's three summary tiles on iPhone.

| Tile | Value | Sub-line |
|---|---|---|
| `จำนวนแผง` | `<n> แผง` | `<แนวตั้ง/แนวนอน> · <m> แผงต่อแถว` (the most modules in one row of the layout) |
| `กำลังติดตั้ง` | `<kWp> kWp` | `<n> × <Wp> W` |
| `สตริง` | `<k> × <s> แผง` | the remainder, or `ลงตัวพอดี` |
| `พื้นที่แผง` | `<n × L × W> ตร.ม.` | `<n> × <L> × <W> ม.` |

- **Strings:** only when the job gives a modules-per-string figure. Look for one in B2 / the SLD (`SingleLine`, `InverterStation`) or `PVYield` string sizing.
  - If none exists, show `—` and `ยังไม่กำหนดแผงต่อสตริง`.
  - Do not invent 14. Report what you found (open question 4).
- **Area:** from the standard's module size.

**Everything else `mountTab` shows today:**
- the design banner, `mountNote` undo line, `mountInfo`, the fixing method and rails, the shade switch, the cleaning walkway, faces, align, bearing, BOQ, rules, the energy card and the footer

On iPhone it goes **after** `03`, under one closed disclosure `ตั้งค่าและรายละเอียดเพิ่มเติม` (44 pt row with a chevron, the same pattern as `boqOpen`). Nothing is deleted.
- The `mountNote` undo line and `DesignCheckBanner` stay **above** `02`, since they report the last action.
- `mountInfo` (the selected module or obstacle) also stays above `02`.
- Report this (open question 1).

### 6. DEBUG and docs
- **New `-surveyC1` states** (with `-surveyPage roof`, iPhone):
  - `pvphone`: `จัดแผง` open
  - `pvland2`: landscape pairs, the plan in view
  - `pvpairs`: scrolled to the pair gap
  - `pvaccessleft`: access left, walkway 1.00 m
  - `pvedit`: edit on, three modules removed
  - `pvsummary`: scrolled to `03`
  - They write into the demo job, as the other `pv…` states do; say so.
- **CLAUDE.md:** add the new states to the `-surveyC1` item in one sentence, and mention `landscapePairs` / `pairGap` / `ridgeWalkwayWidth` there.
- **UI test** `PhoneRoofPVUITests` (iPhone) from `-surveyFreshJob YES`:
  - switch to `จัดแผง`, pick `แนวนอน` then `วางคู่ 2 แผ่น`; the pair-gap row appears; `+` changes it to 0.50
  - `แก้แผง`, tap a module on the plan; the hint reads `เอาออกแล้ว 1 แผ่น` and the tag's count drops by one
  - `จัดแผงใหม่` brings it back
  - access `ด้านซ้าย` is selected after a tap
- **`PhoneRoofFitUITests` must still pass** (nothing off screen in either tab).

## Rules
- Colours from `Theme`. No hex in views, no `Color.white`. Plans on `Theme.paper`.
- Hit areas ≥ 44 pt. Buttons use `TCButtonStyle`. Segments use the existing `RoofSegments`.
- Split each new card into its own computed property or view (Debug type-check limits; see `body`'s `AnyView` note).
- **Old job JSON must still decode;** new `Choice` keys are optional. An old job's layout, PDF, Excel and DXF are unchanged.
- **Engineering values come from the job, `RoofMountStandard`, `RoofWalkway` and the catalog,** never from the board.

## Check list
- [ ] `swift test` in `TCRoofKit` passes, with the new layout and decode tests, and with the `RoofDXF` golden files unchanged.
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, run in the background.
- [ ] `PhoneRoofPVUITests`, `PhoneRoofFitUITests` and `RoofRulesUITests` pass.
- [ ] iPhone 16 Pro screenshots `02`–`09` in `screenshots/`, named like `states/`, taken with `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyPage roof -surveyC1 <state>`.
- [ ] The iPad C1 (`-surveyWideA1 YES -surveyPage roof -surveyC1 pv`) still works, with the new choices in its cards.
- [ ] The `-surveyRoofPDF YES` PDF of the demo job is unchanged unless pairs or a walkway width are set.

## Open questions (report, don't decide)
1. The board shows only `02` and `03` under the plan on iPhone, and the row `แก้แผง · จัดแผงใหม่ · CAD`. Where should `วาด` (keep-out areas, obstacles), `ย้อน` and today's other PV cards live on iPhone? (This task keeps them below, closed.)
2. The board's note says the two modules of a pair are 0.4 ซม. apart, while the standard's `moduleGap` is 2 ซม. (the clamp). Which is right for the pair?
3. Ridge walkway width: the board's range is 0.40–1.20 m with 0.60 m by default, but the team's walkway detail (`RoofWalkway.band`) is 0.90 m wide. Can the walkway be narrower than the detail? Which default should it be?
4. `สตริง`: where should modules per string come from (B2, the SLD, ModuleRules' max in series for the inverter)? The board's 14 has no source.
5. `ระยะห่างจากขอบหลังคา`: one value for the eave and the verges (as built here), or separate eave / verge steppers as the iPad standard has?
6. Pairs: which way is right, pairs along the row (as built) or pairs up the slope? This is still open with the designer.
