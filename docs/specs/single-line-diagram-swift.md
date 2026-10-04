# Auto Single Line Diagram — Swift implementation spec (iPad + iPhone)

**Status:** Updated 2026-10-01 to match the code being built on `main` and the SLD page design
**Design spec:** [`single-line-diagram.md`](single-line-diagram.md) (what is drawn and why)
**Page design / task:** `docs/ui/survey-sld/CLAUDE_CODE_TASK.md`. Visual reference: `diagram-lv.svg`, `diagram-hv.svg`, `preview.png`, `preview-hv.png`.
**Targets:** `TCRoofKit` (iOS 17+, macOS 14 for tests) inside the TCRoof app
**New dependencies:** none. Layout is written by hand, because the SLD topology is fixed.

## What changed from the 2026-09-29 draft

| Draft | Now |
|---|---|
| `SolarSurveyKit/Sources/SurveyCore/SLD/…` | `TCRoofKit/Sources/TCRoofCore/SingleLine.swift`, `SingleLineLayout.swift` (package and module renamed) |
| `BreakerInfo`, `Transformer.breakers`, `EquipmentCondition` | the A3 model already on `main`: `Transformer` nameplate fields, `Board`, `Breaker`, `resolvedBoards` |
| nameplate in `tr<i>_type`, `tr<i>_z` … keys | stored inside `Transformer` (`type`, `voltage`, `vectorGroup`, `impedance`, `brand`, `serial`, `year`, `hvProtection`, `hasLA`, `condition`, `conditionNote`) |
| B1 breaker fields (`breakerType`, `breakerKA` …) | not added; outgoing breakers are recorded on the A3 board (`Breaker.target` names the B1 panel); B1 still gives `loadKW` / `loadTime` |
| HV side always DOF, "No VCB/52" | follows A3 `hvProtection`: DO fuse / DS / VCB |
| PV always at TR1's feed MDB | picked on the SLD page (`sldTransformer`, `sldBoard`), default TR1 main board |
| new fields required (block completion) | nothing new is required; A3 completion counts as before, and blanks show as red `?` plus the missing list |
| `SLDPreviewCard`, `BreakerEditor`, `TransformerPlate`, `ConditionPicker` | not needed: editing stays on the A3 wide page; the SLD page is read-only with links back |
| SLD image in Excel | not in v1 (design spec, open question 5) |
| short-circuit studies a non-goal | a simple Isc estimate and a breaker IC check are in v1 |

## 1. Goals and non-goals

**Goals**

1. Generate the SLD automatically from the survey. The surveyor never draws, and every edit redraws it.
2. Show every missing value as a red `?`, list it, and link it back to where it is entered.
3. Use the board names written on site.
4. Size the PV breakers, estimate Isc, and check existing breaker IC against it.
5. Use the same drawing on screen and in the A3 PDF.

**Non-goals (v1)**
- Editing the drawing by hand
- Cable sizing or voltage drop from real lengths
- Level 2 feeder detail
- An Excel image

## 2. Where the code goes

```
TCRoofKit/Sources/
  TCRoofCore/                     (no UIKit / SwiftUI; tested with swift test)
    SingleLine.swift              model (SL* types), SLConstants, calculations, build(job)
    SingleLineLayout.swift        SingleLine → SingleLineDrawing (Sketch + hit boxes)
    Flood.swift                   FloodCheck (read for the flood card)
  SurveyUI/
    SingleLinePage.swift          page: toolbar (B4 toggle, PV board menu, zoom), drawing card, bottom bar
    SingleLinePage+Panel.swift    side panel: PV data, IC check, blocking list, flood card, sheets
    ElectricalPageWide.swift      A3 button "สร้าง Single Line Diagram →" opens the page
    JobEditor*.swift              navigation to / from the page and to link targets
    SurveyModel+Export.swift      "ส่งออก PDF (A3)" share
  PDFReport/
    SingleLinePage.swift          A3 landscape page (vector drawing, title block, tables)
    ReportLayout.swift            attachesSingleLine(job) → page after the A3 section
Tests/TCRoofCoreTests/
  SingleLineTests.swift
```

## 3. Data read (no new required fields)

| Value | Read from |
|---|---|
| meter | `values.text("meterNo" / "meterCA" / "meterRate" / "meterCT")`, `choice("meterKV" / "meterPhase")` |
| transformers | `values.transformers("trafos")`, entries where `Schema.transformerPresent` is true, up to 5 |
| boards | `Transformer.resolvedBoards`; board 0 name / location also from `tr{i}_feed` / `tr{i}_feedLoc` |
| PV size | A1 `number("capacity")` |
| inverters | sum of `number("inverterCount")` over `.inverter` modules |
| loads | `.panel` modules: `number("loadKW")`, `text("loadTime")`, matched to `Breaker.target` by section name |
| zero export | first `.backfeed` module `choice("level")`, `choice("pole")`; `hasB4` = such a module exists |
| FTS / emergency | a `.fts` module exists |
| flood | `FloodCheck.state(values)`, `level`, `minCm` |

