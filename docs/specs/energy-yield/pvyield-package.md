# PVYield (TCRoofKit)

Portable PV module and inverter specifications, PVsyst one-diode model, inverter efficiency model and string-sizing checks in pure Swift (Foundation only). It runs on iOS, iPadOS, macOS and Linux CI.

## What's inside

| File | Purpose |
|---|---|
| `PVModuleSpec.swift` | `Codable` module spec: datasheet ratings, temperature coefficients, cell layout, PVsyst one-diode parameters, dimensions, bifaciality, IAM profile. Includes `validate()` and JSON helpers. |
| `PANParser.swift` | Reads PVsyst `.PAN` text files (v6/v7) into `PVModuleSpec`. Protected/binary PAN files are rejected with `.protectedOrBinary`. |
| `PVsystSingleDiode.swift` | PVsyst one-diode model: `parameters(G, Tc)`, `maxPowerPoint`, `openCircuitVoltage`, `current(atVoltage:)`. Same equations as pvlib `calcparams_pvsyst` + `singlediode`. |
| `DatasheetFitter.swift` | Builds the one-diode parameters from a datasheet when no PAN file exists. |
| `ZnshineExamples.swift` | ZNSHINE ZXM7-UHLDD144 (565–595 W) datasheet entries and `fit(_:)`. |
| `InverterSpec.swift` | `Codable` inverter spec, three-term loss model (Schmidt–Sauer) fitted from max + European efficiency, AC output with clipping and night consumption. |
| `GrowattCatalog.swift` | Growatt MAX 60KTL3 LV, MAX 80KTL3 LV, MAX 125KTL3-X LV from the datasheets. |
| `StringSizing.swift` | Min/max modules per string and checks for max DC voltage, MPPT window, start voltage, Isc and Imp per MPPT, inputs available, DC/AC ratio. The voltage limit is the lower of the inverter's and the module's `maxSystemVoltageV`; the cold Voc comes from the datasheet coefficient, or the one-diode model when the spec has none (never the STC Voc); the start voltage against the hot Vmp is a hard minimum in both `limits` and `check`; Isc over the limit is an error and Isc × `iscSafetyFactor` (1.25, IEC 62548) over it a warning. |
| `Hourly/*.swift` | The hourly yield chain (§ Hourly engine). |
| `tools/yield-reference/components/*.json` | Exported specs: ET Solar 550 W (from PAN), Znshine 570 W (fitted), the three Growatt inverters. |

## Usage

```swift
import PVYield

// From a PVsyst PAN file (closest match to PVsyst)
let spec = try PANParser.parse(data: panData)

// Or from a datasheet
let spec = try ZnshineZXM7UHLDD144.fit(570).spec

// Store / exchange
let json = try spec.jsonData()
let same = try PVModuleSpec.from(json: json)

// Model one module at one hour
let model = PVsystSingleDiodeModel(spec: spec)
let mpp = model.maxPowerPoint(effectiveIrradiance: 850, cellTempC: 52)   // W/m², °C
print(mpp.p, mpp.v, mpp.i)
```

## Model

```text
IL   = (G/Gref) · [IL_ref + μIsc·(Tc − Tref)]
γ    = γref + μγ·(Tc − Tref)
I0   = I0_ref · (Tc/Tref)³ · exp[ q·Eg/(k·γ) · (1/Tref − 1/Tc) ]      Eg = 1.121 eV, kelvin
a    = γ · Ns · k·Tc / q
Rsh  = Rsh_base + (Rsh_0 − Rsh_base)·exp(−Rsh_exp·G/Gref)
I    = IL − I0·[exp((V + I·Rs)/a) − 1] − (V + I·Rs)/Rsh
```

- `IL_ref` and `I0_ref` come in closed form from Isc and Voc at STC.
- I(V) is solved with guarded Newton, Voc likewise, and the MPP with a golden-section search.

## Datasheet fit

When there is no PAN file, the fitter solves three parameters in turn:

1. **γ** so the model reproduces Pmp = Vmp·Imp at STC.
2. **Rs** so the relative efficiency at 200 W/m² matches the datasheet's low-light figure. If the datasheet gives none, it defaults to 0.975, typical of modern mono c-Si PAN models.
3. **μγ** so the model's dPmp/dT matches the datasheet μPmp.

Rsh defaults to 300 Ω × Ns/72, with Rsh₀ = 4 × Rsh and an exponent of 5.5.

Vmp is reported as a check, not used as a target. Fitting Vmp exactly gave an unphysical γ ≈ 1.34 and −7 % error at 200 W/m².

