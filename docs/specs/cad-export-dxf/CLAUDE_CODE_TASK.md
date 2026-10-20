# Claude Code task: CAD export (DXF R12) for the SLD and D1, from one shared `Sketch` → DXF writer

**Status:** done (C1, the SLD, D1, and A2 as well). The as-built layer tables are in `SPEC.md` (As built).

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/specs/cad-export-dxf/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; English in brackets is only a gloss. Background, the SDK comparison and the open questions are in `SPEC.md` in this folder. Read it first.

## Goal
TCRoof already writes the C1 roof as a DXF R12 file (`TCRoofCore/RoofDXF.swift`, sheet `ส่งออก CAD` in `TCRoofUI/Survey/Pages/Roof/RoofPageWide+Sheets.swift`). It uses no library, costs nothing, and AutoCAD / BricsCAD / DraftSight / LibreCAD open it.

Do three things, in this order. Each phase ends green (`swift test` + an app build) before the next starts:
1. **Phase 1:** pull the generic DXF writing out of `RoofDXF` into a shared `SketchDXF` that can write **any** `Sketch`. `RoofDXF` output must stay **byte-for-byte identical**.
2. **Phase 2:** add `ส่งออก DXF` (export DXF) to the single line diagram page (`SingleLinePage`), next to `ส่งออก PDF (A3)`.
3. **Phase 3:** add the same to D1 (`TankPageWide`), drawing the tank plan at real scale in metres.

No new dependencies. No GPL code (LibreDWG, libdxfrw and dxflib are **not** allowed). No DWG writing.

## Before reading the source
Use code-review-graph first (per `CLAUDE.md`; run `code-review-graph build` if it is empty), then read the source:
- `DrawOp`, `Sketch`, `Pt`, `Box`, `RGBA` (`TCRoofCore/Sketch.swift`)
- `RoofDXF` (`TCRoofCore/RoofDXF.swift`) and `RoofDXFTests` (`Tests/TCRoofCoreTests/RoofDXFTests.swift`)
- `Sketch.svg` and `ApproxText.width` / `ApproxText.wrap` (`TCRoofCore/SketchSVG.swift`): reuse the wrap for `textBox`
- `SingleLineLayout.draw` and its colour constants (`TCRoofCore/SingleLineLayout.swift`), `SingleLine.build(_:hvOverride:)` (`TCRoofCore/SingleLine+Build.swift`), `SLSymbols`
- `PDFRenderer.renderSingleLine` (how the PDF chooses `hv` and scale)
- `SingleLinePage` (`buttons`, `padBar`, the phone `BottomBar`, `exportPDF`, `shared` / `ShareSheet`)
- `SurveyModel+Export.swift` (`exportSingleLinePDF`, `tempURL`, `baseName`, `ExportFile`)
- `TankPlan` (`TCRoofCore/TankPlan.swift`: `init?(_:width:chips:hints:)`, the local `k`, `ox`, `oy`, `compactFrame`) and `TankPageWide*`
- `tests_for` on `RoofDXF`, `SingleLineLayout`, `TankPlan`

Facts to check in the source before relying on them:
- `RoofDXF.write(_:)` writes `rect`, `polygon`, `polyline` as separate `LINE`s, `circle` as `CIRCLE`, `text` as a centred `TEXT` with a **fixed** height, and skips everything else. It ignores dash, colour and width.
- `RoofDXF` header: `$ACADVER AC1009`, `$DWGCODEPAGE ANSI_874`, `$INSUNITS` 4 (mm) / 6 (m), LTYPE table with only `CONTINUOUS`, a LAYER table in first-use order with `RoofDXF.colors`, CRLF line ends, bytes from `RoofDXF.tis620`.
- `SingleLineLayout.width` is 1560 (sketch points); the SLD PDF page is A3.
- `TankPlan`'s first op is a white background `rect` with `stroke: nil`. It must **not** be written.
- `TCRoofCoreTests` has no resources in `Package.swift`. Golden files need `resources: [.copy("Fixtures")]` added to that test target (same as `ExcelExportTests`).

## Phase 1: `SketchDXF` (TCRoofCore, pure, tested)

