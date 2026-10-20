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
- `TCRoofKit/Tests/PVYieldTests`: 14 tests.
  - The one-diode model matches pvlib to within 0.0001 % Pmp.
  - The Znshine 570 W datasheet fit matches the datasheet NMOT to within +0.29 %.
  - The Growatt efficiency fits reproduce the datasheet values.
  - The string-sizing tests use the Znshine 570 W on each Growatt model.
- `TCRoofKit/Tests/PVYieldTests/Fixtures/golden`: golden yield values per scenario, plus a full hourly trace for `60kW-ERA5`.
  - The Swift hourly engine port is tested against these, step by step.
- `tools/yield-reference/`: the hourly PVsyst-style chain in Python (pvlib), which is the specification for the Swift engine.
  - `site_yield.py --lat --lon`: any site from its coordinates.
  - `pwa_batch.py`: the PWA station list, with per-face survey input in `data/pwa-faces.csv`.
  - `make_report.py`: regenerates `RESULTS.md`.

## Next step

Port the hourly chain to `PVYield`, covering:
- sun position, Perez, IAM, cell temperature;
- inverter, multi-face and horizon shading;
- bifacial and row-to-row shading;
- P50/P90 and ageing.

Test it against `Fixtures/golden`. After that, wire it to the survey's roof faces and layout (`RoofMount`).
