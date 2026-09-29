# Auto Single Line Diagram — Swift implementation spec (iPad + iPhone)

**Status:** Draft for development, 2026-09-29
**Design spec:** [`single-line-diagram.md`](single-line-diagram.md) (what is drawn and why)
**Prototype to match:** `img/sld_form.py` with `img/sld_form_sample.json` and `img/sld_form_large.json`
**Targets:** `SolarSurveyKit` (iOS 17+, macOS 14 for tests) inside the TCRoof app (`TARGETED_DEVICE_FAMILY = 1,2`)
**New dependencies:** none

This document tells a Swift developer what to build, where it goes, and how to know it is done. The prototype PNGs
are the visual reference; the Swift output must match them within a few points.

![](img/sld_form_hv.png)

---

## 1. Goals and non-goals

**Goals**

1. Generate the SLD automatically from the survey. The surveyor never draws; every edit redraws it.
2. Record every transformer and breaker completely, with its condition. Blanks show as a red `?` and are listed.
3. Use the MDB names written on site (MDP-1, SDB ระบบกรอง, MDB-ADMIN …), not fixed MDB1…MDB6.
4. Run well on iPad (primary, field use) and iPhone (review, quick checks), portrait and landscape.
5. Put the same drawing in the preview, the PDF report and the Excel export.

**Non-goals (v1)**

- Editing the drawing by hand (moving symbols, adding lines).
- Cable sizing, voltage drop, short-circuit studies.
- The detailed MDP level (feeder cables and conduits, `img/sld.py`), which comes later.
- Anything on the TCRoof-only `SurveyForm` (the PWA survey lives in SolarSurveyKit).

## 2. Where the code goes

```
SolarSurveyKit/Sources/
  SurveyCore/
    Models.swift            + BreakerInfo, Transformer.breakers, EquipmentCondition
    Schema.swift            + transformer nameplate fields, B1 breaker fields, required rules
    Progress.swift          + missing-field lines for breakers and transformers
    WebBackup.swift         + round-trip of the new keys (PWA parity)
    SLD/                    (new folder, platform-neutral, fully unit-testable on macOS)
      SLDInput.swift        Job → SLDInput (+ missing, assumed)
      SLDRatings.swift      standard AT/AF tables, PV breaker sizing
      SLDLayout.swift       SLDInput → positions (no drawing)
      SLDSymbols.swift      DrawOp builders: breaker, draw-out, CT, VT, DOF, LA, transformer, inverter …
      SLDDrawing.swift      SLDLayout → Sketch
  PDFReport/
    ReportLayout.swift      + SLD page(s)
  ExcelExport/
    ExcelExporter.swift     + SLD image on the electrical sheet
  SurveyUI/
    SLD/                    (new folder, #if canImport(UIKit))
      SLDScreen.swift       full preview: zoom, pan, share, missing list
      SLDPreviewCard.swift  thumbnail card on the A3 page
      BreakerEditor.swift   one breaker card (used for MDB rows and B1 panels)
      TransformerPlate.swift nameplate + condition fields under each transformer
      ConditionPicker.swift ดี / พอใช้ / ชำรุด + note
    TransformerPhotos.swift feed picker uses on-site names
    Fields.swift            .transformers editor opens BreakerEditor per MDB
```

SurveyCore stays free of UIKit and SwiftUI so layout and drawing are tested with `swift test` on a Mac or Linux.

## 3. Data model (SurveyCore/Models.swift)

All additions decode from old jobs and old web backups. **Do not rely on synthesized `Codable` for new stored
properties**: a missing key throws. Use optionals or a custom `init(from:)` with `decodeIfPresent`.

```swift
public enum EquipmentCondition: String, Codable, CaseIterable, Sendable {
    case good = "ดี", fair = "พอใช้", damaged = "ชำรุด"
}

public enum BreakerMount: String, Codable, CaseIterable, Sendable { case fixed = "Fixed", drawOut = "Draw-out" }

/// One surveyed breaker. Numbers stay as String, like every other form value, so typing is never blocked.
public struct BreakerInfo: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name = ""          // on-site panel name, e.g. "MDP-1" (MDB rows only; B1 uses the section name)
    public var type = ""          // "MCCB" | "ACB" | other text
    public var mount: BreakerMount?
    public var poles = ""         // "1" "2" "3" "4"
    public var at = ""
    public var af = ""
    public var ka = ""            // IC kA
    public var brand = ""
    public var condition: EquipmentCondition?
    public var note = ""          // required when condition != .good
    public var plate: Photo?      // optional nameplate photo
}

public struct Transformer: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kva = ""
    public var mdb: [String]                 // kept: the AT of each MDB, read by old code and the web app
    public var breakers: [BreakerInfo]       // NEW, index-aligned with `mdb`
    // custom init(from:) → breakers = decodeIfPresent ?? []; then `normalise()`
}
```

