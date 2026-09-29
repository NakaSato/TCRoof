"""Accurate auto layout: panels face true south, rows chosen for the most energy per year, not the most modules.

Adds to tank_mount.py:
  * the tank's real orientation (bearing of the plan's top wall, measured on site with a compass) and the site latitude
    (from the survey GPS), so rows run exactly east–west and panels face true south, or parallel to the walls when that
    gives more energy;
  * an hourly clear-sky sun model for the whole year (NOAA sun position, Haurwitz GHI, Erbs split, isotropic sky) with
    row-to-row shading in the rows' own plane and a portrait-2 electrical rule (a shaded bottom edge drops the module);
  * rotated geometry: modules, footings and openings as polygons (separating axis test), so any orientation works;
  * a search over strategy × row gap × row offset × column offset for the highest annual energy.
Run from docs/specs/img/: writes tank_mount_opt_plan.png and tank_mount_opt_compare.png and prints the candidates.
"""
import math, os, time
HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "tank_mount.py")).read().split('if __name__ == "__main__":')[0].replace("__file__", repr(os.path.join(HERE, "tank_mount.py")))
exec(_src)

SITE = dict(lat=17.0, bearing=12.0)      # survey GPS latitude; bearing of the plan's top wall (° clockwise from true north)
MODEL = dict(clear=0.72, pr=0.80, albedo=0.20, step_min=15, day_step=3)   # assumed; printed as ค่าสมมติ


# ---- sun + energy ----------------------------------------------------------------------------------------------------------
def sun(lat, n, t):
    """Solar altitude and azimuth (from south, + west), degrees, for day n and solar time t (h)."""
    d = math.radians(23.45 * math.sin(math.radians(360 * (284 + n) / 365)))
    w = math.radians(15 * (t - 12)); p = math.radians(lat)
    sa = math.sin(p) * math.sin(d) + math.cos(p) * math.cos(d) * math.cos(w)
    a = math.asin(max(-1, min(1, sa)))
    if a <= 0: return None
    cz = (math.sin(a) * math.sin(p) - math.sin(d)) / (math.cos(a) * math.cos(p))
    g = math.degrees(math.acos(max(-1, min(1, cz)))) * (1 if w > 0 else -1)
    return math.degrees(a), g


def irradiance(n, alt):
    cz = math.sin(math.radians(alt))
    ghi = 1098 * cz * math.exp(-0.057 / cz) * MODEL["clear"]
    i0 = 1367 * (1 + 0.033 * math.cos(math.radians(360 * n / 365))) * cz
    kt = ghi / i0 if i0 > 0 else 0
    fd = 1 - 0.09 * kt if kt <= 0.22 else (0.9511 - 0.1604 * kt + 4.388 * kt ** 2 - 16.638 * kt ** 3 + 12.336 * kt ** 4 if kt <= 0.8 else 0.165)
    dhi = ghi * fd; dni = (ghi - dhi) / cz
    return ghi, dni, dhi


_SUN = None
def sun_table(lat):
    global _SUN
    if _SUN is None:
        pts = []
        for n in range(1, 366, MODEL["day_step"]):
            t = 5.0
            while t <= 19.0:
                s = sun(lat, n, t)
                if s: pts.append((n, s[0], s[1], *irradiance(n, s[0])))
                t += MODEL["step_min"] / 60
        _SUN = pts
    return _SUN


def energy_factors(lat, tilt_deg, gamma_p, pitch, slope_len):
    """kWh per kWp per year for an unshaded row and for a shaded (inner) row."""
    b = math.radians(tilt_deg); dt = MODEL["step_min"] / 60 * MODEL["day_step"]
    free = shaded = 0.0
    for n, alt, gs, ghi, dni, dhi in sun_table(lat):
        a = math.radians(alt); rel = math.radians(gs - gamma_p)
        cos_i = math.cos(b) * math.sin(a) + math.sin(b) * math.cos(a) * math.cos(rel)
        beam = dni * max(0.0, cos_i)
        diff = dhi * (1 + math.cos(b)) / 2 + ghi * MODEL["albedo"] * (1 - math.cos(b)) / 2
        free += (beam + diff) * dt
        # row shading in the plane perpendicular to the rows (profile angle)
        lost = 0.0
        if beam > 0 and math.cos(rel) > 1e-6:
            ap = math.atan(math.tan(a) / math.cos(rel))
            f = 1 - (pitch / slope_len) * math.sin(ap) / math.sin(ap + b)
            if f > 0.04: lost += 0.5                       # bottom module of the portrait pair loses its beam
            if f > 0.54: lost += 0.5                       # the shadow reaches the top module too
        shaded += (beam * (1 - lost) + diff) * dt
    k = MODEL["pr"] / 1000                                   # Wh/m² → kWh/kWp with PR
    return free * k, shaded * k


