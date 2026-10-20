# Dev Spec: Preliminary Energy Yield

| | |
|---|---|
| **Feature** | Preliminary Energy Yield (on-site quick estimate) |
| **App** | TCRoof (iOS / iPadOS, Swift) |
| **Status** | Research complete, figures rechecked live 2026-10-20 — UI not started |
| **Date** | 2026-10-20 |

## 1. Summary

On site, before engineers run PVsyst, the app estimates annual energy for a proposed PV system from GPS coordinates plus the tilt/azimuth of each array face, and shows the customer a P50/P90 range.

Decisions:

- **Primary engine:** PVGIS v5.3 `PVcalc`, one call per array face, always with `loss=0` so the app owns the system-loss chain.
- **Resource correction:** scale PVGIS irradiance with Global Solar Atlas (Solargis satellite data). In Thailand PVGIS only offers **PVGIS-ERA5** (reanalysis, 2005–2023), not SARAH; at Bangkok it reads ~5% higher than Solargis.
- **Open-Meteo is not the primary source.** The free tier is non-commercial only, and the historical/satellite APIs need the Professional plan or higher.
- **Default PR ≈ 76% on a POA basis** (range 73–80% by mounting type). The original draft's 78–80% was effectively GHI-based (1,450 ÷ 1,850 = 78.4%).
- **Always show P50 and P90**, never a single figure. Default P90 ≈ 0.90 × P50.

Main risks are not API choice but: double-counting PVGIS losses, a wrong orientation entered for a roof face (e.g. east/west swapped), and presenting P50 as a guaranteed figure.

## 2. Scope

**In scope:** data sources, calculation chain, mounting types (pitched roof, flat roof, ground mount), input contract from the TCRoof layout, input validation, uncertainty, customer-facing disclaimer text, data model, caching/offline.

**Out of scope (this phase):** UI design, the layout editor itself, sensor-based orientation capture, single-axis trackers, bifacial gain in P50, bankable (P90 for financing) studies, hourly self-consumption modelling beyond a stub.

### 2.1 Input source: the TCRoof layout

The estimator does **not** capture orientation itself. TCRoof's existing data entry already holds each roof face's orientation, the panel layout and the tilt; the estimator is a pure function of that data.

| Estimator input | Taken from TCRoof |
|---|---|
| Site lat/lon | Project location |
| Array faces | Roof faces (pitched) or array blocks (flat roof / ground) in the layout |
| `tiltDeg`, `azimuthDegTrueN` | Tilt and orientation entered per face — converted to canonical 0 = N, clockwise |
| `pDCkWp` per face | Σ (module count on that face × module Wp) / 1000 |
| `mounting` | Mounting type entered for the face |
| Row pitch, module length, GCR | Layout geometry (flat roof / ground blocks) |
| DC/AC ratio | Σ kWp ÷ inverter AC rating from the selected inverter(s) → sets clipping loss |
| Near shading, parapet height | Survey fields where present; otherwise default and widen σ_shade |

Rules:
- Group faces with identical (tilt, azimuth, mounting) into one PVGIS call; sum their kWp.
- Recompute whenever the layout changes. Most edits hit the cache, since only kWp changes and PVGIS results are per kWp.
- Store a `layoutRevision` with each estimate so a result can always be traced to the layout it came from.

## 3. Assessment of the original draft numbers

| Draft value | Assessment | Recommended (80 kWp, central Thailand) |
|---|---|---|
| GHI ~1,850 kWh/m²/yr | OK as a **national** mean (DEDE map: 18.2 MJ/m²/day ≈ 1,846). Too high for Bangkok (GSA 1,794), low for lower Isan (GSA Korat 1,898). | Use per-site GSA value, not a constant. |
| Specific yield 1,450 kWh/kWp/yr | **Best case** — PVGIS-ERA5 at optimum tilt, free-standing; ERA5 itself likely reads high. | **~1,330–1,430** (P50) depending on mounting, orientation, tilt. |
| PR 78–80% | **Internally inconsistent** — this is PR on GHI. On POA (~1,840–1,930) it is 75–79%. | **~76%** POA-based for rooftops (73–78%); 78–80% for ground mount. |
| ~116,000 kWh/yr | ~1–8% high, no P90. | **P50 ≈ 106,000–115,000**, **P90 ≈ 95,000–103,000**. |

Derivation: PVGIS H(i) Bangkok 10°S = 1,927 kWh/m² × k = 1,794 / 1,876 ≈ 0.956 → 1,843 kWh/m² × PR 0.75–0.78 → 1,382–1,438 kWh/kWp → 110.6–115.0 MWh for 80 kWp. Low-pitch (3–5°) or east/west roofs lose a further 1–5% → lower bound ~106 MWh.

## 4. Data sources

### 4.1 PVGIS v5.3 (primary)

