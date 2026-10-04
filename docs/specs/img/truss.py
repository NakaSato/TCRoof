"""Detailed steel roof truss section prototype (Howe / Pratt / Warren), with eave and ridge details and a member schedule."""
import math, sys
src = open("draw.py").read().split("# ---------------------------------------------------------------- roof section")[0]
exec(src)

GUSSET = "#6b6b6b"


def seg_len(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def truss_geometry(B, th, E, d0, n, kind):
    """Metres, y-up. Returns chords, verticals, diagonals, nodes."""
    h = B / 2
    tan = math.tan(th)
    xs = [i * h / n for i in range(n + 1)]
    top = lambda x: E + d0 + (x if x <= h else B - x) * tan
    L_top, L_bot = [], []
    for side in (0, 1):
        X = xs if side == 0 else [B - x for x in xs]
        for i in range(n):
            L_top.append(((X[i], top(X[i])), (X[i + 1], top(X[i + 1]))))
            L_bot.append(((X[i], E), (X[i + 1], E)))
    verts, diags = [], []
    for side in (0, 1):
        X = xs if side == 0 else [B - x for x in xs]
        for i in range(n + 1):
            if i == n and side == 1:
                continue  # king post once
            if kind == "warren" and 0 < i < n:
                continue
            if i == 0 and d0 <= 0:
                continue
            verts.append(((X[i], E), (X[i], top(X[i]))))
        for i in range(n):
            if kind == "howe":      # bottom(i) → top(i+1): slopes up toward the ridge
                diags.append(((X[i], E), (X[i + 1], top(X[i + 1]))) if i > 0 or d0 > 0 else ((X[i], E), (X[i + 1], top(X[i + 1]))))
            elif kind == "pratt":   # top(i) → bottom(i+1): slopes down toward the ridge
                if i == 0 and d0 <= 0:
                    continue
                diags.append(((X[i], top(X[i])), (X[i + 1], E)))
            else:                   # warren zig-zag
                a = (X[i], E) if i % 2 == 0 else (X[i], top(X[i]))
                b = (X[i + 1], top(X[i + 1])) if i % 2 == 0 else (X[i + 1], E)
                diags.append((a, b))
    nodes = set()
    for s in verts + diags + [((0.0, E), (0.0, E)), ((B, E), (B, E))] + L_top:
        nodes.add((round(s[0][0], 4), round(s[0][1], 4))); nodes.add((round(s[1][0], 4), round(s[1][1], 4)))
    return dict(top=L_top, bot=L_bot, verts=verts, diags=diags, nodes=sorted(nodes), xs=xs, topf=top)


def roof_truss(path, kind="howe"):
    B, th, E, d0, s, o = 16.0, math.radians(15), 4.0, 0.5, 1.0, 0.6
    h = B / 2; R = h * math.tan(th); Ls = h / math.cos(th)
    n = max(2, round(Ls / s))                     # one panel per purlin → purlins sit on nodes
    g = truss_geometry(B, th, E, d0, n, kind)
    W = 690; sk = Sk(W)
    names = {"howe": "Howe", "pratt": "Pratt", "warren": "Warren"}
    title_strip(sk, f"รูปตัดโครงถักหลังคา ({names[kind]}) — C1.1 หลังคา · 1 โรงกรอง",
                "หน่วย: ม. · มาตราส่วนโดยประมาณ · ตัดตามแนวตั้งของแปลน")
    top_y, padL, padR = 64, 64, 64
    xmin, xmax = -o * math.cos(th), B + o * math.cos(th)
    k = min((W - padL - padR) / (xmax - xmin), 250 / (E + d0 + R))
    ox = padL + ((W - padL - padR) - (xmax - xmin) * k) / 2
    gy0 = top_y + (E + d0 + R) * k + 6
    P = lambda x, y: (ox + (x - xmin) * k, gy0 - y * k)

    # ground + columns
    sk.line(P(xmin - 0.5, 0), P(xmax + 0.5, 0), 1.2, DARK)
    sk.hatch(P(xmin - 0.5, 0)[0], gy0, (xmax - xmin + 1.0) * k, 7, FAINT, 7)
    for x in (0.0, B):
        sk.line(P(x, 0), P(x, E), 2.4, DARK)
        sk.rect(P(x, 0)[0] - 5, gy0 - 3, 10, 3, DARK, DARK)
        sk.line((P(x, 0)[0], gy0 + 8), (P(x, 0)[0], top_y - 12), 0.6, INK2, DASHDOT)
        sk.circle((P(x, 0)[0], top_y - 16), 2.4, BLACK, "white", 0.8)
    # overhang top chord + fascia
    ovL = (-o * math.cos(th), E + d0 - o * math.sin(th)); ovR = (B + o * math.cos(th), ovL[1])
    sk.line(P(*ovL), P(0, E + d0), 2.6, DARK); sk.line(P(B, E + d0), P(*ovR), 2.6, DARK)
    for p in (ovL, ovR): sk.line(P(*p), P(p[0], p[1] - 0.22), 2.4, DARK)
    # members
    for a, b in g["bot"]: sk.line(P(*a), P(*b), 2.4, DARK)
    for a, b in g["top"]: sk.line(P(*a), P(*b), 2.8, DARK)
    for a, b in g["verts"]: sk.line(P(*a), P(*b), 1.3, DARK)
    for a, b in g["diags"]: sk.line(P(*a), P(*b), 1.3, DARK)
    # gusset plates
    for (x, y) in g["nodes"]:
        cx, cy = P(x, y); r = 3.2
        sk.poly([(cx - r, cy - r * 0.6), (cx, cy - r), (cx + r, cy - r * 0.6), (cx + r, cy + r * 0.6), (cx, cy + r), (cx - r, cy + r * 0.6)], None, GUSSET)
    # purlins at top nodes + sheet
    off = 7 / k
    for side in (0, 1):
        for i in range(n + 1):
            x = g["xs"][i] if side == 0 else B - g["xs"][i]
            if side == 1 and i == n: continue
            y = g["topf"](x)
            cx, cy = P(x, y)
            ux, uy = (math.cos(th), -math.sin(th)) if side == 0 else (-math.cos(th), -math.sin(th))
            nx, ny = (-math.sin(th), -math.cos(th)) if side == 0 else (math.sin(th), -math.cos(th))
            if abs(x - h) < 1e-6:  # ridge: one each side
                for sgn in (-1, 1):
                    c0 = (cx + sgn * 5, cy - 3.5)
                    sk.rect(c0[0] - 3, c0[1] - 2.5, 6, 5, None, INK2)
                continue
            c0 = (cx + nx * 2.8, cy + ny * 2.8)
            pts = [(c0[0] - ux * 3.5, c0[1] - uy * 3.5), (c0[0] + ux * 3.5, c0[1] + uy * 3.5),
                   (c0[0] + ux * 3.5 + nx * 5, c0[1] + uy * 3.5 + ny * 5), (c0[0] - ux * 3.5 + nx * 5, c0[1] - uy * 3.5 + ny * 5)]
            sk.poly(pts, None, INK2)

    def sheet(t, side):
        x = t * math.cos(th) if side == 0 else B - t * math.cos(th)
        y = E + d0 + t * math.sin(th)
        nx, ny = (-math.sin(th), math.cos(th)) if side == 0 else (math.sin(th), math.cos(th))
        return P(x + nx * off * 1.35, y + ny * off * 1.35)
    sk.line(sheet(-o, 0), sheet(Ls, 0), 1.0, BLUE); sk.line(sheet(Ls, 1), sheet(-o, 1), 1.0, BLUE)

    # dimensions
    yb = gy0 + 26
    p = h / n
    dim_h(sk, P(0, 0)[0], P(h, 0)[0], yb, f"{n} @ {fmt(p)} = {fmt(h)}", ticks=[P(i * p, 0)[0] for i in range(n + 1)])
    dim_h(sk, P(h, 0)[0], P(B, 0)[0], yb, f"{n} @ {fmt(p)} = {fmt(h)}", ticks=[P(h + i * p, 0)[0] for i in range(n + 1)])
    dim_h(sk, P(0, 0)[0], P(B, 0)[0], yb + 20, f"ช่วงโครงถัก {fmt(B)}", 9, True)
    xr = P(xmax, 0)[0] + 22
    dim_v(sk, xr, P(0, E)[1], P(0, E + d0)[1], f"{fmt(d0)}", 1, 7.5)
    dim_v(sk, xr + 22, P(0, E + d0)[1], P(0, E + d0 + R)[1], f"R {fmt(R)}", 1)
    sk.line((xr + 28, P(h, E + d0 + R)[1]), (P(h, 0)[0] + 8, P(h, E + d0 + R)[1]), 0.5, INK2, [2, 2])
    sk.line((xr - 4, P(0, E)[1]), (P(B, 0)[0] + 4, P(0, E)[1]), 0.5, INK2, [2, 2])
    dim_v(sk, P(xmin, 0)[0] - 20, gy0, P(0, E)[1], f"สูงใต้ขื่อ {fmt(E)}", -1)
    sk.arc(P(0, E + d0), 40, 360 - 15, 360, 0.8); sk.text("15°", (P(0, 0)[0] + 44, P(0, E + d0)[1] - 7), 9, True)
    sk.text(f"ลึกกลางช่วง {fmt(d0 + R)} ม.", (P(h, 0)[0] - 6, P(0, E - 0.35)[1]), 8, False, INK2, "right")

    # tags
    t = lambda x, y: P(x, y)
    sk.tag(1, P(2.0, g["topf"](2.0) + 0.25), (P(2.0, 0)[0] - 28, P(0, g["topf"](2.0))[1] - 42))
    sk.tag(2, P(h * 1.45, g["topf"](h * 1.45)), (P(h * 1.45, 0)[0] + 30, P(0, g["topf"](h * 1.45))[1] - 34))
    sk.tag(3, P(p * 2.5, E), (P(p * 2.5, 0)[0] - 10, P(0, E - 0.9)[1]))
    sk.tag(4, P(p * 3, (E + g["topf"](p * 3)) / 2), (P(p * 3, 0)[0] + 2, P(0, E)[1] + 30))
    dmid = g["diags"][4]
    sk.tag(5, P((dmid[0][0] + dmid[1][0]) / 2, (dmid[0][1] + dmid[1][1]) / 2), (P(dmid[0][0], 0)[0] + 18, P(0, E)[1] + 30))
    sk.tag(6, P(*ovL), (P(*ovL)[0] - 22, P(*ovL)[1] + 24))
    sk.tag(7, P(h, E + (d0 + R) * 0.45), (P(h, 0)[0] + 26, P(0, E - 0.7)[1]))
    # detail callouts
    for lab, (x, y) in (("A", (0.0, E + d0 / 2)), ("B", (h, E + d0 + R - 0.1))):
        cx, cy = P(x, y)
        sk.circle((cx, cy), 20, RED, None, 0.9)
        sk.circle((cx + 18, cy - 18), 8, RED, "white", 0.9); sk.text(lab, (cx + 18, cy - 18), 9, True, RED, "center")

    # ---- details (not to scale), side by side
    dy0 = yb + 44
    bw, bh = (W - 28 - 12) / 2, 220
    for i, (lab, ttl) in enumerate((("A", "รายละเอียด A — จุดรองรับปลายโครงถัก / ชายคา"), ("B", "รายละเอียด B — สันหลังคา"))):
        bx = 14 + i * (bw + 12)
        sk.rect(bx, dy0, bw, bh, RULE, None, 0.6)
        sk.circle((bx + 14, dy0 + 14), 8, RED, "white", 0.9); sk.text(lab, (bx + 14, dy0 + 14), 9, True, RED, "center")
        sk.text(ttl, (bx + 28, dy0 + 14), 9, True)
        sk.text("ไม่ได้มาตราส่วน", (bx + bw - 8, dy0 + 14), 7.5, False, INK2, "right")
    detail_eave(sk, 14, dy0 + 26, bw, bh - 30, th)
    detail_ridge(sk, 14 + bw + 12, dy0 + 26, bw, bh - 30, th)

    # ---- member schedule with quantities (one truss)
    top_len = 2 * (Ls + o)
    bot_len = B
    vert_len = sum(seg_len(a, b) for a, b in g["verts"])
    diag_len = sum(seg_len(a, b) for a, b in g["diags"])
    rows = [
        (1, "แป", "C-100x50x20x3.2", f"@{fmt(s)} ม.", f"{2 * (n + 1)} ตัว/โครงถัก"),
        (2, "ขื่อบน (จันทัน)", "2C-150x50x20x3.2", "—", f"{fmt(top_len)} ม."),
        (3, "ขื่อล่าง", "2C-125x50x20x3.2", "—", f"{fmt(bot_len)} ม."),
        (4, "ตัวตั้ง", "C-100x50x20x2.3", f"{len(g['verts'])} ตัว", f"{fmt(vert_len)} ม."),
        (5, "ตัวทแยง", "C-100x50x20x2.3", f"{len(g['diags'])} ตัว", f"{fmt(diag_len)} ม."),
        (6, "เชิงชาย", 'ไม้ 1"x8"', "—", f"{fmt(2 * 1.0)} ม. (ต่อ 1 ม.)"),
        (7, "ดั้ง", "□-100x100x3.2", "1 ตัว", f"{fmt(d0 + R)} ม."),
    ]
    ty = dy0 + bh + 18
    cols = [14, 40, 170, 330, 440, 560]
    heads = ["#", "ชิ้นส่วน", "ขนาด", "ระยะ/จำนวน", "ความยาวรวม", ""]
    sk.rect(14, ty - 9, W - 28, 18, None, "#E2EFDA")
    for c, hd in zip(cols, heads): sk.text(hd, (c + 4, ty), 8.5, True)
    for r_i, (num, name, size, sp, tot) in enumerate(rows):
        yy = ty + 18 + r_i * 16
        sk.line((14, yy - 8), (W - 14, yy - 8), 0.4, RULE)
        sk.rect(cols[0] + 4, yy - 6, 12, 12, TAG, "white", 0.8); sk.text(str(num), (cols[0] + 10, yy), 8, True, TAG, "center")
        for c, v in zip(cols[1:5], (name, size, sp, tot)): sk.text(v, (c + 4, yy), 8.5)
    gus = len(g["nodes"])
    fy = ty + 18 + len(rows) * 16 + 6
    sk.text(f"แผ่นประกับ (gusset) {gus} จุด/โครงถัก · แผงละ {fmt(p)} ม. = ระยะแป → แปวางตรงจุดต่อทุกจุด · น้ำหนักเหล็กประมาณจากตารางหน้าตัด (v2)",
            (14, fy), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, fy + 16), 8, False, RED, "right")
    sk.render(fy + 28, path)


