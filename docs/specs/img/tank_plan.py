"""Clear-water tank roof plan (กปภ. style) generated from survey input: bays, tapped vents, hatches, ladders, pipes.

One function, driven by a config that holds only sizes, distances and tapped cells, the same shape as the Swift TankInput.
"""
import math
src = open("draw.py").read().split("# ---------------------------------------------------------------- roof section")[0]
exec(src)

SET_EDGE, SET_OPEN, M2_PER_KWP = 1.0, 0.5, 6.0     # assumptions (DrawingSettings)
GREEN = "#E2EFDA"


def span_edges(sp):
    e = [0.0]
    for a in sp: e.append(e[-1] + a)
    return e


def tank_plan(cfg, path, W=1000):
    BX, BY = cfg["bx"], cfg["by"]
    TW, TH = sum(BX), sum(BY)
    xs, ys = span_edges(BX), span_edges(BY)
    sk = Sk(W)
    title_strip(sk, cfg["title"], "หน่วย: ม. · มาตราส่วนโดยประมาณ")
    padL, padT, padR = 230, 110 + (50 if cfg.get("section_marks") else 0), 250
    k = min((W - padL - padR) / TW, 520 / TH)
    w, h = TW * k, TH * k
    ox, oy = padL + ((W - padL - padR) - w) / 2, padT
    P = lambda x, y: (ox + x * k, oy + y * k)

    V, HS = cfg.get("vent", 1.5), cfg.get("hatch", 1.2)
    vents = []
    for r, c in cfg["vents"]:
        cx, cy = (xs[c] + xs[c + 1]) / 2, (ys[r] + ys[r + 1]) / 2
        vents.append((cx - V / 2, cy - V / 2, V, V))

    def on_wall(edge, d, s, inset=0.15):
        return {"top": (d - s / 2, inset, s, s), "bottom": (d - s / 2, TH - s - inset, s, s),
                "left": (inset, d - s / 2, s, s), "right": (TW - s - inset, d - s / 2, s, s)}[edge]
    hatches = [on_wall(e, d, HS) for e, d in cfg["hatches"]]

    # usable area, 0.5 m raster
    step = 0.5; usable = 0.0
    nx, ny = int(TW / step), int(TH / step)
    keep = [[False] * nx for _ in range(ny)]
    for j in range(ny):
        for i in range(nx):
            x0, y0 = i * step, j * step
            if x0 < SET_EDGE or y0 < SET_EDGE or x0 + step > TW - SET_EDGE or y0 + step > TH - SET_EDGE: continue
            if any(x0 + step > bx - SET_OPEN and x0 < bx + bw + SET_OPEN and y0 + step > by - SET_OPEN and y0 < by + bh + SET_OPEN
                   for (bx, by, bw, bh) in vents + hatches):
                continue
            keep[j][i] = True; usable += step * step
    for j in range(ny):
        i = 0
        while i < nx:
            if keep[j][i]:
                i0 = i
                while i < nx and keep[j][i]: i += 1
                sk.rect(ox + i0 * step * k, oy + j * step * k, (i - i0) * step * k + 0.3, step * k + 0.3, None, GREEN)
            else: i += 1

    # wall + beam grid (beams as double dashed bands, 0.30 m wide)
    sk.rect(ox, oy, w, h, BLACK, None, 1.4); sk.rect(ox + 3, oy + 3, w - 6, h - 6, BLACK, None, 0.6)
    bw_ = cfg.get("beam", 0.30) / 2
    for x in xs[1:-1]:
        for dx_ in (-bw_, bw_): sk.line(P(x + dx_, 0), P(x + dx_, TH), 0.45, INK2, [4, 3])
    for y in ys[1:-1]:
        for dy_ in (-bw_, bw_): sk.line(P(0, y + dy_), P(TW, y + dy_), 0.45, INK2, [4, 3])

    # vents
    for (bx, by, bw, bh) in vents:
        x, y = P(bx, by); s = bw * k
        if cfg.get("vent_style", "box") == "box":
            sk.rect(x, y, s, s, BLACK, "white", 0.8)
            sk.rect(x + s * 0.18, y + s * 0.18, s * 0.64, s * 0.64, BLACK, None, 0.5)
            sk.circle((x + s / 2, y + s / 2), s * 0.2, BLACK, None, 0.5)
        else:  # cross (mushroom vent on a RC column head)
            c = (x + s / 2, y + s / 2); a, b = s * 0.5, s * 0.17
            sk.poly([(c[0] - b, c[1] - a), (c[0] + b, c[1] - a), (c[0] + b, c[1] - b), (c[0] + a, c[1] - b), (c[0] + a, c[1] + b),
                     (c[0] + b, c[1] + b), (c[0] + b, c[1] + a), (c[0] - b, c[1] + a), (c[0] - b, c[1] + b), (c[0] - a, c[1] + b),
                     (c[0] - a, c[1] - b), (c[0] - b, c[1] - b)], BLACK, "white", 0.8)
            for t in (-1, 1):
                sk.line((c[0] + t * a, c[1] - b * 1.6), (c[0] + t * a, c[1] + b * 1.6), 1.2, BLACK)
                sk.line((c[0] - b * 1.6, c[1] + t * a), (c[0] + b * 1.6, c[1] + t * a), 1.2, BLACK)
            sk.circle(c, s * 0.12, BLACK, None, 0.5)
    for (bx, by, bw, bh) in hatches:
        x, y = P(bx, by); sk.rect(x, y, bw * k, bh * k, BLACK, "white", 0.9)
        sk.hatch(x + 1, y + 1, bw * k - 2, bh * k - 2, FAINT, 4)

    # ladders: own positions on the wall (not tied to hatches)
    for edge, d in cfg["ladders"]:
        if edge in ("top", "bottom"):
            x, y = P(d, 0 if edge == "top" else TH); o = -12 if edge == "top" else 4
            sk.rect(x - 3, y + o, 6, 8, BLACK, "white", 0.8)
        else:
            x, y = P(0 if edge == "left" else TW, d); o = -12 if edge == "left" else 4
            sk.rect(x + o, y - 3, 8, 6, BLACK, "white", 0.8)
    for edge, d, lab in cfg.get("pipes", []):
        x, y = P(0 if edge == "left" else TW, d); sgn = -1 if edge == "left" else 1
        sk.rect(min(x, x + sgn * 26), y - 4, 26, 8, BLACK, "white", 0.8)
        sk.rect(x + sgn * 10 - 2, y - 5, 4, 10, BLACK, INK2, 0.5)
        sk.circle((x + sgn * 26, y), 4, BLACK, "white", 0.8)

    # labels on the right, one leader per vent row / hatch / ladder (like the sheet)
    lx = ox + w + 36
    rows = sorted({r for r, _ in cfg["vents"]})
    for r in rows:
        yy = (ys[r] + ys[r + 1]) / 2
        first = min(c for rr, c in cfg["vents"] if rr == r)
        sk.line(P((xs[first] + xs[first + 1]) / 2, yy), (lx - 2, P(0, yy)[1]), 0.45, BLACK)
        sk.text("ช่องระบายอากาศ", (lx, P(0, yy)[1]), 7.5)
    for (edge, d), (bx, by, bw, bh) in zip(cfg["hatches"], hatches):
        cy = P(0, by + bh / 2)[1]
        if edge == "left":
            sk.line((P(bx, 0)[0], cy), (ox - 36, cy), 0.45, BLACK); sk.text("ช่องลงถัง", (ox - 38, cy), 7.5, False, BLACK, "right")
        elif edge == "right":
            sk.line((P(bx + bw, 0)[0], cy), (lx - 2, cy), 0.45, BLACK); sk.text("ช่องลงถัง", (lx, cy), 7.5)
        elif edge == "top":
            sk.line((P(bx + bw, 0)[0], P(0, by + 0.3)[1]), (lx - 2, P(0, by + 0.3)[1]), 0.45, BLACK); sk.text("ช่องลงถัง", (lx, P(0, by + 0.3)[1]), 7.5)
        else:
            sk.line((P(bx + bw, 0)[0], P(0, by + bh - 0.3)[1]), (lx - 2, P(0, by + bh - 0.3)[1]), 0.45, BLACK); sk.text("ช่องลงถัง", (lx, P(0, by + bh - 0.3)[1]), 7.5)
    for edge, d in cfg["ladders"]:
        if edge == "left":
            y = P(0, d)[1]; sk.line((ox - 12, y), (ox - 36, y), 0.45, BLACK); sk.text(cfg.get("ladder_label", "บันไดขึ้นถัง"), (ox - 38, y), 7.5, False, BLACK, "right")
        elif edge == "right":
            y = P(0, d)[1]; sk.line((ox + w + 12, y), (lx - 2, y), 0.45, BLACK); sk.text(cfg.get("ladder_label", "บันไดขึ้นถัง"), (lx, y), 7.5)
    for edge, d, lab in cfg.get("pipes", []):
        x, y = P(0 if edge == "left" else TW, d)
        if edge == "left": sk.text(lab, (x - 32, y - 12), 7.2, False, BLACK, "right")
        else: sk.text(lab, (x + 34, y), 7.2)
    # section marks
    for mark in cfg.get("section_marks", []):
        n, axis, pos = mark
        if axis == "x":   # cut line at x = pos, bubbles top/bottom
            for yb, up in ((oy - 32, True), (oy + h + 32, False)):
                cx = P(pos, 0)[0]
                sk.poly([(cx - 22, yb - 9), (cx - 10, yb - 9), (cx - 16, yb - 19)], BLACK, BLACK, 0.8)   # view arrow
                sk.circle((cx - 16, yb), 10, BLACK, "white", 0.9); sk.text(str(n), (cx - 16, yb), 9, True, BLACK, "center")
                sk.line((cx, yb), (cx, oy - 6 if up else oy + h + 6), 1.0, BLACK)
                sk.line((cx - 6, yb), (cx, yb), 1.0, BLACK)
        else:             # cut line at y = pos, bubbles left/right
            for xb in (ox - 60, ox + w + 60):
                cy = P(0, pos)[1]
                sk.poly([(xb - 6, cy - 25), (xb + 6, cy - 25), (xb, cy - 35)], BLACK, BLACK, 0.8)       # view arrow
                sk.circle((xb, cy - 16), 10, BLACK, "white", 0.9); sk.text(str(n), (xb, cy - 16), 9, True, BLACK, "center")
                sk.line((xb, cy), (ox - 6 if xb < ox else ox + w + 6, cy), 1.0, BLACK)
                sk.line((xb, cy - 6), (xb, cy), 1.0, BLACK)

    # dimensions
    dy = oy - 26 - (50 if cfg.get("section_marks") else 0)
    sk.line((ox, dy), (ox + w, dy), 0.6)
    for x in xs: sk.line((ox + x * k - 2, dy + 2), (ox + x * k + 2, dy - 2), 0.8)
    for i, a_ in enumerate(BX): sk.text(f"{a_:.2f}", (ox + (xs[i] + a_ / 2) * k, dy - 7), 7, False, BLACK, "center")
    sk.line((ox, dy - 18), (ox + w, dy - 18), 0.6)
    sk.text(f"{TW:.2f}", (ox + w / 2, dy - 25), 8.5, True, BLACK, "center")
    dx = ox - 150
    sk.line((dx, oy), (dx, oy + h), 0.6)
    for y in ys: sk.line((dx - 2, oy + y * k + 2), (dx + 2, oy + y * k - 2), 0.8)
    for i, a_ in enumerate(BY): sk.text(f"{a_:.2f}", (dx - 6, oy + (ys[i] + a_ / 2) * k), 7, False, BLACK, "right")
    sk.line((dx - 44, oy), (dx - 44, oy + h), 0.6)
    sk.text(f"{TH:.2f}", (dx - 50, oy + h / 2), 8.5, True, BLACK, "right")

    # legend + summary
    ly = oy + h + (70 if cfg.get("section_marks") else 24)
    cx = ox
    for kind, lab in (("vent", "ช่องระบายอากาศ"), ("hatch", "ช่องลงถัง"), ("ladder", cfg.get("ladder_label", "บันไดขึ้นถัง")), ("green", "พื้นที่ติดตั้งแผงได้ (ประมาณ)")):
        if kind == "vent":
            if cfg.get("vent_style", "box") == "box":
                sk.rect(cx, ly - 6, 12, 12, BLACK, "white", 0.8); sk.circle((cx + 6, ly), 2.5, BLACK, None, 0.5)
            else:
                sk.line((cx, ly), (cx + 12, ly), 3, BLACK); sk.line((cx + 6, ly - 6), (cx + 6, ly + 6), 3, BLACK)
        elif kind == "hatch": sk.rect(cx, ly - 6, 12, 12, BLACK, "white", 0.9)
        elif kind == "ladder": sk.rect(cx + 3, ly - 4, 6, 8, BLACK, "white", 0.8)
        else: sk.rect(cx, ly - 6, 16, 12, None, GREEN)
        sk.text(lab, (cx + 20, ly), 8.5); cx += 36 + len(lab) * 6.2
    sy = ly + 22
    sk.rect(14, sy, W - 28, 30, RULE, GREEN, 0.6)
    sk.text(f"ขนาด {fmt(TW)} × {fmt(TH)} ม. · หลังคาถัง {fmt(TW*TH)} ม² · ช่องระบายอากาศ {len(vents)} · ช่องลงถัง {len(hatches)} · "
            f"พื้นที่ติดตั้งได้ประมาณ {usable:,.0f} ม² (ราว {usable/M2_PER_KWP:,.0f} kWp)", (W / 2, sy + 15), 9.5, True, BLACK, "center")
    sk.text(f"ค่าสมมติ: เว้นระยะจากขอบถัง {fmt(SET_EDGE)} ม. และรอบช่องเปิด {fmt(SET_OPEN)} ม. · {fmt(M2_PER_KWP)} ม²/kWp",
            (14, sy + 44), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, sy + 44), 8, False, RED, "right")
    sk.render(sy + 58, path)
    return usable