### 1a. Freeze the current output first
Before changing `RoofDXF`, add `Tests/TCRoofCoreTests/Fixtures/` and write the **current** `RoofDXF.build` bytes for the `roof()` values in `RoofDXFTests` as golden files:
- `roof-plan-section-table-mm.dxf` (`[.plan, .section, .table]`, mm)
- `roof-plan-m.dxf` (`[.plan]`, metres)
- `roof-pv-mm.dxf` (`[.pv]`, mm)

Generate them with a one-off test or script from the **unchanged** code and commit them. Then add `testGoldenUnchanged` comparing `Data` exactly. This test must pass before and after the refactor.

### 1b. The writer
New file `TCRoofCore/SketchDXF.swift`:

```swift
public struct SketchDXF: Sendable {
    public struct Layer: Sendable, Hashable { public var name: String; public var aci: Int }
    public struct Options: Sendable {
        public var millimetres = true          // $INSUNITS 4 / 6; coordinates × 1000 when true
        public var dashes = false              // write a DASHED linetype for ops with dash ≠ []
        public var opColours = false           // group 62 when the op colour's ACI differs from the layer's
        public var textBoxes = false           // wrap textBox into TEXT lines
        public var hatches = false             // hatch → clipped LINEs
        public var outlineBoxes = false        // photo / checkbox → outline rectangle
        public var fixedTextHeight: Double? = nil  // metres; nil = from the op's font size (see Text)
        public var centreText = true           // RoofDXF: every .text is centred (72=1, 73=2)
    }
    public init(options: Options = .init())
    /// Writes `ops` mapped by `transform` (sketch point → metres, Y up). `layer` picks a layer per op; nil skips the op.
    /// `pointsPerMetre` converts radii, text sizes and hatch spacing.
    public mutating func add(_ ops: [DrawOp], layer: (Int, DrawOp) -> Layer?, transform: (Pt) -> (Double, Double), pointsPerMetre: Double)
    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double))
    public mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double)
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign = .left, middle: Bool = false, angle: Double = 0)
    public var entityCount: Int { get }
    public var layers: [String] { get }       // first-use order
    public func data() -> Data                // header + tables + entities, CRLF, TIS-620
}
```

- Move `num` and `tis620` into `SketchDXF` (keep `RoofDXF.num` / `RoofDXF.tis620` as thin forwards: the tests call them).
- `RoofDXF.build` keeps its signature and `Output`, and becomes a caller of `SketchDXF` with all `Options` at their defaults + `fixedTextHeight` per call (it passes `th` / `th * 0.8`). Its extra `TEXT` lines (titles, table) use `text(…)`.
- The defaults reproduce today's bytes. If any default has to change to stay identical, change the default, not the golden file.

### 1c. DrawOp → DXF R12 (when the option is on)

| DrawOp | Written as | Option |
|---|---|---|
| `line` | `LINE` | always |
| `polyline` | `LINE` per segment | always |
| `rect`, `polygon` | `LINE` per edge (closed) | always, **unless** `stroke == nil` (fill only → skip) |
| `circle` | `CIRCLE` (fill ignored) | always, unless `stroke == nil && fill == nil` |
| `text` | `TEXT`; `align` → 72 = 0/1/2 with 11/21 alignment point; `angle` → group 50; vertical middle → 73 = 2 | always |
| `textBox` | `ApproxText.wrap(…, width: box.w, size:)` → one `TEXT` per line from the top, line pitch `size × 1.3`, stop at the box bottom | `textBoxes` |
| `hatch` | the same diagonal lines `Sketch.svg` draws, **clipped to the box** in code (no clip in DXF) | `hatches` |
| `photo`, `checkbox` | outline rectangle (checkbox: plus an X when `on`) | `outlineBoxes` |
| `dash ≠ []` | entity group `6 DASHED`; add `LTYPE DASHED` to the table (pattern from the first dash pair, in drawing units) and bump the LTYPE count to 2 | `dashes` |
| colour | group `62` with the nearest ACI (`SketchDXF.aci(_ RGBA)`: 1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 black/white, 8 grey, 30 orange), only when it differs from the layer's | `opColours` |

Rules:
- **Text height:** DXF height is cap height. With `fixedTextHeight == nil`, use `size × 0.7 / pointsPerMetre` metres.
- Drop zero-length lines (as now).
- Skip empty strings.
- `bold` is ignored (R12 has no per-entity weight). Line width is ignored.

