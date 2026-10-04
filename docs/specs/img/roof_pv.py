"""Auto PV layout on a pitched roof (C1 หลังคา), from the survey plan and one roof-mounting standard.

Input is what the surveyor already enters in C1 (spansX/spansY, sheetDir, eaveHeight, ridgeHeight, roofShape, the purlin
size "@spacing", obstacles) plus the plan north and, per obstacle, a kind and a height. Everything else is derived:

  * roof faces (gable 2, shed 1, hip 4) as polygons in each face's own plane (u along the eave, v up the slope);
  * flush mounting, modules portrait, 2 rails per row **on the purlins**: a row is valid only when both rails land on a
    purlin inside the module's clamping zone, so the purlin spacing decides the row pitch;
  * setbacks per edge (eave, ridge, verge, hip), module clearance and a larger **foot clearance** per obstacle kind;
  * shade from tall obstacles (stack, turbine, pipe) projected onto the roof plane 09:00–15:00 on both solstices and
    the equinox; modules are kept out of it;
  * L-feet along each rail ≤ 1.20 m apart, never within the foot clearance of an obstacle; where no clear spot exists
    the module column is cut (red outline), as on the tank;
  * annual yield per face (same clear-sky model as the tank) and a face rule: faces below 85 % of the best face are
    left empty (switchable in the app).
Run from docs/specs/img/: writes roof_pv_plan.png and roof_pv_section.png and prints the quantities.
"""
import math, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "draw.py")).read().split("# ---------------------------------------------------------------- roof section")[0])
_opt = open(os.path.join(HERE, "tank_mount_opt.py")).read()
exec(_opt[_opt.index("# ---- sun + energy"):_opt.index("def prepare(")])        # sun(), irradiance(), energy_factors(), sat(), bbox()
MODEL = dict(clear=0.72, pr=0.80, albedo=0.20, step_min=15, day_step=3)

MOD = "#1F4E79"; GRN = "#2EAD4B"; CUT = "#E0433A"; SHADE = "#FBE3C8"; SKY = "#DCEBF7"; OBS = "#666666"; PUR = "#C9C9C9"

# ---- roof mounting standard (one set per company; editable in settings) ------------------------------------------------
STD = dict(
    mod_l=2.28, mod_w=1.13, mod_gap=0.02, mod_wp=600,     # module, portrait (long side up the slope)
    clamp_min=0.34, clamp_max=0.68,                      # clamping zone: rail distance from the module end (datasheet)
    rail_over=0.05,                                      # rail past the last module
    foot_dx=1.20, foot_cant=0.40, foot_min=0.30,          # L-foot spacing along the rail, end cantilever, shortest bay
    rail_stock=4.20,                                     # rail length as bought (splices)
    set_eave=0.30, set_ridge=0.40, set_verge=0.50, set_hip=0.40,
    face_min=0.85,                                       # faces below this share of the best face's yield stay empty
)
S = STD
# per obstacle kind: module clearance, foot clearance (m), default height above the roof (m), label
KINDS = {
    "skylight": (0.10, 0.50, 0.0, "แผ่นโปร่งแสง"),
    "turbine": (0.30, 0.30, 0.60, "ลูกหมุนระบายอากาศ"),
    "stack": (0.30, 0.30, 2.00, "ปล่อง / ท่อไอเสีย"),
    "pipe": (0.30, 0.30, 0.50, "ท่อระบาย"),
    "other": (0.30, 0.30, 0.0, "สิ่งกีดขวางอื่น"),
}
SHADE_TIMES = [(355, t / 2) for t in range(18, 31)] + [(172, t / 2) for t in range(18, 31)] + [(80, t / 2) for t in range(18, 31)]

ROOF = dict(
    title="แปลนวางแผงบนหลังคา: อาคารโรงกรอง 1",
    spansX=[6, 6, 6, 6, 6, 6, 6], spansY=[6, 6, 6, 6], sheetDir="แนวตั้ง", shape="หลังคาทรงจั่ว",
    eave=6.00, ridge=7.50, purlin="C-100x50x20x2.3 @1.20M",
    lat=17.0, bearing=15.0,                                   # survey GPS; compass bearing of the plan's top edge
    obst=[dict(kind="skylight", x=x, y=y, w=0.82, h=6.0) for x in (10.3, 20.6, 30.9) for y in (3.0, 15.0)]
    + [dict(kind="turbine", x=x, y=10.9, w=0.6, h=0.6) for x in (4.7, 15.7, 26.2, 36.7)]
    + [dict(kind="stack", x=37.2, y=16.4, w=0.5, h=0.5, hgt=2.5),
       dict(kind="pipe", x=16.9, y=5.2, w=0.15, h=0.15, hgt=0.8),
       dict(kind="other", x=2.0, y=19.0, w=1.6, h=1.2, hgt=0.9, label="คอยล์ร้อนแอร์")],
)


def purlin_spacing(txt):
    m = [float(a) for a in __import__("re").findall(r"@\s*([0-9.]+)", txt)]
    return m[0] if m and 0.2 < m[0] <= 12 else None