def rot(p, c, a):
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))


def rrect(sk, cx, cy, w, h, ang, fill=None, stroke=DARK, lw=1.0):
    pts = [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]
    sk.poly([rot(p, (cx, cy), ang) for p in pts], stroke, fill, lw)


def label(sk, text, at, to, align="left"):
    sk.line(at, to, 0.6, INK2)
    sk.circle(at, 1.6, None, INK2)
    sk.text(text, (to[0] + (4 if align == "left" else -4), to[1]), 7.8, False, DARK, align)


def detail_eave(sk, bx, by, bw, bh, th):
    a = -th
    col_x = bx + 110
    heel_y = by + 70          # top chord at the heel
    bc_y = by + 96            # bottom chord top edge
    run = 150                 # top chord run to the right of the heel
    ov = 60                   # overhang to the left
    tan = math.tan(th)
    p0 = (col_x - ov, heel_y + ov * tan)
    p1 = (col_x + run, heel_y - run * tan)
    # column + cap plate + anchors
    sk.rect(col_x - 9, bc_y + 14, 18, by + bh - (bc_y + 14), DARK, "#d9d9d9", 1.0)
    sk.rect(col_x - 16, bc_y + 9, 32, 5, DARK, DARK)
    for dx in (-10, 10): sk.line((col_x + dx, bc_y + 9), (col_x + dx, bc_y + 20), 1.2, DARK)
    # bottom chord
    sk.rect(col_x - 18, bc_y, run + 18, 9, DARK, "#cfcfcf", 1.0)
    # gusset (drawn before chords so the members sit on it)
    sk.poly([(col_x - 16, bc_y + 9), (col_x + 34, bc_y + 9), (col_x + 34, heel_y - 34 * tan - 2), (col_x - 16, heel_y + 16 * tan - 2)], DARK, "#b3b3b3", 0.8)
    # top chord
    mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 5)
    rrect(sk, mid[0], mid[1], math.hypot(p1[0] - p0[0], p1[1] - p0[1]), 9, a, "#cfcfcf")
    # heel vertical + first diagonal
    sk.rect(col_x - 3, heel_y + 9, 6, bc_y - heel_y - 9, DARK, "#e6e6e6", 0.8)
    d_to = (col_x + 70, heel_y - 70 * tan + 9)
    sk.line((col_x + 4, bc_y), d_to, 5, "#9a9a9a"); sk.line((col_x + 4, bc_y), d_to, 0.6, DARK)
    for dx, dy in ((-7, -6), (7, -6), (-7, -18), (7, -18), (22, -12)):
        sk.circle((col_x + dx, bc_y + dy), 1.8, DARK, "white", 0.6)
    # purlins + cleats
    for t in (8, 78, 146):
        px, py = col_x - ov + (t + ov * 0) * 1, 0
        x = col_x - ov + t * math.cos(th) * 1.0
        x = p0[0] + t * math.cos(th); y = p0[1] - t * math.sin(th)
        nx, ny = -math.sin(th), -math.cos(th)
        c = (x + nx * 10, y + ny * 10)
        rrect(sk, c[0], c[1], 8, 11, a, "white", DARK, 1.0)
        rrect(sk, c[0] + math.cos(th) * 6, c[1] - math.sin(th) * 6 + 2, 3, 9, a, DARK, DARK, 0.5)
    # sheet + fascia
    s0 = (p0[0] - math.sin(th) * 17 - 4, p0[1] - math.cos(th) * 17 + 1)
    s1 = (p1[0] - math.sin(th) * 17, p1[1] - math.cos(th) * 17)
    sk.line(s0, s1, 1.6, BLUE)
    sk.rect(p0[0] - 5, p0[1] - 12, 5, 24, DARK, "#e8dcc6", 0.8)
    # labels: right column below the chord, left column for fascia
    lx, ly = bx + bw - 150, by + 112
    t = lambda frac: (p0[0] + frac * (p1[0] - p0[0]), p0[1] + frac * (p1[1] - p0[1]))
    label(sk, "แผ่นหลังคาเมทัลชีท", (s1[0] - 6, s1[1] + 1), (bx + bw - 118, by + 10))
    label(sk, "แป C-100x50 + เหล็กฉากยึด", (p0[0] + 146 * math.cos(th) + 6, p0[1] - 146 * math.sin(th) - 14), (bx + bw - 118, by + 30))
    label(sk, "ขื่อบน 2C-150x50", t(0.86), (bx + bw - 118, by + 52))
    label(sk, "แผ่นประกับ 6 มม. + สลัก", (col_x + 26, bc_y - 8), (lx, ly))
    label(sk, "ขื่อล่าง 2C-125x50", (col_x + 110, bc_y + 5), (lx, ly + 18))
    label(sk, "แผ่นรองหัวเสา + พุก", (col_x + 14, bc_y + 12), (lx, ly + 36))
    label(sk, "เสา", (col_x + 6, by + bh - 12), (lx, ly + 54))
    label(sk, 'เชิงชาย ไม้ 1"x8"', (p0[0] - 3, p0[1] + 8), (bx + 8, by + bh - 20))


