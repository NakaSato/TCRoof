# B2 พื้นที่ติดตั้งอินเวอร์เตอร์ — Swift dev spec (iPad + iPhone)

**Status:** Draft for development, 2026-10-01, from the canvas page `iPadB2` (ขั้น 6/13)
**Task:** [`CLAUDE_CODE_TASK.md`](CLAUDE_CODE_TASK.md) (what to build, in order)
**Design reference:** `preview.png` (outdoor), `preview-indoor.png`, `preview-overflow.png`; plan close-ups `plan-outdoor.png`, `plan-indoor.png`, `plan-overflow.png`; source `iPadB2.dc.html`. Its `<script type="text/x-dc">` is the reference implementation of every formula below.
**Equipment data:** `equipment-catalog.json` (the canvas global spec `TCR_SPECS`, version 2026-09-30)
**Icons:** `icons/` (see §8)
**Targets:** `TCRoofKit` (TCRoofCore / SurveyUI / PDFReport / ExcelExport)
**New dependencies:** none

## 1. What the page does

The surveyor photographs the inverter area, draws its boundary on the photo, and enters the measured size. They then pick the Growatt inverters. The app then:

1. chooses the cabinets, breakers, cables, AC tray and AC cable ladder from the catalog;
2. draws a dimensioned plan of the inverter station, outdoor (a covered station with columns) or indoor (wall-mounted);
3. checks that the equipment fits and that the walkway in front is at least 1.20 m;
4. checks the total inverter kW against A1.

Nothing is designed by hand. The surveyor enters only measurements and the inverter sizes.

## 2. Data (module `.inverter`, section B2)

Existing fields keep their ids and meaning:

| Field | Now | B2 page |
|---|---|---|
| `photoArea` | photo, required | `ภาพพื้นที่ *` tab |
| `photoDetail` | photo, optional | `ภาพระบุขอบเขต` tab; the same photo with the drawn boundary |
| `sizeLWH` | text `"6x2"` | still written, as `"{W} x {L} x {H}"` from the numeric fields, so Excel `K{h+13}`, PDF and `Progress` keep working |
| `inverterCount` | number | still written = number of inverters in `invSizes` (SLD, Flood and Excel read it) |
| `invNote` | note | replaced on the wide page by the live check; kept for `groupPage` |

New fields (all optional in `Schema`, so B2 completion counts as before):

| Field | Kind | Meaning |
|---|---|---|
| `invAreaW`, `invAreaL`, `invAreaH` | number (m) | measured width ก, length ย and height ส; W 1.5–5.0 (step 0.1), L 4.0–16.0 (step 0.5); H is typed |
| `invBoundary` | shapes (`SiteShape` polygon + edge labels) | boundary drawn on `photoDetail`; the edge labels are the typed lengths |
| `invSite` | choice `out` / `in` | ภายนอกอาคาร (station with columns) / ภายในอาคาร (wall-mounted) |
| `invSizes` | text, comma list of kW, e.g. `"60,60"` | the inverters, 1–8, each a catalog size |
| `invSpans` | text, e.g. `"2.5,2.25,2.25"` | outdoor column spans set by the user (all but the last); nil = automatic |
| `invTrayW`, `invLadderW` | number (mm) | user increase over the calculated minimum; nil = minimum |
| `invDetail` | textarea | `รายละเอียดเพิ่มเติม` (e.g. existing slab, roof, cabinets to move) |

The zero export choice on this page reads and writes B4 `level` (`กันย้อนที่แรงต่ำ` / `กันย้อนที่แรงสูง`), the same field the SLD page uses. It is not stored in B2.

**Old jobs:** `sizeLWH` "6x2" or "6x2x3" is parsed into `invAreaW/L/H` on first open (`W x L` order as labelled). `inverterCount` without `invSizes` seeds that many inverters of the smallest catalog size, marked as assumed until the surveyor picks sizes.

## 3. Equipment catalog (`TCRoofCore/EquipmentCatalog.swift`)

A single source for B2, the SLD (per-inverter kW and Imax) and C1 (PV modules), the same role as the canvas `TCR_SPECS`.

