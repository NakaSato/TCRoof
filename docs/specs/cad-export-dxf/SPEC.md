# CAD export (DXF) — iPhone / iPad

Status: built for C1, the SLD, D1 and A2 (`SketchDXF`, `SingleLineDXF`, `TankDXF`, `SiteDXF`). Build steps: `CLAUDE_CODE_TASK.md` in this folder.

## Goal

Every drawing TCRoof already makes as a `Sketch` (C1 roof plan, SLD, D1 tank layout, A2 site plan) can be shared as a CAD file that opens in AutoCAD, BricsCAD, DraftSight, LibreCAD and similar programs. It must cost nothing and add no libraries.

## SDK options for iOS

| Option | DWG read | DWG write | DXF | Offline | Cost | Notes |
|---|---|---|---|---|---|---|
| **Own DXF writer (this spec)** | – | – | write R2000 | yes | free | Built: `TCRoofCore/SketchDXF.swift`, used by C1, the SLD, D1 and A2 |
| ODA File Converter (Mac/Windows desktop) | yes | yes | yes | yes | free | Converts DXF ↔ DWG in batches. Not an iOS library |
| Autodesk Platform Services (Viewer + Model Derivative) | view only | – | view | no | free tier, then usage-billed | Shown in a `WKWebView`; needs an Autodesk account |
| LibreDWG / libdxfrw / dxflib | partial | partial | yes | yes | free | **GPL**: cannot ship in a closed App Store app |
| ODA Drawings SDK (Teigha) | yes | yes | yes | yes | paid yearly membership | Native C++ for iOS; the only full DWG option on device |
| CAD Exchanger SDK, Apryse CAD module | yes | limited | yes | yes | paid | Built on ODA |

There is no official Autodesk SDK for iOS: RealDWG is desktop only (Windows/macOS).

Decision: **write DXF R12 ourselves.** If someone needs a `.dwg`, they open the DXF in their CAD program, or run it through ODA File Converter, and save it as DWG. Look at the ODA SDK only if the app must *open and edit* customers' DWG files.

## Before SketchDXF — `RoofDXF`

- DXF R12 (`$ACADVER AC1009`), CRLF line endings, `HEADER` + `TABLES` (LTYPE `CONTINUOUS`, LAYER) + `ENTITIES`.
- Entities: `LINE`, `CIRCLE`, `TEXT` (centred with group codes 72/73 when `mid`).
- Layers carry an AutoCAD colour index (`RoofDXF.colors`); sketch path tags (`RoofPlan.tags`) map to layers (`planLayers`, `pvLayers`).
- Units: `$INSUNITS` 4 (mm) or 6 (m); the drawing is 1:1 in real metres × `u`.
- Thai text: `$DWGCODEPAGE ANSI_874` and the bytes written as TIS-620 (`tis620`), with `·`, `×`, `°`, `Ø` swapped for CAD-safe text (`%%d`, `%%c`).
- Y is flipped: sketch Y points down, DXF Y points up (`tp` / `ts` transforms).
- UI: the ส่งออก CAD sheet in `RoofPageWide+Sheets.swift` (parts, units, then share the `.dxf` through AirDrop, Files or Mail).

Gaps in `RoofDXF`'s own `write(_:)` then: `textBox`, `hatch`, `photo` and `checkbox` were skipped, and dashes and stroke colours were dropped.

Now: `SketchDXF.Options` has `dashes` (a `DASHED` LTYPE, declared when used), `opColours` (group 62), `textBoxes`, `hatches`, `outlineBoxes` (photo / checkbox outlines) and `skipFillOnly`, plus `millimetres`, `fixedTextHeight` and `centreText`; the defaults write what `RoofDXF` always wrote. The remaining gaps are fills, bitmaps, bold and line widths.

## Plan

### 1. `SketchDXF` in `TCRoofCore`

Move the generic parts of `RoofDXF` out into a shared writer. Built (`TCRoofCore/SketchDXF.swift`):

```swift
public struct SketchDXF: Sendable {
    public struct Layer { public var name: String; public var aci: Int; public init(_ name: String, aci: Int) }
    public struct Options { millimetres, dashes, opColours, textBoxes, hatches, outlineBoxes, skipFillOnly,
                            fixedTextHeight: Double?, centreText }
    public init(options: Options = .init())
    /// Writes `ops` mapped by `transform` (sketch point → metres, Y up); `layer` picks a layer per op (nil skips it).
    public mutating func add(_ ops: [DrawOp], layer: (Int, DrawOp) -> Layer?, transform: (Pt) -> (Double, Double),
                             pointsPerMetre: Double)
    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double))
    public mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double)
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String,
                              align: TextAlign = .left, middle: Bool = false, angle: Double = 0)
    public func data() -> Data   // R12, CRLF, TIS-620
    public static func aci(_ c: RGBA) -> Int   // nearest AutoCAD colour index
}
```

`RoofDXF.build` then calls `SketchDXF`, and its output must stay byte-for-byte the same (a test compares the two).

### 2. DrawOp → DXF R12

