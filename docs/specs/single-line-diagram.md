# Auto Single Line Diagram (SLD)

**Status:** Level 1 is built (checked against the code 2026-10-17). Model and rules: `TCRoofKit/Sources/TCRoofCore/SingleLine.swift`, `SingleLine+Build.swift`; drawing: `SingleLineLayout.swift`, `SLSymbols.swift`; DXF: `SingleLineDXF.swift`; page: `TCRoofUI/Survey/Pages/Electrical/SingleLinePage.swift`, `SingleLinePage+Panel.swift`; PDF: `PDFReport/SingleLinePage.swift`. Built 2026-10-19: VCB and DO fuse symbols (`SLSymbols.vcb`, `dropOutFuse`, `hvDevice`: each transformer's tap draws its A3 `hvProtection`, the PEA tap the one they share; DS keeps the open switch), the FTS cut and emergency button only with a B5 section, and a debounced off-main rebuild (`SingleLineRender`, 250 ms, on the SLD page and the B4 / B5 crops). The 1.25 × breaker factor is the team's rule (no longer a ค่าสมมติ). Level 2 (detailed MDP) built 2026-10-20: the optional `Breaker` / `Board` fields, their drawing on the connection board, the notes under the diagram, the feeder wrap and boards side by side, and their entry on A3 (`ElectricalPageWide+SLD.swift`); details under Level 2 below.
**Not built:** the SLD in Excel.
**Page design and task:** `docs/ui/survey-sld/CLAUDE_CODE_TASK.md`, `preview.png`, `preview-hv.png`, `diagram-lv.svg`, `diagram-hv.svg`
**Builds on:** [`auto-drawing.md`](auto-drawing.md) (same `Sketch` pipeline and drawing rules). DXF export: `docs/specs/cad-export-dxf/` (phase 2).
**Targets:** `TCRoofKit` (iOS 17+, macOS 14 for tests) inside the TCRoof app. **New dependencies:** none. Layout is written by hand, because the SLD topology is fixed.

The SLD is generated from the survey. The surveyor never draws; every edit in A1 / A3 / A4 / B-sections redraws it.

| Level | Source | Reference |
|---|---|---|
| **1. From the survey as it is (v1)** | A1, A3 (meter, transformers, boards, breakers), A4, B1, B2, B4 | `docs/ui/survey-sld/diagram-lv.svg`, `diagram-hv.svg` (the older prototype `img/sld_form.py` is superseded) |
| 2. Detailed MDP (built 2026-10-20) | level 1 plus feeder cables, conduits and loads per breaker | `img/sld.py` |

## Goals and non-goals

**Goals (v1)**
1. Generate the SLD automatically from the survey. The surveyor never draws, and every edit redraws it.
2. Show every missing value as a red `?`, list it, and link it back to where it is entered.
3. Use the board names written on site.
4. Size the PV breakers, estimate Isc, and check existing breaker IC against it.
5. Use the same drawing on screen, in the A3 PDF and in the DXF.

**Non-goals (v1)**
- Editing the drawing by hand. Editing stays on the A3 wide page; the SLD page is read-only with links back.
- Cable sizing or voltage drop from real lengths
- An Excel image
- Required fields: nothing new blocks completion. A3 completion counts as before, and blanks show as red `?` plus the missing list.

## Drawing style

- **Upstream (PEA style):**
  - HV line with `))` breaks and poles, labelled `ระบบจำหน่าย กฟภ. {meterKV} kV, 3Ø 3W, 50 Hz`
  - HV protection, then the PEA meter `kWh`, then the customer HV bus with one drop per transformer
  - Each drop: switch, LA branch, three cable terminations, Δ/Y transformer with grounded neutral
- **HV protection follows A3 `hvProtection`** (DO fuse / DS / VCB). Each device has its own symbol (DO fuse, DS as the open switch, VCB). Each transformer's tap shows its own A3 `hvProtection`, and the PEA tap the kind they share (`SLSymbols.hvDevice`). The label is the answer when every transformer has the same one, otherwise `Drop Out Fuse / Disconnecting Switch`. The older rule "no VCB/52" is dropped because A3 asks for it.
- **LA:** drawn with `LA` when `hasLA == true`, left out when `false`. When it is not answered, the drawing shows red `LA ?`.
- **Downstream (Thai MDP style):**
  - Boards: dashed boxes titled with the on-site name
  - Breakers: arc symbol with the label stack `{MCCB|ACB},{poles}` / `{at}AT` (underlined) / `{af}AF` / `IC {ic} kA` / brand / `สภาพ: …` / note. A blank type is drawn as an assumed `MCCB`, blank poles as `3P`.
  - Draw-out marks on the connection board's main breaker
  - Numbered outgoing breakers, each ending in a black load block
- **Colours** (`SingleLineLayout`):
  - Existing equipment: ink `0x2B2B2B`
  - New PV equipment: blue `0x1F4E8C`, marked `(ใหม่)`
  - Control lines: dashed blue, width 1.5, dash `[5, 4]`
  - Missing values: red `0xD9453B` `?`
  - Assumed values: grey `0x6B7280`
  - Condition text: ดี green `0x2E7D4F`, พอใช้ amber `0xB7791F`, ชำรุด red

## Level 1 — generated from the survey (v1)

| กันย้อนแรงต่ำ (default) | กันย้อนแรงสูง |
|---|---|
| `docs/ui/survey-sld/diagram-lv.png` | `docs/ui/survey-sld/diagram-hv.png` |

### Data it reads

No new form fields are needed for level 1. The A3 wide page already records everything. It keeps the old keys and adds the new values inside `Transformer`.

**Meter (A3):** `values.text` of `meterNo`, `meterCA`, `meterRate`, `meterCT`; `choice` of `meterKV` (0.4 / 22 / 33) and `meterPhase`.

**Transformer (A3, `values.transformers("trafos")`, one `Transformer` each, up to 5):**

| Value | Stored in |
|---|---|
| kVA | `Transformer.kva` |
| type (oil / dry), voltage, vector group, %Z | `type`, `voltage`, `vectorGroup`, `impedance` |
| brand, serial, year | `brand`, `serial`, `year` |
| HV protection, LA | `hvProtection` (DO fuse / DS / VCB), `hasLA` |
| condition + note | `condition` (ดี / พอใช้ / ชำรุด), `conditionNote` |
| boards | `boards: [Board]`. Old jobs fall back to `resolvedBoards` built from `mdb[]`. |

**Board (A3):**
- `name`: the on-site name (MDP-1, SDB ระบบกรอง, MDB-ADMIN …); no fixed MDB1…MDB6. A blank name falls back to `tr{i}_feed` for board 0, then `MDB{k+1}`.
- `isMain`
- main breaker: `mainType` (ACB / MCCB), `at`, `af`, `icu`, `poles`, `brand`
- `condition`, `conditionNote`
- `location`
- `breakers: [Breaker]`

Board k = 0 is the main board. Its name, location and front photo stay in `tr{i}_feed`, `tr{i}_feedLoc` and `tr{i}_feedPhoto`. Every board's AT is mirrored to `Transformer.mdb[k]`, so Excel, the old PDF table and the A2 symbols read the same values as before. A transformer with no boards gets a placeholder main board, so the PV always has a board to connect to.

**Breaker (A3):**
- `at`, `af`, `ic`, `poles`, `brand`
- `target` (where it feeds, e.g. `ตู้ไฟฟ้า โรงสูบน้ำ (B1)`)
- `condition`
- `count` (sub-boards group equal breakers, e.g. `100 A × 2`)

**Other sections:**

| Value | Section and id |
|---|---|
| PV size | A1 `number("capacity")` (kWp) |
| Inverter count | B2 `.inverter` modules, sum of `inverterCount` |
| Inverter sizes | B2 `invSizes` (per-inverter kW, through `InverterStation`), when every B2 section with inverters has them |
| Building loads | B1 `.panel` modules: `loadKW`, `loadTime`. A breaker's load is the B1 building linked to it (`a3Breaker`), else one whose name or number (`(B1.2)`) its `target` mentions. |
| Zero export position | first B4 `.backfeed` module: `level` (`กันย้อนที่แรงต่ำ` / `กันย้อนที่แรงสูง`), `pole` (`เสาเดิม` / `เสาใหม่`, default `เสาใหม่`); `hasB4` = such a module exists |
| Flood at the connection point | A4 `job.floodCheck`: `state`, `level`, `minCm`, plus `floodYear` |

The FTS DC cut-out and the emergency button are drawn on the PV side only when the job has a B5 section (`hasB5`). Old jobs with only `kva` + `mdb[6]` build without crashing.

**New optional answers (written only by the SLD page):**
- `sldAttach` = "1": add the SLD page to the survey PDF
- `sldTransformer`: index of the transformer the PV connects to, as text (nil = 0)
- `sldBoard`: board UUID (nil = that transformer's main board)

### Survey value → drawing

| Survey value | Drawn as |
|---|---|
| meter fields | `kWh` circle with `PEA METER {meterNo}` / `CA {meterCA} · อัตรา {meterRate}` / `รับไฟ {meterKV} kV {meterPhase} · CT {meterCT} A` |
| each transformer | drop off the HV bus, with a text block: `TX{n} {OIL IMMERSED / DRY TYPE}`, `{voltage} V`, `{vectorGroup}, Z={impedance}%`, `{kva} kVA`, `{brand} · SN {serial} · ปี {year}`, `สภาพ: {condition} — {note}` |
| transformer with more than half its nameplate missing | collapsed to `{kva} kVA` + red `ป้ายพิกัดยังไม่ครบ` |
| boards of a transformer | the main board plus sub-boards as branches (dashed boxes 180 × 200), each ending in `ปลายสาย TX{n} · {location}` |
| connection board (`sldTransformer` / `sldBoard`) | drawn large and full width: draw-out main breaker, `MAIN BUS {at} A, 3Ø 4W, 400/230 V`, numbered outgoing breakers with load blocks `ตู้ไฟฟ้า / {target} / โหลด {loadKW} kW @{loadTime}` |
| PV (A1 + B2) | blue PV breaker at the bus end → `SMDB-PV (ใหม่)` → one breaker per inverter (at most 3 columns drawn, then `… × {n}`) → inverter (=/~) `อินเวอร์เตอร์ {n} × {kW} kW (B2)` (or `60 + 60 + 80 kW` for mixed B2 sizes) → `ตู้ FTS ตัดวงจร DC (B5)` (only with a B5 section) → `แผง PV รวม {kWp} kWp (A1)` |
| B4 แรงต่ำ | `CT กันย้อน (ใหม่)` on the connection board incomer, box `รีเลย์กันย้อน แรงต่ำ / Zero export (B4)` |
| B4 แรงสูง | `CT/VT แรงสูง (ใหม่)` under the PEA meter, box `รีเลย์กันย้อน แรงสูง / {pole} (B4)` |
| emergency (only with a B5 section) | `ปุ่ม Emergency`, dashed to the inverters |

**Zero export control:** in both modes the relay's dashed control line goes to the inverters (`สั่งควบคุมกำลังผลิต`), never to a breaker. The toggle on the SLD page writes B4 `level`. If the job has no B4 section, the toggle is a preview only (`hvOverride`).

### Calculations

`SLConstants` holds every figure that is not survey data. Using one adds an `SLAssumption`, listed under `ค่าสมมติ`.

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
| `cables` | copper CV 0.6/1 kV in conduit, by AT; 125 A → `CV 4×35 + G16`, 250 A → `CV 4×120 + G25` |
| `busbars` | copper, by AT; 250 A → `25 × 5` |

| Value | Rule | Example |
|---|---|---|
| PV side with B2 sizes | inverter breakers, PV total breaker and cables come from B2 (`InverterStation`: catalogue Imax × factor, AF = max(100, AT); feeder by Σ Imax, single-core cable `4×1C …`); busbar from `busbars` by the feeder AT | 60, 60, 80 kW → 200 AT max, 500 AT total, `2×(4×1C 120) + G35` |
| Inverter kW without B2 sizes | A1 `capacity` ÷ inverter count, rounded up to a standard size (`standardInverter`) — assumed | 120 kWp ÷ 2 → 60 kW |
| Inverter breaker (fallback) | `breakerAT(kw:)`: `kw·1000 / (√3·400)` × 1.25, next frame; `breakerAF(at:)` = next frame ≥ AT | 60 kW → 86.6 A → 125 AT |
| PV total breaker (fallback) | same rule on the sum | 2 × 60 kW → 250 AT |
| Short circuit at the connection bus | `shortCircuit(kva:zPercent:)`: `kVA / (√3 × 0.4 kV × Z)`, infinite HV source, no cable impedance; %Z missing → 4 % (assumed) and a blocking item | 630 kVA, 4.14 % → 22.0 kA |
| Required IC (PV breaker) | `requiredIC(isc:)`: next `icSizes` ≥ Isc | 22.0 kA → 25 kA |
| Breaker check (main + outgoing on the connection bus) | `classify(ic:isc:)`: ✓ IC ≥ 1.25 × Isc · ! Isc ≤ IC < 1.25 × Isc (`เผื่อน้อย`) · ✗ IC < Isc (`ไม่พอ`) · ? no IC (`ยังไม่รู้`) | 50 ✓, 36 ✓, 25 !, — ? |
| Cables, busbar (fallback) | `cables` / `busbars` by breaker AT — assumed; 20 m per run, n + 1 runs, summed | 125 A → CV 4×35 + G16; 250 A → CV 4×120 + G25; busbar 25 × 5 |
| Flood | `FloodCheck.minCm`; the SMDB-PV and relay must be at least that high | 80 cm + 50 → 130 cm |

### Missing items

- **Blocking** (`ต้องเก็บก่อนออกแบบ`):
  - IC / AF / brand of any outgoing breaker on the connection bus
  - %Z of every transformer (each one has at least a placeholder board drawn)
  - main breaker AT / IC of the connection board
  - A1 `capacity`
  - B2 `inverterCount`
- **Non-blocking** (`ข้อมูลที่ขาดอื่นๆ`): everything else printed as `?` (meter number, nameplate, LA, the main breaker and breakers of other boards, B1 load …).
- The SLD page total `ยังขาด {n} จุด` = blocking + non-blocking.
- **Navigation:** each item links to the page where it is entered. Tapping it opens A3 on that transformer / board / breaker, or opens the A1 / A4 / B-section page.
- **Condition summary:** `ชำรุด {n} · พอใช้ {n}`, with the list of items that are not ดี.

### Page and outputs

- **SLD page:** a full-screen cover opened from the A3 button `สร้าง Single Line Diagram →` (also from B4 and B5, which show a crop of the diagram: `zeroExportBox`, `ftsBox`). Details under UI below.
- **PDF:** one A3 landscape page: vector drawing, title block, legend, and a side column with the PV data, the breaker check, the blocking list, the flood note and a summary. It is added to the survey PDF after the A3 section when `sldAttach` = "1". Footer note on every output: `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง`.
- **DXF:** the same drawing as DXF R12 at A3 paper scale (`ส่งออก DXF`).
- **Excel:** not changed in v1 (open question 5).

## Level 2 — detailed MDP (built 2026-10-20, optional inputs)

| Mode | When | Image |
|---|---|---|
| Existing only | A1 capacity or B2 inverter count blank | ![](img/sld_existing.png) |
| PV + กันย้อนแรงต่ำ | B4 level = แรงต่ำ | ![](img/sld_pv_lv.png) |
| PV + กันย้อนแรงสูง | B4 level = แรงสูง | ![](img/sld_pv_hv.png) |

Level 2 adds cable, conduit and load detail to each outgoing breaker of a board. It extends the A3 model instead of adding a separate schedule.

| New optional field on `Breaker` | Example | Drawn as |
|---|---|---|
| `cable` | 4x50,1x10-IEC01 | rotated −90° left of the feeder line |
| `conduit` | ø50mm. UPVC / IN WIRE WAY | under the cable text |
| `load` | LC11 | bold under the load block |
| `floor` / location | 1st FL. | under the load name |
| `spare` | true | breaker + `SPARE`, no cable or load |

| New optional field on `Board` | Example | Drawn as |
|---|---|---|
| `busbar` | 4x300A. Cu. BUSBAR W/GROUND BUS | label above the bus |
| `ground` | 1x35-IEC01 ø20 PVC. | N/G bar, ground conductor, ground rod |

**Checks (notes under the diagram, never errors):**
- transformer full-load current `kVA × 1000 ÷ (√3 × 400)`
- main AT against full-load current (note outside 0.8–1.25 ×)
- AT ≤ AF on every breaker
- feeder count (in use / spare)
- sum of in-use feeder AT (no diversity)
- PV share of the transformer (note above 100 %)
- PV AT against main AT, always with `ตรวจพิกัดบัสบาร์กับวิศวกร`

**Layout rules (from the older prototype):**
- More than 10 feeders: wrap into a continuation row (`…ต่อ`), or reduce column spacing down to 60 pt.
- Several boards on one transformer: side by side, fed from a common LV line.

**As built (2026-10-20):**
- **Data:** `Breaker.cable`, `conduit`, `load`, `floor` (text) and `spare` (Bool), `Board.busbar` and `ground` (text). All default to empty / false and decode with `decodeIfPresent`, so old jobs load unchanged. No schema field, Excel cell or `Progress` count changes; nothing new is a missing item.
- **Model:** `SLBreaker.feeder` (`cable, conduit`), `SLBreaker.spare`, `SLBoard.busbar` / `ground`, `SingleLine.notes: [SLNote]` (`text`, `flagged`, `target`). A spare breaker gets no cable and no load block, its check name is `SPARE`, and it asks for no B1 load. A `load` name replaces the `ตู้ไฟฟ้า / {name}` lines (bold), `floor` follows as `({floor})`, then the B1 kW line as before.
- **Drawing** (connection board only, the board drawn in detail): the cable text rotated −90° left of the feeder (`{cable}, {conduit}` on one line, as `img/sld.py`), `SPARE` under a spare breaker, the busbar label above the bus (the bus moves down one line for it), and with `ground` the N/G bar, the ground conductor with its size rotated beside it and the ground rod (`GROUND ROD`) at the frame's left.
- **Notes** (`ค่าที่คำนวณจากข้อมูลสำรวจ · หมายเหตุ ไม่ใช่ข้อผิดพลาด`, under the diagram; amber when `flagged`, each taps to its A3 item): full-load current of the connection transformer; its main AT as a multiple of it (flagged outside 0.8–1.25 ×); AT over AF on any breaker of any board (flagged; only the ones that are); feeder count (in use / spare, `count` included); the sum of in-use AT without diversity (and how many have no AT); PV share of the transformer, PV kW from B2 sizes, else A1 ÷ B2, else A1 kWp (flagged above 100 %); the PV breaker against the main AT, always with `(ตรวจพิกัดบัสบาร์กับวิศวกร)`. Level 1 had none of them.
- **Feeders** (`FeederGrid`): one row while there are at most 10 and the columns stay at least 60 apart (from 160), the last column clear of the PV breaker's labels; otherwise continuation rows of up to 10, the bus carried down the incomer's column and labelled `{board} …ต่อ`, the PV side moving down with them. Under 110 apart the breaker labels shrink to AT / AF / IC and the load lines to 8 characters. When the bus is full, `MAIN BUS …` moves up a line, right-aligned before the PV breaker.
- **Boards side by side:** a transformer's other boards sit in a row on a common LV line, 200 apart, when they fit before the next transformer (or the right edge), wrapping into more rows; otherwise they stack as in level 1 (so 4–5 transformers look as before).
- **Entry (A3):** the breaker sheet has a collapsed `รายละเอียดสาย / โหลด (SLD)` group (`ใช้งาน` / `สำรอง (SPARE)`, then cable, conduit, load name, floor), open when anything is filled; the breaker row shows a `SPARE` chip. The main and sub-board cards have a `บัสบาร์ · สายดิน (SLD)` row that opens a small sheet. Sub-board breakers (the `100 A × 2` size rows) have no level 2 entry.
- **Outputs:** the PDF page and the DXF draw the same layout, so they carry all of it (the N/G bars are stroked so the DXF keeps them).

## Implementation (Swift)

### Where the code is

```
TCRoofKit/Sources/
  TCRoofCore/                       (no UIKit / SwiftUI; tested with swift test)
    SingleLine.swift                model (SL* types), SLConstants, calculations
    SingleLine+Build.swift          build(job): reads the survey into SingleLine
    SingleLineLayout.swift          SingleLine → SingleLineDrawing (Sketch + hit boxes + B4 / B5 crops)
    SLSymbols.swift                 symbols as DrawOp paths
    SingleLineDXF.swift             DXF R12 export (via SketchDXF)
    Flood.swift                     FloodCheck (read for the flood card)
  TCRoofUI/Survey/
    Pages/Electrical/SingleLinePage.swift        page: header, toolbar (B4 toggle, PV board menu, zoom), drawing card, bottom bar
    Pages/Electrical/SingleLinePage+Panel.swift  side panel: PV data, IC check, blocking list, flood card, sheets
    Pages/Electrical/ElectricalPageWide.swift    A3 button "สร้าง Single Line Diagram →"
    Pages/Electrical/ElectricalPageWide+SLD.swift  level 2 entry: breaker sheet group, board busbar / ground sheet
    Pages/Electrical/SingleLineRender.swift      debounced off-main rebuild (250 ms) for the page and the B4 / B5 crops
    Editor/JobEditor.swift, JobEditor+Actions.swift  full-screen cover and openFromDiagram(SLTarget)
    Model/SurveyModel+Export.swift               exportSingleLinePDF / exportSingleLineDXF
  PDFReport/
    SingleLinePage.swift            singleLinePage(hv:): the A3 landscape page
    PDFRenderer.swift               renderSingleLine(job:header:hv:photo:)
    ReportLayout.swift              attachesSingleLine(job) → page after the A3 section
Tests/
  TCRoofCoreTests/SingleLineTests.swift, SingleLineDXFTests.swift
  PDFReportTests/SingleLineReportTests.swift
```

### Model (`SingleLine.swift`)

```swift
public enum SLStatus { case known, missing, assumed, new, condition(SLCondition) }
public enum SLCondition: String { case good, fair, bad }        // init from ดี / พอใช้ / ชำรุด
public struct SLTarget { enum Page { case info, electrical, flood, module(ModuleType) }; var page; var trafo, board: Int?; var breaker: UUID?; var linkLabel }
public struct SLText { var text: String; var status: SLStatus; var bold: Bool }

public struct SLBreaker   { id, trafo, board, number, isMain, isNew, type, at, af, ic, brand, condition?, note?, atAmps?, icKA?, name, destination, feeder, spare }
public struct SLBoard     { id, trafo, index, name, location, isMain, main: SLBreaker, breakers: [SLBreaker], busbar, ground }
public struct SLTransformer { id, index, lines: [SLText], collapsed, hasLA: Bool?, cable, boards, kva?, zPercent?, protection }
public struct SLMissing   { id, label, blocking: Bool, target: SLTarget }
public struct SLNote      { id, text, flagged: Bool, target: SLTarget }   // level 2 checks printed under the diagram
public struct SLAssumption{ id, text }
public enum   SLCheckState{ case ok, marginal, insufficient, unknown }
public struct SLCheck     { id, name, icKA?, state, target, value }
public struct SLFlood     { text, minCm, levelCm }
public struct SLPV        { capacityKWp?, inverterCount?, inverterKW?, inverterSizes?, inverterAT?, totalAT?, requiredIC?, busbar?, inverterCable?, mainCable?, cableRuns, totalCableM, rows, inverterSummary }

public struct SingleLine: Sendable {
    sourceLabel, meter: [SLText], protection: SLText, protectionKind: String
    zeroExportHV: Bool, hasB4: Bool, hasB5: Bool, pole: String
    transformers: [SLTransformer]
    connection: (trafo: Int, board: Int)
    pv: SLPV, isc: Double?, iscAssumedZ: Bool, checks: [SLCheck]
    missing: [SLMissing], assumptions: [SLAssumption], notes: [SLNote], flood: SLFlood?
    conditionCounts: (bad: Int, fair: Int), projectLine: String
    static func build(_ job: Job, hvOverride: Bool? = nil) -> SingleLine
}
```

`hvOverride` lets the page, the PDF and the DXF preview the other zero export position when the job has no B4 section. The calculation functions are static on `SingleLine` (`standardInverter`, `breakerAT`, `breakerAF`, `shortCircuit`, `requiredIC`, `classify`, `cable(forAT:)`, `busbar(forAT:)`); the rules are in the calculations table above.

### Layout and drawing (`SingleLineLayout.swift`)

```swift
public struct SLHit { var box: Box; var target: SLTarget }
public struct SingleLineDrawing { var sketch: Sketch; var hits: [SLHit]; var ftsBox, zeroExportBox: Box?; var width, height: Double }
public enum SingleLineLayout { static let width = 1560.0; static func draw(_ m: SingleLine) -> SingleLineDrawing }
```

- **Width:** fixed design width of 1560. Height grows with the content (the connection board frame starts at 820 or lower, plus 660).
- **Placement:**
  - Transformers are spaced evenly across the width (one transformer at x = 500).
  - The connection board spans the width under all transformers.
  - Other boards stack under their transformer, 230 apart.
- **Readability:** must hold with 1–5 transformers and up to 6 boards each.
- **Symbols** (`SLSymbols`, `DrawOp` paths). Lines stop at a symbol and never pass through it.
  - HV: pole, open switch (DS), DO fuse (`dropOutFuse`), VCB (`vcb`), picked by `hvDevice`; LA with ground, three cable terminations, Δ/Y transformer
  - Meter: `kWh` meter
  - Breakers: fixed arc, draw-out arc with chevrons
  - Zero export: CT (also CT/VT on HV), relay box
  - PV side: inverter (=/~), DC disconnect, PV array, emergency button
  - Other: load block, `))` line break
- **Hits:** one `SLHit` for the meter, every transformer, board, main and outgoing breaker, the relay (B4), the PV breaker and inverters (B2) and the emergency button (B5).
- **Crops:** `zeroExportBox` (the zero export parts) and `ftsBox` (inverters, FTS, PV arrays, emergency button) are shown read-only on the B4 and B5 pages.

`Sketch.svg()` output for the design sample should match `docs/ui/survey-sld/diagram-lv.svg` / `diagram-hv.svg` within a few points.

### UI (`SingleLinePage*.swift`)

- **Header:** `แผนภาพเส้นเดียว (Single Line Diagram)` with the sources and the job; back button.
- **Two panes** when the page is at least 900 pt wide: the diagram on the left, the side panel (310 pt) on the right. Layout and labels as in `CLAUDE_CODE_TASK.md` and `preview.png`.
- **Toolbar:**
  - `ตำแหน่งกันย้อน (B4)` segmented control (`แรงต่ำ · ที่ {board}` / `แรงสูง · หลังมิเตอร์`). It writes B4 `level`; with no B4 it previews only and says `ยังไม่มีหัวข้อ B4 · ดูตัวอย่างเท่านั้น`.
  - PV board menu `เชื่อมต่อ PV ที่ {board}`, one item per transformer and board
  - zoom `−` · `{n}%` · `+` · `พอดีจอ` (steps 35 / 50 / 60 / 75 / 90 / 100 %); pinch zooms 30–120 %, and the card scrolls both ways
- **Taps:** a tap picks the smallest hit box under the finger; every hit is at least 44 pt at the current zoom. Below 75 % zoom it first zooms to 90 % on the item. Then it closes the page and navigates to the `SLTarget`: A3 opens that transformer, board or breaker; A1, A4 and B-sections open their page.
- **Side panel:**
  - `ข้อมูลฝั่ง PV`
  - `เบรกเกอร์ทนลัดวงจร {Isc} kA ได้ไหม` (a note when %Z is assumed)
  - `ต้องเก็บก่อนออกแบบ`
  - flood card `จุดเชื่อมต่อเคยน้ำท่วม` (`A4 →`)
  - sheets for `ข้อมูลที่ขาดอื่นๆ`, `สภาพอุปกรณ์`, `ค่าสมมติ`
- **Bottom bar (iPad):** notes `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · อัปเดตเองเมื่อแก้ข้อมูลใน A3` and `ข้อมูลล่าสุด {time} · ยังขาด {n} จุด`, then `‹ แก้ข้อมูลใน A3` · `ส่งออก DXF` · `ส่งออก PDF (A3)` · `แนบในรายงาน` (toggles `sldAttach`).
- **Narrow iPad / iPhone:** the diagram takes the full width, the side panel becomes a sheet opened from the header's `ข้อมูล PV` button, and the zoom sits on the diagram. iPhone bottom bar: the notes, `ส่งออก DXF` and `แนบในรายงาน`, then `แก้ข้อมูลใน A3` / `ส่งออก PDF (A3)`.
- **Rebuild:** the diagram is rebuilt off the main actor 250 ms after the last edit (`SingleLineRender`), and so are the B4 / B5 crops.
- **Accessibility:**
  - The drawing has an accessibility summary (`แผนภาพเส้นเดียว หม้อแปลง {n} ลูก ยังขาด {n} จุด`).
  - Buttons are at least 44 pt.

### PDF and DXF

- `singleLinePage(hv:)`: one A3 landscape page (1190.55 × 841.89 pt). It holds the vector drawing scaled to fit, a title block (document number, project, date, engineer), the legend and a 318 pt side column: PV data, breaker check (with the %Z note), up to 9 blocking items, the flood note, a summary and up to 5 assumptions. The note `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง` is printed top right.
- `ReportLayout.attachesSingleLine(job)`: when true, the page is added after the A3 section, and the other pages do not move or renumber.
- `SingleLineDXF.build(job, hv:)`: DXF R12, 400 mm wide, layers by colour (`SLD_LINE`, `SLD_NEW`, `SLD_OK`, `SLD_WARN`, `SLD_MISSING`, `SLD_POLE`, `SLD_ASSUMED`, text on `SLD_TEXT`), with a title line and the same note under the drawing.

## Tests

`SingleLineTests.swift`:

| Test | Checks |
|---|---|
| `testBreakerSizing` | 60 kW → 125 AT; 2 × 60 kW → 250 AT |
| `testShortCircuit` | 630 kVA, 4.14 % → 22.0 kA; required IC 25 kA |
| `testBreakerCheckClassification` | 50 / 36 / 25 / nil against 22 kA |
| `testFixtureModel` | design sample builds the expected transformers, boards and PV rows |
| `testMissingItems` | blocking and non-blocking counts on the fixture |
| `testPVFromB2Sizes` | B2 `invSizes` give the breakers, feeder and summary; without them the A1 ÷ B2 fallback |
| `testPVBlockingWhenA1AndB2Empty` | no capacity or inverter count → blocking items, no PV sizes |
| `testAssumedZWhenImpedanceMissing` | %Z blank → 4 % assumed + blocking item |
| `testHVOverrideAndSelection` | `hvOverride`, `sldTransformer` / `sldBoard` pick the connection |
| `testOldJobBuilds` | job with only `kva` + `mdb` builds |
| `testLayoutHitsAndHeight` | every transformer / board / breaker has a hit box; height grows with content |
| `testWriteSVG` | with `SLD_SVG=<folder>`, writes the sample SVG for visual comparison with `diagram-*.svg`, plus `level2-lv/hv.svg` and `level2-wrap.svg` (14 feeders, four sub-boards side by side) |
| `testLevel2FieldsDecodeFromOldJSON` | old breaker / board JSON decodes with empty level 2 fields; they round-trip |
| `testLevel2FieldsLeaveCompletionAndMissingAlone` | completion unchanged; a spare only drops its B1 load item |
| `testLevel2Model`, `testLevel2Drawing` | feeder text, load / floor lines, spare, busbar, N/G bar and ground rod |
| `testLevel2Notes` | the seven checks, flagged ones, and no missing items added |
| `testFeedersWrapOrNarrow` | 10 feeders in one row ≥ 60 apart; 14 wrap into `…ต่อ` |
| `testBoardsSideBySideOnOneTransformer` | four sub-boards in one row; with five transformers they stack |

`SingleLineDXFTests.swift` checks the layers, paper scale, the missing-value layer, that HV and LV differ, and that the level 2 detail reaches the DXF (`testLevel2Detail`). `SingleLineReportTests.swift` checks that `แนบในรายงาน` adds one A3 page and leaves the other pages alone, that the page builds on its own, and that the level 2 detail and notes are on it (`testLevel2OnThePage`).

## Done when

- [x] A3 → `สร้าง Single Line Diagram →` opens the page on iPad and iPhone.
- [ ] The design sample matches `preview.png` / `preview-hv.png` and `diagram-lv.svg` / `diagram-hv.svg` (checked by eye in the simulator).
- [x] The LV / HV toggle changes B4 (or previews when there is no B4).
- [x] Tapping a red `?` opens A3 on that item. Filling it removes it from the list on return.
- [x] Changing the PV board redraws the connection board, Isc and the IC check.
- [x] `ส่งออก PDF (A3)` shares one vector A3 page. With `แนบในรายงาน` on, the survey PDF contains it.
- [x] Old jobs open without data loss. `swift test` passes.

## Open questions

None of them block v1.

1. ~~Do PV and B1 panels always connect at TR1's main board?~~ Answered: the SLD page has `เชื่อมต่อ PV ที่ตู้นี้` (`sldTransformer` / `sldBoard`); the default is TR1's main board.
2. ~~Is 1.25 × rated current the team's breaker rule?~~ Yes (2026-10-19).
3. Cable size table and 20 m run length are assumptions. Does the team have a standard table to replace them?
4. For กันย้อนแรงสูง, which equipment and ratings does กฟภ. expect on the SLD (recloser / LBS, relay 32R, CT/VT ratios)?
5. Should the SLD image also go on the Excel electrical sheet? (not in v1)
6. Large stations: v1 fits one A3 page with zoom in the app. Split the PDF per transformer when the scale gets too small?
7. Should DOF / DS / VCB, LA and grounding also get a condition field?
8. Keep the Thai breaker symbol (arc) everywhere, or allow the IEC symbol as a setting?
9. ~~VCB / DO fuse symbols; FTS without B5?~~ Own symbols; FTS and the emergency button left out without B5 (2026-10-19).