- Endpoint: `GET https://re.jrc.ec.europa.eu/api/v5_3/PVcalc` — **pin `/api/v5_3/`**; the unversioned path serves 5.2 only "for a limited period". PVGIS 6 is beta with a different API.
- Required: `lat`, `lon`, `peakpower` (kWp), `loss` (%). Optional used: `angle` (tilt), `aspect` (**0 = S, 90 = W, −90 = E**), `mountingplace` (`free` | `building`), `usehorizon`, `userhorizon`, `pvtechchoice`.
- **Always pass `outputformat=json`** (default is CSV).
- Outputs: `E_y`, `E_m`, `H(i)_y` (POA kWh/m²/yr), `H(i)_m`, `SD_y`, `SD_m`, `l_aoi`, `l_spec`, `l_tg`, `l_total`.
  - **`l_spec` is returned as a string** (e.g. `"0.86"`); others are numbers.
  - No PR field. Compute `PR = E_y / (peakpower × H(i)_y)`.
  - `PVcalc` has no `startyear/endyear`; always the full-period mean. (`seriescalc`, `MRcalc`, `tmy` do accept years.)
- **Database in Thailand: PVGIS-ERA5 only, 2005–2023, ~0.25°.** `raddatabase=PVGIS-SARAH3` returns HTTP 400 "Location out of the spatial coverage" despite docs listing SARAH3 as Asia's default. `PVGIS-SARAH2` / `PVGIS-NSRDB` are invalid in v5.3.
- Horizon: DEM horizon (SRTM 90 m) is on by default but covers terrain only, not buildings/trees. Near obstructions must be sent via `userhorizon`: comma-separated horizon heights (°) at equal azimuth steps, **starting at north, clockwise**.
- Model: Huld (2011) power model; Faiman module temperature — `free` U0 = 26.9, U1 = 6.2; `building` U0 = 20.0, U1 = 3.2; Martin & Ruiz AOI; monthly spectral correction (c-Si/CdTe only). Inverter, wiring, mismatch are **not** modelled — they live in `loss` (its suggested 14% also bundles ~0.5%/yr degradation).
- `pvtechchoice=crystSi2025` available since 2025-09-05 (default still `crystSi`).
- Limits/terms: no key, no registration, **30 req/s per IP** (429 above that, 529 when overloaded). No CORS — irrelevant for native `URLSession`. No SLA. Observed ~1 s latency, ~5 KB response, 2 connection resets in ~20 calls (cleared on retry). No commercial-use prohibition found; presumed basis is EU reuse policy (Decision 2011/833/EU) with attribution — **verify PVGIS "Usage Conditions" page before release.**

### 4.2 Global Solar Atlas (resource correction / cross-check)

- Endpoint (undocumented): `GET https://api.globalsolaratlas.info/data/lta?loc={lat},{lng}`.
- Returns long-term GHI, DNI, DIF, GTI_opta, OPTA (optimum tilt), PVOUT, temperature. Solargis data v2.2.68, updated April 2026, covering through 2025.
- Bangkok: GHI 1,794 kWh/m², GTI_opta 1,841.7, OPTA 15°, PVOUT 1,447.9 kWh/kWp.
- Licence CC BY 4.0 (commercial use with attribution). No documented rate limit or SLA — **confirm with ESMAP/Solargis before production use; cache aggressively.**
- PVOUT is for a reference system at optimum tilt only; it cannot model the real face.

### 4.3 Alternatives

| Source | Thailand | PV sim / tilt-azimuth | Terms / price | Role |
|---|---|---|---|---|
| **PVGIS v5.3** | ERA5 only, 2005–2023 | Yes / Yes | Free, no key, no SLA | **Primary** |
| **Global Solar Atlas** | Solargis to 2025 | PVOUT at opt. tilt only / No | CC BY 4.0, undocumented endpoint | **Resource scaling, cross-check** |
| **PVWatts v8** `dataset=nsrdb` | NSRDB Himawari TMY-2020, 4 km | Yes / Yes | Free key, 1,000 req/h; non-US commercial terms unverified | Online fallback |
| **Open-Meteo** | Himawari 5 km, ERA5, IFS | No (GTI only) / Yes | Historical/satellite need Professional+ | Recent time series only |
| **Solargis API** | Himawari, bankable | Yes / Yes | Prospect €2,400–4,800/yr; API by quote | Bankable phase |
| **Solcast** | Himawari 1–2 km | Yes / Yes | Quote only; free/hobbyist non-commercial | Bankable; direct PVsyst import |
| **Meteonorm API** | Global | Yes / Yes | Quote; demo key has no Thai points | Match PVsyst default |
| **NASA POWER** | 1° grid | No / No | Free, no key | Sanity check only |
| **DEDE / TMD** | Research maps | No | No public API | Reference in Thai reports |

