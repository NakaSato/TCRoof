# Auto 2D Drawings: Swift Implementation Spec

**Companion to:** [`auto-drawing.md`](auto-drawing.md), which covers the design, drawing standard and prototype images.
**Package:** `SolarSurveyKit` (targets `SurveyCore`, `SurveyUI`, `PDFReport`).
**Swift:** 5.9 tools, iOS 17 / macOS 14 (as in `Package.swift`). No new dependencies.
**Reference output:** `docs/specs/img/*.png`, rendered by the Python prototypes in the same folder. The Swift output
should match them. The same inputs must give the same geometry, down to the numbers in the tests (§10).

---

## 0. Preconditions

1. **Branch base.** Build on the `main` that contains this morning's Mac commits (`30b3253 … 904728d`). This spec
   uses `NumberInput` from `SurveyCore/Validation.swift`, and those commits are not on GitHub yet. Push them first,
   then branch `feature/auto-drawings` from that `main`.
2. **Principle.** The surveyor enters **only sizes and distances**. Every other value is derived (§4) or assumed.
   Assumed values are listed in `assumed` and printed under the drawing.
3. **Units.** Geometry works in **metres, y-up**. `Sketch` works in **points, y-down**. The layout step (§6) is the
   only place that converts between the two.

---

## 1. Files

```
SolarSurveyKit/Sources/SurveyCore/Drawing/
  Spans.swift              span lists incl. "16@4", cumulative positions
  MemberSpec.swift         member size/spacing parsing
  DrawingSettings.swift    defaults & assumptions (setbacks, sizes, m²/kWp)
  RoofInput.swift          Values → RoofInput (derivation, missing, assumed)
  RoofGeometry.swift       section + truss geometry, schedule
  TankInput.swift          Values → TankInput (openings, setting)
  TankGeometry.swift       outline, resolved openings, usable area
  DrawingKit.swift         layout transform, dimension chains, tags, callouts, legend, notes
  RoofDrawings.swift       section, framing plan, truss details, schedule table
  TankDrawings.swift       roof plan (กปภ. style), section, summary
SolarSurveyKit/Sources/SurveyUI/
  DrawingField.swift       .roofSection / .tankDrawing field views, tap-to-place vents
SolarSurveyKit/Tests/SurveyCoreTests/
  SpansTests.swift, MemberSpecTests.swift, RoofTests.swift, TankTests.swift, DrawingSnapshotTests.swift
  Fixtures/drawings/*.svg
```

The following existing files change: `Models.swift` (`Obstacle`), `Schema.swift`, `Progress.swift` (`parseSpans`),
`Validation.swift` (`missingGroups`), `WebBackup.swift`, `Fields.swift`, `ReportLayout.swift` and `SurveyModel.swift`
(`SurveySettings`).

---

## 2. Spans (`Spans.swift`)

Adds the `n@d` shorthand used on กปภ. sheets ("16@4" means sixteen bays of 4 m). The existing `parseSpans` keeps its
signature and delegates to this, so current callers (`Drawings.plan`, `facts`) pick up the shorthand for free.

```swift
public enum Spans {
    /// "1.5,4,4", "16@4", "1.5, 3@4, 1.5", "4ม., ๔" → metres. Non-positive values are dropped.
    public static func parse(_ s: String) -> [Double] {
        var out: [Double] = []
        for token in s.split(whereSeparator: { ",/ \t\n".contains($0) }) {
            let t = String(token)
            if let at = t.firstIndex(of: "@"),
               let n = Int(NumberInput.clean(String(t[..<at]))), n > 0, n <= 500,
               let d = NumberInput.value(String(t[t.index(after: at)...])), d > 0 {
                out += Array(repeating: d, count: n)
            } else if let d = NumberInput.value(t), d > 0 {
                out.append(d)
            }
        }
        return out
    }

    /// [4, 4, 4] → [0, 4, 8, 12]
    public static func edges(_ spans: [Double]) -> [Double] {
        spans.reduce(into: [0.0]) { $0.append($0.last! + $1) }
    }

    /// Compact label for a chain: "16 @ 4.00 = 64.00" when all equal, else nil.
    public static func uniformLabel(_ spans: [Double]) -> String? {
        guard let f = spans.first, spans.count > 1, spans.allSatisfy({ abs($0 - f) < 1e-9 }) else { return nil }
        return "\(spans.count) @ \(String(format: "%.2f", f)) = \(String(format: "%.2f", f * Double(spans.count)))"
    }
}

// Progress.swift
public func parseSpans(_ s: String) -> [Double] { Spans.parse(s) }
```

The **`@` token must be tested before the plain number**. Otherwise `NumberInput.clean("16@4")` returns `"164"`.

---

## 3. Members (`MemberSpec.swift`)

```swift
public enum RoofComponent: Int, CaseIterable, Sendable, Codable {
    // 1–7 keep the numbering of Drawings.truss() and the C1 comp1…7 fields
    case purlin = 1, rafter, wallPlate, tieBeam, strut, fascia, kingPost
    // truss members (C1 compTop…compDiagonal)
    case topChord = 20, bottomChord, vertical, diagonal

    public var thai: String {
        switch self {
        case .purlin: "แป"; case .rafter: "จันทัน"; case .wallPlate: "อเส"; case .tieBeam: "ขื่อ"
        case .strut: "ค้ำยัน"; case .fascia: "เชิงชาย"; case .kingPost: "ดั้ง"
        case .topChord: "ขื่อบน"; case .bottomChord: "ขื่อล่าง"; case .vertical: "ตัวตั้ง"; case .diagonal: "ตัวทแยง"
        }
    }
}

public struct MemberSpec: Hashable, Sendable {
    public var label: String      // size as entered, without the spacing part
    public var depth: Double?     // m
    public var spacing: Double?   // m
    public var isAbsent: Bool     // "-"

    public enum Unit: Sendable { case millimetre, centimetre }   // C1 lists are mm, C2 lists are cm

    public static func parse(_ raw: String, unit: Unit = .millimetre, spacingCm: String? = nil) -> MemberSpec?
}
```