```swift
public struct EquipmentCatalog: Codable, Sendable {
    public struct Inverter: Codable, Sendable { kw: Int; brand, model: String; imax, sac: Double; mppt, vdc: Int; w, h, d: Int /* mm */; kg: Double; ip: String }
    public struct PVModule: Codable, Sendable { id: String; w: Int; model: String; l, wd, t: Int; kg, voc, isc, vmp, imp: Double; def: Bool? }
    public struct ACCabinet: Codable, Sendable { upTo: Int; w, h, d: Int; busbar: String }
    public struct DCCabinet: Codable, Sendable { mpptUpTo: Int; w, h, d: Int; strings: Int }
    public struct Box: Codable, Sendable { w, h, d: Int }
    public struct Rules: Codable, Sendable { cbFactor: Double; cbStd: [Int] }
    public var version: String; inverters: [Inverter]; pv: [PVModule]
    public var cabinets: (ac: [ACCabinet], dc: [DCCabinet], meter: Box, sem: Box)   // as a nested Codable struct
    public var rules: Rules
    public static let bundled: EquipmentCatalog     // Resources/equipment-catalog.json
}
```

- Ship `equipment-catalog.json` as a TCRoofCore resource. This needs `resources: [.process("Resources")]` on the target.
- A later settings screen may override it. Keep the version string in the PDF footer.
- **Lookups:**
  - `inverter(kw)` falls back to a generic `{kw} kW` spec: `imax = kW·1000/(√3·400)`, 870 × 580 × 290, 6 MPPT.
  - AC cabinet: by inverter count (≤ 2 → 900 wide, ≤ 4 → 1000, ≤ 8 → 1200).
  - DC cabinet: by MPPT count (≤ 4 → 600, ≤ 6 → 700, ≤ 10 → 800).
  - Meter and SEM boxes: 630 wide.

## 4. Calculations (`TCRoofCore/InverterStation.swift`)

All pure functions, unit-tested. Numbers in brackets are the design sample (2 × 60 kW, 9.5 × 2.5 m).

| Value | Rule |
|---|---|
| inverter breaker | `I = imax`; AT = first `cbStd` ≥ I × `cbFactor` (1.25); AF = max(100, AT) [96.6 A → 125 AT] |
| inverter AC cable | table by AT: 80 → `4×25+G10` (OD 30 + 7), 125 → `4×35+G16` (33 + 8), 160 → `4×50+G16` (37 + 8), 200 → `4×95+G16` (47 + 8), 250 → `4×120+G25` (52 + 10); OD in mm, including sheath |
| AC tray (inverters → AC-DB) | min width = next of 100 / 150 / 200 / 300 / 400 / 450 / 500 / 600 mm ≥ 1.2 × Σ cable OD; the user can step it up, never below the minimum [82 × 1.2 = 98 → 100] |
| feeder (AC-DB → injection point) | `Itot = Σ imax`; AT = next of 100 … 1250 ≥ 1.25 × Itot [193.2 → 250] |
| feeder cable | single-core Cu table (mm², A, Ø mm): 25/100/11.5, 35/125/12.5, 50/150/14, 70/190/16, 95/230/18, 120/270/20, 150/310/22, 185/355/24.5, 240/420/27.5, 300/480/30.5; smallest size with `A × runs ≥ AT` for runs 1…4; ground G = 10 (≤ 100 A), 16 (≤ 200), 25 (≤ 400), 35 (≤ 500), 50 (≤ 800), else 70; label `4×1C 120 + G25`, or `2×(4×1C 120) + G35` for 2 runs (60 + 60 + 80 kW → 500 AT) |
| AC cable ladder | min width = next of 200 / 300 / 400 / 500 / 600 / 750 / 900 mm ≥ (8 × runs − 1) × Ø + 50 (cables spaced one diameter apart); user may step up [190 → 200] |
| CB summary | group equal ATs: `2 × 125AT`, or `2×125+1×200 AT` |
| total kW | Σ `invSizes` compared with A1 `capacity`: equal → `= A1 ✓` (green), else `≠ A1 {capacity}` (red) — see open question 1 |

**Outdoor station (`invSite = out`):**
- **Row:** the equipment stands in one row along the back wall, in this order and with these clear gaps:
  - AC-DB-01 (depth 0.45) — gap 0.24
  - METER-DB-01 (0.28) — gap 0.45
  - for each inverter: INVERTER No.i (catalog depth) — gap 0.47 — DC-DB-0i (0.28) — gap 0.47 before the next inverter