Notes:
- PVWatts: NREL was renamed National Laboratory of the Rockies (Dec 2025); working host is **`developer.nlr.gov`**. Bangkok, 15°S, 14% loss → 1,400 kWh/kWp.
- NASA POWER Bangkok GHI 5.23 kWh/m²/day (~1,910/yr), ~6% above GSA.
- Open-Meteo: `global_tilted_irradiance` with `tilt`/`azimuth` (same convention as PVGIS) on forecast, archive and `satellite-api.open-meteo.com/v1/archive` (JMA/JAXA Himawari 0.05°, 10-min). Isotropic sky, fixed 20% albedo, hourly values are preceding-hour means. `era5_land` returns null radiation at Bangkok. Requests > 2 weeks count as multiple calls (a 10-year hourly pull ≈ ~260 calls, estimated). Last published prices (Jun 2023): Standard $29/mo, Professional $99/mo — current page shows no figures. Data CC BY 4.0, server AGPLv3 (self-hostable).

## 5. Irradiance accuracy in Thailand

- No peer-reviewed numeric validation of PVGIS-ERA5, Solargis, Solcast or Meteonorm against Thai ground stations was found.
- Thai satellite models (Silpakorn group): monthly GHI RMSD 6.1%, MBD 0.3% over 38 stations; another model RMSE 6.9% over 36 stations.
- Reanalysis runs high in humid tropics: GLDAS vs 5 southern Thai stations MBD +15.8% (Ranong RMSD 35.6%). ERA5 globally +4 W/m² but overestimates under cloud (up to +28% hourly rMBD in humid West Africa). One KMUTT 2024 poster reports ERA5 *under*estimating near Bangkok — bias direction may vary, but all authors recommend correcting ERA5.
- Satellite products do better: Solargis tropical-site GHI bias +1.5% (SD 3.4%), SE Asia P90 uncertainty ±8%; Solcast humid-tropics bias +0.5% vs ERA5 +2.4% (vendor data).
- Bangkok, ~15°S plane: PVGIS-ERA5 **1,937**, GSA GTI_opta **1,842**, Open-Meteo 10-yr archive 1,899 kWh/m² → **ERA5 ≈ +5% vs Solargis.**
- Regional yield check: PVGIS predicted a 4.5 kWp Surabaya rooftop within +1.52%/yr (single system).
- Inter-annual variability (PVGIS `SD_y`): 1.7–3.2% (Bangkok 2.0%, Chiang Mai 3.2%), but SE Asia GHI in 2023 was ~10% above long-term mean — single years can swing more than `SD_y` suggests.

## 6. Performance ratio and losses

### 6.1 PR definition

Per IEC 61724-1 (NREL restatement): **PR = Yf / Yr = (E_AC / P_STC) / (H_POA / 1 kW/m²)**. Must use POA irradiation. GHI-based "PR" folds transposition gain into system efficiency and is not comparable across faces.

From PVGIS: `PR = E_y / (peakpower × H(i)_y)` — e.g. Bangkok 10°S, loss=14: 1,446.4 / 1,927.4 = **75.0%** (= 1 + `l_total`/100).

For later comparison against monitoring data, use temperature-corrected PR (temperature alone swings PR up to ±10% seasonally).

### 6.2 Measured Thai references

- 1 MW rooftop, Samut Songkhram: **PR 77.2%** (PVsyst predicted 75.6%); same-equipment ground plant **83.0%**. Degradation 0.62%/yr rooftop vs 0.42%/yr ground.
- 32.4 kWp Bangkok: PR 0.712.
- 9.8 kWp northern home (S/W, W, E arrays): PR ~70–80%, 1,250–1,315 kWh/kWp/yr.
- 3.5 kWp Tak: ~1,391 kWh/kWp/yr.
- PVGIS (loss 14%) Bangkok: ~75% `free`, 72.2% `building` (thermal loss −11.1% → −14.5%).
- Newer TOPCon/PERC modules may add 1–2 points of PR (unverified in Thai field data).

### 6.3 Loss table — two groups to prevent double-counting

| Group | Loss | Default | Range | Notes |
|---|---|---|---|---|
| **A: already in PVGIS** | IAM/reflection (`l_aoi`) | ~2.7% | 2–3.5% | Do not apply again |
| | Spectral (`l_spec`) | ~+0.9% (gain) | ±1% | Do not apply again |
| | Temperature + low irradiance (`l_tg`) | 11% (`free`) – 14.5% (`building`) | 10–15% | Controlled via `mountingplace` |
| **B: applied by app** | Soiling | 3% | 2–5% | 4–5% near farms, quarries, unpaved roads, ground mounts |
| | LID / module quality | 1% | 0.5–2% | |
| | Mismatch | 1% | 1–2% | |
| | DC wiring | 1.5% | 1–2% | |
| | Inverter | 2.5% | 1.5–3% | |
| | AC wiring | 0.5% | 0.5–1% | |
| | Clipping (DC/AC ≤ 1.2) | 0.5% | 0–2% | Increase if DC/AC > 1.3 |
| | Availability | 1% | 0.5–2% | |
| | **Group B product** | **≈ 0.895** | | Excludes shading and degradation |

