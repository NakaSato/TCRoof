"""Step-by-step fixtures for the Swift port of the hourly chain (TCRoofKit/Sources/PVYield/Hourly).

Writes, next to the golden scenarios, without touching them:
  stages-60kW-ERA5.json   sun position (raw SPA and the hour's effective sun), the DNI fix, airmass, Perez parts,
                          IAM, cell temperature and module MPP for every 37th hour of 60kW-ERA5, the Perez parts of a
                          second plane (30° east), and Marion's diffuse IAM factors for a few tilts.
  60kW-ERA5-faces-horizon.json
                          a two-face gable (east with a horizon and 2 % near shading, west open) on the 60 kW design,
                          the multi-face and horizon path of `run`.
  stages-sheds.json       pvlib infinite sheds step by step: the view factors of a few row geometries (front and
                          back), the 21-December design pitch, and for every 37th hour the front and back sides of the
                          125kW-ERA5-ground-bifacial rows, the roof-frame rear side of 60kW-ERA5-bifacial-roof (the sun
                          turned into the roof plane), and each scenario's front, rear and effective irradiance.

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


def sheds_stages() -> dict:
    from pvlib.bifacial import infinite_sheds as IS, utils as U
    geoms = []
    for tilt, gcr, height, pitch in ((15, 0.803, 1.192, 5.697), (10, 0.853, 0.997, 5.363), (0.01, 0.990, 0.12, 2.30),
                                     (25, 0.5, 1.5, 4.0)):
        out = dict(tilt=tilt, gcr=gcr, height=height, pitch=pitch)
        for side, t in (("front", tilt), ("back", 180 - tilt)):
            max_rows = float(np.ceil(height / (pitch * pvlib.tools.tand(5))))
            out[side] = dict(
                rowSky=float(U.vf_row_sky_2d_integ(t, gcr, 0., 1.)),
                rowGround=float(U.vf_row_ground_2d_integ(t, gcr, x0=0., x1=1., g0=0., g1=1.)),
                groundSky=float(U.vf_ground_sky_2d_integ(t, gcr, height, pitch, g0=0, g1=1, max_rows=max_rows)))
        geoms.append(out)
    pitches = [dict(tilt=t, slant=4.576, pitch=R.design_pitch(13.75, 100.50, t, 4.576, 180)) for t in (10, 15, 20)]

    def setup(name):
        sc = next(s for s in R.scenarios() if s.name == name)
        df = R.load_meteo(sc)
        sp = R.sun_position(df, sc.lat, sc.lon)
        return sc, df, sp, R.plane_of_array(df, sp, sc)

    gsc, gdf, gsp, gpoa = setup("125kW-ERA5-ground-bifacial")
    sh = R.sheds(gdf, gsp, gsc)
    _, g_shade, g_front = R.effective_irradiance(gpoa, gsc, gdf, sh, gsp)
    g_rear = gsc.bifacial.bifaciality * np.where(gdf["ghi"].values > 0, sh["poa_back"], 0.0) * (1 - gsc.bifacial.rear_mismatch)

    rsc, rdf, rsp, rpoa = setup("60kW-ERA5-bifacial-roof")
    _, _, r_front = R.effective_irradiance(rpoa, rsc, rdf, None, rsp)
    r_raw = R.rear_irradiance(rdf, rsp, rpoa, rsc)

    f = lambda a, k: round(float(np.nan_to_num(np.asarray(a)[k])), 6)
    keys = ["poa_front_direct", "poa_front_sky_diffuse", "poa_front_ground_diffuse", "shaded_fraction_front",
            "poa_back_direct", "poa_back_sky_diffuse", "poa_back_ground_diffuse", "shaded_fraction_back"]
    hours = []
    for k in range(0, len(gdf), STEP):
        hours.append(dict(row=k, ground={key: f(sh[key], k) for key in keys} | dict(
            gShade=f(g_shade, k), gFront=f(g_front, k), gRear=f(g_rear, k)),
            roof=dict(rearRaw=f(r_raw, k), gFront=f(r_front, k))))
    return dict(groundScenario=gsc.name, roofScenario=rsc.name, every=STEP, pvlib=pvlib.__version__,
                pitch=round(float(sh["pitch_m"]), 9), geometries=geoms, designPitches=pitches, hours=hours)


def main():
    (GOLD / "stages-60kW-ERA5.json").write_text(json.dumps(stages(), indent=0))
    r = R.run(faces_scenario())
    r.pop("_hourly")
    (GOLD / "60kW-ERA5-faces-horizon.json").write_text(json.dumps(r, indent=1))
    (GOLD / "stages-sheds.json").write_text(json.dumps(sheds_stages(), indent=0))
    print("stages, faces and sheds written to", GOLD)


if __name__ == "__main__":
    main()
