"""TCRoof reference yield engine (Python / pvlib).

PVsyst-style hourly chain used as the specification and golden-data source for the Swift
port in TCRoofKit/Sources/PVYield. Every step is a separate function so the Swift engine can be tested
step by step against `golden/*.json`.

Run:  python3 -I reference_engine.py   (needs pvlib >= 0.10, pandas, numpy)

Chain per hour (PVsyst order):
  GHI/DNI/DHI ─► sun position ─► Perez transposition (GlobInc) ─► IAM ─► soiling (GlobEff)
  ─► cell temperature (PVsyst Uc/Uv) ─► one-diode module MPP (PVsyst model)
  ─► module quality, LID, mismatch ─► DC ohmic ─► MPPT current limit ─► inverter
  efficiency ─► clipping ─► AC ohmic ─► unavailability, night consumption ─► E_Grid
Then: PR, monthly table, PVsyst ageing (linear, mid-year), P50/P90.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field, asdict
from pathlib import Path

import numpy as np
import pandas as pd
import pvlib
from pvlib import iam, irradiance, pvsystem, temperature

HERE = Path(__file__).resolve().parent
ROOT = HERE
K_B = 1.380649e-23
Q_E = 1.602176634e-19


# ----------------------------------------------------------------------------- config
@dataclass
class Losses:
    albedo: float = 0.20
    iam_b0: float = 0.05            # ASHRAE
    soiling: float = 0.03
    module_quality: float = 0.0     # negative = gain
    lid: float = 0.01
    mismatch: float = 0.01
    dc_ohmic_at_stc: float = 0.015
    ac_ohmic_at_nominal: float = 0.005
    unavailability: float = 0.01
    near_shading: float = 0.0       # not modelled geometrically; enter from survey


@dataclass
class Thermal:
    u_c: float = 20.0               # PVsyst: 29 free, 20 semi-integrated, 15 integrated
    u_v: float = 0.0
    alpha: float = 0.9


@dataclass
class StringDesign:
    modules_per_string: int
    strings: int


@dataclass
class Bifacial:
    """Rear-side gain, pvlib infinite-sheds (2D view factors, like PVsyst's bifacial model).

    frame = "roof": modules railed parallel to a pitched roof. The roof plane is the
    'ground' the rear side sees, so the sun is rotated into the roof frame first.
    frame = "ground": racks on horizontal ground or a flat roof.
    """
    enabled: bool = False
    bifaciality: float = 0.80           # Znshine datasheet (80 ± 10 %)
    albedo: float = 0.30                # surface under the array (coloured metal sheet ~0.3)
    height_m: float = 0.12              # rear surface centre above that surface
    pitch_m: float = 2.30               # row pitch measured in that surface
    module_slant_m: float = 2.278       # module length across the row
    tilt_rel_deg: float = 0.0           # module tilt relative to that surface
    frame: str = "roof"
    structure_shading: float = 0.05     # rails/frames on the rear (PVsyst-style default)
    rear_mismatch: float = 0.10         # mismatch from non-uniform rear light (PVsyst-style default)
    transmission: float = 0.0


@dataclass
class RowGeometry:
    """Rows of racks on horizontal ground or a flat roof (ground mount, flat-roof racks).

    Enables row-to-row shading on the front (PVsyst "unlimited sheds"-style: linear beam
    shading × electrical factor, reduced sky view, shaded ground) and sets the geometry the
    bifacial rear model uses.
    """
    slant_m: float = 4.576              # 2 modules in portrait (2 × 2.278 m + 0.02 m gap)
    clearance_m: float = 0.60           # lowest module edge above ground
    pitch_m: float | None = None        # None → design rule (no row shading 09:00–15:00 on 21 Dec)
    albedo: float = 0.20                # grass ≈ 0.2, bare soil 0.15–0.25, white gravel ≈ 0.4
    electrical_factor: float = 1.0      # 1 = linear; >1 approximates string-level loss of partial shade

    def height_m(self, tilt_deg: float) -> float:
        return self.clearance_m + 0.5 * self.slant_m * math.sin(math.radians(tilt_deg))


def design_pitch(lat: float, lon: float, tilt_deg: float, slant_m: float, azimuth_deg: float = 180,
                 local_hour: float = 9.0, tz: str = "Asia/Bangkok") -> float:
    """Row pitch so the row behind is unshaded at `local_hour` (and its mirror) on 21 December."""
    t = pd.DatetimeIndex([pd.Timestamp(2026, 12, 21, int(local_hour), int((local_hour % 1) * 60), tz=tz)])
    spos = pvlib.solarposition.get_solarposition(t, lat, lon)
    alt = math.radians(90 - float(spos["apparent_zenith"].iloc[0]))
    rel = math.radians(float(spos["azimuth"].iloc[0]) - azimuth_deg)
    b = math.radians(tilt_deg)
    rise = slant_m * math.sin(b)
    gap = rise * abs(math.cos(rel)) / math.tan(alt)
    return slant_m * math.cos(b) + gap


@dataclass
class Face:
    """One roof face / array block with its own orientation and shading.

    azimuth uses the pvlib convention (180 = south, 90 = east, 270 = west).
    near_shading: annual shading loss from the site survey (e.g. Solar Pathfinder / SunEye),
    applied to all front irradiance of this face. horizon: far obstacles as
    [(azimuth_deg_from_north, elevation_deg), ...]; cuts beam when the sun is below it and
    reduces sky diffuse by the blocked share of the sky.
    """
    name: str
    n_modules: int
    tilt: float
    azimuth: float
    near_shading: float = 0.0
    horizon: list | None = None
    u_c: float | None = None


@dataclass
class Uncertainty:
    """PVsyst P50-P90 style components (1 σ, fraction). Degradation is excluded."""
    climate_iav: float = 0.020      # year-to-year; PVGIS SD_y at Bangkok ≈ 2.0 %
    meteo_data: float = 0.05        # 0.05 when scaled to Solargis/GSA, 0.08 for ERA5 as-is
    pv_module_model: float = 0.01
    module_quality: float = 0.01
    soiling_mismatch: float = 0.01
    inverter: float = 0.005
    unmodelled_shading: float = 0.02


@dataclass
class Scenario:
    name: str
    lat: float
    lon: float
    tilt: float
    azimuth: float                  # pvlib convention: 180 = south
    module_json: str
    inverter_json: str
    design: StringDesign
    meteo_csv: str
    ghi_target_kwh_m2: float | None = None   # scale TMY to this annual GHI (e.g. GSA/Solargis)
    losses: Losses = field(default_factory=Losses)
    thermal: Thermal = field(default_factory=Thermal)
    uncertainty: Uncertainty = field(default_factory=Uncertainty)
    ageing_per_year: float = 0.004  # Znshine warranty: 0.40 %/yr after year 1
    years: int = 25
    ac_limit: str = "nominal"       # or "max_apparent"
    bifacial: Bifacial = field(default_factory=Bifacial)
    rows: RowGeometry | None = None   # set for ground mount / flat-roof racks
    n_modules: int | None = None      # overrides design product (mixed string lengths / several inverters)
    faces: list | None = None         # list[Face]: several orientations feeding the same inverter(s)
    horizon: list | None = None       # single-face horizon [(az_from_north, elev_deg), ...]


# ----------------------------------------------------------------------------- steps
def load_meteo(sc: Scenario) -> pd.DataFrame:
    df = pd.read_csv(ROOT / sc.meteo_csv, index_col=0, parse_dates=True)
    if sc.ghi_target_kwh_m2:
        k = sc.ghi_target_kwh_m2 / (df["ghi"].sum() / 1000)
        df[["ghi", "dni", "dhi"]] *= k
    return df


def sun_position(df: pd.DataFrame, lat: float, lon: float) -> pd.DataFrame:
    """Sun geometry for hourly PVGIS TMY rows, and DNI made consistent with it.

    PVGIS-ERA5 TMY GHI/DHI are averages over the hour that starts at the timestamp, but the
    file's DNI was derived with the sun position AT the timestamp. That pushes beam light
    into the morning: an east face came out equal to south and a west face 8 % lower,
    against PVGIS's own E/S 0.971 and W/S 0.958 at 10° in Bangkok.

    Fix: use the mean cos θz over the sunlit part of the hour (5-min steps) as the effective
    zenith, the mid-hour azimuth, and recompute DNI = (GHI − DHI) / mean cos θz. This gives
    E/S 0.967 and W/S 0.958, with the south-facing total unchanged (−0.05 %). Mutates
    df["dni"] (and moves beam into DHI in the few sunrise/sunset hours with cos θz < 0.02).
    """
    subs = [pvlib.solarposition.get_solarposition(df.index + pd.Timedelta(minutes=m), lat, lon)
            for m in range(0, 60, 5)]
    cos_all = np.array([np.clip(np.cos(np.radians(s["apparent_zenith"].values)), 0, None) for s in subs])
    up = cos_all > 0
    frac_up = up.mean(axis=0)
    with np.errstate(divide="ignore", invalid="ignore"):
        cos_eff = np.where(frac_up > 0, cos_all.sum(axis=0) / np.maximum(up.sum(axis=0), 1), 0.0)
    # azimuth at the middle of the sunlit part of the hour
    az_all = np.array([s["azimuth"].values for s in subs])
    first = np.argmax(up, axis=0); last = len(subs) - 1 - np.argmax(up[::-1], axis=0)
    mid_idx = np.where(frac_up > 0, (first + last) // 2, 6)
    azimuth = az_all[mid_idx, np.arange(len(df))]
    zen = np.where(frac_up > 0, np.degrees(np.arccos(np.clip(cos_eff, 0, 1))), 95.0)

    bh = (df["ghi"] - df["dhi"]).clip(lower=0).values
    cos_mean_hour = cos_all.mean(axis=0)                 # beam energy over the whole hour
    ok = cos_mean_hour > 0.02
    dni_extra = irradiance.get_extra_radiation(df.index).values
    dni = np.where(ok, np.minimum(bh / np.where(ok, cos_mean_hour, 1), dni_extra), 0.0)
    df["dhi"] = np.where(ok, df["dhi"].values, df["ghi"].values)
    # keep GHI = DNI·cosθz_eff·frac_up + DHI by expressing DNI against the effective zenith
    with np.errstate(divide="ignore", invalid="ignore"):
        df["dni"] = np.where(ok & (cos_eff > 0), dni * cos_mean_hour / np.where(cos_eff > 0, cos_eff, 1), 0.0)
    return pd.DataFrame({"apparent_zenith": zen, "zenith": zen, "azimuth": azimuth}, index=df.index)


def plane_of_array(df, sp, sc: Scenario) -> pd.DataFrame:
    dni_extra = irradiance.get_extra_radiation(df.index)
    am = pvlib.atmosphere.get_relative_airmass(sp["apparent_zenith"])
    poa = irradiance.get_total_irradiance(
        sc.tilt, sc.azimuth, sp["apparent_zenith"], sp["azimuth"], df["dni"], df["ghi"], df["dhi"],
        dni_extra=dni_extra, airmass=am, model="perez", albedo=sc.losses.albedo).fillna(0.0)
    poa["aoi"] = irradiance.aoi(sc.tilt, sc.azimuth, sp["apparent_zenith"], sp["azimuth"])
    return poa


def sheds(df, sp, sc: Scenario) -> dict:
    """pvlib infinite-sheds for row arrays on horizontal ground (front shading + rear)."""
    from pvlib.bifacial import infinite_sheds
    r, bf = sc.rows, sc.bifacial
    pitch = r.pitch_m or design_pitch(sc.lat, sc.lon, sc.tilt, r.slant_m, sc.azimuth)
    out = infinite_sheds.get_irradiance(
        sc.tilt, sc.azimuth, sp["apparent_zenith"].values, sp["azimuth"].values,
        r.slant_m / pitch, r.height_m(sc.tilt), pitch, df["ghi"].values, df["dhi"].values,
        df["dni"].values, r.albedo, model="isotropic", bifaciality=bf.bifaciality,
        shade_factor=-bf.structure_shading, transmission_factor=-bf.transmission)
    out = {k: np.nan_to_num(np.asarray(v, float)) for k, v in out.items()}
    out["pitch_m"], out["gcr"] = pitch, r.slant_m / pitch
    return out


def horizon_factors(sp, horizon, tilt):
    """Beam on/off per hour and the sky-diffuse factor for a horizon profile."""
    if not horizon:
        return np.ones(len(sp)), 1.0
    pts = sorted((float(a) % 360, float(e)) for a, e in horizon)
    az = np.array([p[0] for p in pts] + [pts[0][0] + 360]); el = np.array([p[1] for p in pts] + [pts[0][1]])
    hz = np.interp(sp["azimuth"].values % 360, az, el, period=360)
    sun_el = 90 - sp["apparent_zenith"].values
    beam = (sun_el > hz).astype(float)
    # isotropic sky: share blocked for a horizontal plane = mean sin²(h); a tilted plane sees
    # (1+cos β)/2 of the sky, of which the blocked band is the same low strip
    grid = np.arange(0, 360, 1.0)
    blocked_h = float(np.mean(np.sin(np.radians(np.interp(grid, az, el, period=360))) ** 2))
    sky_view = (1 + math.cos(math.radians(tilt))) / 2
    sky_factor = max(0.0, 1 - blocked_h / sky_view)
    return beam, sky_factor


def effective_irradiance(poa, sc: Scenario, df=None, sh: dict | None = None, sp=None):
    b0 = sc.losses.iam_b0
    iam_beam = iam.ashrae(poa["aoi"], b0).fillna(0.0).values
    diff = iam.marion_diffuse("ashrae", sc.tilt, b=b0)
    beam, sky, gnd = poa["poa_direct"].values, poa["poa_sky_diffuse"].values, poa["poa_ground_diffuse"].values
    g_iam = beam * iam_beam + sky * diff["sky"] + gnd * diff["ground"]
    if sp is not None and sc.horizon:
        hb, hs = horizon_factors(sp, sc.horizon, sc.tilt)
        beam, sky = beam * hb, sky * hs
    if sh is not None:
        # row-to-row shading: linear beam shading × electrical factor, reduced sky view,
        # ground-reflected light from the partly shaded ground between rows
        f_sh = np.clip(sh["shaded_fraction_front"] * sc.rows.electrical_factor, 0, 1)
        iso_sky = df["dhi"].values * (1 + math.cos(math.radians(sc.tilt))) / 2
        with np.errstate(divide="ignore", invalid="ignore"):
            vf = np.where(iso_sky > 0, sh["poa_front_sky_diffuse"] / iso_sky, 1.0)
        g_rows = (beam * (1 - f_sh) * iam_beam + sky * np.clip(vf, 0, 1) * diff["sky"]
                  + sh["poa_front_ground_diffuse"] * diff["ground"])
        # report the Perez-albedo ground term vs the view-factor one as part of the shading line
        g_shade = g_rows * (1 - sc.losses.near_shading)
    else:
        g_shade = (beam * iam_beam + sky * diff["sky"] + gnd * diff["ground"]) * (1 - sc.losses.near_shading)
    g_eff = g_shade * (1 - sc.losses.soiling)
    return pd.Series(g_iam, index=poa.index), pd.Series(g_shade, index=poa.index), pd.Series(g_eff, index=poa.index)


def rear_irradiance(df, sp, poa, sc: Scenario) -> np.ndarray:
    """Back-surface irradiance reaching the cells (W/m²), before bifaciality and rear mismatch."""
    from pvlib.bifacial import infinite_sheds
    bf = sc.bifacial
    zen = np.radians(sp["zenith"].values); azi = np.radians(sp["azimuth"].values)
    if bf.frame == "roof":
        # rotate the sun vector into the roof frame (roof tilted sc.tilt towards sc.azimuth)
        b = math.radians(sc.tilt); ra = math.radians(sc.azimuth)
        sx, sy, sz = np.sin(zen) * np.sin(azi), np.sin(zen) * np.cos(azi), np.cos(zen)   # E, N, Up
        n = np.array([math.sin(b) * math.sin(ra), math.sin(b) * math.cos(ra), math.cos(b)])  # roof normal
        up_slope = np.array([-math.cos(b) * math.sin(ra), -math.cos(b) * math.cos(ra), math.sin(b)])
        across = np.cross(up_slope, n)
        s_n = sx * n[0] + sy * n[1] + sz * n[2]
        s_u = sx * up_slope[0] + sy * up_slope[1] + sz * up_slope[2]
        s_a = sx * across[0] + sy * across[1] + sz * across[2]
        zen_f = np.degrees(np.arccos(np.clip(s_n, -1, 1)))
        azi_f = (np.degrees(np.arctan2(s_a, s_u)) + 360) % 360
        dhi_f = poa["poa_sky_diffuse"].values                      # sky seen by the roof plane
        dni = df["dni"].values
        ghi_f = dni * np.clip(np.cos(np.radians(zen_f)), 0, None) + dhi_f
        tilt_f, surf_az = max(bf.tilt_rel_deg, 0.01), 180.0          # rows run across the slope
    else:
        zen_f, azi_f = sp["apparent_zenith"].values, sp["azimuth"].values
        ghi_f, dhi_f, dni = df["ghi"].values, df["dhi"].values, df["dni"].values
        tilt_f, surf_az = sc.tilt, sc.azimuth
    gcr = bf.module_slant_m / bf.pitch_m
    out = infinite_sheds.get_irradiance(
        tilt_f, surf_az, zen_f, azi_f, gcr, bf.height_m, bf.pitch_m, ghi_f, dhi_f, dni,
        bf.albedo, model="isotropic", bifaciality=bf.bifaciality,
        shade_factor=-bf.structure_shading, transmission_factor=-bf.transmission)
    rear = np.nan_to_num(np.asarray(out["poa_back"], float))
    return np.where(df["ghi"].values > 0, rear, 0.0)


def cell_temperature(g_inc, temp_air, wind, eta_module, th: Thermal):
    return temperature.pvsyst_cell(g_inc, temp_air, wind, u_c=th.u_c, u_v=th.u_v,
                                   module_efficiency=eta_module, alpha_absorption=th.alpha)


def reference_currents(spec):
    s, d = spec["stc"], spec["oneDiode"]
    ns = spec["cells"]["cellsInSeries"]
    a = d["gammaRef"] * ns * K_B * 298.15 / Q_E
    rs, rsh = d["rSeriesOhm"], d["rShuntRefOhm"]
    i0 = (s["iscA"] * (1 + rs / rsh) - s["vocV"] / rsh) / (math.exp(s["vocV"] / a) - math.exp(s["iscA"] * rs / a))
    il = i0 * (math.exp(s["vocV"] / a) - 1) + s["vocV"] / rsh
    return il, i0


def module_params(spec, g, t):
    d, tc = spec["oneDiode"], spec["temperatureCoefficients"]
    il, i0 = reference_currents(spec)
    return pvsystem.calcparams_pvsyst(
        g, t, tc["muIscAPerK"], d["gammaRef"], d["muGammaPerK"], il, i0, d["rShuntRefOhm"],
        d["rShunt0Ohm"], d["rSeriesOhm"], spec["cells"]["cellsInSeries"], d["rShuntExp"])


def module_mpp(spec, g, t):
    g = np.asarray(g, float); t = np.asarray(t, float)
    p = np.zeros_like(g); i = np.zeros_like(g); v = np.zeros_like(g)
    m = g > 0.5
    r = pvsystem.singlediode(*module_params(spec, g[m], t[m]))
    p[m], i[m], v[m] = r["p_mp"], r["i_mp"], r["v_mp"]
    return p, i, v, m


def inverter_eff(p_pu, lm):
    p = np.asarray(p_pu, float)
    with np.errstate(divide="ignore", invalid="ignore"):
        e = (p - (lm["l0"] + lm["l1"] * p + lm["l2"] * p * p)) / p
    return np.where(p > 0, np.clip(e, 0, 1), 0.0)


def inverter_ac(dc_w, inv, limit="nominal"):
    lm = inv["lossModel"]; pdc0 = lm["pDC0W"]
    cap = inv["acNominalPowerW"] if limit == "nominal" else inv["acMaxApparentPowerVA"]
    ac_free = dc_w * inverter_eff(dc_w / pdc0, lm)
    lo, hi = np.zeros_like(dc_w), dc_w.copy()
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        over = mid * inverter_eff(mid / pdc0, lm) > cap
        hi, lo = np.where(over, mid, hi), np.where(over, lo, mid)
    clipped = ac_free > cap
    return ac_free, np.where(clipped, cap, ac_free), clipped


# ----------------------------------------------------------------------------- run
def run_array(sc: Scenario, df, sp, module, inv, n_mod: int) -> dict:
    """Everything up to the inverter DC input, for one orientation."""
    L, ds = sc.losses, sc.design
    poa = plane_of_array(df, sp, sc)
    sh = sheds(df, sp, sc) if sc.rows else None
    g_iam, g_shade, g_front = effective_irradiance(poa, sc, df, sh, sp)
    bf = sc.bifacial
    if bf.enabled:
        g_rear_raw = (np.where(df["ghi"].values > 0, sh["poa_back"], 0.0) if sh is not None
                      else rear_irradiance(df, sp, poa, sc))             # W/m² on the back
        g_rear = bf.bifaciality * g_rear_raw * (1 - bf.rear_mismatch)
    else:
        g_rear_raw = g_rear = np.zeros(len(df))
    g_eff = g_front + g_rear
    area = module["dimensions"]["widthM"] * module["dimensions"]["heightM"]
    eta_m = module["stc"]["pNomW"] / (area * 1000)
    t_cell = cell_temperature(poa["poa_global"], df["temp_air"], df["wind_speed"], eta_m, sc.thermal)

    p_mpp, i_mpp, v_mpp, sunny = module_mpp(module, g_eff, t_cell)
    p_25, _, _, _ = module_mpp(module, g_eff, np.full(len(g_eff), 25.0))
    p_nominal = module["stc"]["pNomW"] * g_eff.values / 1000

    k_q = (1 - L.module_quality) * (1 - L.lid) * (1 - L.mismatch)
    s = module["stc"]
    with np.errstate(divide="ignore", invalid="ignore"):
        ohm_frac = np.where(v_mpp > 0, L.dc_ohmic_at_stc * (i_mpp / s["impA"]) * (s["vmpV"] / v_mpp), 0.0)
    p_arr = n_mod * p_mpp * k_q * (1 - ohm_frac)                       # EArrMPP

    n_mppt = inv["mpptCount"]
    two = max(0, min(n_mppt, ds.strings - n_mppt)) if ds.strings > n_mppt else 0
    i_lim_str = inv["maxInputCurrentPerMpptA"] / 2
    over = sunny & (i_mpp > i_lim_str) if two > 0 else np.zeros_like(sunny)
    p_mod_lim = p_mpp.copy()
    if over.any():
        idx = np.where(over)[0]
        prm = module_params(module, g_eff.values[idx], t_cell.values[idx])
        v_lim = pvsystem.v_from_i(np.full(len(idx), i_lim_str), *prm)
        p_mod_lim[idx] = v_lim * i_lim_str
    share_two = min(1.0, two * 2 * ds.modules_per_string / n_mod)
    p_mod_eff = share_two * p_mod_lim + (1 - share_two) * p_mpp
    p_dc_in = n_mod * p_mod_eff * k_q * (1 - ohm_frac)

    kwh = lambda x: float(np.sum(x)) / 1000
    return dict(
        n_mod=n_mod, poa=poa["poa_global"].values, g_eff=np.asarray(g_eff), t_cell=t_cell.values,
        p_mpp=p_mpp, p_dc_in=p_dc_in, sunny=sunny, over=over, sh=sh,
        e=dict(H_inc=kwh(poa["poa_global"]), H_iam=kwh(g_iam), H_shade=kwh(g_shade), H_front_eff=kwh(g_front),
               H_rear_raw=kwh(g_rear_raw), H_rear_eff=kwh(g_rear), H_eff=kwh(g_eff),
               E_nominal=kwh(p_nominal) * n_mod, E_after_irr_level=kwh(p_25) * n_mod,
               E_after_temp=kwh(p_mpp) * n_mod, E_after_quality_lid_mm=kwh(p_mpp) * n_mod * k_q,
               E_arr_mpp=kwh(p_arr), E_after_current_limit=kwh(p_dc_in)))


def run(sc: Scenario) -> dict:
    from dataclasses import replace
    module = json.loads((ROOT / sc.module_json).read_text())
    inv = json.loads((ROOT / sc.inverter_json).read_text())
    L, ds = sc.losses, sc.design
    df = load_meteo(sc)
    sp = sun_position(df, sc.lat, sc.lon)

    if sc.faces:
        parts = []
        for f in sc.faces:
            fsc = replace(sc, tilt=f.tilt, azimuth=f.azimuth, horizon=f.horizon, faces=None,
                          losses=replace(sc.losses, near_shading=f.near_shading),
                          thermal=replace(sc.thermal, u_c=f.u_c) if f.u_c else sc.thermal)
            parts.append((f, run_array(fsc, df, sp, module, inv, f.n_modules)))
    else:
        n = sc.n_modules or ds.modules_per_string * ds.strings
        parts = [(None, run_array(sc, df, sp, module, inv, n))]

    n_mod = sum(a["n_mod"] for _, a in parts)
    p_nom_dc = n_mod * module["stc"]["pNomW"]
    w = [a["n_mod"] / n_mod for _, a in parts]                     # irradiance weights by module count
    p_dc_in = sum(a["p_dc_in"] for _, a in parts)
    sunny = np.any([a["sunny"] for _, a in parts], axis=0)
    over = np.any([a["over"] for _, a in parts], axis=0)
    poa_w = sum(wi * a["poa"] for wi, (_, a) in zip(w, parts))
    g_eff = sum(wi * a["g_eff"] for wi, (_, a) in zip(w, parts))
    t_cell = pd.Series(sum(wi * a["t_cell"] for wi, (_, a) in zip(w, parts)), index=df.index)
    p_mpp = sum(wi * a["p_mpp"] for wi, (_, a) in zip(w, parts))
    sh = parts[0][1]["sh"]
    poa = pd.DataFrame({"poa_global": poa_w}, index=df.index)
    ea = {}
    for k in parts[0][1]["e"]:
        vals = [a["e"][k] for _, a in parts]
        ea[k] = sum(wi * v for wi, v in zip(w, vals)) if k.startswith("H_") else sum(vals)

    ac_free, ac, clipped = inverter_ac(p_dc_in, inv, sc.ac_limit)
    ac_ohm = L.ac_ohmic_at_nominal * (ac / inv["acNominalPowerW"])
    ac_after_ohm = ac * (1 - ac_ohm)
    night = np.where(~sunny, inv["nightConsumptionW"], 0.0)
    p_grid = ac_after_ohm * (1 - L.unavailability) - night

    kwh = lambda x: float(np.sum(x)) / 1000
    h_hor, h_inc = kwh(df["ghi"]), ea["H_inc"]
    e = dict(H_hor=h_hor, **ea, E_after_inv_eff=kwh(ac_free), E_after_clipping=kwh(ac),
             E_after_ac_ohmic=kwh(ac_after_ohm), E_grid=kwh(p_grid))
    pr = e["E_grid"] / (p_nom_dc / 1000 * h_inc)

    def pct(a, b):
        return round((e[b] / e[a] - 1) * 100, 2)
    loss_diagram = [
        ("Transposition gain (Perez)", round((h_inc / h_hor - 1) * 100, 2)),
        ("IAM (ASHRAE b0=%.2f)" % L.iam_b0, pct("H_inc", "H_iam")),
        ("Shading (horizon, near, row-to-row)", pct("H_iam", "H_shade")),
        ("Soiling", pct("H_shade", "H_front_eff")),
        ("Bifacial rear gain (after φ, structure shading, rear mismatch)", pct("H_front_eff", "H_eff")),
        ("PV loss due to irradiance level", pct("E_nominal", "E_after_irr_level")),
        ("PV loss due to temperature", pct("E_after_irr_level", "E_after_temp")),
        ("Module quality + LID + mismatch", pct("E_after_temp", "E_after_quality_lid_mm")),
        ("DC ohmic wiring", pct("E_after_quality_lid_mm", "E_arr_mpp")),
        ("MPPT current limit", pct("E_arr_mpp", "E_after_current_limit")),
        ("Inverter efficiency", pct("E_after_current_limit", "E_after_inv_eff")),
        ("Clipping (AC %s)" % sc.ac_limit, pct("E_after_inv_eff", "E_after_clipping")),
        ("AC ohmic", pct("E_after_clipping", "E_after_ac_ohmic")),
        ("Unavailability + night consumption", pct("E_after_ac_ohmic", "E_grid")),
    ]

    # monthly (local time)
    local = df.index.tz_convert("Asia/Bangkok")
    month = np.array([t.month for t in local])
    monthly = []
    for mth in range(1, 13):
        sel = month == mth
        hi, eg = kwh(poa["poa_global"][sel]), kwh(p_grid[sel])
        monthly.append(dict(month=mth, GHI=round(kwh(df["ghi"][sel]), 1), POA=round(hi, 1),
                            E_grid=round(eg, 0), PR=round(eg / (p_nom_dc / 1000 * hi), 4)))

    # PVsyst ageing: linear, mid-year (year n uses rate × (n − 0.5)); LID already in year 1
    ageing = [dict(year=n, E_grid=round(e["E_grid"] * (1 - sc.ageing_per_year * (n - 0.5)), 0))
              for n in range(1, sc.years + 1)]

    u = sc.uncertainty
    others = [u.meteo_data, u.pv_module_model, u.module_quality, u.soiling_mismatch, u.inverter, u.unmodelled_shading]
    sig1 = math.sqrt(u.climate_iav ** 2 + sum(x * x for x in others))
    sig10 = math.sqrt((u.climate_iav / math.sqrt(10)) ** 2 + sum(x * x for x in others))
    p50 = e["E_grid"]
    prob = dict(sigma_1yr=round(sig1, 4), sigma_10yr=round(sig10, 4),
                P50=round(p50), P90_1yr=round(p50 * (1 - 1.2816 * sig1)), P90_10yr=round(p50 * (1 - 1.2816 * sig10)),
                P99_1yr=round(p50 * (1 - 2.3263 * sig1)))

    return dict(
        scenario=sc.name, config=asdict(sc), p_nom_dc_kWp=p_nom_dc / 1000,
        rows=(dict(pitch_m=round(sh["pitch_m"], 3), gcr=round(sh["gcr"], 3),
                   height_m=round(sc.rows.height_m(sc.tilt), 3),
                   shaded_hours=int((sh["shaded_fraction_front"] > 0.001).sum()))
              if sh is not None else None),
        dc_ac_ratio=round(p_nom_dc / inv["acNominalPowerW"], 3), modules=n_mod,
        faces=([dict(name=f.name, modules=a["n_mod"], tilt=f.tilt, azimuth=f.azimuth,
                     near_shading=f.near_shading, horizon=bool(f.horizon),
                     H_inc=round(a["e"]["H_inc"], 1), H_shade=round(a["e"]["H_shade"], 1),
                     E_dc_in=round(a["e"]["E_after_current_limit"]),
                     dc_yield_kWh_per_kWp=round(a["e"]["E_after_current_limit"] / (a["n_mod"] * module["stc"]["pNomW"] / 1000), 1))
                for f, a in parts] if sc.faces else None),
        energies_kWh={k: round(v, 2) for k, v in e.items()},
        specific_yield=round(e["E_grid"] / (p_nom_dc / 1000), 1), PR=round(pr, 4),
        loss_diagram=loss_diagram, monthly=monthly, ageing=ageing,
        lifetime_kWh=round(sum(a["E_grid"] for a in ageing)), probability=prob,
        hours=dict(current_limited=int(over.sum()), clipped=int(clipped.sum()),
                   max_dc_kW=round(float(p_dc_in.max()) / 1000, 2),
                   t_cell_mean_daylight=round(float(t_cell[poa["poa_global"] > 100].mean()), 1),
                   t_cell_max=round(float(t_cell.max()), 1)),
        _hourly=dict(ghi=df["ghi"].values, poa=poa["poa_global"].values, g_eff=np.asarray(g_eff),
                     t_cell=t_cell.values, p_module=p_mpp, p_dc_in=p_dc_in, p_ac=ac, p_grid=p_grid),
    )


def scenarios() -> list[Scenario]:
    base = dict(lat=13.75, lon=100.50, tilt=10, azimuth=180,
                module_json="components/znshine-zxm7-uhldd144-570.json",
                meteo_csv="data/pvgis-tmy-era5-bangkok-13.75-100.50.csv")
    designs = [("60kW", "components/growatt-max-60ktl3-lv.json", StringDesign(11, 12)),
               ("80kW", "components/growatt-max-80ktl3-lv.json", StringDesign(13, 14)),
               ("125kW", "components/growatt-max-125ktl3-x-lv.json", StringDesign(14, 20))]
    out = []
    for label, inv, d in designs:
        out.append(Scenario(name=f"{label}-ERA5", inverter_json=inv, design=d,
                            uncertainty=Uncertainty(meteo_data=0.08), **base))
        out.append(Scenario(name=f"{label}-GSA", inverter_json=inv, design=d,
                            ghi_target_kwh_m2=1794.0, uncertainty=Uncertainty(meteo_data=0.05), **base))
    roof60 = dict(inverter_json=designs[0][1], design=designs[0][2], uncertainty=Uncertainty(meteo_data=0.08), **base)
    out.append(Scenario(name="60kW-ERA5-bifacial-roof", bifacial=Bifacial(enabled=True), **roof60))
    out.append(Scenario(name="60kW-ERA5-bifacial-roof-albedo0.5-h0.20",
                        bifacial=Bifacial(enabled=True, albedo=0.5, height_m=0.20), **roof60))
    for label, inv, d in designs[1:]:
        out.append(Scenario(name=f"{label}-ERA5-bifacial-roof", inverter_json=inv, design=d,
                            bifacial=Bifacial(enabled=True), uncertainty=Uncertainty(meteo_data=0.08), **base))
    # ---- ground mount: 2-in-portrait tables, 0.6 m clearance, pitch from the 21-Dec 09:00 rule
    gbase = dict(base, tilt=15)
    free = Thermal(u_c=29.0)
    for label, inv, d in designs:
        out.append(Scenario(name=f"{label}-ERA5-ground-bifacial", inverter_json=inv, design=d,
                            thermal=free, rows=RowGeometry(), bifacial=Bifacial(enabled=True, frame="ground"),
                            uncertainty=Uncertainty(meteo_data=0.08), **gbase))
    g125 = dict(inverter_json=designs[2][1], design=designs[2][2], thermal=free,
                uncertainty=Uncertainty(meteo_data=0.08))
    out.append(Scenario(name="125kW-ERA5-ground-monofacial", rows=RowGeometry(), **g125, **gbase))
    for t in (10, 20):
        out.append(Scenario(name=f"125kW-ERA5-ground-bifacial-tilt{t}", rows=RowGeometry(),
                            bifacial=Bifacial(enabled=True, frame="ground"), **g125, **dict(base, tilt=t)))
    out.append(Scenario(name="125kW-ERA5-ground-bifacial-gravel0.4", rows=RowGeometry(albedo=0.4),
                        bifacial=Bifacial(enabled=True, frame="ground"), **g125, **gbase))
    return out


def main():
    gold = HERE.parents[1] / "TCRoofKit" / "Tests" / "PVYieldTests" / "Fixtures" / "golden"
    gold.mkdir(parents=True, exist_ok=True)
    summary = []
    for sc in scenarios():
        r = run(sc)
        hourly = r.pop("_hourly")
        (gold / f"{sc.name}.json").write_text(json.dumps(r, indent=1))
        if sc.name == "60kW-ERA5":   # full hourly trace for step-by-step Swift tests
            (gold / "60kW-ERA5-hourly.json").write_text(json.dumps({k: [round(float(x), 4) for x in v] for k, v in hourly.items()}))
        summary.append(r)
        print(f"{sc.name:12s} {r['p_nom_dc_kWp']:7.2f} kWp  DC/AC {r['dc_ac_ratio']:.2f}  "
              f"E_grid {r['energies_kWh']['E_grid']:>9,.0f} kWh  {r['specific_yield']:7.1f} kWh/kWp  "
              f"PR {r['PR']*100:5.2f}%  P90(1y) {r['probability']['P90_1yr']:>9,} kWh  "
              f"25y {r['lifetime_kWh']:>11,} kWh" + (f"  pitch {r['rows']['pitch_m']} m GCR {r['rows']['gcr']} shaded h {r['rows']['shaded_hours']}" if r.get('rows') else ""))
    (HERE / "results-summary.json").write_text(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