Thai soiling peaks in January (avg 0.47%/day accumulation), near zero in the rainy season; up to 3%/month in some areas. Group B values for mismatch, wiring, availability and clipping have no Thai-specific source.

Bangkok 10°S, PVGIS `loss=0` (verified live 2026-10-20): E_y 1,681.86 / 1,618.57 kWh/kWp on H(i)_y 1,927.43 → Group A ≈ 87.3% (`free`) / 84.0% (`building`) × 0.895 → **PR ≈ 78.1% / 75.1%**.

## 7. Mounting types

| Mounting type | Geometry source | `mountingplace` | Typical PR (POA) | Extra losses |
|---|---|---|---|---|
| Pitched roof, flush on metal sheet (gap < ~10 cm) | **Measured** | `building` | ~75% | — |
| Pitched roof, railed (gap ≥ 15 cm) | **Measured** | between `building` and `free` (call both, interpolate) | ~76–77% | — |
| Flat roof, tilted racks | **Designed** | `free` | ~77–78% | Row shading, parapet shading |
| Flat roof, east–west (~10°) | **Designed** | `free` | ~76–77% | Two faces at aspect −90 / +90 |
| Ground mount, fixed tilt | **Designed** | `free` | ~78–80% | Row shading, vegetation, higher soiling |

The gap thresholds for `building`/`free` are an engineering inference, not a sourced rule.

### 7.1 Designed geometry (flat roof, ground)

- Tilt/azimuth are design choices, not measurements. Default to optimum tilt for the site and due south: Bangkok 15–17°, Chiang Mai ~24°, Hat Yai ~7° (PVGIS; Bangkok optimum 17°, azimuth −12° → 1,455.5 kWh/kWp).
- Compass is only used to check the orientation of the plot or building edge.

### 7.2 Row-to-row shading (not modelled by PVGIS)

- Design rule: no inter-row shading 09:00–15:00 on 21 December.
- Bangkok (13.75°N), 09:00 on 21 Dec: sun altitude ≈ 32.4°, azimuth ≈ 50° east of south. Required clear gap between rows ≈ **1.0 × module top height** (h = L·sin β).
- Example: L = 2.28 m portrait, β = 15° → h ≈ 0.59 m, ground footprint 2.20 m, **pitch ≈ 2.8 m, GCR ≈ 0.81**.
- Tighter spacing → add a row-shading loss to Group B (computed from sun position).
- Flat roof: capture **parapet height** for edge-row shading. East–west racks: call PVGIS for two faces at aspect −90 and +90.
- Ground mount: consider vegetation shading and raise soiling to 4–5% near farms or unpaved roads.

### 7.3 Not modelled

- **Bifacial gain / real ground albedo:** PVGIS does not model bifacial. Show any bifacial gain separately, never folded into P50.
- **Trackers:** PVGIS supports tracking axes, but defer to a later phase.

## 8. Validating the entered tilt and azimuth

### 8.1 Yield sensitivity (PVGIS, Bangkok)

The yield surface is flat; small errors barely matter, gross errors do.

| Case | Yield (kWh/kWp) | Change |
|---|---|---|
| Optimum 17°, −12° (slightly east) | 1,455.5 | — |
| 10°S vs 10° at 5° W of S | 1,446.4 vs 1,445.3 | ~0.1% |
| 15°, 20° W of S | — | −0.6% |
| 15°, 30° W of S | — | −1.1% |
| 15° E | 1,396 | −3.9% vs S |
| 15° W | 1,365 | −6.1% vs S |
| 15° N | 1,289 | −11.3% vs S |
| 30° N | 1,103 | −23% vs S |

East faces beat west faces by ~1.5–2.5% across central, northeast and northern Thailand. Low pitch (3°) facing north loses only −2.3%.

**Input accuracy that matters:** tilt ±2°, azimuth ±5–10° is plenty. The critical failure is **a wrong orientation on a face** (e.g. east/west swapped on a gable roof, or north entered as south).

### 8.2 Validation rules (run before calculating)

| Check | Rule | Action |
|---|---|---|
| Tilt range | 0° ≤ tilt ≤ 60° | Block outside range |
| Steep tilt | tilt > 35° | Warn (unusual for Thai roofs) |
| North-facing | azimuth within ±60° of N and tilt > 10° | Warn: yield −8% to −23%; require confirmation |
| Gable pair | Two faces of one roof whose azimuths are not 180° ± 10° apart | Warn: possible swapped or mistyped face |
| Missing azimuth | tilt > 2° and no azimuth | Block |
| Near-flat | tilt ≤ 2° | Azimuth has negligible effect; accept any value |
| Ground / flat roof | tilt differs from site optimum by > 10° | Info: show optimum (e.g. Bangkok 15–17°) |
| Cross-check (optional) | Google Solar API segment pitch/azimuth differs by > 10° | Warn; do not override the entered value |

Warnings go into `YieldEstimate.warnings` and are shown with the result; they never silently change the input.