# ---- faces ----------------------------------------------------------------------------------------------------------------
def faces(r):
    """Each face: polygon in (u, v) with an edge kind per edge, the plan map (u, v) → (x, y), and the downslope compass azimuth."""
    LX, LY = sum(r["spansX"]), sum(r["spansY"])
    ridge_x = r["sheetDir"] != "แนวนอน"             # sheets run down the slope, so vertical sheets → ridge along x
    A, B = (LX, LY) if ridge_x else (LY, LX)          # A along the ridge, B across
    rise = r["ridge"] - r["eave"]; shape = r["shape"]
    h = B if "เพิง" in shape else B / 2
    th = math.atan(rise / h); c = math.cos(th); Ls = h / c
    sw = (lambda x, y: (x, y)) if ridge_x else (lambda x, y: (y, x))
    b = r["bearing"]; F = []
    down = lambda dx, dy: (b + math.degrees(math.atan2(dx, -dy))) % 360    # plan direction → compass
    def add(name, poly, kinds, mp, dvec):
        F.append(dict(name=name, poly=poly, ek=kinds, map=lambda u, v, mp=mp: sw(*mp(u, v)), az=down(*sw(*dvec)), tilt=th, Ls=Ls))
    if "เพิง" in shape:                                 # shed: low eave at the plan bottom (assumed)
        add("S", [(0, 0), (A, 0), (A, Ls), (0, Ls)], ["eave", "verge", "ridge", "verge"], lambda u, v: (u, B - v * c), (0, 1))
    elif "ปั้นหยา" in shape:
        rl = max(0.0, A - B)
        add("S", [(0, 0), (A, 0), (A - (A - rl) / 2, Ls), ((A - rl) / 2, Ls)], ["eave", "hip", "ridge", "hip"], lambda u, v: (u, B - v * c), (0, 1))
        add("N", [(0, 0), (A, 0), (A - (A - rl) / 2, Ls), ((A - rl) / 2, Ls)], ["eave", "hip", "ridge", "hip"], lambda u, v: (A - u, v * c), (0, -1))
        add("E", [(0, 0), (B, 0), (h, Ls)], ["eave", "hip", "hip"], lambda u, v: (A - v * c, B - u), (1, 0))
        add("W", [(0, 0), (B, 0), (h, Ls)], ["eave", "hip", "hip"], lambda u, v: (v * c, u), (-1, 0))
    else:                                              # gable
        add("S", [(0, 0), (A, 0), (A, Ls), (0, Ls)], ["eave", "verge", "ridge", "verge"], lambda u, v: (u, B - v * c), (0, 1))
        add("N", [(0, 0), (A, 0), (A, Ls), (0, Ls)], ["eave", "verge", "ridge", "verge"], lambda u, v: (A - u, v * c), (0, -1))
    for f in F:
        P = f["poly"]; hp = []; hp0 = []
        for i, kind in enumerate(f["ek"]):
            (x1, y1), (x2, y2) = P[i], P[(i + 1) % len(P)]
            L = math.hypot(x2 - x1, y2 - y1); n = (-(y2 - y1) / L, (x2 - x1) / L)          # inward for a CCW polygon
            hp.append((n, n[0] * x1 + n[1] * y1 + S["set_" + kind])); hp0.append((n, n[0] * x1 + n[1] * y1))
        f["hp"] = hp; f["hp0"] = hp0
        o, eu, ev = f["map"](0, 0), f["map"](1, 0), f["map"](0, 1)
        f["O"] = (o[0], o[1], 0.0); f["eu"] = (eu[0] - o[0], eu[1] - o[1], 0.0)
        f["ev"] = (ev[0] - o[0], ev[1] - o[1], math.sin(th))
        f["inv"] = lambda x, y, f=f: _inv(f, x, y)
    return dict(faces=F, LX=LX, LY=LY, A=A, B=B, rise=rise, tilt=th, Ls=Ls, ridge_x=ridge_x, h=h)


def _inv(f, x, y):
    O, eu, ev = f["O"], f["eu"], f["ev"]
    dx, dy = x - O[0], y - O[1]
    u = (dx * eu[0] + dy * eu[1]) / (eu[0] ** 2 + eu[1] ** 2)
    v = (dx * ev[0] + dy * ev[1]) / (ev[0] ** 2 + ev[1] ** 2)
    return u, v


def in_face(f, pts):
    return all(n[0] * p[0] + n[1] * p[1] >= d - 1e-9 for p in pts for (n, d) in f["hp"])


def inset_poly(f):
    """Usable area polygon (for drawing): intersect consecutive offset lines."""
    out = []; m = len(f["hp"])
    for i in range(m):
        (n1, d1), (n2, d2) = f["hp"][i - 1], f["hp"][i]
        det = n1[0] * n2[1] - n1[1] * n2[0]
        if abs(det) < 1e-12: continue
        out.append(((d1 * n2[1] - d2 * n1[1]) / det, (n1[0] * d2 - n2[0] * d1) / det))
    return out


def purlins(Ls, s):
    t = [0.0];
    while t[-1] + s <= Ls + 1e-9: t.append(t[-1] + s)
    if Ls - t[-1] > 0.25 * s: t.append(Ls)
    return t


# ---- obstacles and shade ------------------------------------------------------------------------------------------------
def pt3(f, u, v):
    return (f["O"][0] + u * f["eu"][0] + v * f["ev"][0], f["O"][1] + u * f["eu"][1] + v * f["ev"][1], v * f["ev"][2])