### 1d. Tests (`Tests/TCRoofCoreTests/SketchDXFTests.swift`)
- `testGoldenUnchanged` (above).
- A sketch with one of every `DrawOp` case and every option on gives:
  - an even number of lines;
  - `0 EOF` last;
  - each layer once in the LAYER table, with the right count;
  - `DASHED` declared once when used and not declared when unused.
- Fill-only `rect` writes nothing.
- `text` with `align: .right, angle: 90` writes `72 = 2` and `50 = 90`.
- `textBox` with a long Thai string wraps into ≥ 2 `TEXT`s, all inside the box.
- `hatch` lines all lie inside the box (check every endpoint).
- Y flip: with a transform `(x, H − y)`, a point at sketch (0, 0) lands at (0, H × 1000) in mm.
- `aci` maps `SingleLineLayout.red` → 1 and `.ink` → 7.

## Phase 2: SLD `ส่งออก DXF`

### Engine
`TCRoofCore/SingleLineDXF.swift`:
```swift
public enum SingleLineDXF {
    public static func build(_ job: Job, hv: Bool? = nil) -> RoofDXF.Output   // reuse Output (data, entities, layers)
}
```
- Draw with the same calls the PDF uses: `SingleLineLayout.draw(SingleLine.build(job, hvOverride: hv))`. Read `PDFRenderer.renderSingleLine` and copy its `hv` handling. The DXF and the PDF must show the same diagram.
- **Paper scale** (decision; see SPEC open question 2): units mm, the whole sketch scaled so its width is **400 mm** (A3 landscape 420 mm minus 10 mm margins). The transform is `(x × s, (H − y) × s)` with `s = 400 / sketch.width` mm per point, and `pointsPerMetre = 1000 / s`.
- All options on.
- **Layers by colour.** Read `SingleLineLayout` and `SLSymbols` to confirm what each colour means, then map them. Proposed defaults (fix the names if the source says otherwise, and record the final table in `SPEC.md`):

| Colour constant | Layer | ACI |
|---|---|---|
| `ink` | `SLD_LINE` | 7 |
| `blue` | ~~`SLD_PV`~~ `SLD_NEW` (superseded) | 5 |
| `green` | `SLD_OK` | 3 |
| `amber` | `SLD_WARN` | 30 |
| `red` | `SLD_MISSING` | 1 |
| `grey` | ~~`SLD_NOTE`~~ `SLD_ASSUMED` (superseded) | 8 |
| `pole` | `SLD_POLE` | 8 |
| any `text` / `textBox` op | `SLD_TEXT` (keep the op colour with group 62) | 7 |
| anything else | `SLD_OTHER` | 7 |

- Add a title block line under the drawing: `SINGLE LINE DIAGRAM · <job no> · <site name> · <date>` on `SLD_TEXT`, 3.5 mm high. Read the job number and site name from the same fields the PDF header uses; check `reportHeader` / `baseName`.
- Keep the `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง` (made from survey data, not a construction drawing) note as text on the drawing too.

### UI (`SingleLinePage`)
- `SurveyModel+Export.swift`: add `exportSingleLineDXF(_ job: Job, hv: Bool? = nil) throws -> ExportFile`. Do it the same way as `exportSingleLinePDF`: `flush`, then `tempURL("SLD " + baseName(job) + ".dxf")`, with summary `Single Line Diagram DXF`.
- **iPad** `buttons(_:)`: add `barButton("ส่งออก DXF", filled: false, action: exportDXF)` between `‹ แก้ข้อมูลใน A3` and `ส่งออก PDF (A3)`.
- **iPhone:** the `BottomBar` `.pair` stays as is. Add a 44 pt `ส่งออก DXF` button to the row above it (beside `attachButton`).
- `exportDXF()` mirrors `exportPDF()` (same `hv` rule, `shared = ShareItem(url:)`, errors to `self.error`).
- Use `Theme` / existing `barButton` styling only. No hex literals. Hit areas ≥ 44 pt.
- DEBUG: `-surveySLDDXF YES` (with `-surveyPage sld`) writes the file to `Documents/sld.dxf` on open, for checks without the share sheet. Add it to the launch-argument list in `CLAUDE.md`.

### Tests
- `SingleLineDXFTests`, using the demo or test job that `SingleLineTests` uses:
  - the output has `SLD_LINE` and `SLD_TEXT`;
  - every X lies in 0…400 mm;
  - a job with a missing A3 value has `SLD_MISSING`;
  - `hv: true` and `hv: false` give different entity counts when the PDF also differs.