`parse` rules (identical to the design spec §5.3):

| Input (after `StructureSizes.split`) | depth |
|---|---|
| empty | returns `nil` (not entered) |
| `-` | `isAbsent = true` |
| prefix `C`, `2C`, `□`, `H`, `I`, `L`, `Ø` | first number × 0.001 (mm) or × 0.01 (cm) |
| contains `"` (wood, inches) | largest number × 0.0254 |
| prefix `ค.ส.ล` | largest number. If it is < 5 it is metres, otherwise cm × 0.01 |
| wood in cm (`ไม้ 5x15`) | largest number × 0.01 |

- Spacing comes from the `@x.xxM` part, or from `spacingCm` (C2 `space{n}`) × 0.01.
- Spacing is kept only if it is in `0.2…12` m.
- The regex to use is `#"(\d+(?:\.\d+)?)"#` over the size part. Never parse the spacing part for depth.

---

## 4. Roof input (`RoofInput.swift`)

```swift
public enum RoofShape: Sendable { case gable, hip, shed, flat, curved }

public enum TrussPattern: Sendable { case howe, pratt, warren, verticalsOnly }

public enum RoofFrame: Sendable, Equatable {
    case rafter                      // จันทัน + ขื่อ + ดั้ง + ค้ำยัน
    case truss(TrussPattern)
}

public struct RoofInput: Sendable {
    public var title: String
    public var shape: RoofShape
    public var frame: RoofFrame
    public var across: [Double]              // bays ⟂ ridge (section direction), m
    public var along: [Double]               // bays ∥ ridge, m
    public var eaveHeight: Double?           // ground → underside at support
    public var rise: Double                  // top chord rise, m (> 0 unless flat)
    public var heel: Double                  // truss depth at support, m
    public var overhang: Double
    public var members: [RoofComponent: MemberSpec]
    public var missing: [String]             // non-empty ⇒ no drawing
    public var assumed: [String]             // printed as "ค่าสมมติ: …"
    public var warnings: [String]            // printed in red under the drawing

    public var span: Double { across.reduce(0, +) }
    public var half: Double { shape == .shed ? span : span / 2 }
    public var pitch: Double { atan2(rise, half) }            // radians
    public var slopeLength: Double { half / cos(pitch) }
    public var purlinSpacing: Double { members[.purlin]?.spacing ?? DrawingSettings.current.purlinSpacing }

    public static func from(_ m: SurveyModule) -> RoofInput?  // .roof, .roofForm, .house; nil otherwise
}
```

### 4.1 Derivation (`from`)