### 8.3 Optional measurement aids (if the layout editor offers a "measure" button)

Not part of this feature, but notes for whoever builds that button:
- **Tilt:** `CMDeviceMotion.gravity` in `.xArbitraryZVertical`; β = acos(|g_z|) averaged over 1–2 s; flip-average 180° to cancel device offset. No magnetometer, so steel roofs don't affect it.
- **Azimuth:** `CLHeading.trueHeading` (declination in Thailand only −0.2° to −1.0°, applied automatically). `headingAccuracy` cannot detect a steady offset from steel; field errors up to ~20° are reported. Cross-check with a magnetometer-free method: eave line on MapKit satellite imagery, sun sighting with SPA, Google Solar API (`requiredQuality=BASE`, `azimuthDegrees` 0 = N), or drone photogrammetry.

### 8.4 Horizon capture and conventions

| Target | Azimuth convention | Format |
|---|---|---|
| App canonical | 0 = N, clockwise | — |
| PVGIS `aspect` / Open-Meteo `azimuth` | 0 = S, −90 = E, +90 = W | — |
| PVGIS `userhorizon` | starts N, clockwise, equal steps | comma-separated heights |
| PVsyst | 0 = S | azimuth/elevation pairs, `.HOR` |
| PV*SOL / SunEye | −180…179 | space-separated, `.hor` |
| Google Solar API | 0 = N | — |

Store azimuth only in canonical form; convert at the API/export boundary. Reference app: Azimutis (iOS) — clinometer, compass with interference warnings, "Align with the Sun", exports CSV (PVsyst), TXT (PVGIS), HOR.

## 9. Calculation chain (per array face i)

```text
1)  aspect_i = normalize(az_trueN_i − 180)  → [−180, 180]
2)  PVcalc(lat, lon, peakpower=1, loss=0, angle=β_i, aspect=aspect_i,
           mountingplace=m_i, usehorizon=1, userhorizon?, outputformat=json)
       → E0_i   = E_y      (kWh/kWp; includes AOI + spectral + thermal + horizon)
       → H_POA_i = H(i)_y  (kWh/m²/yr);  SD_i = SD_y
3)  k = clamp(GHI_GSA / GHI_PVGIS(angle=0), 0.85, 1.05)    ; no GSA → k = 1
4)  H_POA_adj_i = k × H_POA_i ;  E0_adj_i = k × E0_i
5)  PR_model_i = E0_i / H_POA_i                              ; Group A — never re-apply
6)  f_sys = Π(1 − loss_j), j ∈ Group B                      ; default ≈ 0.895
7)  f_shade_i = (1 − near_shading_i) × (1 − row_shading_i)  ; skip near_shading if
                                                              ; already sent as userhorizon
8)  Yspec_i = E0_adj_i × f_sys × f_shade_i                  ; kWh/kWp/yr, P50, year 1
9)  E_i = P_DC_i × Yspec_i ;  E_total = Σ E_i ;  P_DC = Σ P_DC_i
10) PR_i = Yspec_i / H_POA_adj_i   (POA basis; flag whether shading is included)
    PR_system = E_total / Σ(P_DC_i × H_POA_adj_i)
11) σ = √(σ_res² + σ_model² + σ_loss² + σ_shade² + (SD_y/E_y)²/N)
    P90 = P50 × (1 − 1.282σ) ;  P99 = P50 × (1 − 2.326σ)
12) Lifetime (PVsyst ageing method, linear, mid-year):
    E_n = E_0 × (1 − d × (n − 0.5)),  n = 1…20
    E_0 = step 9 result (includes LID in Group B, no ageing)
    d = 0.6%/yr rooftop, 0.45%/yr ground (Thai measured 0.62 / 0.42)
    P90_n = P50_n × p90Factor   ; degradation is NOT added to σ (PVsyst treats it
                                ; as incompatible with the P90 concept)
13) GHI shown to customer = GHI_GSA if available, else GHI_PVGIS(angle=0), with source label
```

Rules:
- All geometry and kWp come from the TCRoof layout (§2.1). Faces with identical (tilt, azimuth, mounting) share one PVGIS call.
- Clipping loss in Group B follows the layout's DC/AC ratio: ≤ 1.2 → 0.5%; 1.2–1.3 → 1%; > 1.3 → 2% and add a warning (engineering defaults, confirm in PVsyst).
- **Hard-code `loss=0`** in the PVGIS client. Never multiply `f_sys` onto a result fetched with `loss=14`.
- One extra `angle=0` call per site gives ERA5 GHI for computing k (Bangkok: `H(i)_y` at angle 0 = 1,875.96 kWh/m²).
- σ_res = 5% when k comes from GSA; 8% when ERA5 is unscaled.

## 10. Uncertainty (P50 / P90)