## Phase 3: D1 tank `ส่งออก DXF`

### Engine
`TCRoofCore/TankDXF.swift`, `TankDXF.build(_ v: Values) -> RoofDXF.Output?` (nil when `TankPlan` is nil):
- **Real scale**, metres × 1000 (mm). `TankPlan.init` computes `k`, `ox`, `oy` locally. Expose them as a `public let frame: (ox: Double, oy: Double, k: Double)` (or a small struct) without changing the drawing. Then the transform is `((x − ox)/k, TH − (y − oy)/k)`, with `TH` the total depth in metres.
- Tag ops by what they draw. `TankPlan` has no `tags` today. Add a parallel `tags: [String?]` like `RoofPlan.tags` / `RoofSection.tags`, filled where each op is appended: `grid`, `out`, `dim`, `dimtxt`, `obst`, `pv`, `kz`, `north`, `txt`, and `nil` for the background.
- Layers: `GRID 8, OUTLINE 7, DIM 3, OBSTACLE 1, PV 150, ~~KEEPOUT 1~~, NORTH 7, TEXT 7` (same colours as `RoofDXF.colors` where the name matches). Superseded: there is no `KEEPOUT`; `TankDXF` writes `PV` / `PV_GROUP` from the layout plus `BEAM` / `SECTION_MARK`.
- The sub-step 3 PV layout (`TankLayoutPlan` / layout values), if it lives in a separate sketch, goes on `PV` / `PV_GROUP` the same way. Read `TankPageWide+Layout` and include it only if it is a `Sketch` in `TCRoofCore`. Otherwise list it as an open question.
- Options: `hatches` on (obstacles are hatched), `dashes` on, `textBoxes` on, `opColours` off (layer colours carry the meaning).

### UI
- Put `ส่งออก DXF` where D1 already offers export or share. If D1 has none, add it to the D1 `cardBar` actions. Use the same `ExportFile` + share pattern, file name `<job no>_D<n>.dxf` like C1.
- DEBUG: `-surveyTankDXF YES` (with `-surveyPage tank`) writes `Documents/tank.dxf`, and add it to `CLAUDE.md`.

### Tests
- `TankDXFTests`:
  - the outline's extents equal the spans' sums × 1000 (±1 mm);
  - an obstacle gives `OBSTACLE` lines all inside its box;
  - no entity comes from the background rect;
  - `TankPlan` still draws exactly the same ops as before (compare `Sketch.svg()` before and after adding `tags`).

## Data rules (from `CLAUDE.md`, must hold)
- Export only **reads** `Values` / `Job`. No new stored fields. Excel, PDF and `Progress` stay unchanged.
- `RoofDXF` bytes are unchanged (golden test).
- `TankPlan` / `SingleLineLayout` drawings are unchanged (same ops, same order). Adding `tags` / `frame` must not touch `ops`.
- Split long SwiftUI expressions into computed properties (Debug type-check / SIGSEGV issue).

## Check list
1. `cd TCRoofKit && swift build && swift test`: all green, including the golden test.
2. App build, in the background, with your own DerivedData:
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build`
3. Simulator:
   - `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage sld -surveySLDDXF YES`. Screenshot the bar to show `ส่งออก DXF`, then pull `Documents/sld.dxf` from the app data container.
   - Same with `-surveyPage tank -surveyD1 layout -surveyTankDXF YES` → `Documents/tank.dxf`.
4. Validate the files off-device:
   - `python3 -m pip install --user ezdxf && python3 -m ezdxf audit sld.dxf tank.dxf` must report no errors. Fixes it lists as "auto-fixed" count as errors.
   - Also `python3 -m ezdxf draw sld.dxf -o sld.png`, and compare the PNG with the SLD PDF page by eye: same boxes, lines and labels, Thai readable.
5. If the Mac has ODA File Converter or LibreCAD, open both files once and note the result.

## Report at the end
- The final SLD colour → layer table, and whether you changed any proposed name.
- File sizes and entity counts of the demo `sld.dxf` and `tank.dxf`.
- Anything `SketchDXF` skips that a user would notice (fills, photos, bold).
- The open questions from `SPEC.md`, plus any new ones, e.g. whether D1's layout plan is a `Sketch`.