New optional answers, written only by the SLD page:
- `sldAttach` ("1")
- `sldTransformer` (index as text, nil = 0)
- `sldBoard` (board UUID, nil = main board)

Old jobs with only `kva` + `mdb[6]` must build without crashing (covered by a test).

## 4. Model (`SingleLine.swift`)

```swift
public enum SLStatus { case known, missing, assumed, new, condition(SLCondition) }
public enum SLCondition: String { case good, fair, bad }        // init from ดี / พอใช้ / ชำรุด
public struct SLTarget { enum Page { case info, electrical, flood, module(ModuleType) }; var trafo, board: Int?; var breaker: UUID? }
public struct SLText { var text: String; var status: SLStatus; var bold: Bool }

public struct SLBreaker   { id, trafo, board, number, isMain, isNew, type, at, af, ic, brand, condition?, note?, atAmps?, icKA?, destination }
public struct SLBoard     { id, trafo, index, name, location, isMain, main: SLBreaker, breakers: [SLBreaker] }
public struct SLTransformer { id, index, lines: [SLText], collapsed, hasLA: Bool?, cable, boards, kva?, zPercent? }
public struct SLMissing   { id, label, blocking: Bool, target: SLTarget }
public struct SLAssumption{ id, text }
public enum   SLCheckState{ case ok, marginal, insufficient, unknown }
public struct SLCheck     { id, name, icKA?, state, target }
public struct SLFlood     { text, minCm, levelCm }
public struct SLPV        { capacityKWp?, inverterCount?, inverterKW?, inverterAT?, totalAT?, requiredIC?, busbar?, inverterCable?, mainCable?, cableRuns, totalCableM, rows }

public struct SingleLine {
    sourceLabel, meter: [SLText], protection: SLText
    zeroExportHV: Bool, hasB4: Bool, pole: String
    transformers: [SLTransformer]
    connection: (trafo: Int, board: Int)
    pv: SLPV, isc: Double?, iscAssumedZ: Bool, checks: [SLCheck]
    missing: [SLMissing], assumptions: [SLAssumption], flood: SLFlood?
    conditionCounts: (bad: Int, fair: Int), projectLine: String
    static func build(_ job: Job, hvOverride: Bool? = nil) -> SingleLine
}
```

`hvOverride` lets the page preview the other zero export position when the job has no B4 section.

## 5. Constants and calculations

`SLConstants` holds every figure that is not survey data. Using one adds an `SLAssumption`.

| Constant | Value |
|---|---|
| `lineVoltage` | 400 V |
| `breakerFactor` | 1.25 |
| `icMargin` | 1.25 |
| `defaultZPercent` | 4.0 % |
| `cableRunM` | 20 m |
| `inverterSizes` | 5, 10, 15, 20, 25, 30, 36, 40, 50, 60, 75, 100, 110 kW |
| `frames` | 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800 A |
| `icSizes` | 10, 15, 25, 36, 50, 65, 85 kA |
| `cables` | table by AT; 125 A → `CV 4×35 + G16`, 250 A → `CV 4×120 + G25` |
| `busbars` | table by AT; 250 A → `25 × 5` |

Functions (all static on `SingleLine`):

| Function | Rule | Test value |
|---|---|---|
| `standardInverter(kw)` | first standard size ≥ kW | 60 → 60 |
| `breakerAT(kw:)` | `kw·1000 / (√3·400) × 1.25` → next frame | 60 kW → 125; 120 kW → 250 |
| `breakerAF(at:)` | next frame ≥ AT | 125 → 125 |
| `shortCircuit(kva:zPercent:)` | `kva / (√3 · 0.4 · z/100)` / 1000 (kA) | 630, 4.14 → 22.0 |
| `requiredIC(isc:)` | next `icSizes` ≥ Isc | 22.0 → 25 |
| `classify(ic:isc:)` | ok ≥ 1.25·Isc · marginal ≥ Isc · insufficient < Isc · unknown when no IC | 50/36 ok, 25 marginal, nil unknown |

**Missing items:**
- `blocking == true` for:
  - IC / AF / brand of breakers on the connection bus
  - %Z of transformers with drawn boards
  - main AT / IC of the connection board
  - A1 `capacity`
  - B2 `inverterCount`
- `blocking == false` for everything else printed as `?`.

## 6. Layout and drawing (`SingleLineLayout.swift`)

```swift
public struct SLHit { var box: Box; var target: SLTarget }
public struct SingleLineDrawing { var sketch: Sketch; var hits: [SLHit]; var width, height: Double }
public enum SingleLineLayout { static let width: Double; static func draw(_ m: SingleLine) -> SingleLineDrawing }
```

- **Width:** fixed design width of 1560. Height grows with the content (design sample 1480).
- **Placement:**
  - Transformers are spaced evenly across the width.
  - The connection board spans the width under its transformer.
  - Other boards stack under their transformer.