def hull(P):
    P = sorted(set((round(x, 6), round(y, 6)) for x, y in P))
    if len(P) < 3: return P
    cr = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in P:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(P):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def obstacles_on(R, r):
    """Every obstacle in plan → its home face (u, v) box, 3D base, clearances and shade hulls on every face."""
    out = []
    for o in r["obst"]:
        kind = o.get("kind", "other"); mc, fc, hdef, lab = KINDS[kind]; hgt = o.get("hgt", hdef)
        cx, cy = o["x"] + o["w"] / 2, o["y"] + o["h"] / 2
        home = next((f for f in R["faces"] if in_face(dict(hp=f["hp0"]), [f["inv"](cx, cy)])), R["faces"][0])
        corners = [(o["x"], o["y"]), (o["x"] + o["w"], o["y"]), (o["x"] + o["w"], o["y"] + o["h"]), (o["x"], o["y"] + o["h"])]
        base3 = []
        for (x, y) in corners:
            u, v = home["inv"](x, y); base3.append(pt3(home, u, v))
        out.append(dict(o=o, kind=kind, mc=mc, fc=fc, hgt=hgt, label=o.get("label", lab), home=home["name"], corners=corners, base3=base3))
    for f in R["faces"]:
        f["obs"] = []; f["shade"] = []
        n = _cross(f["eu"], f["ev"]); n = n if n[2] > 0 else tuple(-a for a in n)
        for ob in out:
            uv = [f["inv"](x, y) for (x, y) in ob["corners"]]
            us, vs = [p[0] for p in uv], [p[1] for p in uv]
            box = (min(us), min(vs), max(us), max(vs))
            if ob["home"] == f["name"]: f["obs"].append(dict(ob, box=box))
            if ob["hgt"] <= 0: continue
            for (day, t) in SHADE_TIMES:
                s = sun(r["lat"], day, t)
                if not s: continue
                alt, g = math.radians(s[0]), s[1]; Az = math.radians(180 + g - r["bearing"])
                Sv = (math.sin(Az) * math.cos(alt), -math.cos(Az) * math.cos(alt), math.sin(alt))
                ns = _dot(n, Sv)
                if ns <= 1e-6: continue                                   # face turned away: no output anyway
                pts = []
                for P in ob["base3"]:
                    Q = (P[0], P[1], P[2] + ob["hgt"])
                    tt = _dot(n, _sub(Q, f["O"])) / ns
                    if tt < 0: continue                                    # top below this face's plane
                    X = _sub(Q, tuple(tt * a for a in Sv))
                    pts.append(_uv(f, X))
                    pts.append(_uv(f, P) if ob["home"] == f["name"] else _uv(f, _sub(P, tuple(_dot(n, _sub(P, f["O"])) / ns * a for a in Sv))))
                if len(pts) >= 3:
                    Hh = hull(pts)
                    if len(Hh) >= 3: f["shade"].append(Hh)
    return out


def _cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def _dot(a, b): return sum(x * y for x, y in zip(a, b))
def _sub(a, b): return tuple(x - y for x, y in zip(a, b))
def _uv(f, X):
    d = _sub(X, f["O"]); eu, ev = f["eu"], f["ev"]
    return (_dot(d, eu) / _dot(eu, eu), _dot(d, ev) / _dot(ev, ev))


# ---- rows on purlins -----------------------------------------------------------------------------------------------------
def rows_on(f, P, rib=False, shift=0.0, centre=True):
    """Greedy (earliest start) is optimal for equal-length intervals: returns [(v0, rail_a, rail_b)]."""
    L, g = S["mod_l"], S["mod_gap"]; lo, hi = S["clamp_min"], S["clamp_max"]
    vmin = max(d for (n, d) in f["hp"] if abs(n[1]) > 0.99 and n[1] > 0)         # eave setback line
    vmax = min(-d for (n, d) in f["hp"] if n[1] < -0.99) if any(n[1] < -0.99 for n, d in f["hp"]) else f["Ls"] - S["set_ridge"]
    out = []; v = vmin + shift
    while v + L <= vmax + 1e-9:
        if rib:
            out.append((v, v + L / 4, v + 3 * L / 4)); v += L + g; continue
        found = None; w = v
        while w + L <= vmax + 1e-9:
            a = [p for p in P if lo - 1e-9 <= p - w <= hi + 1e-9]
            b = [p for p in P if lo - 1e-9 <= w + L - p <= hi + 1e-9]
            if a and b: found = (w, a[0], b[-1]); break
            w = round(w + 0.01, 4)
        if not found: break
        out.append(found); v = found[0] + L + g
    # centre each row on its two purlins where the neighbours allow (equal clamp distances), top row first
    for i in (range(len(out) - 1, -1, -1) if centre else []):
        w, a, b = out[i]
        lo_ = max(a - hi, b + lo - L, vmin if i == 0 else out[i - 1][0] + L + g)
        hi_ = min(a - lo, b + hi - L, vmax - L, out[i + 1][0] - L - g if i + 1 < len(out) else 1e9)
        out[i] = (min(max((a + b) / 2 - L / 2, lo_), hi_), a, b)
    return out


def slot_block(f, u, v):
    key = (round(u, 3), round(v, 3)); c = f.setdefault("_sb", {})
    if key not in c: c[key] = _slot_block(f, u, v)
    return c[key]