- **Row length:** `row = acW + 0.24 + meterW + 0.45 + Σ(invW + 0.47 + dcW) + (n − 1) × 0.47` [6.77 m].
- **Minimum room:** length = `row + 2.25`, rounded up to 0.5 m; width shown as 2.5 m [9.5 × 2.5 m].
- **Columns:** automatic spans follow the team's stations (`docs/specs/cad-export-dxf/reference/inverter-station`, 2026-10-27): end spans 2.0 and the inside ones equal, none over 2.5, `k = ceil((L − 4)/2.5)` inside spans (6.0 → 2.00 · 2.00 · 2.00, 9.0 → 2.00 · 2.50 · 2.50 · 2.00); where they would come out under 2.0, one column fewer with 2.5 inside and the ends evened out [2.25 · 2.50 · 2.50 · 2.25]; up to 5 m two equal spans (one up to 2.5). Until 2026-10-27 the rule was `2.5, k × (L − 5)/k, 2.5`.
  - The user edits the spans as chips (select, − / + 0.05 m, 0.5–6.0 m), `+ เพิ่มช่วง` (max 10), `ลบช่วงที่เลือก`, `EQ เท่ากัน`, `คืนค่าอัตโนมัติ`.
  - The last span is always `L − Σ others` and is read-only. It must be ≥ 0.5 m, else the chip turns red and the status reads `ระยะช่วงเสารวมเกินความยาวห้อง`.
- **Frame and tray band:**
  - The band starts 1.05 m from the left wall and 0.17 m from the back wall.
  - Band length `0.10 + used + 0.30`; depth `max(0.40, tray/1000 + 0.20)`.
  - Frame posts at both edges: `max(3, round(length/1.2) + 1)` posts per edge.
  - Tray drawn inside, labelled `AC PERFORATED TRAY {w}x100 WITH COVER`.
- **Equipment:** starts 0.10 m into the band, directly below it.
- **Walkway:** `W − (bandBottom + 0.45)` must be ≥ 1.20 m [1.48 ✓]. It is shown red when short.
- **Door:** 1.30 m, bottom-left, with a swing arc.

**Indoor (`invSite = in`):**
- **Row:** the equipment hangs on an existing wall in one row:
  - AC-DB-01 — 0.24 — METER-DB-01 — 0.37 — SEM-DB (0.28) — 0.46
  - then INVERTER / DC-DB pairs with 0.46 gaps
- **Minimum wall length:** `used + 0.60`, rounded up to 0.5 m [8.5 m]. The label is `ผนังยาวขั้นต่ำ`.
- **Steel frame:** 0.20 m deep, 0.05–0.25 m off the wall. Posts go at the gaps between groups.
- **Tray:** width `min(0.14, tray/1000)` inside the frame.
- **Riser:** a ladder riser from AC-DB-01, labelled `TO INJECTION POINT · AC CABLE LADDER {w}x100 (NON COVER)`.
- **Walkway:** equipment depth is taken as 0.85 m, so walkway = `W − 0.85` ≥ 1.20 m.
- **Inverter labels:** `GROWATT {model}`.

**Both:**
- **Too short:** when the minimum length exceeds `L`, the plan draws the overflow as a red dashed area with `เกินพื้นที่ {x} ม.`. The fit pill reads `พื้นที่ไม่พอ ✗`.
- **Status line:**
  - `ครบช่องบังคับแล้ว · พื้นที่พอสำหรับ {n} เครื่อง`
  - `พื้นที่จริงสั้นไป {x} ม. สำหรับ {n} เครื่อง`
  - `ทางเดินหน้าตู้แคบกว่า 1.2 ม.`
  - `ระยะช่วงเสารวมเกินความยาวห้อง`

## 5. Drawing (`TCRoofCore/InverterStationDrawing.swift`)

- **Engine:** build a `Sketch` from the same numbers, drawn in metres × scale, with the plan in a 1470 × 752 frame. Use the stroke styles below, matching the design.

| Layer | Style |
|---|---|
| available area / walls outline | 1 pt, dash `22 5 3 5` (dash-dot) |
| outdoor walls | double line (±2 pt) |
| columns | 22 pt square, white fill, 12 pt inner square |
| frame posts | 18 × 14 pt (indoor 16 × 14) with two inner verticals |
| equipment boxes | 1.2 pt, white fill; cabinets labelled `SOLAR` / `{name}`; inverters split 55 % / 35 % with a base line and the model |
| grid bubbles | r 20, numbered 1…, above the plan with a leader |
| dimensions | 1 pt line, 1.4 pt 45° ticks, text 20 pt above |
| door | 3 pt leaf, 1 pt dashed arc `12 8` |
| existing wall (indoor) | 0.12 m hatched band, `EXISTING WALL` |
| overflow | red fill 10 %, 2 pt red dash `8 5` |
| text | Arial Narrow (fallback Arial / Helvetica), black; walkway dim red when short |

