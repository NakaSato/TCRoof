"""Clear-water tank roof plan in the style of the PWA drawing: bay grid, vents, hatches, railing, level, PV-usable area."""
import math
src = open("draw.py").read().split("# ---------------------------------------------------------------- roof section")[0]
exec(src)

# ---- survey input (sizes & distances only) -------------------------------------------------
BX, BY = [4.0] * 16, [4.0] * 10            # bay grid (m) — 16 @ 4.00 = 64.00, 10 @ 4.00 = 40.00
TOP_LEVEL = None                            # ระดับฝาถัง (not on this sheet)
DIVIDE_Y = None                             # no dividing wall on this tank
VENT = 1.5                                  # ช่องระบายอากาศ (ม.)
VENT_ROWS, VENT_COLS = [0, 3, 6, 9], [0, 4, 8, 12, 15]   # tapped cells (row, col)
HATCH = 1.2                                 # ช่องลงถัง (ม.) — each with a ladder บันไดลงถัง
HATCH_EDGE = [("top", 14.3), ("top", 46.0), ("bottom", 14.1), ("bottom", 45.7), ("left", 18.0), ("left", 22.0), ("right", 18.2), ("right", 22.2)]
HATCH_BIG = None
RAIL_EDGE = None
PIPES = [("left", 14.0, "ท่อเชื่อมถังน้ำใส Ø600 มม."), ("left", 26.0, "ท่อเชื่อมถังน้ำใส Ø600 มม."),
         ("right", 14.0, "ท่อน้ำใส Ø700 มม."), ("right", 26.0, "ท่อน้ำใส Ø700 มม."),
         ("right", 17.0, "ท่อน้ำล้น Ø500 มม. ปลายท่อปิดตะแกรงกันแมลง"), ("right", 23.0, "ท่อน้ำล้น Ø500 มม. ปลายท่อปิดตะแกรงกันแมลง")]
SET_EDGE, SET_OPEN = 1.0, 0.5               # ค่าสมมติ: ระยะเว้นขอบ / รอบช่องเปิด
M2_PER_KWP = 6.0                            # same constant as TCRoof survey form


