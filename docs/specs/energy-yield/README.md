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

Next:
- Bifacial rear gain and row-to-row shading (pvlib infinite sheds; golden `*-bifacial-*` and `*-ground-*`).
- Wire it to the survey's roof faces and layout (`RoofMount`).
- A weather source per site (only the Bangkok TMY is in the repo; the engine takes any `HourlyWeather`).
