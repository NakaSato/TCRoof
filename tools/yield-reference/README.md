# Yield reference engine (Python / pvlib)

This is the reference implementation of the PVsyst-style hourly chain. It produces the golden data for the Swift port in `TCRoofKit/Sources/PVYield`. See `docs/specs/energy-yield/`.

```bash
pip install pvlib pandas numpy
python3 -I reference_engine.py      # reference scenarios → TCRoofKit/Tests/PVYieldTests/Fixtures/golden
python3 -I site_yield.py --lat 15.04596 --lon 100.54901 --mount roof --inverter 125
python3 -I pwa_batch.py             # PWA stations; faces from data/pwa-faces.csv
python3 -I make_report.py           # rebuilds RESULTS.md
python3 -I stage_fixtures.py        # stage-by-stage and multi-face fixtures for the Swift tests
```

**Survey input (`data/pwa-faces.csv`).** Add one row per roof face, with these columns:

| Column | Meaning |
|---|---|
| `station` | Station name |
| `face` | Roof face name |
| `modules` | Number of modules on the face |
| `tilt_deg` | Tilt, degrees |
| `azimuth_deg` | Compass bearing: 0 N, 90 E, 180 S, 270 W |
| `shading_pct` | Annual shading loss from the survey, % |
| `horizon` | Optional far obstacles, e.g. `240:25;300:25` |

**Data.**
- `data/` caches the PVGIS TMY downloads (PVGIS © European Union). Only the Bangkok file is committed; the others are fetched again on demand.
- Global Solar Atlas (Solargis, CC BY 4.0) is read live and used to scale the irradiance.
