# Energy yield

Preliminary and PVsyst-equivalent energy yield for TCRoof: residential surveys and the PWA (กปภ.) Solar Rooftop stations.

| File | What it is |
|---|---|
| `preliminary-energy-yield.md` | Dev spec: data sources, calculation chain, mounting types, input validation, data model, open items |
| `research-th.md` | Research report (Thai): PVGIS / Open-Meteo / alternatives, irradiance accuracy in Thailand, PR and losses, P50/P90, iOS tilt/azimuth |
| `pvyield-package.md` | The `PVYield` target in TCRoofKit: module/inverter specs, PAN parser, PVsyst one-diode model, datasheet fit, string sizing, verification |
| `../../../tools/yield-reference/RESULTS.md` | Reference results: Bangkok designs, bifacial, ground mount, multi-face and shading, the 9 PWA stations |

## Layout

- `TCRoofKit/Sources/PVYield`: pure Swift, Foundation only; no dependency on the other targets yet.
  - The module and inverter ids match `TCRoofCore/Resources/pv-modules/znshine-zxm7-uhldd144.json` and `equipment-catalog.json` (Growatt MAX 60/80/125).
- `TCRoofKit/Sources/PVYield/Hourly`: the hourly chain ported from the reference engine (sun position, Perez, IAM, cell temperature, inverter, multi-face, horizon, P50/P90, ageing). See `pvyield-package.md` § Hourly engine.
- `TCRoofKit/Tests/PVYieldTests`: 26 tests (14 module/inverter, 12 hourly chain).
  - The one-diode model matches pvlib to within 0.0001 % Pmp.
  - The Znshine 570 W datasheet fit matches the datasheet NMOT to within +0.29 %.
  - The Growatt efficiency fits reproduce the datasheet values.
  - The string-sizing tests use the Znshine 570 W on each Growatt model.
- `TCRoofKit/Tests/PVYieldTests/Fixtures/golden`: golden yield values per scenario, a full hourly trace for `60kW-ERA5`, every stage of every 37th hour (`stages-60kW-ERA5.json`) and a two-face gable with a horizon (`60kW-ERA5-faces-horizon.json`).
  - The Swift hourly engine matches every front-lit scenario to rounding (E_grid within 0.0001 %, every step within 0.0003 %).
- `tools/yield-reference/`: the hourly PVsyst-style chain in Python (pvlib), which is the specification for the Swift engine.
  - `site_yield.py --lat --lon`: any site from its coordinates.
  - `pwa_batch.py`: the PWA station list, with per-face survey input in `data/pwa-faces.csv`.
  - `make_report.py`: regenerates `RESULTS.md`.
  - `stage_fixtures.py`: writes the stage and multi-face fixtures for the Swift tests.

## Status

Done:
- Hourly chain in `PVYield` for front-lit arrays: sun position (NREL SPA), the hour-effective sun and DNI fix, Perez, IAM, horizon and near shading, soiling, cell temperature, one-diode MPP, DC losses, MPPT current limit, inverter and clipping, AC losses, PR, monthly table, ageing, P50/P90. Tested against `Fixtures/golden`.

- C1's แผงบนหลังคา tab shows `พลังงานต่อปี` from it (`TCRoofCore/RoofPV/RoofMountYield.swift`): P50 and P90 MWh/yr, kWh/kWp, PR, per face, the inverters and the source. It runs on the layout's faces in use (tilt from `Roof.slope`, compass azimuth from the plan's bearing), their module counts, the standard's module matched to the catalog (`p570` → Znshine ZXM7-UHLDD144-570) and B2's inverter sizes (Growatt MAX 60/80/125; with one roof section the roof takes all of them, else as many as keep DC/AC ≤ 1.3, said as ค่าสมมติ). It is computed off the main thread, 0.6 s after the layout settles, and never stored.
- Weather: `PVYield/Resources/weather` ships the Bangkok PVGIS-ERA5 TMY (`BundledWeather`), used for sites within 100 km. Elsewhere, without A1's GPS, or with a module that has no model, the card shows `SolarModel`'s clear-sky estimate and says why.

Next:
- A weather year for every site: more bundled TMYs (one per region or a PVGIS grid), or a fetch-and-cache step. Needs a decision on the source and its licence (§4 of the dev spec).
- Bifacial rear gain and row-to-row shading (pvlib infinite sheds; golden `*-bifacial-*` and `*-ground-*`).
- Models for the catalog's other modules (`p550`, `p580`, `p620`: PAN files or datasheet temperature coefficients).
- Near shading and the obstacles' shade from the layout into `ArrayFace.nearShadingLossFrac`.
- Switch the layout's face choice, the report line (`RoofMount.summaryLine`) and the tank's energy search (`TankLayout+Energy`, `TankShade`) once every site has hourly weather; until then they stay on `SolarModel` so a job's numbers don't change with its location.
