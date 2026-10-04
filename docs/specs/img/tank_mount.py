"""Auto mounting layout on a clear-water tank roof, from the tank survey (bays, openings) and one mounting standard.

The standard is the team's tank-roof structure (front post 1.00, back post 2.00, 2.80 between posts, 2.70 between
rows, 2 modules portrait along the slope, posts ≤ 2.70 apart along the row, 300×300×150 concrete footing anchored to the
roof slab). Everything else is derived. Run from docs/specs/img/: writes tank_mount_plan.png, tank_mount_section.png,
tank_mount_front.png and prints the bill of quantities.
"""
import math, os
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "draw.py")).read().split("# ---------------------------------------------------------------- roof section")[0])

MOD = "#1F4E79"; GRN = "#2EAD4B"; LUG = "#E0433A"; OPEN = "#9a9a9a"

# ---- mounting standard (one set per company; editable in settings) -------------------------------------------------
STD = dict(
    mod_l=2.28, mod_w=1.13, mod_gap=0.02, mod_wp=600,  # module (portrait along the slope)
    n_slope=2,                                         # modules along the slope
    h_front=1.00, h_back=2.00, post_dy=2.80,           # post heights above the roof, front→back post distance (plan)
    row_gap=2.70,                                      # back post of one row → front post of the next
    post_dx=2.70, end_over=0.40,                       # max post spacing along the row, rail overhang past the end posts
    front_over=0.46,                                   # slope length from the front post to the lower panel edge
    rails=4, footing=0.30,                             # rails per table, footing size
    edge=1.0, open_clear=0.5,                          # setbacks (same as the usable-area rule)
    vent_h=1.00, under_clear=0.10,                     # vent height above the roof, clearance under the panels
)
S = STD
TILT = math.atan((S["h_back"] - S["h_front"]) / S["post_dy"])
SLOPE = S["n_slope"] * S["mod_l"] + (S["n_slope"] - 1) * S["mod_gap"]
BACK_OVER = SLOPE - S["post_dy"] / math.cos(TILT) - S["front_over"]
F_PLAN, B_PLAN = S["front_over"] * math.cos(TILT), BACK_OVER * math.cos(TILT)
DEPTH = SLOPE * math.cos(TILT)                               # plan depth of one table
PITCH = S["post_dy"] + S["row_gap"]                          # front post → next front post


def height_at(y_front_post, y):
    """Panel underside height above the roof at plan y (y-down, south = larger y, front post at y_front_post)."""
    return S["h_front"] + (y_front_post - y) * math.tan(TILT)


# ---- tank (same input shape as tank_plan.py) ---------------------------------------------------------------------------
TANK = dict(
    title="ผังติดตั้งโครงสร้างแผงบนหลังคาถัง — D1.2 ถังน้ำใส 2", bx=[4.0] * 10, by=[4.0] * 10,
    vents=[(r, c) for r in (0, 4, 9) for c in (0, 4, 5, 9)], vent=1.5, hatch=1.2,
    hatches=[("top", 10.2), ("top", 29.6), ("bottom", 10.2), ("bottom", 29.6), ("left", 21.7), ("right", 21.7)],
    ladders=[("left", 6.4), ("left", 33.4), ("right", 33.4)], north="top",
)


def edges(sp):
    e = [0.0]
    for a in sp: e.append(e[-1] + a)
    return e


def openings(t):
    xs, ys, TW, TH = edges(t["bx"]), edges(t["by"]), sum(t["bx"]), sum(t["by"])
    V, H = t["vent"], t["hatch"]
    vents = [((xs[c] + xs[c + 1]) / 2 - V / 2, (ys[r] + ys[r + 1]) / 2 - V / 2, V, V) for r, c in t["vents"]]
    on = lambda e, d: {"top": (d - H / 2, .15, H, H), "bottom": (d - H / 2, TH - H - .15, H, H),
                       "left": (.15, d - H / 2, H, H), "right": (TW - H - .15, d - H / 2, H, H)}[e]
    return vents, [on(e, d) for e, d in t["hatches"]]


def overlap(a0, a1, b0, b1): return a0 < b1 and b0 < a1


