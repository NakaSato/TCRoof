# TCRoof — inverter station CAD components

Extracted from drawings by Chanthawat.K:
`Internal_Inverter_Station_EXL-LV.dxf`, `Inverter.dxf`, `Inverter_EXL-HV.dxf` and `Part_1.dxf` (column base detail).
Cable trays and ladders are generated parametrically, sized from the Niedax and Excel EZ-FIT Revit content (`Electrical_Distribution_Niedax_Cable_Trays_2022.rvt`, `Electrical_Distribution_Excel_Electric_Group_EZ-FIT_Cable_Tray_2019.rvt`).

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
