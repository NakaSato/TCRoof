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
  0.053–0.253 (dotted, P-CTRY-N, green), the HDG grating 0.30 × 2.40 × 0.03 m at 0.325–0.625 in panels with a
  0.03 inner frame, cross-hatched (ANSI37, P-WALK-N, red), with L-feet every 1.20 m from 0.63 m in at both its
  edges (magenta), the 3/4" PPR pipe at 0.656, the rail at 0.687–0.712 (solid, green) and the 6 mm wire-rope lifeline
  at 0.80 with supports every 2.40 m from 0.65 m in (P-LIFE-N, cyan); grating and tray on WIPEOUTs, with the
  band's width and a tag. Open: `Walkway_S1` draws the grating panels about 3.06 m long while its note says
  0.30 × 2.40; the app follows the note. The team's walkway detail sheet (`Walkway.dxf`: top view,
  elevations 1–3, detail 1) is no longer placed beside the drawing (2026-10-22, at the team's request); it stays
  converted in `Resources/walkway-detail.json` (`CADDetail.walkway`, `tools/cad-details/convert.py`) should it come
  back. Under the
  band, a cross rail (hat section 24 mm, P-RAIL-N, grey) at every L-foot. Down the middle (`walkwayCentre`) each
  face's walkway runs on past its top row to the ridge (`RoofWalkway.ridgeEnd`, or where a hip edge crosses the
  band), and on a roof with a ridge a walkway runs along it (`RoofWalkway.ridgeWalkway`: centred on the ridge, 0.50 m
  in from each end; the layout then keeps the modules 0.50 m from the ridge, `ridgeClear`), the up-slope walkways
  stopping at its edge. The roof is reached on one side only (`access`). On a gable roof that is one end of the ridge
  walkway, left or right on plan (the roof page's `ทางขึ้นหลังคา (บันไดลิง)`, `Choice.accessRight`, drawing only, not
  in the digest): the team's top view (`reference/Roof access Topview.dxf`) as the block `TC_ROOF_ACCESS` on
  P-LADD-N (magenta) at the gable wall on the ridge, turned along the walkway: the cat ladder 0.60 m between its
  stiles, the cage R 0.30 m standing 0.90 m out with its brackets, and the landing grating 0.60 × 0.98 m on the roof,
  framed 0.05 m and cross-hatched, where the ridge walkway starts. Its tag, `ROOF ACCESS: CAT LADDER WITH CAGE +
  LANDING 0.60x1.00 (SEE TOP VIEW)` and `ONE SIDE ONLY (LEFT|RIGHT) - CONFIRM ON SITE`, sits past the plan's grid and
  dimension chains with a leader to the cage. Without a gable ridge walkway (hip or shed roofs, or a walkway every n
  columns) the lowest walkway of the face whose eave is at the plan's top starts at the eave instead, with a cat ladder
  0.45 m wide 0.75 m out on plan, rungs and an UP arrow; a ladder below the plan pushes its title and the section
  down. The roof page's plan and the PDF draw the same walkways and way up, simplified (`RoofPlan.walkways`: the band,
  its grating and lifeline, the cage and landing or the eave ladder, `ทางขึ้นหลังคา`; tags `walkway` and `access`,
  which the CAD export leaves to its own drawing), under the face labels; a roof without walkways draws as before.
  Every module of the roof's CAD plan is the team's PV panel block (`TK_MODULE_PLAN`, `RoofDXF.modulePanel`), its long
  side along the module's, stretched to the module on plan, on its WIPEOUT; a roof file defines only that block of the
  tank components. The BOQ counts the walkways (`RoofWalkwayQuantities`, `RoofMount.walkwayLine`: length, HDG
  gratings, cross rails and their L-feet, lifeline and supports, cable tray and PPR, caged or eave ladders) on the roof
  page, in the PDF and in the Excel's row 39; the tank's BOM adds a base and two M12 bolts per footing and two side
  braces and a strut per post pair (`TableBOM`), on the tank page and in its BOQ line (one post per pair since the
  tank-roof frame, below). Open: whether the team keeps the eave
  ladder for hip roofs.