| DrawOp | DXF |
|---|---|
| `line` | `LINE` |
| `polyline` | one `LINE` per segment (as built) |
| `polygon`, `rect` | one `LINE` per side (as built) |
| `circle` | `CIRCLE` |
| `text` | `TEXT`; `angle` → group 50; `align` → 72 (0/1/2) with 11/21 alignment point |
| `textBox` | wrap into lines like the PDF renderer does, then one `TEXT` per line |
| `hatch` | the clipped hatch lines as `LINE`s (R12 has no `HATCH`) |
| `dash` ≠ [] | a `DASHED` LTYPE in `TABLES`, set on the entity (group 6) |
| stroke colour | layer colour by default; group 62 only when the op's colour differs from the layer |
| `photo`, `checkbox` | outline rectangle only (no bitmaps in CAD) |

Fills are not written (R12 `SOLID` only takes 3–4 points; not worth it).

### 3. Exports to add

1. **SLD (A3)**: layers by colour, as built (see As built). This one matters most: PEA permit packs ask for it.
2. **D1 tank layout**: tank outline, obstacles (hatch), PV tables, keep-out.
3. **A2 site plan**: building models, symbols, cable route.

Each gets a `…DXF.build(_ v: Values, …) -> RoofDXF.Output`-style function and reuses the ส่งออก CAD sheet pattern.

### 4. Tests (`swift test`)

- `RoofDXF` output is unchanged after the refactor (golden file).
- Every DrawOp case writes valid group-code pairs (even line count, ends with `0 EOF`).
- Thai text round-trips through TIS-620; unknown symbols become `?`.
- Y flip: a point at sketch top-left lands at DXF (0, height).
- Open each golden file in LibreCAD / ODA File Converter once by hand before release.

## Data rules

- Export only reads `Values`; no new fields, no change to Excel, PDF or `Progress`.
- File name: `<job no>_<section>.dxf`, spaces removed (as C1 does now).

## As built

SLD layers, by the op's colour (`SingleLineDXF.colourLayers`; meanings from `SingleLineLayout.color(_:)`):

| Colour | Means | Layer | ACI |
|---|---|---|---|
| `ink` | known value | `SLD_LINE` | 7 |
| `blue` | new equipment (PV breaker, inverter, CT, control lines) | `SLD_NEW` | 5 |
| `green` | condition good | `SLD_OK` | 3 |
| `amber` | condition fair | `SLD_WARN` | 30 |
| `red` | missing value | `SLD_MISSING` | 1 |
| `pole` fill | pole marker | `SLD_POLE` | 8 |
| `grey` | assumed value | `SLD_ASSUMED` | 8 |
| any `text` | labels; the op colour kept with group 62 | `SLD_TEXT` | 7 |
| anything else | | `SLD_OTHER` | 7 |

Condition colours (green, amber, and red for poor) only colour text, so lines in red always mean a missing value. The
task's proposed `SLD_PV` and `SLD_NOTE` were renamed `SLD_NEW` and `SLD_ASSUMED` to match what the colours mean.

D1 layers: `GRID 8, OUTLINE 7, DIM 3, OBSTACLE 1, NORTH 7, TEXT 7, BEAM 8, SECTION_MARK 5` from `TankPlan.tags`, and `PV 150` (panels switched
on) / `PV_GROUP 170` (table outlines, footing circles) from `TankLayout.current`. The layout is drawn from
`TankLayout`'s tank-metre data, not from a sketch (the page draws it in a SwiftUI `Canvas`). Cut columns are not written.