# ---- the two กปภ. sheets, as the surveyor would enter them ----------------------------------
TANK_64x40 = dict(
    title="แปลนฝาถังน้ำใส — D1.1 ถังน้ำใส 1", bx=[4.0] * 16, by=[4.0] * 10, vent_style="box",
    vents=[(r, c) for r in (0, 3, 6, 9) for c in (0, 4, 8, 12, 15)],
    hatches=[("top", 14.3), ("top", 46.0), ("bottom", 14.1), ("bottom", 45.7), ("left", 18.0), ("left", 22.0), ("right", 18.2), ("right", 22.2)],
    ladders=[("top", 14.3), ("top", 46.0), ("bottom", 14.1), ("bottom", 45.7), ("left", 22.0), ("right", 22.2)],
    pipes=[("left", 14.0, "ท่อเชื่อมถังน้ำใส Ø600 มม."), ("left", 26.0, "ท่อเชื่อมถังน้ำใส Ø600 มม."),
           ("right", 14.0, "ท่อน้ำใส Ø700 มม."), ("right", 26.0, "ท่อน้ำใส Ø700 มม."),
           ("right", 17.0, "ท่อน้ำล้น Ø500 มม. ปลายท่อปิดตะแกรงกันแมลง"), ("right", 23.0, "ท่อน้ำล้น Ø500 มม. ปลายท่อปิดตะแกรงกันแมลง")],
)
TANK_40x40 = dict(
    title="แปลนพื้น เสา ค.ส.ล. ที่ฝาถัง — D1.2 ถังน้ำใส 2", bx=[4.0] * 10, by=[4.0] * 10, vent_style="cross",
    vents=[(r, c) for r in (0, 4, 9) for c in (0, 4, 5, 9)],
    hatches=[("top", 10.2), ("top", 29.6), ("bottom", 10.2), ("bottom", 29.6), ("left", 21.7), ("right", 21.7)],
    ladders=[("left", 6.4), ("left", 33.4), ("right", 33.4)],
    section_marks=[(1, "x", 19.0), (2, "y", 14.0)],
)

if __name__ == "__main__":
    print("64x40 usable", tank_plan(TANK_64x40, "tank_pwa.png"))
    print("40x40 usable", tank_plan(TANK_40x40, "tank_40x40.png"))