```swift
public static func from(_ m: SurveyModule) -> RoofInput? {
    guard [.roof, .roofForm, .house].contains(m.type) else { return nil }
    let v = m.values, S = DrawingSettings.current
    var missing: [String] = [], assumed: [String] = [], warnings: [String] = []
    func num(_ id: String) -> Double? { v.number(id) }                 // NumberInput-backed (Models.swift)

    // spans
    var across: [Double], along: [Double]
    switch m.type {
    case .roof:
        let sx = Spans.parse(v.text("spansX")), sy = Spans.parse(v.text("spansY"))
        // sheets run down the slope → ridge ⟂ sheetDir; else ridge along the longer side
        let ridgeAlongX: Bool = switch v.choice("sheetDir") {
            case "แนวตั้ง"?: true             // sheets vertical in plan → slope along Y → ridge along X
            case "แนวนอน"?: false
            default: sx.reduce(0, +) >= sy.reduce(0, +)
        }
        (across, along) = ridgeAlongX ? (sy, sx) : (sx, sy)
        if v.choice("sheetDir") == nil { assumed.append("แนวสันหลังคาตามด้านยาว") }
    default:
        across = num("buildingWidth").map { [$0 / 100] } ?? []
        along  = num("buildingLength").map { [$0 / 100] } ?? []
    }
    if across.isEmpty { missing.append(m.type == .roof ? "ระยะช่วงเสา" : "ความกว้างอาคาร") }

    // heights → rise
    let heel = num("heelDepth") ?? 0
    if num("heelDepth") == nil, m.type == .roof { assumed.append("ความลึกโครงถักที่เสา 0 ม.") }
    var eave: Double?, ridge: Double?
    if m.type == .house { eave = num("measI2").map { $0 / 100 }; ridge = num("measI1").map { $0 / 100 } }
    else { eave = num("eaveHeight"); ridge = num("ridgeHeight") }
    var rise: Double? = (eave != nil && ridge != nil) ? ridge! - eave! - heel : nil
    if rise == nil, m.type == .house, let deg = num("roofAngle"), !across.isEmpty {
        rise = tan(deg * .pi / 180) * across.reduce(0, +) / 2
        assumed.append("ความสูงสันจากมุม \(fmt(deg))°")
    }
    if eave == nil { missing.append("ความสูงชายคา") }
    if ridge == nil && rise == nil { missing.append("ความสูงสันหลังคา") }
    if let r = rise, r <= 0, (eave ?? 0) > 0 { missing.append("ความสูงสันหลังคา (ต้องมากกว่าชายคา)") }

    // shape
    var shape: RoofShape = switch v.choice("roofShape") {
        case "หลังคาทรงปั้นหยา"?: .hip; case "หลังคาเพิงหมาแหงน"?: .shed
        case "หลังคาคอนกรีต (ดาดฟ้า)"?: .flat; case "หลังคาทรงโค้ง"?: .curved; default: .gable
    }
    if let r = rise, r < 0.05 { shape = .flat }

    // members (C1 mm lists; C2 cm lists with separate spacing)
    var members: [RoofComponent: MemberSpec] = [:]
    for c in RoofComponent.allCases where c.rawValue <= 7 {
        let spec: MemberSpec? = m.type == .roofForm
            ? MemberSpec.parse(v.text("size\(c.rawValue)"), unit: .centimetre, spacingCm: v.text("space\(c.rawValue)"))
            : MemberSpec.parse(v.text("comp\(c.rawValue)"))
        if let spec { members[c] = spec }
    }
    let trussFields: [(RoofComponent, String, RoofComponent)] = [
        (.topChord, "compTop", .rafter), (.bottomChord, "compBottom", .tieBeam),
        (.vertical, "compVertical", .kingPost), (.diagonal, "compDiagonal", .strut)]
    for (c, id, fallback) in trussFields {
        if let s = MemberSpec.parse(v.text(id)) { members[c] = s }
        else if let f = members[fallback] { members[c] = f }
    }

    // frame
    let has = { (c: RoofComponent) in members[c].map { !$0.isAbsent } ?? false }
    let explicitWeb = MemberSpec.parse(v.text("compVertical")) != nil || MemberSpec.parse(v.text("compDiagonal")) != nil
    let frame: RoofFrame
    if has(.bottomChord) && explicitWeb {
        frame = has(.vertical) && has(.diagonal) ? .truss(.howe)
              : has(.diagonal) ? .truss(.warren) : .truss(.verticalsOnly)
        if case .truss(.verticalsOnly) = frame { warnings.append("ไม่ได้ระบุตัวทแยง") }
    } else { frame = .rafter }

    // checks on derived pitch (not errors)
    if let r = rise, !across.isEmpty, shape != .flat {
        let deg = atan2(r, shape == .shed ? across.reduce(0, +) : across.reduce(0, +) / 2) * 180 / .pi
        if deg > 45 || deg < 3 { warnings.append("ตรวจความสูงอีกครั้ง (มุม ≈ \(fmt(deg, digits: 1))°)") }
    }
    if num("overhang") == nil { assumed.append("ชายคายื่น 0 ม.") }

    return RoofInput(title: m.title, shape: shape, frame: frame, across: across, along: along,
                     eaveHeight: eave, rise: max(rise ?? 0, 0), heel: heel, overhang: num("overhang") ?? 0,
                     members: members, missing: missing, assumed: assumed, warnings: warnings)
}
```

The truss is chosen only when the surveyor has entered a **web member explicitly**. The fallbacks from ดั้ง
and ค้ำยัน don't count. Without that rule, every existing C1 job with a king post would turn into a truss.

---

## 5. Roof geometry (`RoofGeometry.swift`)

```swift
public struct Segment: Hashable, Sendable { public var a, b: Pt; public var role: RoofComponent }
public struct PurlinMark: Hashable, Sendable { public var at: Pt; public var slope: Double; public var side: Int } // side −1/+1

public struct RoofGeometry: Sendable {
    public var input: RoofInput
    public var topLine: [Pt]            // underside of sheet, incl. overhangs (m, y-up)
    public var segments: [Segment]      // chords, web, rafters, tie, king post, struts, fascia, columns
    public var nodes: [Pt]              // gusset points (truss only)
    public var purlins: [PurlinMark]
    public var panelsPerHalf: Int
    public var supports: [Double]       // x of columns
    public static func section(_ i: RoofInput) -> RoofGeometry?     // nil if !i.missing.isEmpty
}
```

### 5.1 Common

```swift
let B = i.span, h = i.half, E = i.eaveHeight ?? 0, d = i.heel, R = i.rise, θ = i.pitch
func top(_ x: Double) -> Double {                    // top chord / rafter line
    switch i.shape {
    case .shed: return E + d + x * tan(θ)
    case .flat: return E + d
    default:    return E + d + (x <= h ? x : B - x) * tan(θ)
    }
}
```

- Overhang points: `(-o·cosθ, E+d-o·sinθ)` and `(B+o·cosθ, E+d-o·sinθ)`.
- Fascia: a segment of 0.22 m straight down from each tip.
- Columns (`role: .kingPost` is **not** used for these): segments `(x,0)→(x,E)`, at `supports = [0, B]` for a truss.
  For a rafter frame they sit at every `Spans.edges(across)` (open question Q1 in the design spec).
- `topLine` is the sheet line: offset the top chord outward by `0.18 m` (drawn, not structural).

### 5.2 Purlins

```swift
let s = i.purlinSpacing, L = i.slopeLength
var ts = stride(from: 0.0, through: L + 1e-9, by: s).map { $0 }
if L - (ts.last ?? 0) > 0.25 * s { ts.append(L) }
// gable/hip/curved: mirror on both halves. The ridge gets a pair (one purlin per side, as in detail B); shed: one side
```

For a **truss**, the purlins are placed at the top-chord nodes instead (§5.3), so they coincide with gussets.

### 5.3 Truss