# ---- geometry helpers ------------------------------------------------------------------------------------------------------
def rot(p, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def rect_poly(x, y, w, h): return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def sat(A, B):
    for P in (A, B):
        for i in range(len(P)):
            (x1, y1), (x2, y2) = P[i], P[(i + 1) % len(P)]
            nx, ny = y2 - y1, x1 - x2
            a = [nx * x + ny * y for x, y in A]; b = [nx * x + ny * y for x, y in B]
            if max(a) <= min(b) or max(b) <= min(a): return False
    return True


def inside(poly, p):
    s = None
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
        c = (x2 - x1) * (p[1] - y1) - (y2 - y1) * (p[0] - x1)
        if abs(c) < 1e-9: continue
        if s is None: s = c > 0
        elif (c > 0) != s: return False
    return True


def bbox(P): xs = [p[0] for p in P]; ys = [p[1] for p in P]; return min(xs), min(ys), max(xs), max(ys)


def prepare(t, phi):
    """Tank and openings in the layout frame F = Rot(phi)·plan (south = +y in F)."""
    TW, TH = sum(t["bx"]), sum(t["by"]); e, oc = S["edge"], S["open_clear"]
    vents, hatches = openings(t)
    R = lambda P: [rot(p, phi) for p in P]
    ops = []
    for kind, lst in (("vent", vents), ("hatch", hatches)):
        for (x, y, w, h) in lst:
            core = R(rect_poly(x, y, w, h)); grown = R(rect_poly(x - oc, y - oc, w + 2 * oc, h + 2 * oc))
            ops.append(dict(kind=kind, core=core, grown=grown, cb=bbox(core), gb=bbox(grown)))
    return dict(tank=R(rect_poly(0, 0, TW, TH)), inset=R(rect_poly(e, e, TW - 2 * e, TH - 2 * e)), ops=ops, phi=phi)


def layout_f(G, gap, off, colsh, want_posts=True):
    W, g, D0 = S["mod_w"], S["mod_gap"], None
    pitch = S["post_dy"] + gap
    ix0, iy0, ix1, iy1 = bbox(G["inset"])
    xs = []; x = ix0 + colsh
    while x + W <= ix1 + 1e-9: xs.append(x); x += W + g
    rows = []; k = 0; vH = S["vent_h"] + S["under_clear"]; tb_ = math.tan(TILT)
    while True:
        y_front = iy1 - off - k * pitch; yfp = y_front - F_PLAN; ybp = yfp - S["post_dy"]; y_back = ybp - B_PLAN
        if y_back < iy0 - 1e-9: break
        ok = []
        for cx in xs:
            slot = rect_poly(cx, y_back, W, y_front - y_back)
            good = all(inside(G["inset"], p) for p in slot)
            if good:
                for o in G["ops"]:
                    bx0, by0, bx1, by1 = o["gb"]
                    if bx1 <= cx or bx0 >= cx + W or by1 <= y_back or by0 >= y_front: continue
                    if not sat(slot, o["grown"]): continue
                    if o["kind"] == "vent":
                        vy = min(o["cb"][3], y_front)
                        if S["h_front"] + (yfp - vy) * tb_ >= vH: continue       # fits under the panels
                    good = False; break
            ok.append(good)
        tables = []; i = 0
        while i < len(xs):
            if not ok[i]: i += 1; continue
            j = i
            while j < len(xs) and ok[j]: j += 1
            if j - i >= 2: tables.append(dict(i0=i, i1=j, xa=xs[i], xb=xs[j - 1] + W, n=j - i))
            i = j
        if want_posts:
            f = S["footing"] / 2 + 0.30
            def free(xx, yl):
                sq = rect_poly(xx - S["footing"] / 2, yl - S["footing"] / 2, S["footing"], S["footing"])
                if not all(inside(G["tank"], p) for p in sq): return False
                big = rect_poly(xx - f, yl - f, 2 * f, 2 * f)
                return all(not sat(big, o["core"]) for o in G["ops"] if not (o["cb"][2] <= xx - f or o["cb"][0] >= xx + f or o["cb"][3] <= yl - f or o["cb"][1] >= yl + f))
            for tb in tables:
                span = tb["xb"] - tb["xa"] - 2 * S["end_over"]; nP = max(2, math.ceil(span / S["post_dx"]) + 1)
                px = [tb["xa"] + S["end_over"] + span * q / (nP - 1) for q in range(nP)]; bad = []
                both = lambda xx: tb["xa"] <= xx <= tb["xb"] and free(xx, yfp) and free(xx, ybp)
                out = []
                for x in px:
                    c = next((x + s * 0.05 for s in [0] + [a * d for a in range(1, 31) for d in (1, -1)] if both(x + s * 0.05)), None)
                    if c is None: bad.append(x); c = x
                    out.append(c)
                out.sort(); q = 0
                while q < len(out) - 1:
                    if out[q + 1] - out[q] > S["post_dx"] + 1e-6:
                        m = (out[q] + out[q + 1]) / 2
                        c = next((m + s * 0.05 for s in [0] + [a * d for a in range(1, 21) for d in (1, -1)] if both(m + s * 0.05)), None)
                        if c is not None: out.insert(q + 1, c)
                    q += 1
                tb["px"], tb["bad"] = out, bad
        rows.append(dict(k=k, y_front=y_front, yfp=yfp, ybp=ybp, y_back=y_back, tables=tables))
        k += 1
    return rows


def strategies(bearing):
    """True south (phi = bearing) and parallel to the wall that faces nearest to south."""
    wall = round(bearing / 90) * 90
    out = [("หันทิศใต้จริง", bearing, 0.0)]
    if abs(bearing - wall) > 0.5: out.append(("ขนานผนังถัง", wall, bearing - wall))
    return out


def evaluate(rows, gamma_p, pitch):
    y1, y2 = energy_factors(SITE["lat"], math.degrees(TILT), gamma_p, pitch, SLOPE)
    kw = [sum(tb["n"] for tb in r["tables"]) * S["n_slope"] * S["mod_wp"] / 1000 for r in rows]
    # the south-most row with modules sees no row in front; the others use the shaded factor (conservative for short rows)
    first = next((i for i, v in enumerate(kw) if v > 0), None)
    e = sum(v * (y1 if i == first else y2) for i, v in enumerate(kw))
    return sum(kw), e, y1, y2


def optimise(t):
    cands = []
    for name, phi, gamma in strategies(SITE["bearing"]):
        G = prepare(t, phi)
        for gap in [round(S["row_gap"] + 0.2 * i, 2) for i in range(0, 11)]:
            pitch = S["post_dy"] + gap
            best = None
            for io in range(int(pitch / 0.2) + 1):
                for ic in range(int(S["mod_w"] / 0.1) + 1):
                    rows = layout_f(G, gap, io * 0.2, ic * 0.1, want_posts=False)
                    mods = sum(tb["n"] for r in rows for tb in r["tables"])
                    if best is None or mods > best[0]: best = (mods, io * 0.2, ic * 0.1, rows)
            kwp, e, y1, y2 = evaluate(best[3], gamma, pitch)
            cands.append(dict(name=name, phi=phi, gamma=gamma, gap=gap, pitch=pitch, off=best[1], col=best[2], kwp=kwp, mwh=e / 1000,
                              yf=y1, ys=y2, spec=e / kwp if kwp else 0, G=G))
    return cands


# ---- drawings --------------------------------------------------------------------------------------------------------------
def plan_opt(t, c, rows, path, title_extra, W=1100):
    TW, TH = sum(t["bx"]), sum(t["by"]); xs_, ys_ = edges(t["bx"]), edges(t["by"])
    sk = Sk(W); title_strip(sk, f"ผังโครงสร้างแผง ({c['name']}) — " + t["title"].split("—")[-1].strip(), title_extra)
    padL, padT, padR = 150, 70, 300
    k = min((W - padL - padR) / TW, 620 / TH); ox, oy = padL, padT
    P = lambda x, y: (ox + x * k, oy + y * k)
    back = lambda p: rot(p, -c["phi"])                            # F → plan
    Q = lambda p: P(*back(p))
    sk.rect(ox, oy, TW * k, TH * k, BLACK, None, 1.4); sk.rect(ox + 3, oy + 3, TW * k - 6, TH * k - 6, BLACK, None, 0.6)
    for x in xs_[1:-1]: sk.line(P(x, 0), P(x, TH), 0.4, FAINT, [4, 3])
    for y in ys_[1:-1]: sk.line(P(0, y), P(TW, y), 0.4, FAINT, [4, 3])
    vents, hatches = openings(t)
    for (bx, by, bw, bh) in vents:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, OPEN, "white", 0.8); sk.circle((x + bw * k / 2, y + bh * k / 2), bw * k * .2, OPEN, None, .6)
    for (bx, by, bw, bh) in hatches:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, BLACK, "white", 0.9); sk.hatch(x + 1, y + 1, bw * k - 2, bh * k - 2, FAINT, 4)
    Wm = S["mod_w"]; nt = nm = npost = nbad = 0
    for r in rows:
        for tb in r["tables"]:
            nt += 1
            for s_ in range(S["n_slope"]):
                ya = r["y_back"] + s_ * (S["mod_l"] + S["mod_gap"]) * math.cos(TILT); yb = ya + S["mod_l"] * math.cos(TILT)
                for i in range(tb["n"]):
                    xa = tb["xa"] + i * (Wm + S["mod_gap"]); nm += 1
                    sk.poly([Q(p) for p in rect_poly(xa, ya, Wm, yb - ya)], MOD, "#e8eff7", 0.5)
            rails = [r["y_back"] + DEPTH * f for f in (0.12, 0.38, 0.62, 0.88)]
            for yy in rails: sk.line(Q((tb["xa"], yy)), Q((tb["xb"], yy)), 0.8, DARK)
            for x in tb["px"]:
                sk.line(Q((x, r["y_back"])), Q((x, r["y_front"])), 0.8, DARK)
                for yy in rails: sk.circle(Q((x, yy)), 1.9, GRN, GRN)
                for yl in (r["yfp"], r["ybp"]):
                    npost += 1; bad = x in tb["bad"]; col = LUG if bad else BLACK; nbad += bad
                    sk.poly([Q(p) for p in rect_poly(x - .15, yl - .15, .3, .3)], col, "white", 1.1 if bad else 0.8)
                    cc = Q((x, yl)); sk.rect(cc[0] - 1.5, cc[1] - 1.5, 3, 3, col, col)
            sk.circle(Q((tb["xa"] + 0.15, rails[0])), 2.8, LUG, LUG)
    # north arrow at the true bearing (plan up = bearing B → north is rotated −B from up)
    nx, ny = ox + TW * k + 44, oy + 34; b = math.radians(-SITE["bearing"])
    tip = (nx + 22 * math.sin(b), ny - 22 * math.cos(b)); l = (nx + 7 * math.cos(b), ny + 7 * math.sin(b)); rr = (nx - 7 * math.cos(b), ny - 7 * math.sin(b))
    sk.poly([tip, l, rr], BLACK, BLACK); sk.text("N", (nx + 34 * math.sin(b), ny - 34 * math.cos(b)), 9, True, BLACK, "center")
    sk.text(f"ผนังบนหันไปทิศ {SITE['bearing']:.0f}°", (nx, ny + 22), 7.5, False, INK2, "center")
    lx, ly = ox + TW * k + 24, oy + 90
    rows_txt = [("แนวแถว", c["name"]), ("มุมแผงเทียบทิศใต้", f"{c['gamma']:+.0f}°"), ("มุมเอียง", f"{math.degrees(TILT):.1f}°"),
                ("ระหว่างแถว (เสาหลังถึงเสาหน้า)", f"{c['gap']:.2f} ม."), ("แผง", f"{nm} แผง · {nm * S['mod_wp'] / 1000:.1f} kWp"),
                ("โต๊ะ / เสา", f"{nt} / {npost}"), ("พลังงานต่อปี (ประมาณ)", f"{c['mwh']:.0f} MWh"), ("ต่อ kWp", f"{c['spec']:.0f} kWh/kWp"),
                ("เงาแถวหน้าบังแถวหลัง", f"−{(1 - c['ys'] / c['yf']) * 100:.1f}% ต่อแถว"), ("เสาต้องตรวจ", f"{nbad}")]
    sk.text(c.get("label", "ผลที่เลือก (พลังงานสูงสุด)"), (lx, ly), 9, True); ly += 18
    for a, v in rows_txt: sk.text(a, (lx, ly), 8, False, INK2); sk.text(v, (lx + 265, ly), 8, True, BLACK, "right"); ly += 15
    yb = oy + TH * k + 26
    sk.line((14, yb - 10), (W - 14, yb - 10), 0.5, RULE)
    sk.text(f"ค่าสมมติ: ละติจูด {SITE['lat']:.1f}° (พิกัด GPS ในแบบสำรวจ) · ฟ้าใส Haurwitz × {MODEL['clear']} · PR {MODEL['pr']} · albedo {MODEL['albedo']} · "
            f"แผงแนวตั้ง 2 แผง: ขอบล่างโดนเงาแล้วแผงล่างเสียแสงตรงทั้งแผง", (14, yb + 4), 7.5, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบนพื้นหลังคาถังกับวิศวกรโครงสร้าง", (W - 14, yb + 20), 7.5, False, RED, "right")
    sk.render(yb + 34, path)


def compare_chart(cands, chosen, path, W=1100):
    sk = Sk(W); title_strip(sk, "เลือกผังจากพลังงานต่อปี ไม่ใช่จำนวนแผง", f"ละติจูด {SITE['lat']:.1f}° · ผนังบนหันทิศ {SITE['bearing']:.0f}° · มุมเอียง {math.degrees(TILT):.1f}°")
    x0, y0, w, h = 90, 80, W - 440, 330
    gaps = sorted({c["gap"] for c in cands}); names = []
    for c in cands:
        if c["name"] not in names: names.append(c["name"])
    lo = min(c["mwh"] for c in cands) * 0.97; hi = max(c["mwh"] for c in cands) * 1.01
    X = lambda g: x0 + (g - gaps[0]) / (gaps[-1] - gaps[0]) * w; Y = lambda v: y0 + h - (v - lo) / (hi - lo) * h
    for i in range(6):
        v = lo + (hi - lo) * i / 5; sk.line((x0, Y(v)), (x0 + w, Y(v)), 0.4, "#e3e3e3"); sk.text(f"{v:.0f}", (x0 - 8, Y(v)), 8, False, INK2, "right")
    for g in gaps[::2]: sk.text(f"{g:.1f}", (X(g), y0 + h + 14), 8, False, INK2, "center")
    sk.text("ระหว่างแถว (ม.) เสาหลังถึงเสาหน้าแถวถัดไป", (x0 + w / 2, y0 + h + 32), 8.5, False, BLACK, "center")
    sk.text("MWh/ปี", (x0 - 8, y0 - 14), 8.5, True, BLACK, "right")
    cols = {names[0]: MOD, (names[1] if len(names) > 1 else ""): "#B7791F"}
    for nm in names:
        pts = [(X(c["gap"]), Y(c["mwh"])) for c in cands if c["name"] == nm]
        for a, b in zip(pts, pts[1:]): sk.line(a, b, 2, cols[nm])
        for p in pts: sk.circle(p, 2.6, cols[nm], cols[nm])
    cx, cy = X(chosen["gap"]), Y(chosen["mwh"]); sk.circle((cx, cy), 7, RED, None, 1.4)
    sk.text(f"เลือก: {chosen['name']} · {chosen['gap']:.1f} ม. · {chosen['mwh']:.0f} MWh", (cx + 10, cy - 12), 8.5, True, RED)
    std = next(c for c in cands if c["name"] == names[-1] and abs(c["gap"] - S["row_gap"]) < 1e-6)
    if std is not chosen:
        sx, sy = X(std["gap"]), Y(std["mwh"]); sk.circle((sx, sy), 7, BLACK, None, 1.2)
        sk.text(f"มาตรฐานเดิม: ขนานผนัง {S['row_gap']:.1f} ม. · {std['mwh']:.0f} MWh", (sx + 10, sy + 16), 8.5, True, BLACK)
    else:
        sk.text("(ตรงกับมาตรฐานเดิม ระหว่างแถว 2.70 ม.)", (cx + 10, cy + 6), 8, False, RED)
    ts = next(c for c in cands if c["name"] == names[0] and abs(c["gap"] - chosen["gap"]) < 1e-6)
    if ts is not chosen:
        tx, ty = X(ts["gap"]), Y(ts["mwh"]); sk.circle((tx, ty), 6, MOD, None, 1.2)
        sk.text(f"หันทิศใต้จริง ระยะเดียวกัน: {ts['kwp']:.1f} kWp · {ts['mwh']:.0f} MWh ({(ts['mwh'] / chosen['mwh'] - 1) * 100:+.0f}%)", (tx + 10, ty + 16), 8.5, True, MOD)
    lx, ly = x0 + w + 30, y0 + 10
    for nm in names:
        sk.line((lx, ly), (lx + 22, ly), 2, cols[nm]); sk.text(nm, (lx + 28, ly), 8.5); ly += 18
    ly += 10
    sk.text("แผง (kWp) ตามระยะแถว", (lx, ly), 8.5, True); ly += 16
    for c in cands:
        if c["name"] == chosen["name"] and int(round(c["gap"] * 10)) % 4 == int(round(S["row_gap"] * 10)) % 4:
            sk.text(f"{c['gap']:.1f} ม.", (lx, ly), 8, False, INK2); sk.text(f"{c['kwp']:.1f} kWp · {c['spec']:.0f} kWh/kWp", (lx + 250, ly), 8, False, BLACK, "right"); ly += 14
    sk.text("ระยะแถวน้อย = แผงมากแต่เงาบังมาก · ระยะแถวมาก = แผงน้อยแต่แต่ละแผงผลิตได้มากขึ้น", (x0, y0 + h + 58), 8.5)
    sk.render(y0 + h + 76, path)


if __name__ == "__main__":
    t0 = time.time()
    cands = optimise(TANK)
    best = max(cands, key=lambda c: c["mwh"])
    rows = layout_f(best["G"], best["gap"], best["off"], best["col"], want_posts=True)
    plan_opt(TANK, best, rows, os.path.join(HERE, "tank_mount_opt_plan.png"),
             f"ละติจูด {SITE['lat']:.1f}° · ผนังบนหันทิศ {SITE['bearing']:.0f}° · หน่วย ม.")
    compare_chart(cands, best, os.path.join(HERE, "tank_mount_opt_compare.png"))
    south = max((c for c in cands if c["name"] == "หันทิศใต้จริง"), key=lambda c: c["mwh"])
    south["label"] = "บังคับหันทิศใต้จริง (พลังงานสูงสุดของแบบนี้)"
    rs = layout_f(south["G"], south["gap"], south["off"], south["col"], want_posts=True)
    plan_opt(TANK, south, rs, os.path.join(HERE, "tank_mount_opt_south.png"),
             f"ละติจูด {SITE['lat']:.1f}° · ผนังบนหันทิศ {SITE['bearing']:.0f}° · หน่วย ม.")
    for c in cands:
        if int(round(c["gap"] * 10)) % 4 == 3 or c is best:
            print(f"{c['name']:14s} gap {c['gap']:.1f} off {c['off']:.1f} col {c['col']:.1f}  {c['kwp']:6.1f} kWp  {c['mwh']:6.1f} MWh  {c['spec']:5.0f} kWh/kWp  shade {(1 - c['ys'] / c['yf']) * 100:4.1f}%")
    print("best", best["name"], best["gap"], round(best["mwh"], 1), "time", round(time.time() - t0, 1), "s")
