# Auto Single Line Diagram (SLD)

**Status:** Updated 2026-10-01 to match the A3 wide page and the SLD page design (`docs/ui/survey-sld/`). Level 1 is being built on `main` (`TCRoofKit/Sources/TCRoofCore/SingleLine*.swift`).
**Swift dev spec:** [`single-line-diagram-swift.md`](single-line-diagram-swift.md)
**Page design and task:** `docs/ui/survey-sld/CLAUDE_CODE_TASK.md`, `preview.png`, `preview-hv.png`, `diagram-lv.svg`, `diagram-hv.svg`
**Builds on:** [`auto-drawing.md`](auto-drawing.md) (same `Sketch` pipeline and drawing rules)

The SLD is generated from the survey. The surveyor never draws; every edit in A1 / A3 / A4 / B-sections redraws it.

| Level | Source | Reference |
|---|---|---|
| **1. From the survey as it is (v1)** | A1, A3 (meter, transformers, boards, breakers), A4, B1, B2, B4, B5 | `docs/ui/survey-sld/diagram-lv.svg`, `diagram-hv.svg` (the older prototype `img/sld_form.py` is superseded) |
| 2. Detailed MDP (later) | level 1 plus feeder cables, conduits and loads per breaker | `img/sld.py` |

## Drawing style

- **Upstream (PEA style):**
  - HV line with `))` breaks, labelled `ระบบจำหน่าย กฟภ. {meterKV} kV, 3Ø 3W, 50 Hz`
  - HV protection, then the PEA meter `kWh`, then the customer HV bus with one drop per transformer
  - Each drop: switch, LA branch, Δ/Y transformer with grounded neutral
- **HV protection follows A3 `hvProtection`:** DO fuse / DS / VCB. The label is `Drop Out Fuse / Disconnecting Switch` for DO fuse and DS. VCB is allowed and drawn with its own symbol and label. The older rule "no VCB/52" is dropped because A3 asks for it.
- **LA:** drawn only when `hasLA == true`. When it is not answered, the drawing shows red `LA ?`.
- **Downstream (Thai MDP style):**
  - Boards: dashed boxes titled with the on-site name
  - Breakers: arc symbol with the label stack `{MCCB|ACB},{poles}` / `{at}AT` (underlined) / `{af}AF` / `IC {ic} kA` / brand / `สภาพ: …`
  - Draw-out marks on ACB mains
  - Numbered outgoing breakers, each ending in a black load block
- **Colours:**
  - Existing equipment: black
  - New PV equipment: blue, marked `(ใหม่)`
  - Control lines: dashed blue
  - Missing values: red `?`
  - Condition text: ดี green, พอใช้ amber, ชำรุด red

## Level 1 — generated from the survey (v1)

| กันย้อนแรงต่ำ (default) | กันย้อนแรงสูง |
|---|---|
| `docs/ui/survey-sld/diagram-lv.png` | `docs/ui/survey-sld/diagram-hv.png` |

### Data it reads

No new form fields are needed for level 1. The A3 wide page already records everything. It keeps the old keys and adds the new values inside `Transformer`.

**Meter (A3):**
- `meterNo`
- `meterKV` (0.4 / 22 / 33)
- `meterPhase`
- `meterCA`
- `meterRate`
- `meterCT`

**Transformer (A3, one `Transformer` in `trafos`, up to 5):**

| Value | Stored in |
|---|---|
| kVA | `Transformer.kva` |
| type (oil / dry), voltage, vector group, %Z | `type`, `voltage`, `vectorGroup`, `impedance` |
| brand, serial, year | `brand`, `serial`, `year` |
| HV protection, LA | `hvProtection` (DO fuse / DS / VCB), `hasLA` |
| condition + note | `condition` (ดี / พอใช้ / ชำรุด), `conditionNote` |
| boards | `boards: [Board]`. Old jobs fall back to `resolvedBoards` built from `mdb[]`. |