- **Dimension chains:**
  - overall L on top, then per-span dims (outdoor)
  - equipment chain (every width and gap) under the row
  - band depth, walkway, room width
- **Ladder section:** titled `รูปตัดราง AC ออกจาก SOLAR AC-DB-01`, bottom-right.
  - The U-shaped ladder at its width, with 4 × runs cables as circles with a black core, labelled L1 L2 L3 N.
  - `D` marks between the first cables.
  - Caption `CABLE LADDER {w}x100 (NON COVER) · {cable} · เว้นระยะ D = Ø สาย`.
  - Skip it if it would be drawn below 35 % scale.
- **Outputs:** the same `Sketch` goes to the page (`SketchView`), the PDF (vector) and Excel (PNG, open question 3).

## 6. UI (`SurveyUI/InverterPageWide.swift`)

iPad landscape (same shell as the A1–A4 wide pages; `groupPage` stays for portrait / iPhone):

**Left column (~420 pt):**
1. **Photos:**
   - `ภาพพื้นที่ *` with a segmented control `ภาพพื้นที่ ✓` / `ภาพระบุขอบเขต`.
   - On the boundary photo:
     - `วาดขอบเขต` (tap points, close on the first point)
     - `↶ ย้อน`
     - `×` to clear
     - hint chip `วาดขอบเขตแล้วใส่ระยะบนเส้น`
   - Tapping an edge label types its length (m). The polygon is drawn dashed teal with filled label chips.
2. **`ขนาดพื้นที่ที่มีจริง (วัด) *`:**
   - aside `ก × ย × ส (ม.) · แปลนวาดตามค่านี้`
   - steppers ก (W) and ย (L), field ส (H)
3. **`ระยะช่วงเสา (ม.) *`** (outdoor only):
   - span chips with − / +, the read-only last chip, and the summary `{n} ช่วง · รวม {L} ม. · อัตโนมัติ ✓`
   - buttons `+ เพิ่มช่วง`, `ลบช่วงที่เลือก`, `EQ เท่ากัน`, `คืนค่าอัตโนมัติ`
4. **`รายละเอียดเพิ่มเติม`:** textarea.

**Right column:**
1. **Plan card:**
   - title `แปลน Inverter Station` / `แปลนติดตั้งในอาคาร (Top view)`
   - segmented `ภายนอกอาคาร` / `ภายในอาคาร`, and the fit pill (`พื้นที่พอ ✓` / `พื้นที่ไม่พอ ✗`)
   - the drawing: zoomable; tap opens full screen
   - two steppers: `Tray อินเวอร์เตอร์ → AC-DB {w} มม.` and `Ladder ออกจาก AC-DB {w} มม.`, each with `ขั้นต่ำตามคำนวณ` or `ขั้นต่ำ {min} · ปรับเพิ่มเอง`. The − button is disabled at the minimum, the + button at the maximum.
2. **`คำนวณห้องและแบบให้เอง`:**
   - `กันย้อน (B4) *` แรงต่ำ / แรงสูง
   - `อินเวอร์เตอร์ Growatt *` `{n} / 8 เครื่อง` with `+ เพิ่มเครื่อง` (copies the last size; `ครบแล้ว` at 8)
   - one row per inverter:
     - number badge
     - kW stepper through catalog sizes (40 / 60 / 80 / 125)
     - model
     - `CB {at}AT · {cable}`
     - `×` remove (hidden when only one)
   - summary strip: `กำลังรวม` (green when = A1, red when not), `CB อินเวอร์เตอร์`, `ห้องขั้นต่ำ` / `ผนังยาวขั้นต่ำ` (green when it fits, red when not)

**Bottom bar:** autosave, status line (§4), `บันทึกร่างตอนนี้`, `‹ ก่อนหน้า 5/13 B1 ตู้ไฟฟ้าอาคาร`, `ถัดไป 7/13 B3 ระบบน้ำล้างแผง ›`.

