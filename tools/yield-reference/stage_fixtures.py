"""Step-by-step fixtures for the Swift port of the hourly chain (TCRoofKit/Sources/PVYield/Hourly).

Writes, next to the golden scenarios, without touching them:
  stages-60kW-ERA5.json   sun position (raw SPA and the hour's effective sun), the DNI fix, airmass, Perez parts,
                          IAM, cell temperature and module MPP for every 37th hour of 60kW-ERA5, the Perez parts of a
                          second plane (30° east), and Marion's diffuse IAM factors for a few tilts.
  60kW-ERA5-faces-horizon.json
                          a two-face gable (east with a horizon and 2 % near shading, west open) on the 60 kW design,
                          the multi-face and horizon path of `run`.

Run:  python3 -I stage_fixtures.py   (pvlib >= 0.10; 0.13 reproduces the committed golden files exactly)
"""
from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

import numpy as np
import pandas as pd
import pvlib
from pvlib import iam

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import reference_engine as R  # noqa: E402

GOLD = R.HERE.parents[1] / "TCRoofKit" / "Tests" / "PVYieldTests" / "Fixtures" / "golden"
STEP = 37


def faces_scenario() -> R.Scenario:
    base = next(s for s in R.scenarios() if s.name == "60kW-ERA5")
    return replace(base, name="60kW-ERA5-faces-horizon", faces=[
        R.Face("E", 66, tilt=15, azimuth=90, near_shading=0.02, horizon=[(60, 8), (90, 12), (120, 6)]),
        R.Face("W", 66, tilt=15, azimuth=270),
    ])


def stages() -> dict:
    sc = next(s for s in R.scenarios() if s.name == "60kW-ERA5")
    module = json.loads((R.ROOT / sc.module_json).read_text())
    df = R.load_meteo(sc)
    raw = pvlib.solarposition.get_solarposition(df.index, sc.lat, sc.lon)
    sp = R.sun_position(df, sc.lat, sc.lon)          # mutates df["dni"], df["dhi"]
    poa = R.plane_of_array(df, sp, sc)
    g_iam, g_shade, g_eff = R.effective_irradiance(poa, sc, df, None, sp)
    area = module["dimensions"]["widthM"] * module["dimensions"]["heightM"]
    eta = module["stc"]["pNomW"] / (area * 1000)
    t_cell = R.cell_temperature(poa["poa_global"], df["temp_air"], df["wind_speed"], eta, sc.thermal)
    p, i, v, _ = R.module_mpp(module, g_eff, t_cell)
    am = pvlib.atmosphere.get_relative_airmass(sp["apparent_zenith"])
    extra = pvlib.irradiance.get_extra_radiation(df.index)
    east = R.plane_of_array(df, sp, replace(sc, tilt=30, azimuth=90))
    iam_b = iam.ashrae(poa["aoi"], sc.losses.iam_b0).fillna(0.0)

    idx = list(range(0, len(df), STEP))
    f = lambda a, k: round(float(np.nan_to_num(np.asarray(a)[k])), 6)
    hours = []
    for k in idx:
        hours.append(dict(
            row=k, unix=int(df.index[k].timestamp()),
            rawApparentZenith=f(raw["apparent_zenith"], k), rawAzimuth=f(raw["azimuth"], k),
            zenith=f(sp["apparent_zenith"], k), azimuth=f(sp["azimuth"], k),
            dni=f(df["dni"], k), dhi=f(df["dhi"], k), dniExtra=f(extra, k), airmass=f(am, k),
            aoi=f(poa["aoi"], k), poaDirect=f(poa["poa_direct"], k), poaSky=f(poa["poa_sky_diffuse"], k),
            poaGround=f(poa["poa_ground_diffuse"], k), poaGlobal=f(poa["poa_global"], k), iamBeam=f(iam_b, k),
            gIAM=f(g_iam, k), gEff=f(g_eff, k), tCell=f(t_cell, k), pMpp=f(p, k), iMpp=f(i, k), vMpp=f(v, k),
            eastDirect=f(east["poa_direct"], k), eastSky=f(east["poa_sky_diffuse"], k),
            eastGround=f(east["poa_ground_diffuse"], k)))
    marion = []
    for tilt in (0, 5, 10, 15, 20, 30, 45, 60, 90):
        d = iam.marion_diffuse("ashrae", tilt, b=0.05)
        marion.append(dict(tilt=tilt, sky=round(float(d["sky"]), 10), ground=round(float(d["ground"]), 10)))
    return dict(scenario=sc.name, every=STEP, pvlib=pvlib.__version__, hours=hours, marion=marion)


def main():
    (GOLD / "stages-60kW-ERA5.json").write_text(json.dumps(stages(), indent=0))
    r = R.run(faces_scenario())
    r.pop("_hourly")
    (GOLD / "60kW-ERA5-faces-horizon.json").write_text(json.dumps(r, indent=1))
    print("stages + faces written to", GOLD)


if __name__ == "__main__":
    main()