`Transformer.normalise()` keeps `mdb` and `breakers` in step:

- `breakers.count == mdb.count` (pad with empty `BreakerInfo`).
- Writing `breakers[k].at` also writes `mdb[k]` (and the reverse on decode of old data), so SiteMarks, Progress and
  the web app keep working unchanged.

Transformer nameplate and condition go in `Job.values` under per-transformer keys, like the existing `tr<i>_feed`.
`Values.shiftTransformerAnswers(removed:)` must add the new suffixes:

| Key | Kind | Required |
|---|---|---|
| `tr<i>_type` | choice OIL IMMERSED / DRY TYPE / อื่นๆ | yes |
| `tr<i>_hv` | number kV | yes |
| `tr<i>_lv` | text (230-400) | yes |
| `tr<i>_vector` | text (Dyn11) | yes |
| `tr<i>_z` | number % | yes |
| `tr<i>_brand` | text | yes |
| `tr<i>_serial` | text | yes |
| `tr<i>_year` | number (พ.ศ.) | yes |
| `tr<i>_cond` | choice ดี / พอใช้ / ชำรุด | yes |
| `tr<i>_condNote` | text | when `cond` ≠ ดี |

B1 ตู้ไฟฟ้าอาคาร module values (next to the existing `breakerAT`, `loadKW`, `loadTime`): `breakerType`,
`breakerMount`, `breakerPoles`, `breakerAF`, `breakerKA`, `breakerBrand`, `cond`, `condNote`. The module `name` is the
on-site panel name.

`tr<i>_feed` stores the **name** of the MDB (not an index). Old jobs holding "MDB1" … are mapped on read: if no
breaker has that name and `breakers[k].name` is empty, `"MDB\(k+1)"` matches index `k`.

### Web app parity

`WebBackup.swift` writes and reads `breakers` inside each `trafos[]` entry and the new `tr<i>_*` keys.
`SolarSurveyWeb/survey-app.html` must accept and preserve unknown keys (it already stores `trafos` as JSON). Adding
the editors to the web app is a separate task; until then the web app round-trips the data without showing it.

## 4. Required fields and progress (Schema.swift, Progress.swift)

- A breaker is complete when `type`, `mount`, `poles`, `at`, `af`, `ka`, `brand`, `condition` are set, and `note`
  when the condition is not ดี. MDB rows also need `name`.
- A transformer is complete when `kva` and every required `tr<i>_*` key above is set.
- `Progress` adds one line per incomplete item, in the same words the drawing prints:
  `A3 TR2: Vector group, %Z, Serial no., สภาพ` · `A3 TR2 MDB-ADMIN: IC kA` · `B1 ตู้ไฟฟ้า อาคารสำนักงาน: AF, IC kA, ยี่ห้อ`.
- One function builds these lines (`SLDInput.missing`) and both Progress and the drawing call it.

## 5. SLD core (SurveyCore/SLD)

### 5.1 Input

```swift
public struct SLDInput: Sendable {
    public struct Transformer: Sendable {
        public var index: Int, name: String          // "TR1"
        public var kva: Double?
        public var plate: [String: String]           // type, hv, lv, vector, z, brand, serial, year
        public var condition: EquipmentCondition?, note: String
        public var mdbs: [BreakerInfo]               // name = on-site MDB name
        public var feed: String, feedLocation: String
    }
    public struct Panel: Sendable { public var name: String; public var breaker: BreakerInfo; public var loadKW: Double?; public var loadTime: String }
    public enum ExportLimit: Sendable { case lv, hv(pole: String), unknown }
    public struct PV: Sendable { public var kwp: Double; public var inverters: Int; public var exportLimit: ExportLimit; public var fts: Bool }

    public var projectName: String
    public var meterNo: String
    public var transformers: [Transformer]
    public var panels: [Panel]
    public var pv: PV?                  // nil when A1 capacity or B2 inverter count is blank
    public var missing: [String]        // red list under the drawing, also used by Progress
    public var assumed: [String]        // ค่าสมมติ list

    public init(job: Job)
}
```

Field sources (ids exactly as in `Schema`):

