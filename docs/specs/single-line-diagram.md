# Auto Single Line Diagram (SLD) — existing system

**Status:** Draft, 2026-09-29 · **Prototype:** `img/sld_existing.py` → `img/sld_existing.png` (run from `img/`) ·
**Builds on:** [`auto-drawing.md`](auto-drawing.md) (same `Sketch` pipeline, same rules)

**Scope:** the waterworks' existing electrical system only, from the PEA supply down to the MDB feeders. No PV, no
inverters, no export relay. The drawing follows the style of a Thai MDP drawing: dashed MDB enclosure, breakers drawn
as an arc with `3P AT/AF`, CT and DP meter with pilot lamps, numbered feeders, cable text written along each feeder and
black load blocks.

![](img/sld_existing.png)

Sample values come from the MDP sheet the team shared. The transformer size (250 kVA) is a sample.

## Inputs

The surveyor copies what is written on the panel nameplate, the breakers and the cables: sizes and text only, no
choices to design.

### Upstream (A3, exists today)

| Drawn item | Field | Note |
|---|---|---|
| Grid voltage | new optional `gridKV` | default 22 kV, printed as ค่าสมมติ when blank |
| Transformer name, kVA | `trafos[i].kva` (+ name `TR1`…, derived from order) | |
| PEA meter number | `meterNo` | |

### MDB schedule (new, one per MDB in A3)

| Field | Type | Example | Drawn as |
|---|---|---|---|
| `name` | text | MDP | label at the top-right of the enclosure |
| `icKA` | number (kA) | 25 | `IC ไม่น้อยกว่า 25 kA` |
| `main` | poles, AT, AF | 3, 300, 400 | main breaker |
| `ctRatio` | text | 300/5A | `3xCT 300/5A`; hidden when blank |
| `meterName` | text | DP2 | DP box fed from the CTs; hidden when blank |
| `pilotLamps` | bool + fuse text | yes, 3x6A | fuse → ⊗ x3 |
| `busbar` | text | 4x300A. Cu. BUSBAR W/GROUND BUS | label above the bus |
| `feeders[]` | rows (below) | 6 rows | numbered columns |
| `ground` | text | 1x35-IEC01 ø20 PVC. | N/G bar, ground conductor, ground rod |

### Feeder row

| Field | Type | Example |
|---|---|---|
| `poles` | 1 / 2 / 3 | 3 |
| `at`, `af` | number | 100, 100 |
| `cable` | text | 4x50,1x10-IEC01 |
| `conduit` | text | ø50mm. UPVC / IN WIRE WAY |
| `load` | text | LC11 |
| `location` | text | 1st FL. |
| `spare` | bool | a spare row draws the breaker and `SPARE`, no cable or load |

Numbers are typed with the same `NumberInput` rules as the rest of the form. Feeder order is the order entered; the
number above each column is its position.

## Derived values and checks (printed under the diagram, never errors)

| Value | Rule | Example |
|---|---|---|
| Transformer full-load current | kVA × 1000 ÷ (1.732 × 400 V) | 250 kVA → 361 A |
| Main vs transformer | note when main AT > full-load current × 1.25 or < 0.8 × | 300 AT vs 361 A, no note |
| AT ≤ AF | note on any breaker where AT > AF | |
| Feeder count | total, in use, spare | 6 (5 + 1 spare) |
| Sum of feeder AT | in-use feeders only, shown for reference (diversity not applied) | 430 AT |

## Layout rules

- Top to bottom, centre column: grid ▽ → drop-out fuse → transformer (two circles) → PEA kWh meter → dash-dot line
  into the enclosure → main breaker → CT → busbar.
- Pilot lamps and DP meter branch right from the incoming line above the main breaker; the CT signal line returns to
  the DP box.
- Busbar spans the feeder columns; columns are spaced evenly across the enclosure. The incoming line joins the bus at
  the centre column position, never on top of a feeder label.
- Each feeder: number above the bus, breaker with `3P AT/AF` to its right, line down through the enclosure edge, cable
  and conduit text rotated −90° left of the line, black load block, load name (bold) and location below.
- N/G bar and ground rod sit left of feeder 1; the ground text is rotated along the ground conductor.
- More than 10 feeders: wrap into a second row under the first bus drawn as a continuation (`…ต่อ`), or reduce column
  spacing down to a minimum 60 pt, whichever keeps labels readable.
- Several MDBs on one transformer: one enclosure per MDB side by side, fed from a common LV line. One diagram page per
  transformer.
- Footer: assumptions (400/230 V, sample values) and the standard line "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง".

## Swift

| File (`SurveyCore/Drawing/`) | Contents |
|---|---|
| `SLDInput.swift` | `struct SLDInput { gridKV; transformers: [TransformerInput] }`, `struct MDBSchedule`, `struct FeederRow`, `Breaker(poles, at, af)`; `init(job:)`, `missing`, `assumed` |
| `SLDGeometry.swift` | column x positions, bus extent, enclosure rect, checks (`[SLDNote]`) |
| `SLDDrawings.swift` | `SLDGeometry → Sketch`; symbols `breaker`, `ct`, `lamp`, `meter`, `groundRod` as `DrawOp` helpers |

Schema: add `mdbs: [MDBSchedule]` to each A3 transformer entry, all fields optional so older jobs decode. UI: an MDB
editor under A3 with a feeder table (add / reorder / mark spare). PDF: its own page after A3, plus a preview card on
the A3 page. Tests: the sample above (6 feeders, 1 spare), 1 and 14 feeders, blank CT/DP (hidden), two MDBs, AT > AF
note, and snapshot SVGs.

## Open questions

1. One MDB per diagram, or should one transformer with several MDBs share a page?
2. Is the "main vs transformer current" note useful, or should the SLD show values only?
3. Do SMDBs downstream of the MDB (LC11 etc.) need their own sub-diagram later, or does the load block end the drawing?
4. Keep the Thai breaker symbol (arc) everywhere, or allow the IEC symbol as a setting?
