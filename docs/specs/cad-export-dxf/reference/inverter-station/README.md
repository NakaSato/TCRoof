# Inverter station (B2) references

The team's drawings, as sent on 2026-10-27, and their component library:

- `Inverter.dxf`: one Growatt MAX 125KTL3-X LV under a 6.0 × 2.5 m steel shelter (grid 1–4 / A–B), top, front and side views.
- `Inverter_EXL-HV.dxf`: 125 + 40 kW under a 9.0 × 2.5 m shelter (grid 1–5).
- `Internal_Inverter_Station_EXL-LV.dxf`: an 80 kW rack against a building's wall (it refers to a missing block `MASTER`; open it in recover mode).
- `Part_1.dxf`: the column's base plate, 150 × 150 with a 75 × 75 × 2.4 tube and four bolts 105 mm apart.
- `components/cad`: the library extracted from them (see its README): `tcroof-station-blocks.dxf`, `tcroof-cable-tray-blocks.dxf`, `catalog.json`, the three station templates and the SVGs.

All are drawn in metres although `$INSUNITS` says millimetres. The app's B2 DXF (`InverterStationDXF`) inserts the
library's blocks from `TCRoofKit/Sources/TCRoofCore/Resources/station-components.json`, which
`tools/cad-details/station_components.py` makes from `components/cad`.