| Input | Source |
|---|---|
| `meterNo` | `job.values.text("meterNo")` |
| transformers | `job.values.transformers("trafos")` + `tr<i>_*` keys, skipping entries where `Schema.transformerPresent` is false |
| `pv.kwp` | `job.values.number("capacity")` |
| `pv.inverters` | sum of `number("inverterCount")` over `.inverter` modules |
| `pv.exportLimit` | first `.backfeed` module: `choice("level")` = กันย้อนที่แรงสูง → `.hv(pole: choice("pole"))`, กันย้อนที่แรงต่ำ → `.lv` |
| `pv.fts` | any `.fts` module with `photo("photoFTS")` or `photo("photoEmg")` |
| panels | `.panel` modules in order |

Assumptions printed (the form does not ask them): 22 kV system, PEA metering on the HV side, PV and B1 panels
connect at TR1's `tr0_feed` MDB, PF 1, breaker factor 1.25.

### 5.2 Ratings

```swift
public enum SLDRatings {
    public static let at: [Int] = [16, 20, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800,
                                   1000, 1250, 1600, 2000, 2500, 3200]
    public static let af: [Int] = [100, 160, 250, 400, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000]
    public static func current(kw: Double, volts: Double = 400) -> Double   // kW·1000 / (√3·V)
    public static func breaker(forAmps a: Double, factor: Double = 1.25) -> (at: Int, af: Int)
}
```

Expected values (unit tests): 100 kW → 144.3 A → 200 AT / 250 AF; 300 kW → 433.0 A → 630 AT / 630 AF;
30 kW → 43.3 A → 63 AT / 100 AF; 630 kVA → 909 A; 250 kVA → 361 A.

### 5.3 Layout (numbers from the prototype, in points)

`SLDLayout` computes positions only; it holds no `DrawOp`s, so it can be tested with plain asserts.

| Constant | Value | Meaning |
|---|---|---|
| `mdbColumn` | 120 | spacing of MDB boxes under a transformer |
| `blockMin` | 270 | minimum width of a transformer block (its nameplate text must fit) |
| `blockGap` | 30 | gap between transformer blocks |
| `feederSpacing` | 105 | B1 feeders in the expanded MDB |
| `feederStart` | 110 | first feeder right of the MDB incomer |
| `inverterSpacing` | 60 | inverter columns under SMDB-PV (max 10 drawn, label "แสดง 10") |
| `minWidth` | 1300 | sheet width never below this |

Rules:

- Sheet width = max(`minWidth`, end of the last transformer block + 60, PV group right edge + 170).
- The expanded MDB is TR1's feed MDB when PV or B1 panels exist; every other MDB is a compact dashed box.
- Names wrap at about 14 characters on spaces, at most two lines (Thai names without spaces stay on one line and
  may be shrunk to fit the box width with `DrawOp.textBox`).
- Breaker half-height: 11 fixed, 22 draw-out. Lines stop at the symbol, never through it.

### 5.4 Symbols (SLDSymbols.swift)

Each returns `[DrawOp]`; colours: existing `RGBA.dark`, new PV `RGBA.blue`, missing `RGBA.red`, condition ดี
`0x2F855A`, พอใช้ `0xB7791F`, ชำรุด `RGBA.red`.

| Symbol | Drawing |
|---|---|
| `breakerFixed` | terminal dot, arc (r 9) to the right, terminal dot |
| `breakerDrawOut` | arc between two up-chevrons (above) and two down-chevrons (below) |
| `breakerLabel` | `TYPE,nP` / `ATAT` over `AFAF` / `IC kA` / brand / `สภาพ: …` (+ note line) — blank → `?` in red |
| `dropOutFuse` | open terminal, slanted blade with hook |
| `lightningArrester` | box with arrow, ground, label LA |
| `cableTerminations` | **three** filled triangles pointing down |
| `transformer` | two circles (r 17), Δ in the upper, Y in the lower |
| `pea meter` | small square + circle "M" with loop |
| `ct` | circle on the line, slash with the count "3", signal lead |
| `vt` | two small circles on a branch |
| `inverter`, `fts`, `pvArray`, `emergency` | as in the prototype |
| `relay` | blue box, two text lines |
| `control` | dashed blue polyline `[4, 3]` |

HV side is always drop-out fuse → lightning arrester → three terminations → transformer. No VCB/52.

Export limiting: the relay's control line ends on a dashed bus under the inverter boxes, one stub and dot into each
inverter, label "สั่งควบคุมกำลังผลิต". It never goes to a breaker.

### 5.5 Drawing (SLDDrawing.swift)