```swift
let n = max(2, Int((L / s).rounded()))              // panels per half → purlins on nodes
let xs = (0...n).map { Double($0) * h / Double(n) }  // one half; mirror with B − x
```

Per half, with `X = xs` (left) or `X = xs.map { B - $0 }` (right):

| Part | Segments |
|---|---|
| Bottom chord | `(X[i],E)→(X[i+1],E)` for i in 0..<n |
| Top chord | `(X[i],top(X[i]))→(X[i+1],top(X[i+1]))` |
| Verticals | `(X[i],E)→(X[i],top(X[i]))` for i in 0...n. Skip i == 0 when `d == 0`, skip i == n on the right half (king post once), and draw only i == n for `.warren` |
| Diagonals `.howe` | `(X[i],E)→(X[i+1],top(X[i+1]))` |
| Diagonals `.pratt` | `(X[i],top(X[i]))→(X[i+1],E)`. Skip i == 0 when `d == 0` |
| Diagonals `.warren` | alternate: even i `(X[i],E)→(X[i+1],top)`, odd i `(X[i],top)→(X[i+1],E)` |

- `nodes` = the endpoints of every vertical and diagonal, plus the two supports `(0,E)` and `(B,E)`, plus the
  top-chord node points. Deduplicate them by rounding to 1 mm.
- Purlins sit at every top-chord node, with the ridge counted once per side.

### 5.4 Schedule

```swift
public struct ScheduleRow: Sendable { public var tag: Int; public var role: RoofComponent; public var size: String
                                      public var count: Int?; public var length: Double?; public var spacing: Double? }
public extension RoofGeometry { var schedule: [ScheduleRow] }
```

The rows are, per truss:
- purlins: `2(n+1)` (gable/hip) or `n+1` (shed)
- top chord: `2(L+o)`
- bottom chord: `B`
- verticals: count and Σ length
- diagonals: count and Σ length
- fascia: 1 m per metre run, shown per metre
- king post: `d+R`
- gussets: `nodes.count`

A rafter frame lists purlin, rafter, tie beam, king post and struts instead.

---

## 6. Drawing kit (`DrawingKit.swift`)

Everything that turns metres into `DrawOp`s lives here, so the roof and tank drawings share one look.

```swift
/// Metres (y-up or y-down) → points. `flipY` for elevations/sections, not for plans.
public struct DrawingTransform: Sendable {
    public var ox, oy, k: Double          // origin (pt) and scale (pt per m)
    public var flipY: Bool
    public var baseY: Double              // for flipY: point y of metre 0
    public func p(_ x: Double, _ y: Double) -> Pt { Pt(ox + x * k, flipY ? baseY - y * k : oy + y * k) }
    public func metres(_ pt: Pt) -> (x: Double, y: Double) { ((pt.x - ox) / k, flipY ? (baseY - pt.y) / k : (pt.y - oy) / k) }
    /// Fit a metre box into a point box, equal scale, centred.
    public static func fit(width: Double, height: Double, into box: Box, flipY: Bool) -> DrawingTransform
}

public enum DrawingKit {
    public static let dashDot: [Double] = [10, 3, 2, 3], beamDash: [Double] = [5, 3]
    static func titleStrip(_ title: String, _ sub: String, width W: Double) -> [DrawOp]
    static func chainH(_ edges: [Double], t: DrawingTransform, y: Double, labels: [String], total: String?) -> [DrawOp]
    static func chainV(_ edges: [Double], t: DrawingTransform, x: Double, labels: [String], total: String?) -> [DrawOp]
    static func dimV(_ y0: Double, _ y1: Double, x: Double, label: String, side: Double) -> [DrawOp]
    static func tag(_ n: Int, at: Pt, lead: Pt) -> [DrawOp]                 // square tag, TAG colour
    static func callout(_ text: String, from: Pt, to: Pt) -> [DrawOp]        // leader + text
    static func detailBubble(_ letter: String, at: Pt, r: Double) -> [DrawOp]
    static func notes(assumed: [String], warnings: [String], width W: Double, y: Double) -> ([DrawOp], Double)
    static let disclaimer = "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง"
}
```

Rules:
- **Text widths** come from `ApproxText.width`, so layout is identical on Linux tests and on device. Tags that
  would overlap move along their leader direction in 6 pt steps, at most 8 tries.
- **Glyphs:** Sarabun has no `□ ▽ ≈ →`. PDF and iPad fall back to a system font, but keep labels to characters
  Sarabun has where you can: write "ประมาณ", not "≈".
- Every drawing ends with `notes(assumed:warnings:)` plus the disclaimer.

---

## 7. Roof drawings (`RoofDrawings.swift`)

```swift
public enum RoofDrawings {
    /// Section with tags, dimensions and legend/schedule. Truss frames add details A/B and the schedule table.
    public static func section(_ i: RoofInput, width W: Double = 690) -> Sketch?
    /// Existing Drawings.plan + ridge, rafters, purlin lines, hip lines, columns.
    public static func framingPlan(_ i: RoofInput, values: Values, width W: Double = 690) -> Sketch?
}

enum TrussDetails {                     // fixed templates, not to scale; labels filled from members
    static func eave(in box: Box, pitch: Double, members: [RoofComponent: MemberSpec]) -> [DrawOp]
    static func ridge(in box: Box, pitch: Double, members: [RoofComponent: MemberSpec]) -> [DrawOp]
}
```