- **Readability:** must hold with 1–5 transformers and up to 6 boards each.
- **Symbols:** drawn as `DrawOp` paths, listed below. Lines stop at a symbol and never pass through it.
  - HV: switch, DO fuse / DS, VCB, LA with ground, three cable terminations, Δ/Y transformer
  - Meter: `kWh` meter
  - Breakers: fixed arc, draw-out arc with chevrons
  - Zero export: CT with count, CT/VT (HV), relay box
  - PV side: inverter (=/~), DC disconnect, PV array, emergency button
  - Other: load block, `))` line break
- **Colours:**
  - Existing: `RGBA.dark`
  - New PV: `RGBA.blue`
  - Missing: `RGBA.red`
  - Condition: ดี `0x2F855A`, พอใช้ `0xB7791F`, ชำรุด `RGBA.red`
  - Control lines: dashed blue `[4, 3]`
- **Hits:** one `SLHit` for every transformer, board and breaker, plus PV items linking to their B-section.

`Sketch.svg()` must produce output that matches `docs/ui/survey-sld/diagram-lv.svg` / `diagram-hv.svg` for the design sample within a few points.

## 7. UI (`SurveyUI/SingleLinePage*.swift`)

- **iPad landscape:** diagram area on the left (~950 pt), side panel on the right (~310 pt). Layout and labels as in `CLAUDE_CODE_TASK.md` and `preview.png`.
- **Toolbar:**
  - `ตำแหน่งกันย้อน (B4)` segmented control. It writes B4 `level`; with no B4 it passes `hvOverride` only.
  - PV board menu `เชื่อมต่อ PV ที่ตู้นี้`
  - zoom `−` · `50%` · `+` · `พอดีจอ` (35 / 50 / 60 / 75 / 90 / 100 %), pinch and pan
- **Taps:** a tap resolves through `hits`. Below 75 % zoom it first zooms to the item. Then it navigates to the `SLTarget`: A3 expands that transformer, board or breaker; B-sections open their page.
- **Side panel:**
  - `ข้อมูลฝั่ง PV`
  - `เบรกเกอร์ทนลัดวงจร {Isc} kA ได้ไหม`
  - `ต้องเก็บก่อนออกแบบ`
  - flood card (`A4 →`)
  - sheets for `ข้อมูลที่ขาดอื่นๆ`, `สภาพอุปกรณ์`, `ค่าสมมติ`
- **Bottom bar:** `‹ แก้ข้อมูลใน A3` · `ส่งออก PDF (A3)` · `แนบในรายงาน` (toggles `sldAttach`)
- **iPad portrait / iPhone:** diagram full width with zoom; the side panel becomes a sheet opened from the toolbar.
- **Rebuild:** redraw when `job.values` or the modules change, debounced about 150 ms, off the main actor. Core types are `Sendable`.
- **Accessibility:**
  - The drawing has an accessibility summary: transformers, boards, PV, and the missing and condition lists as text.
  - Buttons are at least 44 pt.

## 8. PDF

- `singleLinePage(hv:)`: one A3 landscape page (1190 × 842 pt). It holds the vector drawing scaled to fit, a title block (job number, station, date), the PV data table and the breaker check table.
- `ReportLayout.attachesSingleLine(job)`: when true, the page is added after the A3 section, and the other pages do not move.
- The footer `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง` is printed on the page.

## 9. Tests (`SingleLineTests.swift`)

| Test | Checks |
|---|---|
| `testBreakerSizing` | 60 kW → 125 AT; 2 × 60 kW → 250 AT |
| `testShortCircuit` | 630 kVA, 4.14 % → 22.0 kA; required IC 25 kA |
| `testBreakerCheckClassification` | 50 / 36 / 25 / nil against 22 kA |
| `testFixtureModel` | design sample builds the expected transformers, boards and PV rows |
| `testMissingItems` | blocking and non-blocking counts on the fixture |
| `testPVBlockingWhenA1AndB2Empty` | no capacity or inverter count → blocking items, no PV branch |
| `testAssumedZWhenImpedanceMissing` | %Z blank → 4 % assumed + blocking item |
| `testHVOverrideAndSelection` | `hvOverride`, `sldTransformer` / `sldBoard` pick the connection |
| `testOldJobBuilds` | job with only `kva` + `mdb` builds |
| `testLayoutHitsAndHeight` | every transformer / board / breaker has a hit box; height grows with content |
| `testWriteSVG` | writes the sample SVG for visual comparison with `diagram-*.svg` |

## 10. Done when

- [ ] A3 → `สร้าง Single Line Diagram →` opens the page on iPad and iPhone.
- [ ] The design sample matches `preview.png` / `preview-hv.png` and `diagram-lv.svg` / `diagram-hv.svg`.
- [ ] The LV / HV toggle changes B4 (or previews when there is no B4).
- [ ] Tapping a red `?` opens A3 on that item. Filling it removes it from the list on return.
- [ ] Changing the PV board redraws the connection board, Isc and the IC check.
- [ ] `ส่งออก PDF (A3)` shares one vector A3 page. With `แนบในรายงาน` on, the survey PDF contains it.
- [ ] Old jobs open without data loss. `swift test` passes.

## 11. Open questions

See [`single-line-diagram.md`](single-line-diagram.md#open-questions). None of them block v1.
