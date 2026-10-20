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
| `StringSizing.swift` | Min/max modules per string and checks for max DC voltage, MPPT window, start voltage, Isc and Imp per MPPT, inputs available, DC/AC ratio. |
| `tools/yield-reference/components/*.json` | Exported specs: ET Solar 550 W (from PAN), Znshine 570 W (fitted), the three Growatt inverters. |

## Usage

```swift
import TCPVModule

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

## Verification (`swift test`, 14 tests)

- **One-diode model vs pvlib 0.16.1:** tested on the ET-M772BH550GL PAN at 6 (G, T) points. Pmp agrees within 0.0001 %, Voc within 1 µV, Isc within 1 nA. The reference values are in `TCRoofKit/Tests/PVYieldTests/Fixtures/pvlib-reference-*.json`.
- **PAN model at STC:** 550.6 W against 550 W nameplate.
- **Datasheet fit vs PAN model, same module:** within 2 % across 100–1000 W/m² and 20–60 °C. The largest gap is −1.75 % at 60 °C, because the datasheet μPmp (−0.34 %/K) differs from the PAN model's own value (≈ −0.30 %/K).
- **Growatt fits:** η_max and η_euro reproduced; AC nominal reached at p = 1; clipping and night consumption checked.
- **Znshine 570 W string design:** 7–20 modules per string on the 60/80 kW models and 6–20 on the 125 kW (10 °C min / 70 °C max cell). With 2 strings per MPPT the 60/80 kW models exceed the 26 A operating limit (26.9 A).
- **Znshine 570 W fit vs datasheet NMOT:** the model gives 431.5 W against 430.3 W in the datasheet (+0.29 %), and Vmp 39.93 V against 39.90 V. NMOT is not used by the fit, so this is an independent check. All 7 power classes land within ±0.33 % of NMOT.

## Notes

- **PAN over datasheet:** prefer the manufacturer's PAN file. That is what PVsyst uses, so it is the only way to match PVsyst exactly.
- **Fixture licence:** `ET-M772BH550GL.PAN` comes from pvlib-python test data (BSD-3-Clause).
- **Not modelled here:** bifacial rear gain, IAM application and cell temperature belong to the yield engine, not the module model.
- **Toolchain used for testing:** Swift 6.1 on Linux. `Package.swift` targets iOS 16 / macOS 13.

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