`section` layout, top to bottom:
1. Title strip, 28 pt.
2. Section, fitted to `W − 128` × `min(0.36·W, 250)` pt.
3. Dimension chains, 50 pt: "n @ p = h" per half and the span total.
4. **Truss only:** details A and B side by side, each `(W−40)/2` × 220 pt.
5. Schedule table: 16 pt per row. It replaces the 2-column legend used for a rafter frame.
6. Notes and disclaimer.

The sketch height is the sum of these. Line weights and colours follow the design spec §7:
- top chord 2.8
- bottom chord 2.4
- web 1.3
- columns 2.4
- sheet line 1.0 `.blue`
- gusset hexagon r = 3.2 pt, fill `#6b6b6b`

The purlin marker is a 7 × 5 pt rectangle rotated to the slope, offset 2.8 pt outward from the chord.

---

## 8. Tank

### 8.1 Model change (`Models.swift`)

Tank openings reuse `Obstacle`, so existing data, the obstacle editor and `Drawings.plan` keep working. The new
keys are optional, so synthesized `Codable` decodes old JSON unchanged. `id` is already stored.

```swift
public struct Obstacle: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var label = ""
    public var x = "", y = "", w = "", h = ""
    // new, all optional
    public var kind: OpeningKind?          // nil ⇒ .other
    public var cell: GridCell?             // .vent placed by tap
    public var edge: WallEdge?             // .hatch / .pipe
    public var along: String?              // m along the wall from its start (top/bottom: from left; left/right: from top)
    public var diameter: String?           // mm, pipes
}
public enum OpeningKind: String, Codable, Sendable { case vent, hatch, pipe, other }
public struct GridCell: Codable, Hashable, Sendable { public var row: Int; public var col: Int }
public enum WallEdge: String, Codable, Sendable { case top, bottom, left, right }
```

`WebBackup` import/export adds the keys when present: `kind`, `row`, `col`, `edge`, `along`, `diameter`. It must
keep them when absent, so the web version stays compatible.

### 8.2 Input (`TankInput.swift`)

```swift
public enum TankOutline: Sendable, Equatable { case rectangle(Double, Double), circle(Double) }
public enum TankSetting: Sendable, Equatable { case aboveGround, buried(cover: Double), partlyBuried(above: Double) }

public struct ResolvedOpening: Sendable { public var kind: OpeningKind; public var box: Box   // metres, y-down plan
                                          public var edge: WallEdge?; public var label: String; public var diameter: Double? }

public struct TankInput: Sendable {
    public var title: String
    public var outline: TankOutline
    public var bays: (x: [Double], y: [Double])     // empty for a circle without spans
    public var height: Double?
    public var setting: TankSetting
    public var openings: [ResolvedOpening]
    public var missing: [String], assumed: [String], warnings: [String]
    public static func from(_ m: SurveyModule) -> TankInput?     // .tank only
}
```

- **Outline:** a `tankDiameter` value makes it `.circle`. Otherwise it is `.rectangle(Σ spansX, Σ spansY)`. With
  neither, `missing` gets "ระยะช่วงเสา".
- **Setting:**
  - `tankAboveGround` ≥ `tankHeight` → above ground
  - `tankAboveGround` == 0 → `.buried(cover: soilDepth ?? 0)`
  - anything in between → partly buried
  - no value → the existing `tankPos` choice, else above ground, with an assumed note
- **Resolving openings** (y-down, metres from the top-left corner):
  - `.vent` with `cell`: a square of `S.ventSize`, centred in the bay cell, from `Spans.edges`. A vent whose
    cell is outside the grid is dropped with a warning.
  - `.hatch`: a square of `S.hatchSize` against the wall, offset 0.15 m inside, centred at `along`. Top and
    bottom walls measure from the left; left and right walls measure from the top.
  - `.pipe`: zero-area box at the wall point. `diameter` comes from `NumberInput.value`.
  - `.other` / `nil`: the existing x, y, w, h fields, parsed with `NumberInput.value`.

### 8.3 Geometry (`TankGeometry.swift`)

```swift
public struct TankGeometry: Sendable {
    public var input: TankInput
    public var roofArea: Double, grossVolume: Double?
    public var usableArea: Double, usableKWp: Double
    public var usableRuns: [Box]          // merged horizontal runs of free cells (for the green fill)
    public static func compute(_ i: TankInput, settings: DrawingSettings = .current) -> TankGeometry
}
```

The usable area is computed by rasterising the roof:
- Use a `step = 0.25 m` grid (0.5 m in the prototype. 0.25 m gives ±1% and stays under 50k cells for 64 × 40 m).
- A cell is free if it is:
  - inside the outline (circle test for a round tank)
  - at least `edgeSetback` from the outline
  - clear of every opening's box expanded by `openingSetback`
  - clear of a pipe point expanded by `openingSetback + diameter/2`
- `usableArea = free × step²` and `usableKWp = usableArea / m2PerKWp`.
- `usableRuns` merges consecutive free cells per row, so the fill is a few hundred rects, not tens of thousands.

### 8.4 Drawings (`TankDrawings.swift`)

```swift
public enum TankDrawings {
    /// กปภ.-style roof plan: double wall, dashed bay grid, per-bay + total dimensions, typed opening symbols,
    /// ladders outside hatches, pipes with coupling, green usable area, legend, summary strip, notes.
    public static func roofPlan(_ g: TankGeometry, width W: Double = 690) -> (Sketch, DrawingTransform)?
    /// Elevation: ground line from the setting, soil cover hatch, H and above-ground dimensions.
    public static func section(_ g: TankGeometry, width W: Double = 690) -> Sketch?
}
```

