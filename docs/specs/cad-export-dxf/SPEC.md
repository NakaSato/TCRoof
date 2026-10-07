# CAD export (DXF) — iPhone / iPad

Status: built for C1, the SLD and D1 (`SketchDXF`, `SingleLineDXF`, `TankDXF`). A2 is not built. Build steps: `CLAUDE_CODE_TASK.md` in this folder.

## Goal

Every drawing TCRoof already makes as a `Sketch` (C1 roof plan, SLD, D1 tank layout, A2 site plan) can be shared as a CAD file that opens in AutoCAD, BricsCAD, DraftSight, LibreCAD and similar programs. It must cost nothing and add no libraries.

## SDK options for iOS

| Option | DWG read | DWG write | DXF | Offline | Cost | Notes |
|---|---|---|---|---|---|---|
| **Own DXF writer (this spec)** | – | – | write R12 | yes | free | Already done for C1 in `TCRoofCore/RoofDXF.swift` |
| ODA File Converter (Mac/Windows desktop) | yes | yes | yes | yes | free | Converts DXF ↔ DWG in batches. Not an iOS library |
| Autodesk Platform Services (Viewer + Model Derivative) | view only | – | view | no | free tier, then usage-billed | Shown in a `WKWebView`; needs an Autodesk account |
| LibreDWG / libdxfrw / dxflib | partial | partial | yes | yes | free | **GPL**: cannot ship in a closed App Store app |
| ODA Drawings SDK (Teigha) | yes | yes | yes | yes | paid yearly membership | Native C++ for iOS; the only full DWG option on device |
| CAD Exchanger SDK, Apryse CAD module | yes | limited | yes | yes | paid | Built on ODA |

There is no official Autodesk SDK for iOS: RealDWG is desktop only (Windows/macOS).

Decision: **write DXF R12 ourselves.** If someone needs a `.dwg`, they open the DXF in their CAD program, or run it through ODA File Converter, and save it as DWG. Look at the ODA SDK only if the app must *open and edit* customers' DWG files.

## What already exists — `RoofDXF`

- DXF R12 (`$ACADVER AC1009`), CRLF line endings, `HEADER` + `TABLES` (LTYPE `CONTINUOUS`, LAYER) + `ENTITIES`.
- Entities: `LINE`, `CIRCLE`, `TEXT` (centred with group codes 72/73 when `mid`).
- Layers carry an AutoCAD colour index (`RoofDXF.colors`); sketch path tags (`RoofPlan.tags`) map to layers (`planLayers`, `pvLayers`).
- Units: `$INSUNITS` 4 (mm) or 6 (m); the drawing is 1:1 in real metres × `u`.
- Thai text: `$DWGCODEPAGE ANSI_874` and the bytes written as TIS-620 (`tis620`), with `·`, `×`, `°`, `Ø` swapped for CAD-safe text (`%%d`, `%%c`).
- Y is flipped: sketch Y points down, DXF Y points up (`tp` / `ts` transforms).
- UI: the ส่งออก CAD sheet in `RoofPageWide+Sheets.swift` (parts, units, then share the `.dxf` through AirDrop, Files or Mail).

Gaps in the current `write(_:)`: `textBox`, `hatch`, `photo` and `checkbox` are skipped, and dashes and stroke colours are dropped.

## Plan

### 1. `SketchDXF` in `TCRoofCore`

Move the generic parts of `RoofDXF` out into a shared writer:

```swift
public struct SketchDXF {
    public struct Layer { var name: String; var aci: Int; var linetype: String = "CONTINUOUS" }
    public init(units: Units = .millimetres, codepage: String = "ANSI_874")
    /// Adds a sketch: `tags[i]` picks the layer of `ops[i]`; `transform` maps sketch points to metres (Y up).
    public mutating func add(_ sketch: Sketch, tags: [String?], layers: [String: Layer],
                             transform: (Pt) -> (Double, Double), pointsPerMetre: Double, textHeight: Double)
    public mutating func text(_ layer: String, _ p: (Double, Double), height: Double, _ s: String, centred: Bool)
    public func data() -> Data   // R12, CRLF, TIS-620
}
```

`RoofDXF.build` then calls `SketchDXF`, and its output must stay byte-for-byte the same (a test compares the two).

### 2. DrawOp → DXF R12

| DrawOp | DXF |
|---|---|
| `line` | `LINE` |
| `polyline` | `POLYLINE` (70 = 0) + `VERTEX`… + `SEQEND`, or LINE segments as now |
| `polygon`, `rect` | `POLYLINE` closed (70 = 1) |
| `circle` | `CIRCLE` |
| `text` | `TEXT`; `angle` → group 50; `align` → 72 (0/1/2) with 11/21 alignment point |
| `textBox` | wrap into lines like the PDF renderer does, then one `TEXT` per line |
| `hatch` | the clipped hatch lines as `LINE`s (R12 has no `HATCH`) |
| `dash` ≠ [] | a `DASHED` LTYPE in `TABLES`, set on the entity (group 6) |
| stroke colour | layer colour by default; group 62 only when the op's colour differs from the layer |
| `photo`, `checkbox` | outline rectangle only (no bitmaps in CAD) |

Fills are not written (R12 `SOLID` only takes 3–4 points; not worth it).

### 3. Exports to add

1. **SLD (A3)**: layers by symbol kind (TX, BREAKER, CABLE, INVERTER, PV, METER, TEXT, FRAME). This one matters most: PEA permit packs ask for it.
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

D1 layers: `GRID 8, OUTLINE 7, DIM 3, OBSTACLE 1, NORTH 7, TEXT 7` from `TankPlan.tags`, and `PV 150` (panels switched
on) / `PV_GROUP 170` (table outlines, footing circles) from `TankLayout.current`. The layout is drawn from
`TankLayout`'s tank-metre data, not from a sketch (the page draws it in a SwiftUI `Canvas`). Cut columns are not written.

Not written by any export: fills (R12 has no fill short of `SOLID`), photos (an outline only), bold, line widths.

## Open questions

1. Does PEA (or PWA) accept DXF in the permit pack, or must it be DWG / PDF only?
2. SLD in real scale or paper scale (A3 sheet in mm, 1:1 with the PDF)? Paper scale is simpler for a schematic.
3. Should a title block (company, job, date, signer) be drawn into each DXF?
4. Is the TIS-620 codepage enough, or does any customer's CAD need a Unicode font (`\U+0E01` escapes, R2000+ format)?