| Component | Default σ |
|---|---|
| Resource (GSA-scaled / ERA5 only) | 5% / 8% |
| Transposition + thermal model | 3% |
| Loss assumptions | 4% |
| Shading | 2.5% (lower for open ground mounts) |
| Inter-annual variability, 1 year | 2% (÷ √N for N-year mean) |
| **Total** | **≈ 7.8% → P90 ≈ 0.90 × P50** (ERA5 only: ≈ 10% → 0.87) |

Consistent with Solargis' SE Asia P90 ±8% and IEA PVPS T13 finding of 3.9–9.7% SD between independent assessors. In Thailand IAV is small relative to resource/model terms, so 1-year and 10-year P90 differ by < 1%. Component values are reasoned defaults, not Thai measurements.

## 11. Customer presentation

- Show the loss chain from irradiation to grid, P50 and P90, data source, and assumptions (IEA PVPS T13 practice).
- Show ranges, not false precision (e.g. "106,000–115,000 kWh/yr", not "116,000").
- **Never present P50 as guaranteed.** Any guarantee should reference P90 or lower, and a temperature-corrected PR per IEC 61724-1.
- Near shading: MCS sun-path method (within ~10% of annual yield for most systems) — must use a Thai-latitude sun path (May–July sun passes to the north).
- Disclaimer (TH/EN, required on every output):
  > Preliminary estimate based on [source, years] irradiance data and standard loss assumptions. First-year yield X kWh (P50); conservative case Y kWh (P90). Actual output varies with weather, cleaning, shading and equipment. Final design will be confirmed with PVsyst.
- Attribution: "PVGIS © European Union"; "Global Solar Atlas 2.0, Solargis / World Bank (ESMAP), CC BY 4.0".
- No OCPB/ERC rule on yield-estimate disclaimers was found.

## 12. Tariff hook (baht savings)

- `Savings = E_self × retail tariff (incl. Ft, VAT) + E_export × export rate`.
- People's solar programme export rate **2.20 THB/kWh**. ERC draft (10 Jun 2026): 10-year contract, ≤ 5 kW per meter, 500 MW round. A later headline cites 10,000 MW / 20 years — conflicting, unconfirmed. Retail tariff (~4+ THB) unconfirmed.
- C&I / government sites are often zero-export: surplus becomes curtailment.
- Self-consumption needs an hourly PV-vs-load comparison (PVGIS `seriescalc`, ~1 MB/year, free) — stub only in this phase.
- **Tariffs are server-side config, never hard-coded.**

## 13. Data model (Swift)

