"""PWA (กปภ.) Solar Rooftop stations: yield for each station from its coordinates.

Inverter mix per station is not given, only total AC kW. Each station is modelled as one
virtual inverter with that AC rating and the Growatt MAX 125KTL3-X LV efficiency curve
(all Growatt MAX curves are within 0.2 pt of each other); DC/AC per station is 0.99–1.20,
so clipping and inverter choice change E_Grid by well under 0.5 %.
"""
from __future__ import annotations
import json, math, sys, csv
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reference_engine as R  # noqa: E402
import site_yield as S  # noqa: E402

STATIONS = [
    # name, branch, PEA zone, PWA zone, DC kWp, AC kW, lat, lon
    ("สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล", "กปภ.สาขาชัยบาดาล", "น.3", 2, 163.02, 160, 15.20843, 101.14031),
    ("สถานีผลิตจ่ายน้ำกุดตาเพชร", "กปภ.สาขาชัยบาดาล", "น.3", 2, 137.94, 125, 15.41535, 101.3489),
    ("สถานีผลิตน้ำบ้านหมี่", "กปภ.สาขาบ้านหมี่", "น.3", 2, 150.48, 125, 15.04596, 100.54901),
    ("สถานีผลิตน้ำลพบุรี", "กปภ.สาขาลพบุรี", "น.3", 2, 182.4, 185, 14.79792, 100.63703),
    ("สถานีผลิตน้ำบ้านนา", "กปภ.สาขาบ้านนา", "ก.1", 2, 88.92, 80, 14.25748, 101.0725),
    ("สถานีผลิตน้ำวัดชัยสิทธาวาส", "กปภ.สาขาปทุมธานี", "ก.1", 2, 379.62, 330, 14.039274, 100.538409),
    ("สถานีจ่ายน้ำลาดหลุมแก้ว", "กปภ.สาขาปทุมธานี", "ก.1", 2, 230.28, 205, 14.070193, 100.450894),
    ("สถานีผลิต-จ่ายน้ำหนองโดน", "กปภ.สาขาพระพุทธบาท", "ก.1", 2, 349.98, 310, 14.69744, 100.74083),
    ("โรงกรองน้ำหนองแค", "กปภ.สาขาหนองแค", "ก.1", 2, 574.56, 540, 14.35302, 100.8412),
]


def virtual_inverter(ac_kw: float) -> str:
    base = json.loads((R.ROOT / "components/growatt-max-125ktl3-x-lv.json").read_text())
    k = ac_kw * 1000 / base["acNominalPowerW"]
    base.update(id=f"virtual-growatt-{ac_kw:g}kW", model=f"Virtual {ac_kw:g} kW (MAX 125KTL3-X curve)",
                acNominalPowerW=ac_kw * 1000, acMaxApparentPowerVA=base["acMaxApparentPowerVA"] * k,
                mpptCount=999, nightConsumptionW=base["nightConsumptionW"] * math.ceil(k))
    base["lossModel"] = dict(base["lossModel"], pDC0W=base["lossModel"]["pDC0W"] * k)
    rel = f"data/virtual-inverter-{ac_kw:g}kW.json"
    (R.ROOT / rel).write_text(json.dumps(base, indent=1))
    return rel


FACES_CSV = R.ROOT / "data/pwa-faces.csv"


