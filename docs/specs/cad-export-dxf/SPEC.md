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
- **Roof walkways** (2026-10-22, after the team's walkway drawings in `reference/`): each walkway gap of C1's PV layout
  (`RoofWalkway.walkways`: one module column up the slope, every n columns or, as most roofs have it, one down the
  middle of each face, `walkwayCentre`, the roof page's `กลางหลังคา`, the default once walkways are on) is drawn as the
  team's top view `Walkway_S1.dxf`, measured: a 0.90 m band with, from its cable-tray side, the 200 mm cable tray at
  0.053–0.253 (dotted, TC-PV-CABLETRAY, green), the HDG grating 0.30 × 2.40 × 0.03 m at 0.325–0.625 in panels with a
  0.03 inner frame, cross-hatched (ANSI37, TC-PV-WALKWAY, red), with L-feet every 1.20 m from 0.63 m in at both its
  edges (magenta), the 3/4" PPR pipe at 0.656, the rail at 0.687–0.712 (solid, green) and the 6 mm wire-rope lifeline
  at 0.80 with supports every 2.40 m from 0.65 m in (TC-PV-LIFELINE, cyan); grating and tray on WIPEOUTs, with the
  band's width and a tag. Open: `Walkway_S1` draws the grating panels about 3.06 m long while its note says
  0.30 × 2.40; the app follows the note. With any walkway the DXF also carries the team's walkway detail
  (`Walkway.dxf`: top view, elevations 1–3, detail 1) as one block `TC_DETAIL_WALKWAY` on TC-DETAIL beside the drawing,
  at the plot scale; it comes from `Resources/walkway-detail.json`, made by `tools/cad-details/convert.py` from the DXF
  (blocks, dimensions and leaders exploded, XCLIP frames applied); run it again when the detail changes. Under the
  band, a cross rail (hat section 24 mm, TC-PV-RAIL, grey) at every L-foot. Down the middle (`walkwayCentre`) each
  face's walkway runs on past its top row to the ridge (`RoofWalkway.ridgeEnd`, or where a hip edge crosses the
  band), and on a roof with a ridge a walkway runs along it (`RoofWalkway.ridgeWalkway`: centred on the ridge, 0.50 m
  in from each end; the layout then keeps the modules 0.50 m from the ridge, `ridgeClear`), the up-slope walkways
  stopping at its edge. The roof is reached on one side only (`access`). On a gable roof that is one end of the ridge
  walkway, left or right on plan (the roof page's `ทางขึ้นหลังคา (บันไดลิง)`, `Choice.accessRight`, drawing only, not
  in the digest): the team's top view (`reference/Roof access Topview.dxf`) as the block `TC_ROOF_ACCESS` on
  TC-PV-ACCESS (magenta) at the gable wall on the ridge, turned along the walkway: the cat ladder 0.60 m between its
  stiles, the cage R 0.30 m standing 0.90 m out with its brackets, and the landing grating 0.60 × 0.98 m on the roof,
  framed 0.05 m and cross-hatched, where the ridge walkway starts. Its tag, `ROOF ACCESS: CAT LADDER WITH CAGE +
  LANDING 0.60x1.00 (SEE TOP VIEW)` and `ONE SIDE ONLY (LEFT|RIGHT) - CONFIRM ON SITE`, sits past the plan's grid and
  dimension chains with a leader to the cage. Without a gable ridge walkway (hip or shed roofs, or a walkway every n
  columns) the lowest walkway of the face whose eave is at the plan's top starts at the eave instead, with a cat ladder
  0.45 m wide 0.75 m out on plan, rungs and an UP arrow; a ladder below the plan pushes its title and the section
  down. Open: whether the team keeps the eave ladder for hip roofs.
- **Tank mounting plan** (2026-10-22, after the team's `Mounting_plan.dxf`): with a layout, D1's DXF has a second
  plan to the right of the module plan: the tank plan again (outline, grid, hatched openings, span chains) with, per
  table, the rafters (50 mm members up the slope at every post pair, TC-PV-RAFTER, red), the four rails (TC-PV-RAIL,
  yellow) and the bracing between neighbouring posts on the front and back lines (TC-PV-BRACE, cyan), each on its own
  WIPEOUT; the team's footing block at every post (`TC_FOOTING_<mm>`: the footing square at `footing`, the base plate,
  the C post's flanges and the two 50 mm plates; TC-PV-FOOTING, green); a dimension chain along each table beyond its
  low edge (cantilever, bays, cantilever) and one across the post lines from wall to wall. No modules are drawn there.
- **Tank sections** (2026-10-22): D1's DXF also carries, under the plan and to scale in metres, sections 1–1 and 2–2
  (`TankDrawings.sectionCAD`, when the tank has a height), and with a layout the module rows' section
  (`tableSectionCAD`) and the longest table's front elevation (`tableFrontCAD`): the PDF's drawings, each with its zero
  at x = 0, on TC-TANK-SECTION / TC-TANK-SOIL / the PV layers by colour, their lengths, heights, spacings, post heights
  and bays as live DIMENSIONs.
- **Metres** (2026-10-22): the roof, tank and site plan DXFs are drawn in metres (1 unit = 1 m, `$INSUNITS` 6), so
  CAD's distance and list commands read metres and the dimensions read their length as it is (DIMLFAC 1, two
  decimals). `millimetres: true` (and the roof sheet's mm switch) still writes 1 unit = 1 mm; the golden files use it.
  The single line diagram stays in paper millimetres: it is an A3 sheet, not a real-world drawing.
- **Layer standard** (`TCRoofCore/CADLayers.swift`, 2026-10-22): every export takes its layers from one list, named
  `TC-<area>-<item>` (shared `TC-GRID`, `TC-DIM`, `TC-TEXT`, `TC-NORTH`, `TC-SECTION-MARK`, `TC-OBSTACLE`; then
  `TC-ROOF-*`, `TC-PV-*`, `TC-TANK-*`, `TC-SITE-*`, `TC-SLD-*`). Each layer has its colour, linetype (grid CENTER;
  beams, keep-out, cable and crane HIDDEN), lineweight, plot flag (the site picture frame and Defpoints don't plot) and
  a Thai / English description (XDATA `AcAecLayerStandard`, the layer manager's Description). `$LTSCALE` is the plot
  scale that fits the drawing on A3 (`SketchDXF.plotScale`), so CENTER and HIDDEN print with their paper-millimetre
  patterns; a sketch's own dash is divided by it. `$LWDISPLAY` is on. Open: map these onto the company's own layer
  list once its drawing is available as DXF.
- **Dimensions and hatches** (2026-10-22): the plans' span chains and totals (C1's plan, D1's square and round plans:
  `RoofPlan.Layout.dimensions`, `TankPlan.dimensions`) are DIMENSIONs (`SketchDXF.dimension`), one per span and one per
  total, in place of their lines and texts. Each draws as the sketch did (extension lines, 45° ticks, the text above
  the line) from an anonymous block `*D<n>`, in a style per text height (`TC_<height>`: DIMTSZ ticks, CORDIA text,
  DIMLFAC to metres, two decimals; `TC_<height>_Z` drops trailing zeros for labels like `4` or `1.5`), so CAD redraws it
  the same after an edit. The measured part of the label is written `<>`, so moving a point updates the number;
  `Ø <>` keeps its prefix, and any other label stays as written. The C1 section is drawn to scale for the DXF
  (`RoofSection(trueScale:)`, 2026-10-22: the ground at the clear height under the tie, or under the column top for a
  rafter frame; the page and the PDF keep the compact diagram), so its half spans, span, overhangs, clear height, rise
  and heel are DIMENSIONs too (`RoofSection.dimensions`). A `hatch` is one HATCH (ANSI31 at the sketch's spacing, inside the box), and an opaque
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
4. ~~Is the TIS-620 codepage enough?~~ Answered 2026-10-22: TIS-620 with the team's `cordia.shx` (width 0.85), above.