## Inverter efficiency fit

Datasheets give only η_max and η_euro. The loss model is
`p_loss = l0 + l1·p + l2·p²` (per unit of the DC power that yields AC nominal). Two numbers can't fix three parameters, so the load of peak efficiency is assumed at 40 %, and l1 is solved to reproduce η_euro.

The result reproduces η_max to within 0.01 pt and η_euro exactly. Swap in the PVsyst `.OND` curve when it becomes available (OND parsing is not implemented yet).

| Inverter | η 10 % | η 30 % | η 50 % | η 100 % |
|---|---|---|---|---|
| MAX 60KTL3 LV | 97.29 % | 98.74 % | 98.77 % | 98.20 % |
| MAX 80KTL3 LV | 97.11 % | 98.93 % | 98.96 % | 98.25 % |
| MAX 125KTL3-X LV | 97.67 % | 98.76 % | 98.77 % | 98.35 % |

## Verification (`swift test`, 14 module and inverter tests)

- **One-diode model vs pvlib 0.16.1:** tested on the ET-M772BH550GL PAN at 6 (G, T) points. Pmp agrees within 0.0001 %, Voc within 1 µV, Isc within 1 nA. The reference values are in `TCRoofKit/Tests/PVYieldTests/Fixtures/pvlib-reference-*.json`.
- **PAN model at STC:** 550.6 W against 550 W nameplate.
- **Datasheet fit vs PAN model, same module:** within 2 % across 100–1000 W/m² and 20–60 °C. The largest gap is −1.75 % at 60 °C, because the datasheet μPmp (−0.34 %/K) differs from the PAN model's own value (≈ −0.30 %/K).
- **Growatt fits:** η_max and η_euro reproduced; AC nominal reached at p = 1; clipping and night consumption checked.
- **Znshine 570 W string design:** 7–20 modules per string on the 60/80 kW models and 6–20 on the 125 kW (10 °C min / 70 °C max cell). With 2 strings per MPPT the 60/80 kW models exceed the 26 A operating limit (26.9 A).
- **Znshine 570 W fit vs datasheet NMOT:** the model gives 431.5 W against 430.3 W in the datasheet (+0.29 %), and Vmp 39.93 V against 39.90 V. NMOT is not used by the fit, so this is an independent check. All 7 power classes land within ±0.33 % of NMOT.

## Notes

- **PAN over datasheet:** prefer the manufacturer's PAN file. That is what PVsyst uses, so it is the only way to match PVsyst exactly.
- **Fixture licence:** `ET-M772BH550GL.PAN` comes from pvlib-python test data (BSD-3-Clause).
- **Not modelled in the module model:** bifacial rear gain, IAM and cell temperature belong to the yield engine (`Hourly/`).
- **Toolchain used for testing:** Swift 6.1 on Linux. `Package.swift` targets iOS 16 / macOS 13.

## Hourly engine (`Sources/PVYield/Hourly`)

A port of `tools/yield-reference/reference_engine.py` (`sun_position`, `plane_of_array`, `effective_irradiance`, `run_array`, `run`) for front-lit arrays on one or more faces.