A2 (`SiteDXF`, the picture menu's `ส่งออก DXF`): the site picture's frame in millimetres from its bottom-left corner,
at real scale from `siteScale` (metres across the picture). Without a scale it is 400 mm wide, the title says so, and
building models are left out (as on the report). Layers: `FRAME 8`, `PV_AREA 5` / `BUILDING 4` (building models),
`SHAPE 4` (boundary and PV point shapes), `PANEL_AREA 1`, `CABLE 5`, `MEASURE 3`, `CRANE 30`, `SHADE 30` (drawn shapes), `SYMBOL 7` (marks, their colours kept with
group 62), `NORTH 7`, `TEXT 7` (title line). Symbol and tag sizes follow the picture's width as on the report, so they
are not at a real size. Translucent tints (a model's area) are not written; the picture itself is not either.

Not written by any export: fills (R12 has no fill short of `SOLID`), photos (an outline only), bold, line widths.

Every export (built 2026-10-22, in `SketchDXF.data`, checked with `ezdxf audit` and LibreCAD):
- **Text style `CORDIA`**: the STYLE table holds `STANDARD` (txt) and `CORDIA` (`cordia.shx`, width factor 0.85, the
  team's Thai SHX font); every `TEXT` names it (group 7) with width 0.85 (group 41), and `$TEXTSTYLE` is `CORDIA`. A
  Thai SHX font reads the TIS-620 bytes as they are written, so the codepage stays. Before, the text used the CAD
  program's default font, which has no Thai (the letters showed as boxes). A computer without `cordia.shx` gets the CAD
  program's font substitution prompt; copy the font into its Fonts folder.
- **Extents and view**: `$EXTMIN` / `$EXTMAX` and `$LIMMIN` / `$LIMMAX` from what the entities cover (text by an estimate
  of its width), and a VPORT table whose `*ACTIVE` view is centred on them with a 5 % margin, so the file opens framed.
- **Standard DXF R2000** (`AC1015`, replacing R12 on 2026-10-22): every object has a handle and its owner, entities
  carry their subclass markers, and the file has every standard table (VPORT, LTYPE ByBlock / ByLayer / Continuous,
  LAYER with `0`, STYLE `Standard` + `CORDIA`, VIEW, UCS, APPID `ACAD`, DIMSTYLE `Standard`, BLOCK_RECORD), the
  `*Model_Space` / `*Paper_Space` blocks, a CLASSES section and OBJECTS (the root dictionary, `ACAD_GROUP`, the layouts
  `Model` / `Layout1`, `ACAD_MLINESTYLE`, `ACAD_PLOTSTYLENAME`). `ezdxf audit` finds no errors; LibreCAD opens it
  (its `dxf2pdf` needs `-a` to fit the page). Shapes are LWPOLYLINEs.
- **Wipeouts under PV modules**: each D1 module block (`PV_MODULE_<w>x<h>`) and each C1 แผงบนหลังคา module starts with a
  WIPEOUT of its outline, so the grid, beams and purlins under a module are hidden as on the printed plan; the frame is
  off (`ACAD_WIPEOUT_VARS` → `WIPEOUTVARIABLES` 70 = 0), so only the module's own outline shows and prints. LibreCAD
  ignores WIPEOUT and shows the lines under it.
- **Dimensions and hatches** (2026-10-22): the plans' span chains and totals (C1's plan, D1's square and round plans:
  `RoofPlan.Layout.dimensions`, `TankPlan.dimensions`) are DIMENSIONs (`SketchDXF.dimension`), one per span and one per
  total, in place of their lines and texts. Each draws as the sketch did (extension lines, 45° ticks, the text above
  the line) from an anonymous block `*D<n>`, in a style per text height (`TC_<height>`: DIMTSZ ticks, CORDIA text,
  DIMLFAC to metres, two decimals; `TC_<height>_Z` drops trailing zeros for labels like `4` or `1.5`), so CAD redraws it
  the same after an edit. The measured part of the label is written `<>`, so moving a point updates the number;
  `Ø <>` keeps its prefix, and any other label stays as written. The C1 section's dimensions stay lines: the section is
  a diagram, not to scale. A `hatch` is one HATCH (ANSI31 at the sketch's spacing, inside the box), and an opaque
  coloured fill with no stroke (posts, rail feet, junction dots, a north arrow's head) adds a SOLID HATCH inside its
  outline (`Options.hatchEntities`; off writes the old lines).
- **Objects, not loose lines**: a polyline, a rectangle, a polygon and an outline are one LWPOLYLINE each (closed for the
  shapes). The SLD's symbols are BLOCKs placed by INSERTs (`SingleLineDrawing.symbols`, marked where the layout draws
  them: `SLD_BREAKER`, `SLD_BREAKER_DRAWOUT`, `SLD_TRANSFORMER`, `SLD_METER`, `SLD_CT`, `SLD_POLE`, `SLD_HV_SWITCH`,
  `SLD_HV_DEVICE`, `SLD_ARRESTER`, `SLD_CABLE_TERMINATIONS`, `SLD_INVERTER`, `SLD_DC_DISCONNECT`, `SLD_PV_ARRAY`,
  `SLD_EMERGENCY`, `SLD_LOAD`, `SLD_GROUND`, `SLD_LINE_BREAK`), and each D1 module an INSERT of `PV_MODULE_<w>x<h>`. Block
  bodies are on layer 0 in colour BYBLOCK, so an insert shows its own layer and colour (a new-equipment breaker is the same
  block on `SLD_NEW`). A symbol whose geometry differs from its name's block gets its own (`SLD_HV_SWITCH-2`), so the
  drawing never changes; `SketchDXF.Symbol` marks any sketch's symbols the same way. Plain wires, grid lines and hatch
  strokes stay LINEs. The roof golden files hold the same segments, circles and texts as before.
- **Symbols**: `m²` / `m³` become ตร.ม. / ลบ.ม.; ± → `%%p`; ø, φ, ⌀ → `%%c`; — − → `-`; → `->`; ≥ ≤ ≠ ≈ … ² ³ ¾ quotes ✓ ✕
  Ω to ASCII. A `?` left in a file is a value the survey hasn't got yet (`IC ? kA`, `?AF`).

## Open questions

1. Does PEA (or PWA) accept DXF in the permit pack, or must it be DWG / PDF only?
2. SLD in real scale or paper scale (A3 sheet in mm, 1:1 with the PDF)? Paper scale is simpler for a schematic.
3. Should a title block (company, job, date, signer) be drawn into each DXF?
5. Should the C1 section be drawn to scale, so its dimensions can be real ones too?
4. ~~Is the TIS-620 codepage enough?~~ Answered 2026-10-22: TIS-620 with the team's `cordia.shx` (width 0.85), above.
