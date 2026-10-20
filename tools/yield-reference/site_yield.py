"""Run the reference engine for any site in Thailand from its coordinates.

    python3 -I site_yield.py --lat 18.79 --lon 98.98 --mount roof --inverter 60
    python3 -I site_yield.py --lat 14.97 --lon 102.10 --mount ground --inverter 125 --bifacial --albedo 0.2

What it does for the given location:
  1. Downloads the PVGIS 5.3 TMY (PVGIS-ERA5) for that point and caches it in data/.
  2. Reads Global Solar Atlas (Solargis) long-term GHI and optimum tilt for that point.
  3. Runs two meteo scenarios: ERA5 as-is, and ERA5 scaled to the Solargis annual GHI.
  4. Ground mount: tilt defaults to the Solargis optimum, row pitch from the 21-Dec 09:00 rule at
     that latitude. Roof: tilt/azimuth as given (default 10°, south).
  5. Writes sites/<name>.json and prints a summary.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

import pandas as pd
import pvlib

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reference_engine as R  # noqa: E402

INVERTERS = {
    "60": ("components/growatt-max-60ktl3-lv.json", R.StringDesign(11, 12)),
    "80": ("components/growatt-max-80ktl3-lv.json", R.StringDesign(13, 14)),
    "125": ("components/growatt-max-125ktl3-x-lv.json", R.StringDesign(14, 20)),
}


def fetch_tmy(lat: float, lon: float) -> str:
    rel = f"data/pvgis-tmy-era5-{lat:.4f}-{lon:.4f}.csv"
    path = R.ROOT / rel
    if not path.exists():
        import time
        for attempt in range(4):           # PVGIS has no SLA; ~1 in 10 calls gets reset
            try:
                data, *_ = pvlib.iotools.get_pvgis_tmy(lat, lon, outputformat="json", map_variables=True,
                                                       url="https://re.jrc.ec.europa.eu/api/v5_3/")
                break
            except Exception:
                if attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))
        data[["ghi", "dni", "dhi", "temp_air", "wind_speed", "relative_humidity", "pressure"]] \
            .to_csv(path, float_format="%.3f")
    return rel


def fetch_gsa(lat: float, lon: float) -> dict | None:
    url = f"https://api.globalsolaratlas.info/data/lta?loc={lat},{lon}"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            d = json.load(r)["annual"]["data"]
        return dict(ghi=float(d["GHI"]), opta=float(d["OPTA"]), pvout=float(d["PVOUT_csi"]),
                    temp=float(d["TEMP"]))
    except Exception as e:  # GSA endpoint is undocumented; keep going without it
        print(f"  Global Solar Atlas unavailable ({e}); ERA5-only results", file=sys.stderr)
        return None


def build(args) -> list[R.Scenario]:
    tmy = fetch_tmy(args.lat, args.lon)
    gsa = fetch_gsa(args.lat, args.lon)
    inv_json, design = INVERTERS[args.inverter]
    if args.strings and args.per_string:
        design = R.StringDesign(args.per_string, args.strings)

    ground = args.mount == "ground"
    tilt = args.tilt if args.tilt is not None else (round(gsa["opta"]) if (ground and gsa) else (15 if ground else 10))
    common = dict(lat=args.lat, lon=args.lon, tilt=tilt, azimuth=args.azimuth,
                  module_json="components/znshine-zxm7-uhldd144-570.json", inverter_json=inv_json,
                  design=design, meteo_csv=tmy,
                  losses=R.Losses(soiling=args.soiling, near_shading=args.near_shading))
    if ground:
        common.update(thermal=R.Thermal(u_c=29.0),
                      rows=R.RowGeometry(albedo=args.albedo, pitch_m=args.pitch),
                      bifacial=R.Bifacial(enabled=args.bifacial, frame="ground"))
    else:
        common.update(thermal=R.Thermal(u_c=args.uc),
                      bifacial=R.Bifacial(enabled=args.bifacial, frame="roof", albedo=args.albedo))

    out = [R.Scenario(name=f"{args.name}-ERA5", uncertainty=R.Uncertainty(meteo_data=0.08), **common)]
    if gsa:
        out.append(R.Scenario(name=f"{args.name}-GSA", ghi_target_kwh_m2=gsa["ghi"],
                              uncertainty=R.Uncertainty(meteo_data=0.05), **common))
    return out, gsa, tilt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--mount", choices=["roof", "ground"], default="roof")
    ap.add_argument("--tilt", type=float, default=None)
    ap.add_argument("--azimuth", type=float, default=180, help="pvlib convention, 180 = south")
    ap.add_argument("--inverter", choices=list(INVERTERS), default="60")
    ap.add_argument("--strings", type=int); ap.add_argument("--per-string", type=int)
    ap.add_argument("--bifacial", action="store_true")
    ap.add_argument("--albedo", type=float, default=None)
    ap.add_argument("--pitch", type=float, default=None, help="ground row pitch, m (default: design rule)")
    ap.add_argument("--uc", type=float, default=20.0, help="roof thermal Uc")
    ap.add_argument("--soiling", type=float, default=0.03)
    ap.add_argument("--near-shading", type=float, default=0.0)
    args = ap.parse_args()
    args.name = args.name or f"{args.lat:.4f}_{args.lon:.4f}_{args.mount}_{args.inverter}kW"
    if args.albedo is None:
        args.albedo = 0.20 if args.mount == "ground" else 0.30

    scs, gsa, tilt = build(args)
    results = []
    for sc in scs:
        r = R.run(sc); r.pop("_hourly"); results.append(r)
    site = dict(lat=args.lat, lon=args.lon, mount=args.mount, tilt=tilt, azimuth=args.azimuth,
                gsa=gsa, results=results)
    outdir = HERE / "sites"; outdir.mkdir(exist_ok=True)
    (outdir / f"{args.name}.json").write_text(json.dumps(site, indent=1))

    print(f"Site {args.lat}, {args.lon}  mount={args.mount} tilt={tilt}° azimuth={args.azimuth}°")
    if gsa:
        print(f"  Solargis/GSA: GHI {gsa['ghi']:.0f} kWh/m²/yr, optimum tilt {gsa['opta']:.0f}°, "
              f"PVOUT {gsa['pvout']:.0f} kWh/kWp, mean temp {gsa['temp']:.1f} °C")
    for r in results:
        e = r["energies_kWh"]; p = r["probability"]
        rows = f"  pitch {r['rows']['pitch_m']} m (GCR {r['rows']['gcr']})" if r.get("rows") else ""
        print(f"  {r['scenario']:40s} GHI {e['H_hor']:6.0f}  POA {e['H_inc']:6.0f}  "
              f"E_grid {e['E_grid']:>9,.0f} kWh  {r['specific_yield']:7.1f} kWh/kWp  PR {r['PR']*100:5.1f}%  "
              f"P90 {p['P90_1yr']:>9,}  25y {r['lifetime_kWh']:>11,}{rows}")


if __name__ == "__main__":
    main()