- **Tank mounting plan** (2026-10-22, after the team's `Mounting_plan.dxf`): with a layout, D1's DXF has a second
  plan to the right of the module plan: the tank plan again (outline, grid, hatched openings, span chains) with, per
  table, the rafters (50 mm members up the slope at every post pair, P-RAFT-N, red), the four rails (P-RAIL-N,
  yellow) and the X braces on the back line (P-BRAC-N, cyan; every other bay since the tank-roof frame), each on its own
  WIPEOUT; the team's footing block at every post (`TC_FOOTING_<mm>`: the footing square at `footing`, the base plate,
  the C post's flanges and the two 50 mm plates; P-FTNG-N, green); a dimension chain along each table beyond its
  low edge (cantilever, bays, cantilever) and one across the post lines from wall to wall. No modules are drawn there.
- **Tank mounting grid** (2026-10-22, `TankMountGrid`): the mounting plan carries the structure's own grid on G-GRID:
  a letter line on every post line across the slope (A, B the first row's front and back posts, then C, D …, ordered
  in the layout frame; lines closer than 50 mm share a letter) with a bubble past each wall, and per row a number line
  through every post pair (1, 2, 3 … from the frame's west end; a row's tables share a number where their pairs line
  up) from behind its back posts to past its low edge, with its bubble there. Each footing is tagged with its
  reference, letter and number (`B-3`, G-ANNO-TEXT). The rows' section carries the first two rows' letters under its
  posts and the front elevation the longest table's numbers, as bubbles under their lowest dimension, so a section
  reads against the plan.
  Beside the mounting plan, a footing schedule (G-ANNO-SCHD): a line per letter line with its footings' references
  (`A-1…A-14`), the footing size, what stands on it (the back post and its height, or the front line's V) and the
  count, and the total.
- **Roof structure drawing** (2026-10-22): the plan's words reach the DXF: the T1 marks on the trusses, the slope
  labels, `สันหลังคา`, obstacle labels and the purlin callout (`แป @1.00` with its ticks) on G-ANNO-TEXT, and the
  section mark's letters and arrows on G-ANNO-SYMB. Section A-A's member callouts ①–⑦ (bubble, number, leader and
  arrow) are on G-ANNO-SYMB with their numbers, which the DXF left out before. The table part is the member schedule
  the PDF prints (`RoofTruss.schedule`, `RoofDXF.memberSchedule`): per member row its size, pieces and length per
  truss and for the roof, kg/m, kg per truss and in all, the steel total, the summary and the notes, on G-ANNO-SCHD;
  under it details A (support) and B (ridge), not to scale, as the PDF draws them (`RoofTruss.details`). The PDF and
  the screen are unchanged (the plan's ops are the same; only their CAD tags were added).
- **Roof mounting grid** (2026-10-22, `RoofMountGrid`): the roof PV DXF carries the mounting's own grid on G-GRID, on
  each face in use: a lower-case letter on every line along the eave that carries L-feet (the rails along the purlins,
  or the purlins under rails up the slope), running on from face to face (a, b … then e, f … on the next face), with a
  bubble past both ends, and a number on every line up the slope through feet (1, 2, 3 … left to right on the plan),
  from past the eave to past its highest foot with its bubble beyond the eave. Every L-foot is tagged with its
  reference (`b-3`, G-ANNO-TEXT). Lower case keeps it apart from the building's grid (A, B … and 1, 2 …). The plan's
  title moves down past the bubbles beyond a bottom eave. The PDF keeps only the panel layout: no grid, no tags, no
  schedule. Open: whether the team names the mounting grid differently (for example R1, R2 for rails).
- **Tank sections** (2026-10-22; sections 1–1 and 2–2 taken out of the DXF 2026-10-27, with the plan's cut marks: the
  PDF keeps both): D1's DXF also carried, under the plan and to scale in metres, sections 1–1 and 2–2
  (`TankDrawings.sectionCAD`, when the tank has a height), and with a layout the module rows' section
  (`tableSectionCAD`) and the longest table's back post line elevation (`tableFrontCAD`): the PDF's drawings, each with its zero
  at x = 0, on S-TANK-SECT-E / C-TOPO-E / the PV layers by colour, their lengths, heights, spacings, post heights
  and bays as live DIMENSIONs.
- **Tank mounting components** (2026-10-22, after the team's `Tank mounting Section 1.dxf`, `Section 2.dxf` and
  `PV_Panel.dxf` in `reference/`): `tools/cad-details/components.py` takes the components out one by one, true size in
  metres with their base point at (0, 0), into `Resources/tank-components.json` (`TankComponents`): the module's side
  view with its two rail clamps (2280 mm, stretched along the slope to the layout's module), the R30 rail with its
  clamp and on its own, the post base side and front, the expansion bolt M12, the base plate on plan, the concrete
  topping 300 × 150 (its AR-CONC hatch kept with the source's line families), the topping on plan, DETAIL 1 (topping,
  base, bolt, post and brace stubs) and the PV panel on plan (cells and busbars). Each is one block `TK_…` on its PV
  layer (BYBLOCK inside, so the INSERT's layer colours it; coordinates to a micrometre), so a component is edited once
  for every place it is used. The tank DXF puts them together: the rows' section (topping, side base and M12 at every
  post, the posts, the rafter along the tilt over the post tops, 0.82 m past the low post and 0.28 m past the high one
  (4.00 m) but kept inside the modules, the braces to the rafter 0.565 m from the low post and 1.40 m from the high
  post and the outer strut from the low post's foot to the rafter 0.60 m past it, all measured on section 1, the two
  modules with their clamps on the rafter), the front elevation (topping and
  front base at every post, the posts, X bracing in every bay), the footing block on the mounting plan (the footing
  square with `TK_BASE_PLAN` inside), every module on the plan (`TK_MODULE_PLAN` on its WIPEOUT, stretched to the
  module) and, under the sections at 1:10, DETAIL CONCRETE TOPPING and DETAIL 1 with their dimensions and labels.
  Posts, rafters and braces are closed polylines (50, 75 and 45 mm), stretched by their grips. The PDF keeps its own
  drawings. Run the tool again when a reference drawing changes.
- **Tank-roof frame** (2026-10-27, after the team's tank-roof drawings `Top.dxf`, `Back_Side.dxf` and `Side_View.dxf`
  of a 40 × 26 m tank with 240 modules, in `reference/tank-roof/`: their blocks as `tcroof-tank-mount-blocks.dxf`,
  SVGs, the catalog, the layout as JSON with its BOQ and the extraction scripts): the frame follows their drawing,
  in the DXF, the PDF, the B1-C3 sheet and the BOQ. Per post pair one vertical post on the back (high) line; on the
  front (low) line no post, one foot (AG5-B03) carrying a V of two struts to the rafter (`TankComponents.frame`: the
  inner leg 0.565 m up the rafter from the front line, the outer leg 0.60 m down it, the back diagonal 1.40 m down
  from the post). X braces only on the back line, in every other bay and the last (`TankLayout.bracedBays`: 8 bays
  give 1, 3, 5, 7, 8; their drawing's 30 sets), between 0.376 m above the slab and 0.108 m under the post's top;
  on the mounting plan each X is the team's pair of 40 mm members 152 mm apart either side of the line. The
  elevation under the sections is the back post line's (`รูปด้านแนวเสาหลัง`: back posts, the braced bays, the modules
  behind as dashed hidden outlines); the footing schedule says what stands on each line (`เสา 2.00 ม.` or
  `ขาค้ำ V`). BOQ: `เสา` = post pairs (back posts only), `ฐานราก` and `ฐานเสา` = 2 per pair, M12 2 per base,
  `ค้ำโครงข้าง` 2 and `ค้ำยื่น` 1 per pair, `ค้ำ X` = braced bays. The heights stay the standard's (`hFront` is the
  rafter's height over the front line). Their drawing's own conflicts (rafter drawn 4000 on plan too, schematic rail
  heights in the back view, unlabelled member sections) are listed in its README and layout JSON. Open: the member
  sections (post, strut, rafter, brace) are named nowhere in their drawings.
- **Tank plan module** (2026-10-27, after the team's `reference/PV_570W.dxf`: a frame on a WIPEOUT, 2.19911 × 1.134 m,
  the slope along x): every module on D1's plan is one INSERT of one block named for its power, `PV_570W`
  (`TankDXF.moduleBlock`), written to a micrometre, in place of the per-size blocks with the cells drawing inside. Its
  frame is the layout's module projected on plan: `moduleL` × cos(tilt) by `moduleW` (`Params.cellH` × `cellW`), so
  at the team's 15° the ZXM7 570 W (2278 × 1134 mm) gives 2.20038 × 1.134; their block's 2.19911 is 1.3 mm shorter
  (their drawing's own 2199, from a module 2276.7 mm long or a tilt of 15.12°). Where the slope runs up the plan the
  INSERT is turned 90° at the panel's lower-right corner; a panel of any other size keeps a frame block of its own.
  The C1 roof export keeps its `TC_PV_MODULE_…` blocks with the cells.
- **Inverter station** (2026-10-27, after the team's `reference/inverter-station`: `Inverter.dxf` one 125 kW inverter
  under a 6.0 × 2.5 m shelter, `Inverter_EXL-HV.dxf` 125 + 40 kW under 9.0 × 2.5 m, `Internal_Inverter_Station_EXL-LV.dxf`
  an 80 kW rack on a building's wall, `Part_1.dxf` the column's base plate, and the component library extracted from
  them in `components/cad`): B2's `ส่งออก DXF` (`InverterStationDXF`) draws the section's station at real scale in
  metres. TOP VIEW on the B2 page's own positions (`InverterStationDrawing`: the rack band 0.17 m off the back line, the
  row in front of it, the door by column 1 on line A): outdoors the columns 1, 2 … on lines A (front, door) and B
  (back) with bubbles, each the library's 150 plate with its 75 tube; indoors the existing wall (hatched) and the
  measured area; the rack with its posts (no span over 1.40 m, as the team's), the AC tray (`TCR_TRAY_PLAN_COVER_W…`),
  the inverters' top views (MAX 125 / 80 blocks), the chains of spans, width, row and walkway. FRONT VIEW under it on
  the same x: the columns of line A, the edge beam, the rafters' ends, the purlin and sheet, a T8 LED lamp on each
  inside column line; the rack on its 200×100 concrete footings and 200×10 plates, the top rail at 2.00 m, the AC tray
  at 0.50 m and the DC tray at 0.90 m (the library's side modules, 1.0 m), each cabinet topped at 2.00 m and each
  inverter at 2.10 m (the team's station templates: AC-DB 0.598, meter 1.248, inverter 1.461, DC-DB 0.998 for 1.40 /
  0.75 / 0.635 / 1.00 m tall), the library's front blocks stretched to the equipment catalog's sizes, the ladder
  (`TCR_LADDER_PLAN_W…`, 1.2 m modules) up from AC-DB-01 and a DC tray up from each DC-DB, labelled over the roof.
  SIDE VIEW right of it, seen from the right end: the posts 3.00 m at A and 2.75 m at B (the measured height ส for the
  front when there is one), the edge beams' sections, the tie beam, the rafter 0.40 m past A and 0.55 m past B, its
  purlins about 1 m apart and the sheet; the rack's section with its arms, the trays' sections (`TCR_TRAY_SECTION_…`),
  the equipment from the generic side blocks drawn far end first so nearer items hide farther ones; indoors the wall.
  The scale figure stands in both views. Right of the plan the equipment schedule (model, W × H × D, the levels), the
  notes (including a short area and a narrow walkway) and the base plate DETAIL at 5 : 1 with its sizes in mm.
  The shelter's members are marked (2026-10-27): a mark in a circle with a leader, in the front view C1 column, B1
  edge beam, R1 rafter, P1 purlin, in the side view C1, B1, TB tie beam, R1, P1, and right of the base plate detail
  `ตารางชิ้นส่วนโครงสร้าง / MEMBER SCHEDULE` (`InverterStationDXF.members`): mark, member, size, count and length
  together centre to centre (columns from their base plates; the rafter along its slope, 0.40 m past A and 0.55 m past
  B; the purlins over the length and both 0.50 m overhangs), the column `□75×75×2.4 (รอยืนยัน)` and the rest at the
  depth drawn, `ตามแบบ`, until the team names the sections. A station on a wall has none.
  Layers: `S-COLS-N`, `S-BEAM-N`, `S-ROOF-PURL-N`, `A-ROOF-N`, `S-FRAM-N` (rack), `S-FTNG-N`, `E-EQPM-N`, `E-CTRY-N`,
  `E-LITE-N`, `A-DOOR-N`, `A-WALL-E` (hatched), `A-AREA-E`, ground `C-TOPO-E`. A size the library lacks (a tray over
  300 or a ladder over 600 mm wide) is drawn by the file itself. Open: the column size (the library's tube is 75×75×2.4
  on a 150 plate, its layer says 100×100×3, and the elevations' plate is 200 wide); the catalog's AC-DB (900 × 1200 for
  up to 2 inverters) against the team's 900 × 1400, the meter 630 × 800 against 630 × 750, the MAX 80 870 × 580
  against the block's 860 × 628, the 40 kW 580 × 435 against 580 × 600; the beams', rafters' and purlins' sections.
- **Tank roof beam plan** (2026-10-27, after the team's `reference/Tank_Truss.dxf` / `.dwg`: a 40 × 24 m tank on a
  4.00 m grid, B1 0.20 m on the perimeter wall line and B2 0.20 m on every interior line, a mark per span, 4.00 chains
  and the 40.00 / 24.00 overall): D1's DXF draws it for any rectangular tank from its own spans (`TankFraming`), right
  of the other plans with grid line A level with the module plan's: the B1 outer edge as one closed polyline and every
  other beam edge between the faces of the beams crossing it, so the junctions read clean (the reference drew each
  beam as a full-length rectangle, crossing every other one, and several twice); a B1 / B2 mark on every span beside
  its beam towards the inside and along it; the grid's centre lines with a bubble at both ends (1, 2, 3 … and A, B, C …,
  as the module plan names them); the span chains and the overall sizes on top and on the left as DIMENSIONs; the title
  `แปลนคานหลังคาถัง / ROOF BEAM PLAN` with the width and the note; and to its right `ตารางคาน / BEAM SCHEDULE` (mark,
  location, width × depth `0.20 × ตามแบบ`, spans, length centre to centre, the total) with three notes. Layers: the
  beams S-BEAM-E (existing, continuous lines as the team draws them; the module plan keeps S-TANK-BEAM-E hidden), marks G-ANNO-TEXT, grid G-GRID, chains G-ANNO-DIMS, the
  schedule G-ANNO-SCHD. A round tank (ring beams) has none. The module plan's beams (`TankPlan.beam`) are 0.20 m too.
  Open: the beams' depth and whether some tanks carry a third mark (a deeper beam on a column line).
- **Metres** (2026-10-22): the roof, tank and site plan DXFs are drawn in metres (1 unit = 1 m, `$INSUNITS` 6), so
  CAD's distance and list commands read metres and the dimensions read their length as it is (DIMLFAC 1, two
  decimals). `millimetres: true` (and the roof sheet's mm switch) still writes 1 unit = 1 mm; the golden files use it.
  The single line diagram stays in paper millimetres: it is an A3 sheet, not a real-world drawing.
- **Layer standard** (`TCRoofCore/CADLayers.swift`, 2026-10-22, after `AutoCAD_Layer_Management_Best_Practices.md`):
  every export takes its layers from one list in the US National CAD Standard's format (AIA CAD Layer Guidelines):
  `Discipline-Major[-Minor]-Status`, the discipline one letter (`G` general, `A` architectural, `S` structural, `E`
  electrical, `C` civil), four-letter groups, and the status last: `E` existing (roof, tank, what the survey found),
  `N` new (what we install), `T` temporary (crane access). So a layer filter `*-N` shows everything we build and `S-*`
  the structure. The groups: `G-GRID`, `G-ANNO-DIMS | TEXT | NRTH | SYMB | SCHD | MEAS`, `G-ANNO-NPLT` (the only
  non-plot layer, named so), `G-DETL`; the existing roof `S-ROOF-OTLN | RIDG | FRAM | PURL | SECT-E`, `S-COLS-E`,
  `A-ROOF-SKYL-E`, `A-OPNG-E`; new PV `P-MODL-N`, `P-MODL-KEEP-N`, `P-CTRY-N`, `P-RAIL-N`, `P-RAIL-CUTS-N`, `P-FOOT-N`,
  `P-TABL-N`, `P-RAFT-N`, `P-BRAC-N`, `P-FTNG-N`, `P-WALK-N` (`-RAIL-N`, `-FOOT-N`), `P-LIFE-N` (`-RAIL-N`, `-SUPT-N`),
  `P-LADD-N`; the existing tank `S-TANK-OTLN | BEAM | SECT-E` (and the roof beam plan's continuous `S-BEAM-E`), `C-TOPO-E`; the inverter station `S-COLS | BEAM | FRAM | FTNG-N`, `S-ROOF-PURL-N`, `A-ROOF | DOOR-N`, `E-EQPM | CTRY | LITE-N`, `A-WALL-E`, `A-AREA-E`; the site `A-BLDG-E`, `P-AREA-N`,
  `P-AREA-DRAW-N`, `E-CABL-N`, `E-EQPM-E`, `C-ACCS-T`, `C-SHAD-E`, `C-BNDY-E`; the single line diagram `E-SLDG-E | N`,
  `E-SLDG-OKAY | WARN | MISS | ASSM | TEXT | OTHR`, `E-SLDG-POLE-E`. Every object is ByLayer (no colour on an entity):
  a part drawn in another colour has its own layer, and a single line text whose colour means something goes on that
  meaning's `TEXT` layer (`E-SLDG-MISS-TEXT`, `CADLayers.annotation(of:)`). Every hatch goes on its layer's `HATC`
  minor group (`P-FTNG-HATC-N`, `CADLayers.hatch(of:)`, 0.13 mm), placed by `SketchDXF` itself, so hatches freeze
  apart from the lines they fill. Layer 0 holds only block contents (BYBLOCK, so a block takes its INSERT's layer) and
  Defpoints only what AutoCAD puts there. Each layer has its colour, linetype (grid CENTER; beams, keep-out, cable and
  crane HIDDEN), lineweight and a Thai / English description (XDATA `AcAecLayerStandard`, the layer manager's
  Description). `$LTSCALE` is the plot scale that fits the drawing on A3 (`SketchDXF.plotScale`), so CENTER and HIDDEN
  print with their paper-millimetre patterns (model-space plotting; no viewports); `$LWDISPLAY` is on.
  `CADLayers.standardsFile()` writes every layer (with its hatch and text layers), a sample line and description on
  each and the old `TC-` names' map: open it in AutoCAD and save it as a `.dws` for CHECKSTANDARDS and LAYTRANS (older
  drawings' `TC-…` layers map one to one, `CADLayers.legacy`), or as the `.dwt` new drawings start from. Open: whether
  the office uses CTB or STB plot styles (the layers carry lineweights, which suits both), and its own discipline
  codes if they differ.
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
