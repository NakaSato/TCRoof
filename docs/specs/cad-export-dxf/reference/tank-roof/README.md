> In TCRoof: only the tank-roof part of this package is here (the station, cable tray and column base files it
> describes live elsewhere). The app's tank frame, BOQ and DXF follow it: see `docs/specs/cad-export-dxf/SPEC.md`,
> "Tank-roof frame".

# TCRoof — inverter station CAD components

Extracted from drawings by Chanthawat.K:
`Internal_Inverter_Station_EXL-LV.dxf`, `Inverter.dxf`, `Inverter_EXL-HV.dxf` and `Part_1.dxf` (column base detail).
Cable trays and ladders are generated parametrically, sized from the Niedax and Excel EZ-FIT Revit content (`Electrical_Distribution_Niedax_Cable_Trays_2022.rvt`, `Electrical_Distribution_Excel_Electric_Group_EZ-FIT_Cable_Tray_2019.rvt`).
The tank-roof PV array (`Top.dxf`, `Back_Side.dxf`, `Side_View.dxf`) is covered in its own section below.

All values are in **mm**. The source DXFs are drawn in metres even though `$INSUNITS` says mm.

| Path | What |
|---|---|
| `catalog.json` | Component library: id, kind, name/nameTh, dimensionsMm, views → SVG + DXF block + source block |
| `svg/<id>-<view>.svg` | One vector symbol per component view, origin bottom-left, no background, black strokes |
| `stations/*.json` | Three station templates: structure grid, rack posts, roof heights, equipment placements in front view (x from grid 1 / first post, elevation from ground) |
| `tcroof-station-blocks.dxf` | Extracted symbols as a clean block library (`TCR_<ID>_<VIEW>`) in real mm |
| `tcroof-cable-tray-blocks.dxf` | Cable tray / ladder blocks (`TCR_TRAY_SECTION_<W>X<H>`, `TCR_TRAY_PLAN_<PERF/SOLID>_W<W>`, `TCR_TRAY_PLAN_COVER_W<W>`, `TCR_TRAY_SIDE_<PERF/SOLID>_H<H>`, `TCR_LADDER_*`), layers TRAY / TRAY-SLOT / TRAY-COVER / TRAY-HIDDEN |
| `trays/niedax.json`, `trays/excel-ezfit.json` | Manufacturer type catalogues pulled from the RVT files: every family (straight, fitting, cover, accessory, support), every type with H/W/finish, sample kg/m, and `geometryId` linking straight types to the 2D blocks |
| `trays/build_from_rvt.py`, `trays/rvt_dump.py` | Rebuild the manufacturer catalogues from the .rvt files (no Revit needed) |
| `extract_from_dxf.py` | Re-runs the extraction: `python3 extract_from_dxf.py <dir-with-dxfs> <out-dir>` (needs `ezdxf`) |
| `generate_cable_trays.py` | Regenerates the tray blocks: `python3 generate_cable_trays.py <out-dir>` (run after the extractor; edit the size lists at the top) |

## Stations
- `pwa-inverter-station-internal-80k`: wall rack 5.5 × 2.0 m against an existing wall, MAX 80KTL3 LV, AC-DB, METER-DB, SEM-DB, DC-DB
- `pwa-inverter-station-shelter-125k`: steel shelter 6.0 × 2.5 m (grid 1–4 / A–B), mono-pitch roof 3.0 → 2.75 m, MAX 125KTL3-X LV, 2 × T8
- `pwa-inverter-station-shelter-125k-40k`: shelter 9.0 × 2.5 m (grid 1–5), MAX 125KTL3-X LV + 40KTL3-X, two DC-DBs, 3 × T8

## Cable trays and ladders
Rebuild order: `extract_from_dxf.py` → `trays/rvt_dump.py` + `trays/build_from_rvt.py` → `generate_cable_trays.py`.

**Geometry** (`catalog.json`, kind `cableway`): 76 tray/ladder components.
- `perforated-tray-<W>x<H>` / `solid-tray-<W>x<H>` cover every Niedax straight size (heights 35–110, widths 50–600), plus the generic 100×50 … 300×100 set.
- `cable-ladder-<W>x<H>` for W = 200–600 and H = 60, 100, drawn to the supplier ladder detail:
  - Rung: C-profile 25 × 15 × 1.25 with an 11 mm top opening, at 300 mm pitch. It's also a standalone block, `ladder-rung-profile`.
  - Rail web: 9 × 15 oblong slots at 50 mm, with Ø5.4 holes at 50 mm in a lower row.
  - Bottom flange: Ø8.5 fixing holes at 100 mm. Holes hidden by rungs are omitted.
  - **Assumed** (not dimensioned on the drawing): rail thickness t (1.5 for H60, 2.0 for H100), the 12 mm outward top flange with 6 mm lip, the 30 mm inward bottom flange, and which face carries the Ø5.4 vs the Ø8.5 holes.
- Views are shared files: the section is per W×H, plan and plan-cover per W, side per H. `manufacturerSeries` lists which product series use each geometry.
- Tray plan/side blocks are 1000 mm modules (50 mm slot pitch). Ladder blocks are 1200 mm modules (4 rungs at 300). Both tile.
- The profile (12 mm lip, 25×7 slots, drawn 1.5 mm sheet) is generic. Manufacturer thickness and weight live on the type.