**Controls:** every button and stepper is at least 44 pt tall (the design's 32–36 pt steppers sit in 44 pt rows; make the hit areas 44 pt).

**Several B2 sections:** a job can have more than one B2 (one per building). Each section is its own page. The SLD sums them.

## 7. Report and export

- **PDF (`ReportLayout`, B2 unit):**
  - photos (area, boundary)
  - the plan drawing scaled to the content width
  - a table: inverters (model, kW, CB, cable), total kW, feeder AT and cable, tray and ladder widths, minimum room / wall, walkway
  - catalog version in the footer
- **Excel:** unchanged cells. `sizeLWH` and the inverter line are still filled (`ExcelExporter` lines ~134–136).
- **SLD:**
  - `SingleLine.build` reads `invSizes` for the per-inverter kW and the catalog `imax`, in place of `capacity ÷ count`.
  - This removes the SLD "inverter kW assumed" item whenever B2 has sizes.
  - The B2 feeder AT and cable become the SLD PV breaker and cable, replacing the SLD's own table.
  - Keep the SLD fallback for jobs without `invSizes`.

## 8. Icons (`icons/`)

`icons/icons.png` shows them all. Formats: `svg/`, `png/` @1x/@2x/@3x, and `B2Icons.xcassets` (PDF vector; `ui-*` are template images).

| File | Use |
|---|---|
| `b2-grid-bubble` | column grid number |
| `b2-column` | structural column |
| `b2-frame-post` | steel frame post |
| `b2-cabinet` | SOLAR cabinets (AC-DB, METER-DB, SEM-DB, DC-DB) |
| `b2-inverter` | inverter box |
| `b2-cable-tray` | AC perforated tray |
| `b2-cable-ladder-section` | ladder cross-section with L1 L2 L3 N |
| `b2-door` | door with swing |
| `b2-dimension` | dimension line with ticks |
| `b2-available-area` | dash-dot available area |
| `b2-existing-wall` | hatched existing wall (indoor) |
| `b2-over-area` | red overflow area |
| `ui-close`, `ui-draw-boundary`, `ui-check`, `ui-prev`, `ui-next` | page controls |

- **Plan drawing:** the plan and PDF must stay vector. Draw these symbols with `DrawOp` paths copying the SVG geometry; the images are a reference.
- **Asset catalog:** use it for legends, list rows and controls. Copy `B2Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/`, next to the A2 and SLD catalogs.

## 9. Tests

| Test | Expect |
|---|---|
| catalog decode | 4 inverters, 3 PV modules, cabinets, rules from `equipment-catalog.json` |
| inverter CB | 40 kW → 80 AT; 60 → 125; 80 → 200 (129 × 1.25 = 161 → 200); 125 → 250 |
| tray / ladder | 2 × 60 kW → tray 100, feeder 250 AT, `4×1C 120 + G25`, ladder 200; 60 + 60 + 80 → tray 200, feeder 500 AT `2×(4×1C 120) + G35`, ladder 400 (as `preview-overflow.png`) |
| outdoor room | 2 × 60 kW → row 6.77, room 9.5 m, spans 2.50 / 2.25 / 2.25 / 2.50, walkway 1.48 |
| indoor wall | 2 × 60 kW → used 7.75, wall 8.5 m, walkway 1.65 |
| overflow | 60 + 60 + 80 in 9.5 m → needs 12.0 m, `เกินพื้นที่ 2.50 ม.` |
| spans | the last span = L − Σ; below 0.5 → invalid; EQ gives equal spans; auto restores |
| old job | `sizeLWH = "6x2"`, `inverterCount = 2` → `invAreaW/L` parsed as labelled (ก 6, ย 2; open question 4), not clamped until edited, and 2 assumed inverters |
| writes back | `sizeLWH`, `inverterCount` stay in step with the new fields |
| snapshot | `Sketch.svg()` for the three previews |

## 10. Open questions

1. **Total kW vs A1:** the design compares inverter kW with A1 `capacity` (kWp) for equality. Should it instead check a DC/AC ratio range (for example 1.0–1.3)?
2. **Clearances:** 0.24 / 0.45 / 0.47 (outdoor), 0.24 / 0.37 / 0.46 (indoor), 1.05 m band offset, 2.25 m room allowance, 1.20 m walkway. Confirm them as the team standard.
3. **Excel:** is there room on the electrical sheet for the plan image?
4. **`sizeLWH` order:** the old label is `ก x ย x ส` with the placeholder `6x2`. Is "6x2" width 6 × length 2, or length 6 × width 2? Parse as labelled unless the team says otherwise.
5. **Other brands:** only Growatt is in the catalog. Add other brands to the catalog later without code changes?