**Board (A3):**
- `name`: the on-site name (MDP-1, SDB ระบบกรอง, MDB-ADMIN …); no fixed MDB1…MDB6
- `isMain`
- main breaker: `mainType` (ACB / MCCB), `at`, `af`, `icu`, `poles`, `brand`
- `condition`, `conditionNote`
- `location`
- `breakers: [Breaker]`

Board k = 0 is the main board. Its name, location and front photo stay in `tr{i}_feed`, `tr{i}_feedLoc` and `tr{i}_feedPhoto`. Every board's AT is mirrored to `Transformer.mdb[k]`, so Excel, the old PDF table and the A2 symbols read the same values as before.

**Breaker (A3):**
- `at`, `af`, `ic`, `poles`, `brand`
- `target` (where it feeds, e.g. `ตู้ไฟฟ้า โรงสูบน้ำ (B1)`)
- `condition`
- `count` (sub-boards group equal breakers, e.g. `100 A × 2`)

**Other sections:**

| Value | Section and id |
|---|---|
| PV size | A1 `capacity` (kWp) |
| Inverter count | B2 `.inverter` modules, sum of `inverterCount` |
| Building loads | B1 `.panel` modules: `loadKW`, `loadTime`, matched to a breaker through its `target` |
| Zero export position | B4 `.backfeed` `level` (`กันย้อนที่แรงต่ำ` / `กันย้อนที่แรงสูง`), `pole` (`เสาเดิม` / `เสาใหม่`) |
| FTS and emergency button | B5 `.fts` module present |
| Flood at the connection point | A4 `FloodCheck.state`, `level`, `minCm` |