def _slot_block(f, u, v):
    L, W = S["mod_l"], S["mod_w"]
    rect = [(u, v), (u + W, v), (u + W, v + L), (u, v + L)]
    if not in_face(f, rect): return "นอกพื้นที่ (ระยะร่นขอบ)"
    for ob in f["obs"]:
        x0, y0, x1, y1 = ob["box"]; m = ob["mc"]
        if u < x1 + m and x0 - m < u + W and v < y1 + m and y0 - m < v + L:
            return f"{ob['label']}: เว้นระยะ {m:.2f} ม."
    for Hh in f["shade"]:
        bx = bbox(Hh)
        if bx[0] < u + W and u < bx[2] and bx[1] < v + L and v < bx[3] and sat(rect, Hh):
            return "เงาสิ่งกีดขวาง 09:00–15:00"
    return None


def forbid(f, v_rail):
    """u-intervals on a rail at v where a foot may not go."""
    out = []
    for ob in f["obs"]:
        x0, y0, x1, y1 = ob["box"]; m = ob["fc"]
        if y0 - m <= v_rail <= y1 + m: out.append((x0 - m, x1 + m, ob["label"]))
    return out


def place_feet(xa, xb, bad):
    ok = lambda x: all(not (a < x < b) for a, b, _ in bad)
    dx, c, mn = S["foot_dx"], S["foot_cant"], S["foot_min"]
    Lr = xb - xa; m = max(1, math.ceil((Lr - 2 * 0.2) / dx))
    eq = [xa + 0.2 + i * (Lr - 0.4) / m for i in range(m + 1)] if Lr > 0.4 else [(xa + xb) / 2]
    if all(ok(x) for x in eq): return eq, None, False
    grid = lambda lo, hi: [round(hi - i * 0.05, 3) for i in range(int((hi - lo) / 0.05) + 1)]
    feet = []
    first = next((x for x in grid(xa + 0.05, min(xb, xa + c)) if ok(x)), None)
    if first is None: return None, xa + c / 2, True
    feet.append(first)
    while feet[-1] < xb - c - 1e-9:
        nxt = next((x for x in grid(feet[-1] + mn, min(xb - 0.05, feet[-1] + dx)) if ok(x)), None)
        if nxt is None: return None, feet[-1] + dx / 2, True
        feet.append(nxt)
    return feet, None, True


def layout_face(f, P, off, rib=False, shift=0.0, centre=True):
    W, g = S["mod_w"], S["mod_gap"]; pw = W + g
    rows = []
    for (v0, ra, rb) in rows_on(f, P, rib, shift, centre):
        umin = min(p[0] for p in f["poly"]); umax = max(p[0] for p in f["poly"])
        slots = []; u = umin + S["set_verge"] + off
        while u + W <= umax + 1e-9:
            slots.append(dict(u=u, why=slot_block(f, u, v0))); u += pw
        rows.append(dict(v=v0, rails=(ra, rb), slots=slots))
    cuts = 0
    for row in rows:
        for _ in range(200):
            runs, cur = [], []
            for i, s in enumerate(row["slots"]):
                if s["why"] is None: cur.append(i)
                elif cur: runs.append(cur); cur = []
            if cur: runs.append(cur)
            fail = None; row["runs"] = []
            for run in runs:
                xa = row["slots"][run[0]]["u"] - S["rail_over"]; xb = row["slots"][run[-1]]["u"] + W + S["rail_over"]
                feet = []; moved = False
                for vr in row["rails"]:
                    fs, at, mv = place_feet(xa, xb, forbid(f, vr)); moved |= mv
                    if fs is None: fail = (run, at); break
                    feet.append(fs)
                if fail: break
                row["runs"].append(dict(i=run, xa=xa, xb=xb, feet=feet, moved=moved))
            if not fail: break
            run, at = fail
            i = min(run, key=lambda j: abs(row["slots"][j]["u"] + W / 2 - at))
            row["slots"][i]["why"] = "ตัดแผงเพื่อไม่ให้ขาโครงสร้างชนสิ่งกีดขวาง"; row["slots"][i]["cut"] = True; cuts += 1
    n = sum(1 for r_ in rows for s in r_["slots"] if s["why"] is None)
    return dict(rows=rows, n=n, cuts=cuts, off=off, shift=shift, centre=centre)


def solve(r, rib=False, force=None):
    R = faces(r); s = purlin_spacing(r["purlin"]) or 1.0
    R["s"] = s; R["P"] = purlins(R["Ls"], s); obstacles_on(R, r)
    for f in R["faces"]:
        best = None; f["tried"] = 0
        pitch = S["mod_l"] + S["mod_gap"] + (0 if rib else s)
        for j in range(int(pitch / 0.10) + 1):                       # row start shift (rows stay on purlins)
            for k in range(int((S["mod_w"] + S["mod_gap"]) / 0.05) + 1):   # column offset
              for centre in (True, False):                               # rows centred on their purlins, or packed toward the eave
                L = layout_face(f, R["P"], k * 0.05, rib, j * 0.10, centre); f["tried"] += 1
                key = (L["n"], -L["cuts"], L["centre"])
                if best is None or key > (best["n"], -best["cuts"], best["centre"]): best = L
        f["L"] = best
        gp = (f["az"] - 180 + 540) % 360 - 180
        f["kwh_kwp"] = energy_factors(r["lat"], math.degrees(f["tilt"]), gp, 1e6, 1.0)[0]
    top = max(f["kwh_kwp"] for f in R["faces"])
    for f in R["faces"]:
        f["use"] = f["kwh_kwp"] >= S["face_min"] * top if force is None else f["name"] in force
    return R