```swift
enum AzimuthSource: String, Codable { case compass, mapEdge, sunSighting, googleSolar, drone, manual, designed }
enum GeometrySource: String, Codable { case measured, designed, optimalSuggested }
enum DataSource: String, Codable { case pvgisERA5, gsaSolargis, pvwattsNSRDB, nasaPower, bundledGrid, openMeteoHimawari }

enum MountingType: String, Codable {
    case pitchedFlush, pitchedRailed             // pitched roof
    case flatRoofTilted, flatRoofEastWest        // flat roof
    case groundFixed                             // ground mount (trackers: later phase)
    var pvgisMounting: String { self == .pitchedFlush ? "building" : "free" }
}

struct ArrayLayout: Codable {                    // flat roof / ground only
    var moduleSlantLengthM: Double               // L
    var rowPitchM: Double
    var gcr: Double { moduleSlantLengthM / rowPitchM }
    var parapetHeightM: Double?                  // flat roof
    var rowShadingLossFrac: Double               // from sun position, 21 Dec
    var bifacial: Bool
    var albedo: Double?                          // shown separately, not in P50
}

struct OrientationEvidence: Codable {          // optional; only if a measure aid was used
    var azimuthSource: AzimuthSource
    var headingAccuracyDeg: Double?              // CLHeading
    var magneticFieldMicroT: Double?             // |B|; expected ~42–45 µT
    var crossCheckDeltaDeg: Double?              // vs Google Solar / map edge; > 10° → warning
}

struct ArrayFaceInput: Codable, Identifiable {
    let id: UUID
    var layoutFaceID: String                     // ID of the roof face / array block in the TCRoof layout
    var label: String                            // e.g. "Gable – East"
    var mounting: MountingType
    var geometrySource: GeometrySource           // pitched = .measured/entered; flat/ground = .designed
    var tiltDeg: Double                          // 0 = flat
    var azimuthDegTrueN: Double                  // canonical: 0 = N, clockwise
    var moduleCount: Int
    var moduleWp: Double
    var pDCkWp: Double { Double(moduleCount) * moduleWp / 1000 }
    var nearShadingLossFrac: Double              // 0...1
    var userHorizonDeg: [Double]?                // from N, clockwise, equal steps
    var layout: ArrayLayout?                     // flat roof / ground
    var evidence: OrientationEvidence?
    var pvgisAspect: Double { var a = azimuthDegTrueN - 180; if a <= -180 { a += 360 }; return a }
}

struct SiteInput: Codable {
    var latitude: Double, longitude: Double
    var projectID: String
    var layoutRevision: Int                      // traceability to the layout used
    var inverterACkW: Double?                    // → DC/AC ratio → clipping loss
    var dcAcRatio: Double? { inverterACkW.map { faces.reduce(0) { $0 + $1.pDCkWp } / $0 } }
    var calculatedAt: Date
    var faces: [ArrayFaceInput]
    var lossProfile: LossProfile
    var tariff: TariffConfig?
}

struct LossProfile: Codable {                    // Group B only (PVGIS covers Group A)
    var version: String                          // "TCRoof-TH-2026.1"
    var soiling = 0.03, lid = 0.01, mismatch = 0.01, dcWiring = 0.015
    var inverter = 0.025, acWiring = 0.005, clipping = 0.005, availability = 0.01
    var degradationPerYear = 0.006               // rooftop; ground 0.0045. Applied linearly, mid-year (PVsyst)
    var factor: Double {
        [soiling, lid, mismatch, dcWiring, inverter, acWiring, clipping, availability]
            .reduce(1) { $0 * (1 - $1) }
    }
}

struct Provenance: Codable {
    var source: DataSource
    var endpoint: String                         // "re.jrc.ec.europa.eu/api/v5_3/PVcalc"
    var radiationDB: String?                     // "PVGIS-ERA5"
    var yearMin: Int?, yearMax: Int?             // 2005, 2023
    var datasetVersion: String?                  // GSA "2.2.68"
    var snappedLat: Double?, snappedLon: Double?
    var requestURL: String
    var fetchedAt: Date
    var attribution: String
}

struct FaceResult: Codable {
    let faceID: UUID
    var e0kWhPerKWp: Double                      // PVGIS, loss=0
    var hPOAkWhm2: Double, hPOAAdjkWhm2: Double
    var lAOIPct: Double, lSpecPct: Double, lTGPct: Double   // l_spec parsed from String
    var sdYkWhPerKWp: Double
    var specificYieldP50: Double                 // kWh/kWp/yr
    var annualEnergyP50kWh: Double
    var prPOA: Double
    var prIncludesShading: Bool
    var monthlyKWh: [Double]                     // 12 values
}

struct Uncertainty: Codable {
    var sigmaResource: Double, sigmaModel: Double, sigmaLoss: Double
    var sigmaShade: Double, sigmaIAV: Double
    var sigmaTotal: Double
    var p90Factor: Double { 1 - 1.282 * sigmaTotal }
    var p99Factor: Double { 1 - 2.326 * sigmaTotal }
}

struct YieldEstimate: Codable {
    let id: UUID
    var schemaVersion: Int
    var input: SiteInput
    var ghiDisplayedkWhm2: Double, ghiSource: DataSource
    var resourceScaleK: Double                   // GSA / PVGIS, clamped 0.85–1.05
    var faces: [FaceResult]
    var systemPR: Double, systemSpecificYieldP50: Double
    var annualEnergyP50kWh: Double, annualEnergyP90kWh: Double   // year 1
    var yearlyP50kWh: [Double]                   // 20 values, PVsyst-style ageing
    var lifetimeP50kWh: Double, lifetimeP90kWh: Double
    var uncertainty: Uncertainty
    var provenance: [Provenance]
    var crossChecks: [String: Double]            // "gsaPVOUT": 1447.9, "pvwattsNSRDB": 1400
    var warnings: [String]                       // "ERA5-only", "azimuth cross-check > 10°", ...
    var isPreliminary: Bool = true
}

struct TariffConfig: Codable {                   // server-side config; never hard-coded
    var retailTHBperKWh: Double
    var exportTHBperKWh: Double?                 // 2.20 (people's programme, ≤ 5 kW)
    var selfConsumptionFrac: Double
    var zeroExport: Bool
    var effectiveFrom: Date
    var sourceNote: String
}

struct CacheKey: Hashable, Codable {             // ERA5 is ~0.25°; snapping to 0.05° loses nothing
    var lat2: Int, lon2: Int                     // round(lat / 0.05)
    var tiltDeg: Int, aspectDeg: Int
    var mounting: MountingType
    var horizonHash: String?
    var source: DataSource
    var sourceVersion: String                    // "v5_3/ERA5/2005-2023"
}
```

## 14. Networking, caching, offline

- PVGIS client: `URLSession`, timeout 15–20 s, 1–2 retries with jitter, respect 30 req/s. Call directly from the device or through a backend proxy.
- Cache results by `CacheKey`; invalidate when `yearMax` or `datasetVersion` changes.
- **Offline fallback 1:** bundled precomputed PVGIS grid for Thailand (~0.25°, ~1,000 cells × a set of tilt/azimuth/mounting combos; generation takes minutes at 30 req/s). Interpolate on device; mark provenance `bundledGrid`.
- **Online fallback 2:** PVWatts v8 `dataset=nsrdb` at `developer.nlr.gov` (after terms check).
- NASA POWER: sanity check only.
- Open-Meteo: only if a Professional plan is purchased for a concrete need (e.g. recent-year Himawari time series). **Never use the free tier in the company app.**