`roofPlan` also returns its `DrawingTransform`. The editor uses it to turn a tap into a `GridCell` (§9.2).
The symbols follow `img/tank_pwa.png`:

| Kind | Symbol |
|---|---|
| vent | square + inner square at 64% + circle at r = 0.2·size |
| hatch | plain square, plus a 6 × 8 pt ladder outside the wall |
| pipe | 26 × 8 pt stub outside the wall, a 4 × 10 pt coupling, and an open circle at the end |

Labels are grouped by type and placed on a free side. The summary strip reads:
"ขนาด {W} × {H} ม. · หลังคาถัง {A} ม² · ช่องระบายอากาศ {n} · ช่องลงถัง {m} · พื้นที่ติดตั้งได้ประมาณ {U} ม² (ราว {kWp} kWp)"

### 8.5 Settings (`DrawingSettings.swift`)

```swift
public struct DrawingSettings: Codable, Equatable, Sendable {
    public var purlinSpacing = 1.0           // m, when not entered
    public var ventSize = 1.5, hatchSize = 1.2   // m
    public var edgeSetback = 1.0, openingSetback = 0.5   // m
    public var m2PerKWp = 6.0                // same constant as TCRoof SurveyForm
    public static var current = DrawingSettings()   // set once from SurveySettings at launch (Swift 5 mode)
}
```

`SurveySettings` gains `drawing: DrawingSettings`, decoded with `decodeIfPresent` like the other keys. It also gains
`autoDrawings: Bool`: true in Debug, false in Release until sign-off. Every value used from these settings is echoed
in `assumed`.

---

## 9. Schema and UI

### 9.1 `Schema.swift`

```swift
// FieldKind
case roofSection          // drawing only, not counted
case tankDrawing          // drawing + tap-to-place vents, not counted

// FieldSpec.countable
case .plan, .diagram, .note, .roofSection, .tankDrawing: return false
```

**C1 `.roof`.** In group "โครงสร้าง", after `comp1…7`, add:

```swift
N("eaveHeight", "ความสูงชายคา (พื้น → ใต้ขื่อที่เสา)", "ม."),
N("ridgeHeight", "ความสูงสันหลังคา (พื้น → หลังคาที่สัน)", "ม."),
N("overhang", "ระยะชายคายื่นจากเสา", "ม.", optional: true),
N("heelDepth", "ความลึกโครงถักที่เสา", "ม.", optional: true),
FieldSpec("compTop", "ขื่อบน", .member(component: 2), optional: true),
FieldSpec("compBottom", "ขื่อล่าง", .member(component: 4), optional: true),
FieldSpec("compVertical", "ตัวตั้ง", .member(component: 7), optional: true),
FieldSpec("compDiagonal", "ตัวทแยง", .member(component: 5), optional: true),
FieldSpec("section", "รูปตัดโครงหลังคา", .roofSection),
```

**C2 `.roofForm`.** Add `eaveHeight` and `ridgeHeight` to group "อาคาร", and `FieldSpec("section", …, .roofSection)`
after the structure group.

**C3 `.house`.** Add `FieldSpec("section", …, .roofSection)` after group 13. It uses `measI1`, `measI2` and `roofAngle`.

**D1 `.tank`.** In group "ข้อมูลถัง", add:

```swift
N("tankDiameter", "เส้นผ่านศูนย์กลาง (ถังกลม)", "ม.", optional: true),
N("tankAboveGround", "ความสูงส่วนที่พ้นดิน", "ม.", optional: true),
```

Then, in the `planFields(tank: true)` group, replace `FieldSpec("plan", "แปลน", .plan(tank: true))` with
`FieldSpec("plan", "แปลน", .tankDrawing)` when `SurveySettings.autoDrawings` is on. Keep `.plan` otherwise.

Keep `N(... "M")` units as they are for existing fields. New fields use `"ม."`.

**Existing switches to update:**
- `FieldView.body`: route both kinds to `DrawingField`.
- `WebBackup` (`case .plan, .diagram, .note: break`): add the two kinds.
- `ReportLayout.formSection`: skip them in the rows.
- `Validation.missingGroups`: append `RoofInput.from(m)?.missing` / `TankInput.from(m)?.missing`, each prefixed
  "ข้อมูลไม่พอวาดรูป: ".

### 9.2 `DrawingField.swift` (SurveyUI)

```swift
struct DrawingField: View {
    let kind: FieldKind            // .roofSection or .tankDrawing
    @Binding var module: SurveyModule
    @State private var zoomed = false

    var body: some View {
        switch kind {
        case .roofSection:
            if let i = RoofInput.from(module), i.missing.isEmpty, let sk = RoofDrawings.section(i) {
                SketchView(sketch: sk).onTapGesture { zoomed = true }
                    .fullScreenCover(isPresented: $zoomed) { ZoomableSketch(sketch: sk) }
            } else { MissingBox(items: RoofInput.from(module)?.missing ?? []) }
        case .tankDrawing:
            TankPlanEditor(module: $module)
        default: EmptyView()
        }
    }
}

/// Tank plan with tap-to-toggle vents on bay cells.
struct TankPlanEditor: View {
    @Binding var module: SurveyModule
    var body: some View {
        if let i = TankInput.from(module), i.missing.isEmpty,
           let plan = TankDrawings.roofPlan(TankGeometry.compute(i)) {      // (Sketch, DrawingTransform)
            GeometryReader { geo in
                SketchView(sketch: plan.0)
                    .gesture(SpatialTapGesture().onEnded { e in
                        toggleVent(at: e.location, size: geo.size, sketch: plan.0, t: plan.1, bays: i.bays)
                    })
            }
            .aspectRatio(plan.0.width / plan.0.height, contentMode: .fit)
        } else { MissingBox(items: TankInput.from(module)?.missing ?? []) }
    }
    /// View point → sketch point (same fit as SketchView) → metres → GridCell; add or remove a .vent Obstacle.
    func toggleVent(at p: CGPoint, size: CGSize, sketch: Sketch, t: DrawingTransform, bays: (x: [Double], y: [Double])) { … }
}
```