def load_faces() -> dict:
    """Survey input: one row per roof face. azimuth_deg is a compass bearing (0 = N, 90 = E,
    180 = S, 270 = W). shading_pct is the annual loss from the shading survey for that face.
    horizon is optional: "az:el;az:el;..." (degrees) for far obstacles such as trees."""
    import csv
    if not FACES_CSV.exists():
        return {}
    out = {}
    with open(FACES_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            hz = None
            if row.get("horizon"):
                hz = [tuple(float(x) for x in p.split(":")) for p in row["horizon"].split(";") if p.strip()]
            out.setdefault(row["station"], []).append(R.Face(
                name=row["face"], n_modules=int(row["modules"]), tilt=float(row["tilt_deg"]),
                azimuth=float(row["azimuth_deg"]), near_shading=float(row["shading_pct"] or 0) / 100,
                horizon=hz))
    return out


def main(tilt=10.0, azimuth=180.0):
    faces_by_station = load_faces()
    rows = []
    for name, branch, pea, pwa, kwp, kw, lat, lon in STATIONS:
        n_mod = round(kwp / 0.57)
        assert abs(n_mod * 0.57 - kwp) < 1e-6, name
        tmy = S.fetch_tmy(lat, lon)
        gsa = S.fetch_gsa(lat, lon)
        faces = faces_by_station.get(name)
        if faces and sum(f.n_modules for f in faces) != n_mod:
            print(f"  ! {name}: faces total {sum(f.n_modules for f in faces)} modules, station has {n_mod}")
        common = dict(lat=lat, lon=lon, tilt=tilt, azimuth=azimuth,
                      module_json="components/znshine-zxm7-uhldd144-570.json",
                      inverter_json=virtual_inverter(kw), design=R.StringDesign(1, 1), n_modules=n_mod,
                      faces=faces, meteo_csv=tmy, bifacial=R.Bifacial(enabled=True, frame="roof"))
        res = {}
        res["ERA5"] = R.run(R.Scenario(name=f"{name}-ERA5", uncertainty=R.Uncertainty(meteo_data=0.08), **common))
        if gsa:
            res["GSA"] = R.run(R.Scenario(name=f"{name}-GSA", ghi_target_kwh_m2=gsa["ghi"],
                                          uncertainty=R.Uncertainty(meteo_data=0.05), **common))
        for r in res.values():
            r.pop("_hourly")
        main_r = res.get("GSA", res["ERA5"])
        e = main_r["energies_kWh"]; p = main_r["probability"]
        rows.append(dict(
            station=name, branch=branch, pea_zone=pea, pwa_zone=pwa, lat=lat, lon=lon,
            modules=n_mod, dc_kwp=kwp, ac_kw=kw, dc_ac=round(kwp / kw, 3),
            meteo="Solargis-scaled" if "GSA" in res else "ERA5",
            ghi=round(e["H_hor"]), poa=round(e["H_inc"]),
            e_grid_p50=round(e["E_grid"]), specific_yield=main_r["specific_yield"], pr=main_r["PR"],
            p90_1yr=p["P90_1yr"], lifetime_25y=main_r["lifetime_kWh"],
            e_grid_era5=round(res["ERA5"]["energies_kWh"]["E_grid"]),
            clipped_hours=main_r["hours"]["clipped"],
            faces=len(faces) if faces else 1,
            shading_loss_pct=[b for a, b in main_r["loss_diagram"] if a.startswith("Shading")][0],
            monthly=[m["E_grid"] for m in main_r["monthly"]]))
        print(f"{name:32s} {kwp:7.2f} kWp {kw:4d} kW  GHI {e['H_hor']:5.0f}  E {e['E_grid']:>9,.0f}  "
              f"{main_r['specific_yield']:6.1f} kWh/kWp  PR {main_r['PR']*100:4.1f}%  P90 {p['P90_1yr']:>9,}  "
              f"ERA5 {res['ERA5']['energies_kWh']['E_grid']:>9,.0f}  clip h {main_r['hours']['clipped']}")
    out = HERE / "sites"; out.mkdir(exist_ok=True)
    (out / "pwa-phase1-sample.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    with open(out / "pwa-phase1-sample.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=[k for k in rows[0] if k not in ("monthly",)] + [f"m{i}" for i in range(1, 13)])
        w.writeheader()
        for r in rows:
            d = {k: v for k, v in r.items() if k != "monthly"}
            d.update({f"m{i+1}": v for i, v in enumerate(r["monthly"])})
            w.writerow(d)
    tot = lambda k: sum(r[k] for r in rows)
    print(f"TOTAL {tot('dc_kwp'):.2f} kWp  {tot('ac_kw')} kW  E_grid P50 {tot('e_grid_p50'):,}  P90 {tot('p90_1yr'):,}  25y {tot('lifetime_25y'):,}")


if __name__ == "__main__":
    main()