**New optional answers (SLD page only):**
- `sldAttach` = "1": add the SLD page to the survey PDF
- `sldTransformer`: index of the transformer the PV connects to (default 0)
- `sldBoard`: board id (default: that transformer's main board)

### Survey value → drawing

| Survey value | Drawn as |
|---|---|
| meter fields | `kWh` circle with `PEA METER {meterNo}` / `CA {meterCA} · อัตรา {meterRate}` / `รับไฟ {meterKV} kV {meterPhase} · CT {meterCT} A` |
| each transformer | drop off the HV bus, with a text block: `TX{n} {OIL IMMERSED / DRY TYPE}`, `{voltage} V`, `{vectorGroup}, Z={impedance}%`, `{kva} kVA`, `{brand} · SN {serial} · ปี {year}`, `สภาพ: {condition} — {note}` |
| transformer with more than half its nameplate missing | collapsed to `{kva} kVA` + red `ป้ายพิกัดยังไม่ครบ` |
| boards of a transformer | the main board plus sub-boards as branches (dashed boxes), each ending in `ปลายสาย TX{n} · {location}` |
| connection board (`sldTransformer` / `sldBoard`) | drawn large and full width: main breaker (draw-out marks for ACB), `MAIN BUS {at} A, 3Ø 4W, 400/230 V`, numbered outgoing breakers with load blocks `ตู้ไฟฟ้า / {target} / โหลด {loadKW} kW @{loadTime}` |
| PV (A1 + B2) | blue PV breaker at the bus end → `SMDB-PV (ใหม่)` → one breaker per inverter → inverter (=/~) `อินเวอร์เตอร์ {n} × {kW} kW (B2)` → `ตู้ FTS ตัดวงจร DC (B5)` → `แผง PV รวม {kWp} kWp (A1)` |
| B4 แรงต่ำ | `CT กันย้อน (ใหม่)` on the connection board incomer, box `รีเลย์กันย้อนแรงต่ำ / Zero export (B4)` |
| B4 แรงสูง | `CT/VT แรงสูง (ใหม่)` under the PEA meter, box `รีเลย์กันย้อนแรงสูง / {pole} (B4)` |
| B5 | `ปุ่ม Emergency`, dashed to the FTS |

**Zero export control:** in both modes the relay's dashed control line goes to the inverters (`สั่งควบคุมกำลังผลิต`), never to a breaker. The toggle on the SLD page writes B4 `level`. If the job has no B4 section, the toggle is a preview only.

### Calculations

All constants live in one place. Every value that is not survey data is listed under `ค่าสมมติ`.

| Value | Rule | Example |
|---|---|---|
| Inverter kW | B2 per-inverter kW when that field exists; until then A1 `capacity` ÷ inverter count, rounded up to a standard size (5 … 110 kW) — assumed | 120 kWp ÷ 2 → 60 kW |
| Inverter breaker | `P / (√3 × 400)` × 1.25, next standard frame; AF = next frame ≥ AT | 60 kW → 86.6 A → 125 AT |
| PV total breaker | same rule on the sum | 2 × 60 kW → 250 AT |
| Short circuit at the connection bus | `Isc = kVA / (√3 × 0.4 kV × Z)`, infinite HV source, no cable impedance; %Z missing → 4 % (assumed) and a blocking item | 630 kVA, 4.14 % → 22.0 kA |
| Required IC (PV breaker) | next standard kA ≥ Isc (10 / 15 / 25 / 36 / 50 / 65 / 85) | 22.0 kA → 25 kA |
| Breaker check (main + outgoing on the connection bus) | ✓ IC ≥ 1.25 × Isc · ! Isc ≤ IC < 1.25 × Isc (`เผื่อน้อย`) · ✗ IC < Isc (`ไม่พอ`) · ? no IC (`ยังไม่รู้`) | 50 ✓, 36 ✓, 25 !, — ? |
| Cables, busbar | lookup table by breaker AT (copper CV 0.6/1 kV in conduit) — assumed; default 20 m per run, summed | 125 A → CV 4×35 + G16; 250 A → CV 4×120 + G25; busbar 25 × 5 |
| Flood | `FloodCheck.minCm`; the SMDB-PV and relay must be at least that high | 80 cm + 50 → 130 cm |

### Missing items

- **Blocking** (`ต้องเก็บก่อนออกแบบ`):
  - IC / AF / brand of any breaker on the connection bus
  - %Z of any transformer whose boards are drawn
  - main breaker AT / IC of the connection board
  - A1 `capacity`
  - B2 `inverterCount`
- **Non-blocking** (`ข้อมูลที่ขาดอื่นๆ`): everything else printed as `?` (nameplate, cable, B1 load …).
- The SLD page total `ยังขาด {n} จุด` = blocking + non-blocking.
- **Navigation:** each item links to the page where it is entered. Tapping it opens A3 on that transformer / board / breaker, or opens the B-section.
- **Condition summary:** `ชำรุด {n} · พอใช้ {n}`, with the list of items that are not ดี.

### Page and outputs

- **SLD page:**
  - opened from the A3 button `สร้าง Single Line Diagram →`
  - drawing with zoom 35–100 %, pinch and pan, tap targets
  - side panel: PV data, breaker IC check, blocking list, flood card, other lists
  - bottom bar: `แก้ข้อมูลใน A3` / `ส่งออก PDF (A3)` / `แนบในรายงาน`
- **PDF:**
  - one A3 landscape page: vector drawing, title block, PV table, breaker check table
  - added to the survey PDF after the A3 section when `sldAttach` = "1"
  - footer on every output: `สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง`
- **Excel:** not changed in v1 (open question 5).

## Level 2 — detailed MDP (later, optional inputs)

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

## Open questions

1. ~~Do PV and B1 panels always connect at TR1's main board?~~ Answered: the SLD page has `เชื่อมต่อ PV ที่ตู้นี้` (`sldTransformer` / `sldBoard`); the default is TR1's main board.
2. Is 1.25 × rated current the team's breaker rule for inverters and the PV incomer? (used now, marked in code)
3. Cable size table and 20 m run length are assumptions. Does the team have a standard table to replace them?
4. For กันย้อนแรงสูง, which equipment and ratings does กฟภ. expect on the SLD (recloser / LBS, relay 32R, CT/VT ratios)?
5. Should the SLD image also go on the Excel electrical sheet? (not in v1)
6. Large stations: v1 fits one A3 page with zoom in the app. Split the PDF per transformer when the scale gets too small?
7. Should DOF / DS / VCB, LA and grounding also get a condition field?
8. Keep the Thai breaker symbol (arc) everywhere, or allow the IEC symbol as a setting?