Tap mapping:
1. `SketchView` scales by `k = min(w/sketch.w, h/sketch.h)` and centres horizontally. Invert that first.
2. Then apply `t.metres(_:)`.
3. Find the cell by a binary search over `Spans.edges`.
4. A tap inside an existing vent's cell removes it. Otherwise it appends
   `Obstacle(kind: .vent, cell: GridCell(row:col:))`.
5. Haptic feedback: `.selection`.

Hatches and pipes use the existing obstacle table with two new columns, **ผนัง** (a picker) and **ระยะ (ม.)**,
shown when the row's type is ช่องลงถัง or ท่อ. The type is a small menu at the start of the row. This menu is
the only choice in the feature, and it describes what the object is, not a design decision.

---

## 10. PDF (`ReportLayout.swift`)

```swift
func planSection(_ mod: SurveyModule) -> [Unit] {
    // existing: plan photo, else Drawings.plan …
    if SurveySettings.autoDrawingsEnabled {
        if mod.type == .tank, let i = TankInput.from(mod), i.missing.isEmpty {
            let g = TankGeometry.compute(i)
            if let plan = TankDrawings.roofPlan(g, width: 690) { U.append(sketchUnit(plan.0, title: "แปลนฝาถัง")) }
            if let s = TankDrawings.section(g, width: 690) { U.append(sketchUnit(s, title: "รูปตัดถัง")) }
        }
        if mod.type == .roof, let i = RoofInput.from(mod), i.missing.isEmpty, let s = RoofDrawings.section(i) {
            U.append(sketchUnit(s, title: "รูปตัดโครงหลังคา"))
        }
    }
    …
}
/// One boxed unit scaled to content width; the paginator splits before it if it doesn't fit.
func sketchUnit(_ sk: Sketch, title: String) -> Unit
```

- `formSection` (C2/C3): if `RoofInput.from(mod)` succeeds, add the section unit. Keep `Drawings.truss()` only
  as the fallback.
- A drawing taller than a page is scaled down to fit; it is never split across pages.
- When a hand sketch (`planPhoto`) is attached, it keeps its place and the auto drawing follows it.

---

## 11. Tests

All tests use `@testable import SurveyCore` and run with `swift test` on macOS. They do not need the simulator.