def quantities(R):
    Q = dict(modules=0, rails_m=0.0, splices=0, feet=0, mid=0, end=0, runs=0, cuts=0, mwh=0.0, moved=0)
    for f in R["faces"]:
        if not f["use"]: continue
        Q["modules"] += f["L"]["n"]; Q["cuts"] += f["L"]["cuts"]
        Q["mwh"] += f["L"]["n"] * S["mod_wp"] / 1000 * f["kwh_kwp"] / 1000
        for row in f["L"]["rows"]:
            for run in row["runs"]:
                Lr = run["xb"] - run["xa"]; k = len(run["i"])
                Q["runs"] += 1; Q["rails_m"] += 2 * Lr; Q["splices"] += 2 * (math.ceil(Lr / S["rail_stock"]) - 1)
                Q["feet"] += sum(len(fs) for fs in run["feet"]); Q["mid"] += 2 * (k - 1); Q["end"] += 4; Q["moved"] += run["moved"]
    Q["kwp"] = Q["modules"] * S["mod_wp"] / 1000
    return Q


COMPASS = ["เหนือ", "ตะวันออกเฉียงเหนือ", "ตะวันออก", "ตะวันออกเฉียงใต้", "ใต้", "ตะวันตกเฉียงใต้", "ตะวันตก", "ตะวันตกเฉียงเหนือ"]
def compass(az): return COMPASS[int(((az % 360) + 22.5) // 45) % 8]


# ---- drawings -------------------------------------------------------------------------------------------------------------
def plan(r, R, Q, path, W=1180, rib_n=None):
    sk = Sk(W); LX, LY = R["LX"], R["LY"]
    title_strip(sk, r["title"], "สร้างจากแปลนหลังคา C1 + มาตรฐานการยึดแผง · หน่วย ม.")
    padL, padT, padR = 70, 76, 330
    k = min((W - padL - padR) / LX, 560 / LY); ox, oy = padL, padT
    Pp = lambda x, y: (ox + x * k, oy + y * k)
    FP = lambda f, u, v: Pp(*f["map"](u, v))
    # roof outline, grid, ridge / hips
    sk.rect(ox, oy, LX * k, LY * k, BLACK, None, 1.3)
    xs = [0]; [xs.append(xs[-1] + s) for s in r["spansX"]]; ys = [0]; [ys.append(ys[-1] + s) for s in r["spansY"]]
    for x in xs[1:-1]: sk.line(Pp(x, 0), Pp(x, LY), 0.35, FAINT, [4, 3])
    for y in ys[1:-1]: sk.line(Pp(0, y), Pp(LX, y), 0.35, FAINT, [4, 3])
    for f in R["faces"]:
        for p in R["P"]:                                                            # purlins
            us = [q[0] for q in f["poly"]]
            sk.line(FP(f, min(us), p), FP(f, max(us), p), 0.35, PUR)
        ip = inset_poly(f)
        if ip: sk.poly([FP(f, *q) for q in ip], "#7FB77E", None, 0.6)
    if "ปั้นหยา" not in r["shape"] and "เพิง" not in r["shape"]:
        a, b = (Pp(0, LY / 2), Pp(LX, LY / 2)) if R["ridge_x"] else (Pp(LX / 2, 0), Pp(LX / 2, LY))
        sk.line(a, b, 1.2, BLACK, DASHDOT)
    # shade, obstacles
    for f in R["faces"]:
        for Hh in f["shade"]:
            sk.poly([FP(f, *q) for q in Hh], None, SHADE, 0)
    for f in R["faces"]:
        for ob in f["obs"]:
            o = ob["o"]; a = Pp(o["x"], o["y"])
            if ob["kind"] == "skylight":
                sk.rect(a[0], a[1], o["w"] * k, o["h"] * k, "#8DB3D6", SKY, 0.7)
            elif ob["kind"] == "turbine":
                c = Pp(o["x"] + o["w"] / 2, o["y"] + o["h"] / 2); sk.circle(c, o["w"] * k / 2, OBS, "white", 0.9)
                sk.line((c[0] - o["w"] * k / 2, c[1]), (c[0] + o["w"] * k / 2, c[1]), 0.6, OBS); sk.line((c[0], c[1] - o["w"] * k / 2), (c[0], c[1] + o["w"] * k / 2), 0.6, OBS)
            elif ob["kind"] in ("stack", "pipe"):
                sk.rect(a[0], a[1], max(3, o["w"] * k), max(3, o["h"] * k), BLACK, OBS, 0.8)
            else:
                sk.rect(a[0], a[1], o["w"] * k, o["h"] * k, BLACK, "white", 0.8); sk.hatch(a[0] + 1, a[1] + 1, o["w"] * k - 2, o["h"] * k - 2, FAINT, 3)
    # modules, rails, feet, cut slots
    L, Wm = S["mod_l"], S["mod_w"]
    for f in R["faces"]:
        for row in f["L"]["rows"]:
            for s in row["slots"]:
                q = [FP(f, s["u"], row["v"]), FP(f, s["u"] + Wm, row["v"]), FP(f, s["u"] + Wm, row["v"] + L), FP(f, s["u"], row["v"] + L)]
                if s["why"] is None:
                    sk.poly(q, MOD, "#E8F0F8" if f["use"] else None, 0.55)
                elif s.get("cut"):
                    sk.poly(q, CUT, None, 1.1)
            if not f["use"]: continue
            for run in row["runs"]:
                for vr, fs in zip(row["rails"], run["feet"]):
                    sk.line(FP(f, run["xa"], vr), FP(f, run["xb"], vr), 0.9, DARK)
                    for x in fs: sk.circle(FP(f, x, vr), 1.9, GRN, GRN)
    # face labels, in the band between the last row and the ridge
    for f in R["faces"]:
        us = [q[0] for q in f["poly"]]; rows = f["L"]["rows"]
        vb = ((rows[-1]["v"] + S["mod_l"]) if rows else 0) ; vb = (vb + f["Ls"]) / 2
        c = FP(f, (min(us) + max(us)) / 2, vb)
        t = (f"ด้าน{compass(f['az'])} · หัน {f['az']:.0f}° · เอียง {math.degrees(f['tilt']):.1f}° · {f['kwh_kwp']:,.0f} kWh/kWp · "
             + (f"{f['L']['n']} แผง" if f["use"] else f"ไม่วางแผง (ต่ำกว่า {S['face_min'] * 100:.0f}% ของด้านที่ดีที่สุด)"))
        w_ = len(t) * 4.3; sk.rect(c[0] - w_ / 2, c[1] - 7, w_, 14, None, "white", 0); sk.text(t, c, 8, True, BLUE if f["use"] else CUT, "center")
    # dims
    xs_ = [Pp(x, 0)[0] for x in xs]
    dim_h(sk, xs_[0], xs_[-1], oy - 26, f"{LX:.2f}", 8.5, True, xs_)
    for i in range(len(xs) - 1): sk.text(f"{r['spansX'][i]:.2f}", ((xs_[i] + xs_[i + 1]) / 2, oy - 12), 7.5, False, INK2, "center")
    dim_v(sk, ox - 24, oy, oy + LY * k, f"{LY:.2f}")
    # north arrow (plan top = bearing)
    nx, ny = ox + LX * k + 36, oy + 24; a = math.radians(-r["bearing"])
    tip = (nx + 16 * math.sin(a), ny - 16 * math.cos(a)); l_ = (nx - 6 * math.cos(a), ny - 6 * math.sin(a)); r_ = (nx + 6 * math.cos(a), ny + 6 * math.sin(a))
    sk.poly([tip, l_, r_], BLACK, BLACK)
    sk.text("N", (nx, ny + 18), 9, True, BLACK, "center")
    # legend + quantities
    lx, ly = ox + LX * k + 70, oy + 6
    for sym, lab in (("mod", "แผง (ฉายลงแปลน) แนวตั้ง"), ("rail", "ราง 2 เส้นต่อแถว วางบนแป"), ("foot", "L-foot ยึดเข้าแป"),
                     ("cut", "ตัดแผงเพื่อไม่ให้ขาชนสิ่งกีดขวาง"), ("shade", "เงาสิ่งกีดขวาง 09:00–15:00"), ("sky", "แผ่นโปร่งแสง"),
                     ("use", "พื้นที่หลังหักระยะร่นขอบ"), ("pur", "แป")):
        if sym == "mod": sk.rect(lx, ly - 5, 14, 10, MOD, "#E8F0F8", 0.6)
        elif sym == "rail": sk.line((lx, ly), (lx + 14, ly), 0.9, DARK)
        elif sym == "foot": sk.circle((lx + 7, ly), 2.5, GRN, GRN)
        elif sym == "cut": sk.rect(lx, ly - 5, 14, 10, CUT, None, 1.1)
        elif sym == "shade": sk.rect(lx, ly - 5, 14, 10, None, SHADE, 0)
        elif sym == "sky": sk.rect(lx, ly - 5, 14, 10, "#8DB3D6", SKY, 0.7)
        elif sym == "use": sk.rect(lx, ly - 5, 14, 10, "#7FB77E", None, 0.6)
        else: sk.line((lx, ly), (lx + 14, ly), 0.6, PUR)
        sk.text(lab, (lx + 22, ly), 8); ly += 17
    ly += 8; sk.text("ปริมาณงาน (อัตโนมัติ)", (lx, ly), 9, True); ly += 17
    for a_, b_ in (("แผง", f"{Q['modules']} แผง · {Q['kwp']:.1f} kWp"), ("พลังงานโดยประมาณ", f"{Q['mwh']:.0f} MWh/ปี"),
                   ("ราง", f"{Q['rails_m']:.0f} ม. · ต่อราง {Q['splices']}"), ("L-foot", f"{Q['feet']} ชุด"),
                   ("mid / end clamp", f"{Q['mid']} / {Q['end']}"), ("ชุดแผงต่อเนื่อง", f"{Q['runs']}"),
                   ("ขาชนสิ่งกีดขวาง", "0"), ("ช่องที่ตัดหลบขา", f"{Q['cuts']}")):
        sk.text(a_, (lx, ly), 8, False, INK2); sk.text(b_, (lx + 240, ly), 8, True, CUT if a_ == "ช่องที่ตัดหลบขา" and Q["cuts"] else BLACK, "right"); ly += 15
    ly += 8; sk.text("แต่ละด้านหลังคา", (lx, ly), 9, True); ly += 16
    for f in R["faces"]:
        sk.text(f"ด้าน{compass(f['az'])} ({f['az']:.0f}°)", (lx, ly), 8, False, INK2)
        sk.text(f"{f['kwh_kwp']:,.0f} kWh/kWp · {f['L']['n'] if f['use'] else 0} แผง", (lx + 240, ly), 8, True, BLACK, "right"); ly += 15
    # notes
    yb = oy + LY * k + 34
    sk.line((14, yb - 10), (W - 14, yb - 10), 0.5, RULE)
    sp = R["s"]; nrow = max(len(f["L"]["rows"]) for f in R["faces"])
    pitch = [b["v"] - a["v"] for f in R["faces"] for a, b in zip(f["L"]["rows"], f["L"]["rows"][1:])]
    sk.text(f"หลังคาจั่ว เอียง {math.degrees(R['tilt']):.1f}° (สูงชายคา {r['eave']:.2f} สัน {r['ridge']:.2f}) · แป @{sp:.2f} ม. ยาวตามเอียง {R['Ls']:.2f} ม. · "
            f"{nrow} แถวต่อด้าน ระยะแถว {min(pitch) if pitch else 0:.2f} ม. (รางตกบนแปทั้ง 2 เส้น)", (14, yb + 4), 8.5, True)
    notes = []
    if rib_n is not None: notes.append(f"ถ้ายึดแบบจับสันลอน (ไม่ต้องตรงแป) จะวางได้ {rib_n} แผง · ใช้แบบยึดเข้าแปเป็นค่าเริ่มต้น")
    notes.append(f"L-foot ห่างแผ่นโปร่งแสงอย่างน้อย {KINDS['skylight'][1]:.2f} ม. และห่างสิ่งกีดขวางอื่น {KINDS['turbine'][1]:.2f} ม.; จัดระยะใหม่เพื่อหลบ {Q['moved']} ชุดแผง")
    for i, n in enumerate(notes): sk.text("• " + n, (22, yb + 22 + i * 14), 8, False, INK2)
    yy = yb + 22 + len(notes) * 14 + 6
    sk.text(f"ค่าสมมติ/มาตรฐาน: แผง {S['mod_l']}×{S['mod_w']} ม. {S['mod_wp']} W · ระยะจับแผง {S['clamp_min']:.2f}–{S['clamp_max']:.2f} ม. จากปลายแผง · "
            f"L-foot ห่างไม่เกิน {S['foot_dx']:.2f} ยื่นปลายรางไม่เกิน {S['foot_cant']:.2f} · ร่นชายคา {S['set_eave']:.2f} สัน {S['set_ridge']:.2f} ขอบจั่ว {S['set_verge']:.2f} ม. · "
            f"PR {MODEL['pr']} ฟ้าใส×{MODEL['clear']} · lat {r['lat']:.1f}°", (14, yy), 7.5, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบรรทุกของโครงหลังคากับวิศวกรโครงสร้าง", (W - 14, yy + 16), 7.5, False, RED, "right")
    sk.render(yy + 30, path)


def section(r, R, path, W=1180):
    """Section across the ridge with every row on its purlins, and detail A (first row on the south face) at a large scale."""
    sk = Sk(W); th = R["tilt"]; B, h = R["B"], R["h"]
    title_strip(sk, "รูปตัดขวางหลังคา: แถวแผงบนแป", f"เอียง {math.degrees(th):.1f}° · แป @{R['s']:.2f} ม. · หน่วย ม.")
    k = (W - 160) / B; x0 = 80; gy = 70 + (r["ridge"] - r["eave"]) * k + 40
    X = lambda x: x0 + x * k; Y = lambda z: gy - z * k
    sk.line((x0 - 20, gy), (X(B) + 20, gy), 0.6, FAINT)
    sk.poly([(X(0), Y(0)), (X(h), Y(R["rise"])), (X(B), Y(0))], BLACK, None, 1.4)
    fS = next(f for f in R["faces"] if f["name"] == "S"); fN = next((f for f in R["faces"] if f["name"] == "N"), None)
    def at(f, v, off=0.0):                                     # slope distance v from the eave, offset off out of the roof
        side = 1 if f["name"] == "S" else -1
        x = (B if side == 1 else 0) - side * v * math.cos(th) + side * off * math.sin(th); z = v * math.sin(th) + off * math.cos(th)
        return (X(x), Y(z))
    for f in (fS, fN):
        if f is None: continue
        for p in R["P"]:
            c = at(f, p); sk.rect(c[0] - 3, c[1], 6, 9, DARK, "white", 0.8)
        for row in f["L"]["rows"]:
            sk.line(at(f, row["v"], 0.14), at(f, row["v"] + S["mod_l"], 0.14), 3.2, MOD if f["use"] else FAINT)
            for vr in row["rails"]:
                c = at(f, vr, 0.07); sk.circle(c, 2.6, GRN, GRN)
    dim_h(sk, X(0), X(B), gy + 30, f"{B:.2f}", 8.5, True)
    dim_v(sk, X(h) + 30, Y(R["rise"]), gy, f"{R['rise']:.2f}", 1)
    sk.text("A", (at(fS, fS["L"]["rows"][0]["v"] + 1.1, 0.9)[0], at(fS, fS["L"]["rows"][0]["v"] + 1.1, 0.9)[1]), 10, True, CUT, "center")
    c = at(fS, fS["L"]["rows"][0]["v"] + 1.1, 0.4); sk.circle(c, 26, CUT, None, 0.8)
    # detail A, drawn in the slope's own frame (rotated flat), large scale
    dy0 = gy + 70; sk.text("รายละเอียด A: แถวที่ 1 ด้านใต้ วางบนแป (ไม่ได้มาตราส่วน)", (40, dy0), 9.5, True)
    q = 150; bx = 110; by = dy0 + 150
    row = fS["L"]["rows"][0]; v0 = row["v"]; Pv = [p for p in R["P"] if p <= v0 + S["mod_l"] + 0.9]
    XD = lambda v: bx + (v - 0) * q
    sk.line((XD(0) - 20, by), (XD(max(Pv) + 0.6), by), 1.6, BLACK)
    for i in range(int((max(Pv) + 0.6) / 0.25) + 1):                                   # corrugation hint
        xx = XD(i * 0.25) - 20; sk.line((xx, by), (xx + 8, by - 5), 0.6, INK2); sk.line((xx + 8, by - 5), (xx + 16, by), 0.6, INK2)
    for p in Pv:
        sk.rect(XD(p) - 18, by + 1, 36, 26, DARK, "white", 1.0); sk.text("แป", (XD(p), by + 40), 7.5, False, INK2, "center")
    sk.text("ชายคา", (XD(0), by + 60), 8, False, INK2, "center"); sk.line((XD(0), by + 4), (XD(0), by + 50), 0.5, INK2, [3, 2])
    for vr in row["rails"]:
        sk.rect(XD(vr) - 6, by - 26, 12, 22, GRN, "white", 1.0); sk.rect(XD(vr) - 10, by - 36, 20, 10, DARK, DARK, 0.8)
    sk.rect(XD(v0), by - 48, S["mod_l"] * q, 12, MOD, "#E8F0F8", 1.2)
    ra, rb = row["rails"]
    dim_h(sk, XD(0), XD(v0), by - 70, f"{v0:.2f}")
    dim_h(sk, XD(v0), XD(ra), by - 90, f"{ra - v0:.2f}")
    dim_h(sk, XD(ra), XD(rb), by - 90, f"{rb - ra:.2f}")
    dim_h(sk, XD(rb), XD(v0 + S["mod_l"]), by - 90, f"{v0 + S['mod_l'] - rb:.2f}")
    dim_h(sk, XD(v0), XD(v0 + S["mod_l"]), by - 112, f"แผง {S['mod_l']:.2f}", 8.5, True)
    for i in range(len(Pv) - 1): dim_h(sk, XD(Pv[i]), XD(Pv[i + 1]), by + 78, f"{Pv[i + 1] - Pv[i]:.2f}")
    tx = XD(max(Pv) + 0.6) + 30; ty = dy0 + 60
    for t in (f"• ราง 2 เส้นต่อแถว วางตรงแปทั้งคู่ ยึดด้วย L-foot เข้าแปผ่านสันลอน",
              f"• ระยะจากปลายแผงถึงราง {ra - v0:.2f} และ {v0 + S['mod_l'] - rb:.2f} ม. อยู่ในช่วงจับแผง {S['clamp_min']:.2f}–{S['clamp_max']:.2f} ม.",
              f"• ร่นจากชายคา {S['set_eave']:.2f} ม. แล้วเลื่อนขึ้นจนรางตกแป จึงเริ่มแผงที่ {v0:.2f} ม.",
              f"• แถวถัดไปเริ่มที่ {fS['L']['rows'][1]['v']:.2f} ม. (ห่างแถวแรก {fS['L']['rows'][1]['v'] - v0 - S['mod_l']:.2f} ม.)" if len(fS["L"]["rows"]) > 1 else "",
              "• แป @ ระยะอื่นให้ระยะแถวต่างกัน: แอปคำนวณใหม่ทุกครั้งที่แก้ระยะแป"):
        if t: sk.text(t, (tx, ty), 8.5, False, BLACK); ty += 17
    yy = by + 110
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, yy), 7.5, False, RED, "right")
    sk.render(yy + 16, path)


if __name__ == "__main__":
    R = solve(ROOF); Q = quantities(R)
    Rr = solve(ROOF, rib=True); Qr = quantities(Rr)
    plan(ROOF, R, Q, os.path.join(HERE, "roof_pv_plan.png"), rib_n=Qr["modules"])
    section(ROOF, R, os.path.join(HERE, "roof_pv_section.png"))
    print({k: (round(v, 1) if isinstance(v, float) else v) for k, v in Q.items()}, "rib", Qr["modules"])
    for f in R["faces"]:
        print(f["name"], round(f["az"]), round(math.degrees(f["tilt"]), 1), round(f["kwh_kwp"]), f["L"]["n"], "rows", [round(r_["v"], 2) for r_ in f["L"]["rows"]],
              "off", f["L"]["off"], "shift", f["L"]["shift"], "centre", f["L"]["centre"], "tried", f["tried"], "cuts", f["L"]["cuts"], "shade", len(f["shade"]), "use", f["use"])
    # 1.00 m purlins for the spec table
    for sp in ("@1.00M", "@1.10M", "@1.20M", "@1.50M"):
        rr = dict(ROOF, purlin="C-100x50x20x2.3 " + sp); X_ = solve(rr); print(sp, quantities(X_)["modules"], [len(f["L"]["rows"]) for f in X_["faces"]])