## 15. Open items before release

1. Confirm PVGIS Usage Conditions (commercial use, attribution wording).
2. Confirm GSA endpoint use in production with ESMAP/Solargis (undocumented, no SLA).
3. Confirm NLR/api.data.gov terms for non-US commercial use (PVWatts fallback).
4. Confirm Open-Meteo 2026 pricing if it is ever needed.
5. ~~Verify Group A values with a live PVGIS `loss=0` call.~~ Done 2026-10-20 (see §6.3).
6. Confirm final ERC export rate and contract term; confirm retail tariff.
7. Decide whether to buy Solargis/Meteonorm API to match the data source engineers use in PVsyst (later phase).

## 16. Follow-up

Store provenance and `LossProfile.version` with every estimate, then compare against the engineers' PVsyst results and post-COD monitoring data to calibrate k and PR from the company's own fleet. No public Thai dataset does this today.

## 17. References

- PVsyst ageing — https://www.pvsyst.com/help/project-design/array-and-system-losses/ageing-pv-modules-degradation/index.html ; forum clarification — https://forum.pvsyst.com/topic/4365-pvsyst-aging-_-clarification-on-degradation-calculation-in-pvsyst/
- PVsyst P50/P90 — https://www.pvsyst.com/help/project-design/p50-p90-evaluations.html
- PVGIS API docs — https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/api-non-interactive-service_en
- PVGIS data sources & calculation methods — https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/pvgis-data-sources-calculation-methods_en
- PVGIS 5.3 release — https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/pvgis-releases/pvgis-53_en
- PVGIS updates — https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/pvgis-releases/updates-bug-fixes-and-history_en
- EU reuse decision 2011/833/EU — https://eur-lex.europa.eu/eli/dec/2011/833/oj
- Open-Meteo historical API — https://open-meteo.com/en/docs/historical-weather-api
- Open-Meteo satellite radiation API — https://open-meteo.com/en/docs/satellite-radiation-api
- Open-Meteo terms — https://open-meteo.com/en/terms ; pricing — https://open-meteo.com/en/pricing
- Global Solar Atlas (World Bank Data Catalog) — https://datacatalog.worldbank.org/search/dataset/0038509/global-solar-atlas-application
- NREL → NLR rename — https://www.energy.gov/eere/articles/energy-department-renames-nrel-national-lab-rockies
- Solargis validation — https://kb.solargis.com/docs/validation-of-solar-irradiance-data ; uncertainty — https://kb.solargis.com/docs/uncertainty-estimates ; P50/P90 — https://kb.solargis.com/docs/p50-p90-and-other-scenarios
- Solcast validation — https://solcast.com/validation-and-accuracy ; terms — https://solcast.com/terms-of-use
- NREL PR methodology (Dierauf et al. 2013) — https://www.nrel.gov/docs/fy13osti/57991.pdf
- IEA PVPS T13-18 (yield uncertainty) — https://iea-pvps.org/wp-content/uploads/2021/01/Executive-Summary-IEA-PVPS-T13-18_2020-Uncertainties-in-Yield-Assessments-and-PV-LCOE.pdf
- IEA PVPS T13 2017 — https://iea-pvps.org/wp-content/uploads/2020/01/Uncertainties_in_PV_System_Yield_Predictions_and_Assessments_by_Task_13.pdf
- DEDE solar map (via EPPO) — https://eppo.go.th/images/Power/renewable-energy/19.pdf
- Janjai et al. — https://www.nepjol.info/index.php/JIE/article/view/5939
- Chanalert et al. 2022 — https://li01.tci-thaijo.org/index.php/sehs/article/view/256713
- Sabooding et al. 2025 — https://www.frontiersin.org/journals/environmental-science/articles/10.3389/fenvs.2025.1657447/full
- Urraca et al. 2018 — https://publications.jrc.ec.europa.eu/repository/handle/JRC108636
- RMUTT rooftop vs ground — https://research.rmutt.ac.th/?p=19666
- KMUTT soiling — https://kirim.kmutt.ac.th/converis/portal/detail/Publication/1478036503?lang=en_GB
- MCS MGD 005 shade analysis — https://mcscertified.com/wp-content/uploads/2025/02/MGD-005-Solar-PV-Shade-Analysis-V1.0-1.pdf
- Apple CMAttitudeReferenceFrame — https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe
- Apple CLHeading.headingAccuracy — https://developer.apple.com/documentation/corelocation/clheading/headingaccuracy
- Google Solar API release notes — https://developers.google.com/maps/documentation/solar/release-notes
- Export rate 2.20 THB — https://thaipublica.org/2026/04/nepc-solar-rooftop-buyback-rate-2-20-baht/ ; ERC draft — https://www.thansettakij.com/sustainable/net-zero/661329