| File | Reference step |
|---|---|
| `HourlyWeather.swift` | Hourly GHI/DNI/DHI, air temperature, wind (UTC hour starts). `pvgisTMY(csv:)` reads the PVGIS TMY as `tools/yield-reference/data` caches it; `scaled(toAnnualGHI:)` is `load_meteo`'s GSA scaling. Nothing fetches data: a site's weather is an input. |
| `SolarPosition.swift`, `SolarPosition+Tables.swift` | NREL SPA, pvlib `spa_python` defaults (ΔT 67 s, 1013.25 hPa, 12 °C). Tables generated from pvlib's `spa.py`. |
| `SunTrack.swift` | `sun_position`: the hour's effective zenith and azimuth over 5-minute samples, and the DNI fix. The slow SPA terms are worked out at each end of the hour and interpolated. One track serves every face at the site. |
| `Irradiance.swift` | Spencer extraterrestrial, Kasten–Young airmass, AOI, Perez 1990 sky diffuse, ground reflection; ASHRAE IAM and Marion's diffuse integration; PVsyst cell temperature (`ThermalModel`). |
| `YieldInputs.swift` | `YieldLosses`, `StringDesign`, `HorizonProfile`, `ArrayFace` (tilt, `azimuthDegTrueN`, near shading, horizon), `YieldUncertainty`, `YieldSystem` (module, inverter × count, faces). |
| `YieldEngine.swift` | `run_array` per face and `run` over the inverters: one-diode MPP, quality/LID/mismatch, DC ohmic, MPPT current limit, inverter efficiency and clipping, AC ohmic, unavailability and night consumption. |
| `BundledWeather.swift` | The weather years in `Resources/weather` (the Bangkok PVGIS-ERA5 TMY), the nearest one within 100 km of a site, and a small cache of their sun tracks. |
| `YieldResult.swift` | Energies at every step (`YieldEnergies`, the golden's `energies_kWh` keys), PR, specific yield, monthly table, loss diagram, PVsyst ageing, P50/P90/P99, hour counts, per-face results, optional hourly trace. |

```swift
let weather = try HourlyWeather.pvgisTMY(csv: text, latitude: 13.75, longitude: 100.50)
let track = SunTrack(weather: weather, site: .init(latitude: 13.75, longitude: 100.50))   // once per site
let system = YieldSystem(module: try ZnshineZXM7UHLDD144.fit(570).spec, inverter: try GrowattCatalog.max60KTL3LV(),
                         design: StringDesign(modulesPerString: 11, strings: 12),
                         faces: [ArrayFace(id: "S", moduleCount: 132, tiltDeg: 10, azimuthDegTrueN: 180)])
let r = YieldEngine.run(system, track: track)
print(r.energies.eGrid, r.specificYield, r.performanceRatio, r.probability.p90OneYear)
```

Extensions beyond the reference: `inverterCount` (identical inverters sharing the array evenly; 1 reproduces the reference) and `design: nil` (no string design yet, so no MPPT current limit).

**Accuracy** (`HourlyYieldTests`, pvlib 0.13 reproduces the committed golden files exactly):

| Check | Tolerance in the test | Measured |
|---|---|---|
| SPA apparent zenith, azimuth (237 hours) | 1e-5° | within the fixture's 6 decimals |
| Effective sun, DNI fix, airmass | 1e-4°, 1e-5 relative | passes |
| Marion diffuse IAM, 9 tilts | 1e-9 | passes |
| POA direct / sky / ground, south 10° and east 30° | 0.01 W/m² or 1e-5 | passes |
| Hourly trace of 60kW-ERA5 (8,760 h): POA, G_eff, T_cell, P_module, P_DC, P_AC, P_grid | 1e-5–1e-4 relative | worst hour at 0.05 of the tolerance (fixture rounding) |
| Annual energies, every step, 7 scenarios (60/80/125 kW × ERA5/GSA, two-face gable with horizon) | 0.01 % | E_grid within 0.0001 %, worst step 0.0003 % |
| Monthly, ageing, lifetime, P50/P90/P99, hour counts | the golden's rounding | passes |

**Runtime** (MacBook, `swift test -c release`): the sun track of a year 66 ms (once per site), one face for a year 29 ms. Debug builds are about 10× slower. Pure Swift on value types, so run it off the main thread.

**Not ported yet:** the bifacial rear side (`rear_irradiance`) and row-to-row shading (`sheds`), both pvlib infinite sheds; their golden scenarios (`*-bifacial-*`, `*-ground-*`) are not tested yet.

## Reference engine (Python)

`tools/yield-reference/reference_engine.py` is the full hourly PVsyst-style chain in pvlib. It covers sun position, Perez, IAM, soiling, PVsyst cell temperature, one-diode MPP, DC losses, MPPT current limit, inverter efficiency and clipping, AC losses, PR, PVsyst ageing and P50/P90. It is the specification for the Swift port.

- `tools/yield-reference/RESULTS.md`: results for the 60/80/125 kW designs.
- `TCRoofKit/Tests/PVYieldTests/Fixtures/golden/*.json`: per-scenario golden values, plus a full hourly trace for `60kW-ERA5`.
- `tools/yield-reference/data/`: the PVGIS TMY used (PVGIS © European Union).

### Any site from coordinates

```bash
python3 -I tools/yield-reference/site_yield.py --lat 18.79 --lon 98.98 --mount roof --inverter 60
python3 -I tools/yield-reference/site_yield.py --lat 14.97 --lon 102.10 --mount ground --inverter 125 --bifacial
```

For the given point, `site_yield.py` does the following:
- downloads the PVGIS TMY and caches it;
- reads Global Solar Atlas GHI and optimum tilt;
- runs the ERA5 and Solargis-scaled scenarios;
- for ground mounts, sets tilt and row pitch for that latitude;
- writes `tools/yield-reference/sites/<name>.json`.

Options: `--tilt --azimuth --strings --per-string --bifacial --albedo --pitch --uc --soiling --near-shading`.