def tank_plan(path):
    TW, TH = sum(BX), sum(BY)
    W = 1000; sk = Sk(W)
    title_strip(sk, "แปลนฝาถังน้ำใส — D1.1 ถังน้ำใส 1", "หน่วย: ม. · มาตราส่วนโดยประมาณ")
    padL, padT, padR = 230, 110, 250
    k = min((W - padL - padR) / TW, 520 / TH)
    w, h = TW * k, TH * k
    ox, oy = padL + ((W - padL - padR) - w) / 2, padT
    P = lambda x, y: (ox + x * k, oy + y * k)

    # usable area (drawn first, under everything)
    blocks = []
    for r in VENT_ROWS:
        for c in VENT_COLS:
            cx, cy = sum(BX[:c]) + BX[c] / 2, sum(BY[:r]) + BY[r] / 2
            blocks.append((cx - VENT / 2, cy - VENT / 2, VENT, VENT))
    hatches = []
    for edge, d in HATCH_EDGE:
        s = HATCH
        if edge == "top": hatches.append((d - s / 2, 0.15, s, s))
        if edge == "bottom": hatches.append((d - s / 2, TH - s - 0.15, s, s))
        if edge == "left": hatches.append((0.15, d - s / 2, s, s))
        if edge == "right": hatches.append((TW - s - 0.15, d - s / 2, s, s))
    if HATCH_BIG: hatches.append(HATCH_BIG)
    # grid cells 0.5 m to estimate usable area
    step = 0.5; usable = 0.0
    nx, ny = int(TW / step), int(TH / step)
    keep = [[False] * nx for _ in range(ny)]
    for j in range(ny):
        for i in range(nx):
            x0, y0 = i * step, j * step
            if x0 < SET_EDGE or y0 < SET_EDGE or x0 + step > TW - SET_EDGE or y0 + step > TH - SET_EDGE:
                continue
            if DIVIDE_Y is not None and abs((y0 + step / 2) - DIVIDE_Y) < 0.5: continue
            bad = False
            for (bx, by, bw, bh) in blocks + hatches:
                if x0 + step > bx - SET_OPEN and x0 < bx + bw + SET_OPEN and y0 + step > by - SET_OPEN and y0 < by + bh + SET_OPEN:
                    bad = True; break
            if not bad:
                keep[j][i] = True; usable += step * step
    GREEN = "#E2EFDA"
    for j in range(ny):
        i = 0
        while i < nx:
            if keep[j][i]:
                i0 = i
                while i < nx and keep[j][i]: i += 1
                sk.rect(ox + i0 * step * k, oy + j * step * k, (i - i0) * step * k + 0.3, step * k + 0.3, None, GREEN)
            else:
                i += 1

    # outline: double line wall
    sk.rect(ox, oy, w, h, BLACK, None, 1.4)
    sk.rect(ox + 3, oy + 3, w - 6, h - 6, BLACK, None, 0.6)
    # bay grid dashed (beams)
    xs = [0.0]
    for a in BX: xs.append(xs[-1] + a)
    ys = [0.0]
    for a in BY: ys.append(ys[-1] + a)
    for x in xs[1:-1]: sk.line(P(x, 0), P(x, TH), 0.5, INK2, [5, 3])
    for y in ys[1:-1]: sk.line(P(0, y), P(TW, y), 0.5, INK2, [5, 3])
    # divide line (dash-dot) with double wall
    if DIVIDE_Y is not None:
        sk.line((ox - 14, P(0, DIVIDE_Y)[1]), (ox + w + 14, P(0, DIVIDE_Y)[1]), 1.0, BLACK, DASHDOT)
    # vents: square + inner square + circle
    for (bx, by, bw, bh) in blocks:
        x, y = P(bx, by)
        sk.rect(x, y, bw * k, bh * k, BLACK, "white", 0.8)
        sk.rect(x + bw * k * 0.18, y + bh * k * 0.18, bw * k * 0.64, bh * k * 0.64, BLACK, None, 0.5)
        sk.circle((x + bw * k / 2, y + bh * k / 2), bw * k * 0.2, BLACK, None, 0.5)
    # hatches: plain square
    for (bx, by, bw, bh) in hatches:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, BLACK, "white", 0.9)
    # ladders outside each hatch + pipes through the wall
    for edge, d in HATCH_EDGE:
        if edge in ("top", "bottom"):
            x, y = P(d, 0 if edge == "top" else TH); o = -12 if edge == "top" else 4
            sk.rect(x - 3, y + o, 6, 8, BLACK, "white", 0.8)
        else:
            x, y = P(0 if edge == "left" else TW, d); o = -12 if edge == "left" else 4
            sk.rect(x + o, y - 3, 8, 6, BLACK, "white", 0.8)
    for edge, d, lab in PIPES:
        x, y = P(0 if edge == "left" else TW, d); sgn = -1 if edge == "left" else 1
        sk.rect(min(x, x + sgn * 26), y - 4, 26, 8, BLACK, "white", 0.8)
        sk.rect(x + sgn * 10 - 2, y - 5, 4, 10, BLACK, INK2, 0.5)
        sk.circle((x + sgn * 26, y), 4, BLACK, "white", 0.8)
    # labels (like the drawing)
    def callout(text, at, to):
        sk.line(at, (to[0] - 2, at[1]) if False else to, 0.5, BLACK)
        sk.text(text, (to[0] + 3, to[1]), 7.5)
    b0 = blocks[0]
    sk.line(P(b0[0] + b0[2] / 2, b0[1] + b0[3]), P(b0[0] + b0[2] / 2, 3.0), 0.5, BLACK)
    sk.line(P(b0[0] + b0[2] / 2, 3.0), (ox + w + 34, P(0, 3.0)[1]), 0.5, BLACK)
    sk.text("ช่องระบายอากาศ", (ox + w + 36, P(0, 3.0)[1]), 7.5)
    hx, hy = P(14.4, 0); sk.line((hx + 8, hy - 8), (hx + 30, hy - 22), 0.5, BLACK); sk.text("ช่องลงถัง + บันไดลงถัง", (hx + 32, hy - 22), 7.5)
    for edge, d, lab in PIPES:
        x, y = P(0 if edge == "left" else TW, d)
        if edge == "left": sk.text(lab, (x - 32, y - 12), 7.2, False, BLACK, "right")
        else: sk.text(lab, (x + 34, y), 7.2)
    # dimensions: bays + total
    dy = oy - 26
    sk.line((ox, dy), (ox + w, dy), 0.6)
    for x in xs: sk.line((ox + x * k - 2, dy + 2), (ox + x * k + 2, dy - 2), 0.8)
    for i, a_ in enumerate(BX): sk.text(f"{a_:.2f}", (ox + (xs[i] + a_ / 2) * k, dy - 7), 7, False, BLACK, "center")
    sk.line((ox, dy - 18), (ox + w, dy - 18), 0.6)
    sk.text(f"{fmt(TW)}.00", (ox + w / 2, dy - 25), 8.5, True, BLACK, "center")
    dx = ox - 150
    sk.line((dx, oy), (dx, oy + h), 0.6)
    for y in ys: sk.line((dx - 2, oy + y * k + 2), (dx + 2, oy + y * k - 2), 0.8)
    for i, a_ in enumerate(BY): sk.text(f"{a_:.2f}", (dx - 8, oy + (ys[i] + a_ / 2) * k), 7, False, BLACK, "center", -90)
    sk.line((dx - 20, oy), (dx - 20, oy + h), 0.6)
    sk.text(f"{fmt(TH)}.00", (dx - 28, oy + h / 2), 8.5, True, BLACK, "center", -90)
    # legend + summary
    ly = oy + h + 24
    items = [("vent", "ช่องระบายอากาศ"), ("hatch", "ช่องลงถัง"), ("green", "พื้นที่ติดตั้งแผงได้ (ประมาณ)")]
    cx = ox
    for kind, lab in items:
        if kind == "vent":
            sk.rect(cx, ly - 6, 12, 12, BLACK, "white", 0.8); sk.circle((cx + 6, ly), 2.5, BLACK, None, 0.5)
        elif kind == "hatch":
            sk.rect(cx, ly - 6, 12, 12, BLACK, "white", 0.9)
        elif kind == "rail":
            sk.line((cx, ly), (cx + 14, ly), 2.2, DARK)
        else:
            sk.rect(cx, ly - 6, 16, 12, None, GREEN)
        sk.text(lab, (cx + 20, ly), 8.5); cx += 30 + ApproxText.width(lab, 8.5) if 'ApproxText' in globals() else 30 + len(lab) * 5.2
    nv, nh = len(blocks), len(hatches)
    sy = ly + 22
    sk.rect(14, sy, W - 28, 30, RULE, GREEN, 0.6)
    sk.text(f"ขนาด {fmt(TW)} × {fmt(TH)} ม. · หลังคาถัง {fmt(TW*TH)} ม² · ช่องระบายอากาศ {nv} · ช่องลงถัง {nh} · "
            f"พื้นที่ติดตั้งได้ประมาณ {usable:,.0f} ม² (ราว {usable/M2_PER_KWP:,.0f} kWp)", (W / 2, sy + 15), 9.5, True, BLACK, "center")
    sk.text(f"ค่าสมมติ: เว้นระยะจากขอบถัง {fmt(SET_EDGE)} ม. และรอบช่องเปิด {fmt(SET_OPEN)} ม. · {fmt(M2_PER_KWP)} ม²/kWp",
            (14, sy + 44), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, sy + 44), 8, False, RED, "right")
    sk.render(sy + 58, path)


tank_plan("tank_pwa.png")
print("ok")