**Niedax** (`trays/niedax.json`), 51 families:
- Straight: RL, RLU, RS, RSU, RLC, RLUC, RLCPV, RLV, RLVC, RSV.
- Fittings: RBA, RES, RESK, REK, RTA, RTAK, RTS, RTSK, RKS, RFD, RSD.
- Covers: RD/RDV and a cover for each fitting.
- Accessories: RV, RA, RAW, RGV, RVV, RW.
- Supports: KTA, HU5050, KU5050, U5050, 2986.
- Type names are `<CODE> <H>.<W>` + finish (none = pre-galv, F = hot-dip, E3/E5 = stainless). Standard length is 6 m.
- `sheetThicknessMmEstimated` is derived from schedule weight: RL ≈ 1.0, RS ≈ 1.5. It is not a catalogue value.
- The U series (RLU, RLUC, RSU) is treated as **unperforated**. The evidence is weight: same derived thickness as RL/RS but about 15 % heavier. Confirm against the Niedax catalogue.

**Excel EZ-FIT** (`trays/excel-ezfit.json`):
- Families: MTX/HTX straight (2.95 m pieces), MFB/HFB 90° elbows, MHB/HHB 45° elbows, MET/HET tees, MX/HX crosses, MRBI/MRBO vertical elbows.
- Widths: 50, 75, 100, 150, 225, 300, 450, 600.
- The RVT lists heights 25 and 50 but doesn't map them to the M/H prefixes, so EZ-FIT types have no `geometryId` yet.

**Station usages:** `ac-perforated-tray-*`, `dc-perforated-tray-*` and `ac-cable-ladder-200x100` carry `productId`, `service` and `withCover`.

## Column base (Part_1.dxf)
`column-base-plate-detail` is the detailed plan of the shelter column base. `steel-column-150` is the simplified symbol on the station grids.
As drawn: 150 × 150 plate, 75 × 75 × 2.4 square tube, 4 anchor bolts at 105 mm c/c (22.5 mm edge distance), Ø18 holes, Ø9 bolts, Ø14.5 washers, 15 mm A/F nuts.
**Size conflict:** the tube layer is named `S-100X100X3-2` (100×100×3.2), but the tube is drawn exactly 0.75× that. At 1:0.75 the plate would be 200 × 200, which matches `base-plate-200` in the station elevations. Confirm before using it for BOQ or fabrication.

## Known drawing quirks
- The MAX125 front block is named `MAX60 KTL3-X` in the DXF, but its labels say MAX125KTL3-LV.
- EXL-HV inserts the MAX125 top view at 0.9 scale; the catalog uses the true 1:1 block.
- AC-DB depth: 400 mm in the LV/125k drawings, 300 mm in EXL-HV.
- `growatt-40ktl3-x` has no spec JSON in `components/inverters/` yet. Its SVG is heavy (~860 KB) because the source block has ~10k polylines.
- `Internal_Inverter_Station_EXL-LV.dxf` referenced a missing block `MASTER`, so it was opened in recover mode.

## Tank-roof PV array (Top.dxf, Back_Side.dxf, Side_View.dxf)
PWA clear-water tank roof 40 × 26 m, 240 modules on a raised 15° frame. Drawn in metres like the station DXFs.

| Path | What |
|---|---|
| `catalog-tank-roof.json` | Extends `catalog.json` with the mounting parts (`kind: mounting`), toppings, tank-roof obstacles |
| `roofs/pwa-tank-roof-40x26-240.json` | Layout: 7 tables (TA–TG), post grid, rafters, rails, bracing, modules, obstacles, inverter station, raceway, cleaning water, plus `elevation`, `section`, `boq`, `conflicts` |
| `tcroof-tank-mount-blocks.dxf` | `TCR_*` blocks plus the roof rebuilt from them in mm (plan at 0,0; back elevation and section below it) |
| `extract_tank_roof.py` → `extract_back_side.py` → `extract_side_view.py` | Rebuild in that order: `python3 <script> <dxf> <out-dir>` |

**Frame** (one per rafter, 56 total, 2700 apart along y):
- Rear (high) line: vertical post 1998 from slab on an AG2-B02 foot, X-bracing in alternate bays.
- Front (low) line, 2800 away: one AG5-B03 foot with a V of two struts (1396, 1148). A 2038 diagonal runs from the rear foot.
- Rafter 4000 at 15°, high end z 2091, low end z 1055, 457 overhang. Rafter nodes along the slope: 1400 / 1000 / 1100.
- Every support point sits on a 300 × 300 × 150 concrete topping (112, 1.51 m³).
- Modules portrait, 2 up the slope, 2280 along the slope. Low edge about 1000, top about 2250. Plan shows them 2199 = 2280 cos 15°.

**Tables:** TA 32 modules, TB–TE 40 each, TF 32, TG 16. Table pitch in x 5500 (2800 + 2700).

**BOQ from the drawing:** 240 modules, 56 rear posts, 168 struts (256.6 m), 56 rafters, 32 rails (562.9 m: 16 × 23.36, 4 × 18.744, 12 × 9.512), 30 X-brace sets, 57.7 m raceway, 38.3 m cleaning pipe with 4 taps.

**Roof:**
- Four Ø1600 vents and four 1000 × 1000 hatches stay clear.
- A 1500 × 600 box on a 600 × 400 base (1 m high) sits under table TB. It's unlabelled.
- The inverter footprint is 6.0 × 2.5, the same as `pwa-inverter-station-shelter-125k`.

**Conflicts between the three drawings** (also in the layout JSON):
- The rafter is drawn 4000 in plan as well as in section. Its true plan projection would be 3864.
- Plan rails sit 1400 / 820 / 1400 apart. The section shows rail clamps at the rafter nodes, 1400 / 1000 / 1100 along the slope.
- The back view draws the four rails evenly 340 apart in height. That view is schematic.
- Member sections (post, strut, rafter, rail, bracing) are not labelled anywhere. The part codes AG2-B02 and AG5-B03 are the only supplier references.