```swift
final class SpansTests: XCTestCase {
    func testShorthand() {
        XCTAssertEqual(Spans.parse("16@4"), Array(repeating: 4, count: 16))
        XCTAssertEqual(Spans.parse("1.5, 3@4, 1.5"), [1.5, 4, 4, 4, 1.5])
        XCTAssertEqual(Spans.parse("4ม., ๔"), [4, 4])
        XCTAssertEqual(Spans.uniformLabel(Spans.parse("16@4")), "16 @ 4.00 = 64.00")
        XCTAssertEqual(parseSpans("1.5,4,4"), [1.5, 4, 4])            // old callers unchanged
    }
}

final class MemberSpecTests: XCTestCase {
    func testDepths() {
        XCTAssertEqual(MemberSpec.parse("C-100x50x20x3.2 @1.00M")?.depth ?? 0, 0.100, accuracy: 1e-9)
        XCTAssertEqual(MemberSpec.parse("C-100x50x20x3.2 @1.00M")?.spacing, 1.0)
        XCTAssertEqual(MemberSpec.parse("ไม้ 2\"x8\"")?.depth ?? 0, 0.2032, accuracy: 1e-4)
        XCTAssertEqual(MemberSpec.parse("ค.ส.ล 0.20x0.40")?.depth, 0.40)
        XCTAssertEqual(MemberSpec.parse("C 10x5x2", unit: .centimetre, spacingCm: "100")?.spacing, 1.0)
        XCTAssertTrue(MemberSpec.parse("-")!.isAbsent)
        XCTAssertNil(MemberSpec.parse(""))
    }
}

final class RoofTests: XCTestCase {
    func c1(_ extra: [String: String]) -> SurveyModule {
        var m = SurveyModule(type: .roof)
        for (k, v) in ["spansX": "1.5,4,4,4,4,1.5", "spansY": "8,8", "sheetDir": "", "eaveHeight": "4",
                       "ridgeHeight": "6.643594", "heelDepth": "0.5", "comp1": "C-100x50x20x3.2 @1.00M"].merging(extra, uniquingKeysWith: { $1 }) {
            m.values[k] = k == "sheetDir" ? (v.isEmpty ? nil : .choice(v, other: "")) : .text(v)
        }
        return m
    }
    func testDerivedPitchAndHowe() throws {
        let i = try XCTUnwrap(RoofInput.from(c1(["compBottom": "2C-125x50x20x3.2", "compVertical": "C-100x50x20x2.3",
                                                 "compDiagonal": "C-100x50x20x2.3"])))
        XCTAssertEqual(i.span, 16); XCTAssertEqual(i.pitch * 180 / .pi, 15, accuracy: 0.01)
        XCTAssertEqual(i.frame, .truss(.howe))
        let g = try XCTUnwrap(RoofGeometry.section(i))
        XCTAssertEqual(g.panelsPerHalf, 8)
        XCTAssertEqual(g.segments.filter { $0.role == .vertical }.count, 17)
        XCTAssertEqual(g.segments.filter { $0.role == .diagonal }.count, 16)
        XCTAssertEqual(g.nodes.count, 34)
    }
    func testFrameInference() {
        XCTAssertEqual(RoofInput.from(c1([:]))?.frame, .rafter)                                   // no web entered
        XCTAssertEqual(RoofInput.from(c1(["compBottom": "2C-125x50", "compDiagonal": "C-100x50"]))?.frame, .truss(.warren))
    }
    func testMissingHeights() {
        XCTAssertTrue(RoofInput.from(c1(["ridgeHeight": "3"]))!.missing.contains { $0.hasPrefix("ความสูงสันหลังคา") })
    }
    func testGableRafterPurlins() throws {
        let g = try XCTUnwrap(RoofGeometry.section(XCTUnwrap(RoofInput.from(c1(["heelDepth": "0", "ridgeHeight": "6.143594"])))))
        XCTAssertEqual(g.purlins.count, 20)             // 9 + ridge per slope (last gap 0.28 > 0.25)
    }
}

final class TankTests: XCTestCase {
    func pwa() -> SurveyModule {                        // the กปภ. sheet: 64 × 40, 20 vents, 8 hatches, 6 pipes
        var m = SurveyModule(type: .tank)
        m.values["spansX"] = .text("16@4"); m.values["spansY"] = .text("10@4"); m.values["tankHeight"] = .text("4.5")
        var o: [Obstacle] = []
        for r in [0, 3, 6, 9] { for c in [0, 4, 8, 12, 15] { var x = Obstacle(); x.kind = .vent; x.cell = GridCell(row: r, col: c); o.append(x) } }
        for (e, a) in [(WallEdge.top, "14.3"), (.top, "46"), (.bottom, "14.1"), (.bottom, "45.7"),
                       (.left, "18"), (.left, "22"), (.right, "18.2"), (.right, "22.2")] {
            var x = Obstacle(); x.kind = .hatch; x.edge = e; x.along = a; o.append(x)
        }
        m.values["obst"] = .obstacles(o)
        return m
    }
    func testSummary() throws {
        let g = TankGeometry.compute(try XCTUnwrap(TankInput.from(pwa())), settings: DrawingSettings())
        XCTAssertEqual(g.roofArea, 2560)
        XCTAssertEqual(g.input.openings.filter { $0.kind == .vent }.count, 20)
        XCTAssertEqual(g.usableArea, 2180, accuracy: 30)     // prototype: 2,180 m² at 0.5 m step
    }
    func testRoundAndSetting() {
        var m = SurveyModule(type: .tank)
        m.values["tankDiameter"] = .text("10"); m.values["tankHeight"] = .text("5"); m.values["tankAboveGround"] = .text("2")
        let i = TankInput.from(m)!
        XCTAssertEqual(i.outline, .circle(10)); XCTAssertEqual(i.setting, .partlyBuried(above: 2))
        XCTAssertEqual(TankGeometry.compute(i).grossVolume ?? 0, 392.7, accuracy: 0.1)
    }
}
```

**Snapshot tests** (`DrawingSnapshotTests`):
- Render `Sketch.svg()` for six fixtures:
  1. C1 gable rafter
  2. C1 Howe truss
  3. C1 Warren truss
  4. C3 house
  5. PWA tank 64 × 40
  6. round tank partly buried
- Compare each with `Fixtures/drawings/<name>.svg` (add the folder to the test target's resources).
- `RECORD_SNAPSHOTS=1` rewrites the files.
- Numbers in the SVG are already rounded by `fmt`, so the output is stable across macOS and Linux.

**Invariant test:** 50 seeded random inputs (spans 1–40 bays, heights, members). Assert:
- no NaN
- every `Pt` inside the sketch bounds
- `ops.count < 2_000`
- the drawing is `nil` exactly when `missing` is non-empty

---

## 12. Order of work (one PR each)

| PR | Content | Done when |
|---|---|---|
| 1 | `Spans`, `parseSpans` delegate, `MemberSpec`, `DrawingSettings` + tests | `swift test` passes; old plans unchanged |
| 2 | `RoofInput`, `RoofGeometry` (rafter + truss + schedule) + tests | Numbers in §11 pass |
| 3 | `DrawingKit`, `RoofDrawings.section`, `TrussDetails` + snapshots | SVGs match `img/roof_section.png`, `img/truss_howe.png` visually |
| 4 | `Obstacle` fields, `WebBackup`, `TankInput`, `TankGeometry`, `TankDrawings` + tests/snapshots | PWA fixture gives 2,560 m², 20 vents, about 2,180 m² |
| 5 | Schema fields and kinds, `DrawingField`, `TankPlanEditor` (tap to place) | iPad: fill C1/D1 from the PWA sheet and see the drawings live |
| 6 | `ReportLayout` integration, `missingGroups`, `autoDrawings` flag | PDF pages match the prototypes; export sheet lists drawing gaps |
| 7 | Framing plan overlay | Matches `img/framing_plan.png` |

PR 1–4 touch only `SurveyCore` and its tests, so they can be written and reviewed without Xcode.
PR 5–6 need an iOS build (`xcodebuild -scheme TCRoof -destination 'generic/platform=iOS Simulator'`),
because `SurveyUI` is `#if canImport(UIKit)` and a macOS `swift build` doesn't compile it.