```swift
public enum SLDDrawing {
    /// Whole diagram on one sheet (preview, Excel).
    public static func sketch(_ input: SLDInput) -> Sketch
    /// Pages for the PDF; one sheet today, split later (open question: page per transformer).
    public static func pages(_ input: SLDInput, page: Box) -> [Sketch]
}
public extension Job { var sld: SLDInput { SLDInput(job: self) } }
```

`Sketch.svg()` already exists: tests compare the SVG of the two sample jobs against checked-in snapshots.

## 6. UI (SurveyUI/SLD)

### 6.1 Entry points

| Where | What |
|---|---|
| A3 page (electrical), under the transformer cards | `SLDPreviewCard`: thumbnail, "ขาด n รายการ", "ชำรุด n", tap → `SLDScreen` |
| Job toolbar | "แผนภาพเส้นเดียว" button (`point.3.connected.trianglepath.dotted`) → `SLDScreen` |
| Export sheet | "SLD (PDF)" option alongside the report |

### 6.2 SLDScreen — iPad (regular width)

```
┌───────────────────────────────┬───────────────────┐
│  drawing (zoom / pan)         │ ข้อมูลที่ขาด (3)   │
│                               │  • TR2: Vector …  │  ← tap: jumps to the field
│                               │ สภาพอุปกรณ์        │
│                               │  • TR1 พอใช้ …     │
│  [ fit ] [ 100% ]  [ share ]  │ ค่าสมมติ           │
└───────────────────────────────┴───────────────────┘
```

- `NavigationSplitView`-style two columns inside the job editor: drawing left (flex), side panel right (320 pt,
  collapsible with a toolbar button).
- Editing in split view (Stage Manager / Slide Over) redraws live: the form on the left of the job editor and the
  preview card on the right.
- Keyboard: ⌘+ / ⌘− zoom, ⌘0 fit.

### 6.3 SLDScreen — iPhone (compact width)

- Full-screen sheet, drawing only, fit-to-width on open; a bottom segmented control switches ภาพ / ขาด (n) / สภาพ.
- Landscape is recommended for large stations; show a one-time hint "หมุนแนวนอนเพื่อดูภาพเต็ม" when the sheet is
  wider than 2× the screen.
- Share button in the toolbar (PDF / PNG) through the existing `ShareSheet`.

### 6.4 Zoom and pan (both)

- `ScrollView([.horizontal, .vertical])` with a `MagnifyGesture`, zoom 0.25×…4×, double tap toggles fit ↔ 100%.
- Render: `SketchView` (Canvas) at the current zoom. For sheets above ~3,000 pt wide, render once to a cached
  `UIImage` via `PDFRenderer.png` at `scale = min(3, 8192 / width)`, keyed by a hash of `SLDInput`, and show that
  image while zooming; redraw vector when the zoom settles.
- The drawing sits on a white "paper" card in both light and dark mode (it is a document, not UI).

### 6.5 Editors

**BreakerEditor** (MDB rows and B1 panels share it):

| Control | iPad | iPhone |
|---|---|---|
| ชื่อตู้ตามหน้างาน (MDB rows) | text field, autocapitalization off | same |
| ชนิด | segmented MCCB / ACB / อื่นๆ | same |
| การติดตั้ง | segmented Fixed / Draw-out with the symbol drawn in each segment | same |
| โพล | segmented 1 2 3 4 | same |
| AT, AF, IC kA | three number fields in one row, `.numberPad`, a menu of standard values beside AT/AF | stacked, two per row |
| ยี่ห้อ | text field with suggestions (Schneider, ABB, Mitsubishi, LS, Siemens, Chint, Hager) | same |
| สภาพ | `ConditionPicker`: three coloured capsules; note field appears when not ดี and is required | same |
| ภาพป้าย (optional) | `PhotoField` 150 pt | 120 pt |

- Card header shows the name and a status: green check when complete, red "ขาด n" otherwise.
- AT > AF shows an inline warning (not blocking).
- The `.transformers` field keeps its compact grid (kVA + 6 AT) for speed; each AT cell gets a disclosure that opens
  the BreakerEditor for that MDB (sheet on iPhone, popover on iPad).

**TransformerPlate** (inside each transformer card in `TransformerPhotosView`): type, kV HV / LV, vector, %Z, brand,
serial, year, condition + note. Two columns on iPad, one on iPhone.

**Feed picker**: the menu lists the on-site MDB names of that transformer; typing a name is still allowed; a name
that matches none shows the red hint "ไม่ตรงกับชื่อตู้ที่กรอก".