# ---- layout ---------------------------------------------------------------------------------------------------------------
def layout(t):
    TW, TH = sum(t["bx"]), sum(t["by"])
    vents, hatches = openings(t)
    W, gap, e, oc = S["mod_w"], S["mod_gap"], S["edge"], S["open_clear"]
    n_all = int((TW - 2 * e + gap) // (W + gap))
    x0 = (TW - (n_all * W + (n_all - 1) * gap)) / 2
    cols = [x0 + i * (W + gap) for i in range(n_all)]
    rows, notes, under = [], [], 0
    k = 0
    while True:
        y_front = TH - e - k * PITCH                          # lower (south) panel edge
        yfp = y_front - F_PLAN; ybp = yfp - S["post_dy"]; y_back = ybp - B_PLAN
        if y_back < e: break
        blocked = [False] * n_all
        for (bx, by, bw, bh) in hatches:
            if overlap(y_back, y_front, by - oc, by + bh + oc):
                for i, cx in enumerate(cols):
                    if overlap(cx, cx + W, bx - oc, bx + bw + oc): blocked[i] = True
        for (bx, by, bw, bh) in vents:
            if not overlap(y_back, y_front, by - oc, by + bh + oc): continue
            h_min = height_at(yfp, min(by + bh, y_front))           # lowest panel point over the vent
            if h_min >= S["vent_h"] + S["under_clear"]: under += 1; continue   # the vent fits under the panels
            for i, cx in enumerate(cols):
                if overlap(cx, cx + W, bx - oc, bx + bw + oc): blocked[i] = True
        # contiguous runs → tables (at least 2 columns)
        i = 0; tables = []
        while i < n_all:
            if blocked[i]: i += 1; continue
            j = i
            while j < n_all and not blocked[j]: j += 1
            if j - i >= 2: tables.append((i, j))
            i = j
        rows.append(dict(k=k, y_front=y_front, yfp=yfp, ybp=ybp, y_back=y_back, tables=[]))
        for (i, j) in tables:
            xa, xb = cols[i], cols[j - 1] + W
            span = xb - xa - 2 * S["end_over"]
            n_post = max(2, math.ceil(span / S["post_dx"]) + 1)
            px = [xa + S["end_over"] + span * q / (n_post - 1) for q in range(n_post)]
            # footings must stay 0.30 m clear of every opening: slide along the row (0.05 m steps, ≤ 0.9 m)
            posts = []
            f = S["footing"] / 2 + 0.30
            free = lambda xx, yline: xa <= xx <= xb and all(not (overlap(xx - f, xx + f, bx, bx + bw) and overlap(yline - f, yline + f, by, by + bh))
                                                             for (bx, by, bw, bh) in vents + hatches)
            both = lambda xx: free(xx, yfp) and free(xx, ybp)          # front and back post share one rafter: move them as a pair
            line = []; bad = []
            for x in px:
                ok_x = next((x + st * 0.05 for st in [0] + [s_ * d for s_ in range(1, 31) for d in (1, -1)] if both(x + st * 0.05)), None)
                if ok_x is None: notes.append(f"แถว {k + 1}: เสาคู่ที่ x = {x:.2f} ม. ชนช่องเปิด ต้องให้วิศวกรตรวจ"); ok_x = x; bad.append(x)
                elif abs(ok_x - x) > 1e-6: notes.append(f"แถว {k + 1}: เลื่อนเสาคู่จาก {x:.2f} เป็น {ok_x:.2f} ม. หลบช่องเปิด")
                line.append(ok_x)
            line.sort(); q = 0
            while q < len(line) - 1:                                   # a slid pair may open a bay wider than the standard
                if line[q + 1] - line[q] > S["post_dx"] + 1e-6:
                    mid = (line[q] + line[q + 1]) / 2
                    cand = next((mid + st * 0.05 for st in [0] + [s_ * d for s_ in range(1, 21) for d in (1, -1)] if both(mid + st * 0.05)), None)
                    if cand is None: notes.append(f"แถว {k + 1}: ช่วงเสา {line[q + 1] - line[q]:.2f} ม. เกินมาตรฐาน"); q += 1; continue
                    line.insert(q + 1, cand); notes.append(f"แถว {k + 1}: เพิ่มเสาคู่ที่ x = {cand:.2f} ม.")
                q += 1
            px = line
            posts = [(x, yl) for yl in (yfp, ybp) for x in px]
            rows[-1]["tables"].append(dict(xa=xa, xb=xb, n=j - i, px=px, posts=posts, bad=bad))
        k += 1
    return dict(TW=TW, TH=TH, vents=vents, hatches=hatches, rows=rows, notes=notes, under=under, cols=cols)


def quantities(L):
    tabs = [tb for r in L["rows"] for tb in r["tables"]]
    mods = sum(tb["n"] * S["n_slope"] for tb in tabs)
    posts = sum(len(tb["posts"]) for tb in tabs)
    rafters = sum(len(tb["px"]) for tb in tabs)
    rail_m = sum((tb["xb"] - tb["xa"]) * S["rails"] for tb in tabs)
    mid = sum((tb["n"] - 1) * 2 * S["n_slope"] for tb in tabs)      # 2 clamps per module joint per module row
    end = sum(2 * 2 * S["n_slope"] for tb in tabs)
    clamps = sum(len(tb["px"]) * S["rails"] for tb in tabs)          # rail clamps where rails cross rafters
    braces = sum(max(0, len(tb["px"]) - 1) * 2 for tb in tabs)       # X in each bay of the back line
    return dict(tables=len(tabs), modules=mods, kwp=mods * S["mod_wp"] / 1000, posts=posts, footings=posts,
                rafters=rafters, rail_m=rail_m, mid=mid, end=end, rail_clamps=clamps, braces=braces, lugs=len(tabs))


# ---- drawings ---------------------------------------------------------------------------------------------------------------
def plan(t, L, Q, path, W=1100):
    TW, TH = L["TW"], L["TH"]; xs, ys = edges(t["bx"]), edges(t["by"])
    sk = Sk(W)
    title_strip(sk, t["title"], "สร้างจากแปลนฝาถัง + มาตรฐานโครงสร้าง · หน่วย ม.")
    padL, padT, padR = 150, 70, 260
    k = min((W - padL - padR) / TW, 620 / TH); w, h = TW * k, TH * k
    ox, oy = padL, padT
    P = lambda x, y: (ox + x * k, oy + y * k)
    # tank
    sk.rect(ox, oy, w, h, BLACK, None, 1.4); sk.rect(ox + 3, oy + 3, w - 6, h - 6, BLACK, None, 0.6)
    for x in xs[1:-1]: sk.line(P(x, 0), P(x, TH), 0.4, FAINT, [4, 3])
    for y in ys[1:-1]: sk.line(P(0, y), P(TW, y), 0.4, FAINT, [4, 3])
    for (bx, by, bw, bh) in L["vents"]:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, OPEN, "white", 0.8, ); sk.circle((x + bw * k / 2, y + bh * k / 2), bw * k * 0.2, OPEN, None, 0.6)
    for (bx, by, bw, bh) in L["hatches"]:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, BLACK, "white", 0.9); sk.hatch(x + 1, y + 1, bw * k - 2, bh * k - 2, FAINT, 4)
    # tables
    for r in L["rows"]:
        for tb in r["tables"]:
            # modules (dashed blue), 2 along the slope
            for s in range(S["n_slope"]):
                ya = r["y_back"] + s * (S["mod_l"] + S["mod_gap"]) * math.cos(TILT); yb = ya + S["mod_l"] * math.cos(TILT)
                for i in range(tb["n"]):
                    xa = tb["xa"] + i * (S["mod_w"] + S["mod_gap"])
                    a = P(xa, ya); sk.rect(a[0], a[1], S["mod_w"] * k, (yb - ya) * k, MOD, None, 0.55)
            # rails (along the row) and rafters (at posts)
            rail_y = [r["y_back"] + DEPTH * f for f in (0.12, 0.38, 0.62, 0.88)]
            for yy in rail_y: sk.line(P(tb["xa"], yy), P(tb["xb"], yy), 0.9, DARK)
            for x in tb["px"]:
                sk.line(P(x, r["y_back"]), P(x, r["y_front"]), 0.9, DARK)
                for yy in rail_y: sk.circle(P(x, yy), 2.2, GRN, GRN)
            for (x, y) in tb["posts"]:
                c = P(x, y); f = max(5, S["footing"] * k); col = LUG if x in tb["bad"] else BLACK
                sk.rect(c[0] - f / 2, c[1] - f / 2, f, f, col, "white", 1.2 if col == LUG else 0.9); sk.rect(c[0] - 1.6, c[1] - 1.6, 3.2, 3.2, col, col)
                if col == LUG: sk.circle(c, 9, LUG, None, 1.0)
            sk.circle(P(tb["xa"] + 0.15, rail_y[0]), 3, LUG, LUG)
    # dims: overall and row pitch on the left
    dx = ox - 40
    sk.line((dx, oy), (dx, oy + h), 0.6); sk.text(f"{TH:.2f}", (dx - 8, oy + h / 2), 8.5, True, BLACK, "right")
    r0 = L["rows"][0]
    for a, b, lab in ((r0["ybp"], r0["yfp"], f"{S['post_dy']:.2f}"),):
        pass
    # north arrow
    nx, ny = ox + w + 40, oy + 20
    sk.poly([(nx, ny - 14), (nx - 6, ny + 4), (nx + 6, ny + 4)], BLACK, BLACK); sk.text("N", (nx, ny + 14), 9, True, BLACK, "center")
    # legend + quantities on the right
    lx, ly = ox + w + 24, oy + 60
    for sym, lab in (("mod", "แผง (ฉายลงแปลน)"), ("post", "เสา + ฐานคอนกรีต 300×300×150 ยึดพุก"), ("clamp", "จุดยึดราง (rail clamp)"),
                     ("lug", "ground lug"), ("bad", "เสาชนช่องเปิด ให้วิศวกรตรวจ"), ("vent", "ช่องระบายอากาศ"), ("hatch", "ช่องลงถัง")):
        if sym == "mod": sk.rect(lx, ly - 5, 14, 10, MOD, None, 0.6)
        elif sym == "post": sk.rect(lx + 2, ly - 5, 10, 10, BLACK, "white", 0.9); sk.rect(lx + 5.4, ly - 1.6, 3.2, 3.2, BLACK, BLACK)
        elif sym == "clamp": sk.circle((lx + 7, ly), 3, GRN, GRN)
        elif sym == "lug": sk.circle((lx + 7, ly), 3.5, LUG, LUG)
        elif sym == "bad": sk.rect(lx + 2, ly - 5, 10, 10, LUG, "white", 1.2); sk.circle((lx + 7, ly), 9, LUG, None, 1.0)
        elif sym == "vent": sk.rect(lx + 1, ly - 6, 12, 12, OPEN, "white", 0.8)
        else: sk.rect(lx + 1, ly - 6, 12, 12, BLACK, "white", 0.9); sk.hatch(lx + 2, ly - 5, 10, 10, FAINT, 3)
        sk.text(lab, (lx + 22, ly), 8); ly += 18
    ly += 10
    sk.text("ปริมาณงาน (อัตโนมัติ)", (lx, ly), 9, True); ly += 18
    for a, b in (("โต๊ะแผง", f"{Q['tables']}"), ("แผง", f"{Q['modules']} แผง · {Q['kwp']:.1f} kWp"), ("เสา / ฐานคอนกรีต", f"{Q['posts']} ชุด"),
                 ("คานเอียง (rafter)", f"{Q['rafters']}"), ("ราง", f"{Q['rail_m']:.0f} ม."), ("rail clamp", f"{Q['rail_clamps']}"),
                 ("mid / end clamp", f"{Q['mid']} / {Q['end']}"), ("เหล็กค้ำ X", f"{Q['braces']} เส้น"), ("ground lug", f"{Q['lugs']}")):
        sk.text(a, (lx, ly), 8, False, INK2); sk.text(b, (lx + 225, ly), 8, True, BLACK, "right"); ly += 15
    # summary + notes
    yb = oy + h + 30
    sk.line((14, yb - 10), (W - 14, yb - 10), 0.5, RULE)
    rows_n = len(L["rows"])
    sk.text(f"{rows_n} แถว · ระยะแถว {PITCH:.2f} ม. (เสาหน้า–เสาหน้า) · มุมเอียง {math.degrees(TILT):.1f}° หันทิศใต้ · ช่องระบายอยู่ใต้แผงได้ {L['under']} จุด (ใต้แผงสูงพอ)",
            (14, yb + 4), 8.5, True)
    notes = L["notes"][:4] + ([f"… อีก {len(L['notes']) - 4} รายการ"] if len(L["notes"]) > 4 else [])
    for i, n in enumerate(notes): sk.text("• " + n, (22, yb + 22 + i * 14), 8, False, INK2)
    yy = yb + 22 + len(notes) * 14 + 6
    sk.text(f"ค่าสมมติ/มาตรฐาน: แผง {S['mod_l']}×{S['mod_w']} ม. {S['mod_wp']} W · เสาหน้า {S['h_front']:.2f} หลัง {S['h_back']:.2f} ห่าง {S['post_dy']:.2f} · "
            f"ระยะเสาตามแถวไม่เกิน {S['post_dx']:.2f} · เว้นขอบ {S['edge']} ม. รอบช่องเปิด {S['open_clear']} ม. · ช่องระบายสูง {S['vent_h']:.2f} ม.", (14, yy), 7.5, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบนพื้นหลังคาถังกับวิศวกรโครงสร้าง", (W - 14, yy + 16), 7.5, False, RED, "right")
    sk.render(yy + 30, path)


def section(path, W=1100):
    """Side section of two rows (as the team's sheet), with a vent standing under the back half of the first row."""
    sk = Sk(W); title_strip(sk, "รูปตัดด้านข้างโครงสร้าง (2 แถว)", f"มุมเอียง {math.degrees(TILT):.1f}° · หน่วย ม.")
    k = 88; gy = 380; x0 = 110
    X = lambda x: x0 + x * k; Y = lambda h: gy - h * k
    sk.line((40, gy), (W - 40, gy), 1.2, BLACK); sk.hatch(40, gy, W - 80, 10, FAINT, 5); sk.text("พื้นหลังคาถัง (คอนกรีต)", (44, gy + 22), 8, False, INK2)
    for r in range(2):
        xf = X(r * PITCH + 0.0); xb = X(r * PITCH + S["post_dy"])     # front post left (south on the left in this view)
        for xp, hh in ((xf, S["h_front"]), (xb, S["h_back"])):
            sk.rect(xp - 0.15 * k, gy - 0.15 * k, 0.30 * k, 0.15 * k, BLACK, "white", 0.9); sk.hatch(xp - 0.15 * k + 1, gy - 0.15 * k + 1, 0.3 * k - 2, 0.15 * k - 2, FAINT, 3)
            sk.line((xp, gy - 0.15 * k), (xp, Y(hh)), 2.4, DARK)
        # rafter + modules
        fx = xf - S["front_over"] * math.cos(TILT) * k; fy = Y(S["h_front"] - S["front_over"] * math.sin(TILT))
        bx = xb + BACK_OVER * math.cos(TILT) * k; by = Y(S["h_back"] + BACK_OVER * math.sin(TILT))
        sk.line((fx, fy), (bx, by), 2.0, DARK)
        nx, ny = -math.sin(TILT), -math.cos(TILT)
        for m in range(S["n_slope"]):
            a = m * (S["mod_l"] + S["mod_gap"]); b = a + S["mod_l"]
            p0 = (fx + a * math.cos(TILT) * k + nx * 7, fy - a * math.sin(TILT) * k + ny * 7)
            p1 = (fx + b * math.cos(TILT) * k + nx * 7, fy - b * math.sin(TILT) * k + ny * 7)
            sk.line(p0, p1, 4, MOD)
        # braces: back post base → rafter near the front post, and front post base → rafter mid
        sk.line((xf, gy - 0.15 * k), (xf + 1.0 * k, Y(S["h_front"] + 1.0 * math.tan(TILT))), 1.2, DARK)        # front brace
        sk.line((xb, gy - 0.15 * k), (xb + 0.8 * k, Y(S["h_back"] + 0.8 * math.tan(TILT))), 1.2, DARK)          # back brace
        # dims
        dim_h(sk, xf, xb, gy + 44, f"{S['post_dy']:.2f}")
        dim_v(sk, xf - 18, Y(S["h_front"]), gy, f"{S['h_front']:.2f}")
        dim_v(sk, xb - 18, Y(S["h_back"]), gy, f"{S['h_back']:.2f}")
    dim_h(sk, X(S["post_dy"]), X(PITCH), gy + 44, f"{S['row_gap']:.2f}")
    dim_h(sk, X(0), X(PITCH + S["post_dy"]), gy + 78, f"{PITCH + S['post_dy']:.2f}", bold=True)
    # vent under the back half of row 1
    vx = 1.05; vw = 1.50
    sk.rect(X(vx), Y(S["vent_h"]), vw * k, 0.60 * k, OPEN, None, 0.9); sk.hatch(X(vx) + 1, Y(S["vent_h"]) + 1, vw * k - 2, 0.6 * k - 2, "#dddddd", 4)
    sk.rect(X(vx + 0.45), Y(0.40), 0.60 * k, 0.40 * k, OPEN, None, 0.9)
    sk.text("ช่องระบายอากาศ", (X(vx + vw / 2), Y(S["vent_h"]) - 10), 8, False, INK2, "center")
    hmin = S["h_front"] + (vx + vw) * 0 + (vx) * math.tan(TILT)
    sk.text(f"ใต้แผงเหนือช่องระบายสูงอย่างน้อย {S['vent_h'] + S['under_clear']:.2f} ม. จึงวางแผงคร่อมได้", (X(vx + vw / 2), Y(S['h_back'] + 1.1)), 8.5, True, GRN, "center")
    sk.line((X(vx + vw / 2), Y(S['h_back'] + 1.0)), (X(vx + vw / 2), Y(S['vent_h']) - 18), 0.6, GRN, [3, 2])
    sk.text(f"แผง {S['n_slope']} แผงตามแนวเอียง · ยาวตามเอียง {SLOPE:.2f} ม. · ยื่นหน้า {S['front_over']:.2f} ม. · ยื่นหลัง {BACK_OVER:.2f} ม.", (40, gy + 112), 8.5)
    sk.text("สร้างอัตโนมัติจากมาตรฐานโครงสร้าง ไม่ใช่แบบก่อสร้าง", (W - 14, gy + 112), 7.5, False, RED, "right")
    sk.render(gy + 130, path)


def front(tb, path, W=1100):
    sk = Sk(W); title_strip(sk, "รูปด้านหน้าโต๊ะแผง (แนวเสาหลัง)", f"โต๊ะยาว {tb['xb'] - tb['xa']:.2f} ม. · เสา {len(tb['px'])} ต้น · หน่วย ม.")
    k = min((W - 160) / (tb["xb"] - tb["xa"]), 60); gy = 90 + (S["h_back"] + 0.8) * k; x0 = 80
    X = lambda x: x0 + (x - tb["xa"]) * k; Y = lambda h: gy - h * k
    sk.line((40, gy), (W - 40, gy), 1.2, BLACK); sk.hatch(40, gy, W - 80, 10, FAINT, 5)
    top = S["h_back"] + BACK_OVER * math.sin(TILT)
    for i in range(tb["n"]):
        xa = tb["xa"] + i * (S["mod_w"] + S["mod_gap"])
        sk.rect(X(xa), Y(top + 0.10), S["mod_w"] * k, (top - S["h_front"] + 0.5) * k * 0.9, MOD, None, 0.6, )
    for f in (0.2, 0.45, 0.7, 0.95):
        yy = Y(S["h_front"] + (top - S["h_front"]) * f)
        sk.line((X(tb["xa"]) - 6, yy), (X(tb["xb"]) + 6, yy), 1.6, DARK)
    for q, x in enumerate(tb["px"]):
        sk.rect(X(x) - 0.15 * k, gy - 0.15 * k, 0.30 * k, 0.15 * k, BLACK, "white", 0.9)
        sk.line((X(x), gy - 0.15 * k), (X(x), Y(S["h_back"])), 2.4, DARK)
        if q < len(tb["px"]) - 1:
            xn = tb["px"][q + 1]
            sk.line((X(x), Y(0.35)), (X(xn), Y(S["h_back"] - 0.15)), 1.0, DARK); sk.line((X(x), Y(S["h_back"] - 0.15)), (X(xn), Y(0.35)), 1.0, DARK)
            dim_h(sk, X(x), X(xn), gy + 40, f"{xn - x:.2f}")
    dim_v(sk, X(tb["xa"]) - 30, Y(S["h_back"]), gy, f"{S['h_back']:.2f}")
    sk.text("เหล็กค้ำ X ทุกช่วงเสา · ฐานคอนกรีต 300×300×150 มม. ยึดพุกกับพื้นหลังคาถัง", (40, gy + 76), 8.5)
    sk.render(gy + 96, path)


if __name__ == "__main__":
    L = layout(TANK); Q = quantities(L)
    plan(TANK, L, Q, os.path.join(HERE, "tank_mount_plan.png"))
    section(os.path.join(HERE, "tank_mount_section.png"))
    first = min((tb for r in L["rows"] for tb in r["tables"] if len(tb["px"]) >= 4), key=lambda tb: tb["n"])
    front(first, os.path.join(HERE, "tank_mount_front.png"))
    print({k: (round(v, 1) if isinstance(v, float) else v) for k, v in Q.items()}, "rows", len(L["rows"]), "under", L["under"], "notes", len(L["notes"]))
    print("tilt", round(math.degrees(TILT), 2), "slope", round(SLOPE, 2), "back_over", round(BACK_OVER, 3), "depth", round(DEPTH, 2))