def detail_ridge(sk, bx, by, bw, bh, th):
    cx, ry = bx + bw / 2 - 60, by + 34
    L = 120
    for side in (-1, 1):
        end = (cx + side * L * math.cos(th), ry + L * math.sin(th))
        mid = ((cx + end[0]) / 2, (ry + end[1]) / 2)
        rrect(sk, mid[0], mid[1] + 5, L, 9, side * th, "#cfcfcf")
        # purlin next to ridge each side
        t = 16
        px, py = cx + side * t * math.cos(th), ry + t * math.sin(th)
        rrect(sk, px, py - 8, 8, 12, side * th, "white", DARK, 1.0)
        # sheet
        sk.line((cx, ry - 16), (cx + side * (L + 10) * math.cos(th), ry - 16 + (L + 10) * math.sin(th)), 1.6, BLUE)
    # ridge cap
    sk.poly([(cx - 26, ry - 11), (cx, ry - 22), (cx + 26, ry - 11), (cx + 26, ry - 14), (cx, ry - 25), (cx - 26, ry - 14)], DARK, "#9fb7d0", 0.6)
    # king post + diagonals
    sk.rect(cx - 5, ry + 8, 10, bh - 52, DARK, "#e6e6e6", 0.8)
    for side in (-1, 1):
        sk.line((cx + side * 5, ry + bh - 48), (cx + side * 70, ry + 30), 5, "#9a9a9a")
        sk.line((cx + side * 5, ry + bh - 48), (cx + side * 70, ry + 30), 0.6, DARK)
    # gusset at ridge
    sk.poly([(cx - 22, ry + 2), (cx, ry - 6), (cx + 22, ry + 2), (cx + 14, ry + 30), (cx - 14, ry + 30)], DARK, "#b3b3b3", 0.8)
    for dx, dy in ((-8, 8), (8, 8), (0, 20)): sk.circle((cx + dx, ry + dy), 1.8, DARK, "white", 0.6)
    # bottom chord splice at centre
    by2 = ry + bh - 44
    sk.rect(cx - 90, by2, 180, 8, DARK, "#cfcfcf", 1.0)
    sk.rect(cx - 16, by2 - 6, 32, 20, DARK, "#b3b3b3", 0.8)
    for dx in (-9, 0, 9): sk.circle((cx + dx, by2 + 4), 1.6, DARK, "white", 0.6)
    lx = bx + bw - 104
    label(sk, "ครอบสันหลังคา", (cx + 18, ry - 20), (lx, by + 8), "left")
    label(sk, "แปคู่ริมสัน", (cx + 16, ry - 5), (lx, by + 28), "left")
    label(sk, "แผ่นประกับสัน + สลัก", (cx + 12, ry + 12), (lx, by + 48), "left")
    label(sk, "ดั้ง □-100x100x3.2", (cx + 5, ry + 60), (lx, by + 70), "left")
    label(sk, "ตัวทแยง C-100x50", (cx + 45, ry + 56), (lx, by + 90), "left")
    label(sk, "ต่อทาบขื่อล่าง", (cx + 16, by2 + 4), (lx, by + 114), "left")


for kind in ("howe", "pratt", "warren"):
    roof_truss(f"truss_{kind}.png", kind)
print("ok")