### 6.6 Accessibility and input

- Editors support Dynamic Type; the drawing does not scale with Dynamic Type (fixed document).
- `SLDScreen` exposes an accessibility summary: transformers, MDBs, PV, and the missing and condition lists as text.
- Number fields accept Thai and Arabic digits (normalise with the same cleaning the other number fields use).

### 6.7 Performance budget

| Step | Budget (iPhone 12) |
|---|---|
| `SLDInput(job:)` + layout + sketch, sample job | < 5 ms |
| same, large sample (3 TR, 9 MDB, 8 feeders, 8 inverters) | < 20 ms |
| first render of the large sheet at fit | < 150 ms |

Rebuild on every change of `job.values` or modules, debounced 150 ms, off the main actor (`Task.detached`) since
SurveyCore types are `Sendable`.

## 7. PDF and Excel

- PDF: a new page "แผนภาพเส้นเดียว (Single Line Diagram)" after the A3 page, A3 landscape (1190 × 842 pt), the
  sketch scaled to fit with the title strip and footer of the report. If the scale drops below 0.45, split per the
  answer to the open question (default for now: one page per transformer plus the expanded MDB on its own page).
- Excel: the sheet PNG (`PDFRenderer.png`) placed on the electrical sheet under the transformer table.
- Both carry the footer "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง".

## 8. Tests

| Target | Test |
|---|---|
| SurveyCoreTests | old `Transformer` JSON without `breakers` decodes; `mdb` ↔ `breakers[k].at` stay in step |
| | old `tr0_feed = "MDB1"` maps to index 0 when names are empty |
| | `shiftTransformerAnswers` moves every new `tr<i>_*` key |
| | `SLDRatings` values in §5.2 |
| | `SLDInput` from the two fixtures: missing lines equal the prototype's list word for word |
| | layout: large fixture width, no two breaker label boxes overlap, every line endpoint touches a symbol |
| | `SLDDrawing.sketch(...).svg()` equals `Fixtures/sld_sample.svg` and `sld_large.svg` |
| PDFReportTests | report with SLD page renders, page count rises by 1 (sample) |
| ExcelExportTests | SLD image present on the electrical sheet |
| UI (manual, both devices) | checklist in §10 |

Fixtures: convert `img/sld_form_sample.json` and `img/sld_form_large.json` to `Job` JSON with a small script
(`Tests/SurveyCoreTests/Fixtures/`).

## 9. Delivery plan

| PR | Content | Size |
|---|---|---|
| 1 | Models: `BreakerInfo`, `EquipmentCondition`, `Transformer.breakers`, decoding, `shiftTransformerAnswers`, WebBackup | S |
| 2 | Schema + Progress: required fields, missing lines | S |
| 3 | `SLDRatings`, `SLDInput` + tests | M |
| 4 | `SLDLayout`, `SLDSymbols`, `SLDDrawing` + snapshot tests | L |
| 5 | Editors: BreakerEditor, TransformerPlate, ConditionPicker, feed picker | M |
| 6 | `SLDScreen` (iPad + iPhone), `SLDPreviewCard`, zoom/pan, share | M |
| 7 | PDF page(s) and Excel image | S |
| 8 | Web app: preserve and later edit the new keys | S / M |

Each PR builds for iOS in Xcode (SurveyUI compiles only with UIKit) and passes `swift test` on macOS.

## 10. Done when

- [ ] The sample job on an iPad and an iPhone draws the same as `img/sld_form_hv.png` and `img/sld_form_lv.png`.
- [ ] The large job scrolls and zooms smoothly on an iPhone SE-size screen, landscape and portrait.
- [ ] Blank fields show `?` in red and appear in "ข้อมูลที่ขาด"; filling one removes it on the next redraw.
- [ ] Renaming an MDB updates the drawing, the feed picker and the missing list.
- [ ] Old jobs open without data loss; web backup round-trips the new fields.
- [ ] PDF and Excel contain the diagram with the footer line.

## 11. Open questions (from the design spec, blocking only where noted)

1. Large stations: one wide sheet or one PDF page per transformer? (blocks PR 7 page split; default above)
2. Do PV and B1 panels always connect at TR1's feed MDB, or does the form need a "PV ต่อที่ตู้" picker? (PR 3)
3. Is 1.25 × rated current the breaker rule for inverters and the PV incomer?
4. For กันย้อนแรงสูง, which equipment and ratings does กฟภ. expect on the SLD?
5. Should DOF, lightning arrester and grounding also get a condition field?
