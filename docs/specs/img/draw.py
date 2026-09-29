"""Prototype of the auto-drawing spec: builds DrawOp-like lists (points, y-down) and renders with matplotlib."""
import math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import Polygon, Rectangle, Circle, Arc

for f in ("Sarabun-Regular.ttf", "Sarabun-Bold.ttf"):
    font_manager.fontManager.addfont(f"../../../SolarSurveyKit/Sources/PDFReport/Resources/{f}")
plt.rcParams["font.family"] = "Sarabun"

DARK, BLACK, INK2, RED, FAINT, TAG, RULE, BLUE = "#333333", "#000000", "#555555", "#E0433A", "#999999", "#C00000", "#9a9a9a", "#1F4E79"
DASHDOT = [10, 3, 2, 3]


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s


class Sk:
    def __init__(self, W):
        self.W, self.ops = W, []

    def line(self, a, b, w=1, c=BLACK, dash=None):
        self.ops.append(("line", a, b, w, c, dash))

    def poly(self, pts, stroke=BLACK, fill=None, w=1):
        self.ops.append(("poly", pts, stroke, fill, w))

    def rect(self, x, y, w, h, stroke=BLACK, fill=None, lw=1):
        self.ops.append(("rect", x, y, w, h, stroke, fill, lw))

    def hatch(self, x, y, w, h, c=FAINT, sp=6):
        self.ops.append(("hatch", x, y, w, h, c, sp))

    def circle(self, c, r, stroke=BLACK, fill=None, w=1):
        self.ops.append(("circle", c, r, stroke, fill, w))

    def arc(self, c, r, a0, a1, w=0.8, col=BLACK):
        self.ops.append(("arc", c, r, a0, a1, w, col))

    def text(self, s, at, size=9, bold=False, color=BLACK, align="left", angle=0):
        self.ops.append(("text", s, at, size, bold, color, align, angle))

    def tag(self, n, at, lead):
        self.line(at, lead, 0.8, TAG)
        self.rect(lead[0] - 7, lead[1] - 7, 14, 14, TAG, "white", 1)
        self.text(str(n), lead, 10, True, TAG, "center")

    def render(self, H, path, scale=2.0):
        fig = plt.figure(figsize=(self.W / 72 * scale / 2, H / 72 * scale / 2), dpi=144)
        ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, self.W); ax.set_ylim(H, 0); ax.axis("off")
        ax.add_patch(Rectangle((0, 0), self.W, H, color="white"))
        pt = 72 / 72  # 1 drawing pt = 1 pt at figsize/72
        k = scale / 2
        for op in self.ops:
            t = op[0]
            if t == "line":
                _, a, b, w, c, d = op
                ln, = ax.plot([a[0], b[0]], [a[1], b[1]], color=c, lw=w * k, solid_capstyle="butt")
                if d: ln.set_dashes([x / max(w, 0.1) for x in d])
            elif t == "poly":
                _, pts, s, f, w = op
                ax.add_patch(Polygon(pts, closed=True, facecolor=f or "none", edgecolor=s or "none", lw=w * k))
            elif t == "rect":
                _, x, y, w, h, s, f, lw = op
                ax.add_patch(Rectangle((x, y), w, h, facecolor=f or "none", edgecolor=s or "none", lw=lw * k))
            elif t == "hatch":
                _, x, y, w, h, c, sp = op
                clip = Rectangle((x, y), w, h, transform=ax.transData)
                tt = -h
                while tt < w:
                    ln, = ax.plot([x + tt, x + tt + h], [y + h, y], color=c, lw=0.9 * k)
                    ln.set_clip_path(clip); tt += sp
            elif t == "circle":
                _, c, r, s, f, w = op
                ax.add_patch(Circle(c, r, facecolor=f or "none", edgecolor=s or "none", lw=w * k))
            elif t == "arc":
                _, c, r, a0, a1, w, col = op
                ax.add_patch(Arc(c, 2 * r, 2 * r, theta1=a0, theta2=a1, color=col, lw=w * k))
            elif t == "text":
                _, s, at, size, bold, col, al, ang = op
                ax.text(at[0], at[1], s, fontsize=size * k, fontweight="bold" if bold else "normal", color=col,
                        ha={"left": "left", "center": "center", "right": "right"}[al], va="center", rotation=-ang if ang else 0,
                        rotation_mode="anchor")
        fig.savefig(path, dpi=144); plt.close(fig)


def title_strip(sk, title, sub, y=16):
    sk.text(title, (14, y), 11, True)
    sk.text(sub, (sk.W - 14, y), 8.5, False, INK2, "right")
    sk.line((14, y + 12), (sk.W - 14, y + 12), 0.8, BLACK)


def dim_h(sk, x0, x1, y, label, size=8.5, bold=False, ticks=None):
    sk.line((x0, y), (x1, y), 0.6)
    for x in (ticks or [x0, x1]):
        sk.line((x - 3, y + 3), (x + 3, y - 3), 0.9)
    if label: sk.text(label, ((x0 + x1) / 2, y - 7), size, bold, BLACK, "center")


def dim_v(sk, x, y0, y1, label, side=-1, size=8.5):
    sk.line((x, y0), (x, y1), 0.6)
    for y in (y0, y1): sk.line((x - 3, y + 3), (x + 3, y - 3), 0.9)
    sk.text(label, (x + side * 8, (y0 + y1) / 2), size, False, BLACK, "center", -90)


# ---------------------------------------------------------------- roof section
MEMBERS = {
    1: ("แป", "C-100x50x20x3.2", 1.00),
    2: ("จันทัน", "2C-150x50x20x3.2", 4.00),
    3: ("อเส", "C-150x50x20x3.2", None),
    4: ("ขื่อ", "H-200x100x5.5x8", None),
    5: ("ค้ำยัน", "L-50x50x5", None),
    6: ("เชิงชาย", 'ไม้ 1"x8"', None),
    7: ("ดั้ง", "□-100x100x3.2", None),
}


def roof_section(path):
    across = [1.5, 4.5, 4, 4.5, 1.5]
    B, th, E, o, s = sum(across), math.radians(15), 4.0, 0.5, 1.0
    h = B / 2; R = h * math.tan(th); L = h / math.cos(th)
    W = 690
    sk = Sk(W)
    top, padL, padR = 70, 70, 70
    xmin, xmax = -o * math.cos(th), B + o * math.cos(th)
    k = (W - padL - padR) / (xmax - xmin)
    k = min(k, 300 / (E + R))
    gx = lambda x: padL + ((W - padL - padR) - (xmax - xmin) * k) / 2 + (x - xmin) * k
    gy0 = top + (E + R) * k  # ground
    gy = lambda y: gy0 - y * k
    P = lambda x, y: (gx(x), gy(y))
    title_strip(sk, "รูปตัดโครงหลังคา — C1.1 หลังคา · 1 โรงกรอง", "หน่วย: ม. · มาตราส่วนโดยประมาณ · ตัดตามแนวตั้งของแปลน")

    # ground
    sk.line(P(xmin - 0.6, 0), P(xmax + 0.6, 0), 1.2, DARK)
    sk.hatch(gx(xmin - 0.6), gy0, (xmax - xmin + 1.2) * k, 7, FAINT, 7)
    # grid + columns
    xs = [0.0]
    for a in across: xs.append(xs[-1] + a)
    roof_y = lambda x: E + (x if x <= h else B - x) * math.tan(th)
    for x in xs:
        sk.line((gx(x), gy(0) + 16), (gx(x), top - 8), 0.6, INK2, DASHDOT)
        sk.circle((gx(x), top - 12), 2.4, BLACK, "white", 0.8)
        # column to underside of tie beam (outer) / rafter (inner)
        ytop = E if x in (0.0, B) else E
        sk.line(P(x, 0), P(x, ytop), 1.6, DARK)
        sk.rect(gx(x) - 3, gy(0) - 3, 6, 3, DARK, DARK)
    # tie beam
    sk.line(P(0, E), P(B, E), 2.0, DARK)
    # rafters with overhang
    ov = (-o * math.cos(th), E - o * math.sin(th))
    ov2 = (B + o * math.cos(th), E - o * math.sin(th))
    sk.line(P(*ov), P(h, E + R), 2.6, DARK); sk.line(P(h, E + R), P(*ov2), 2.6, DARK)
    # king post, struts
    sk.line(P(h, E), P(h, E + R), 1.8, DARK)
    for xq in (h / 2, 1.5 * h):
        sk.line(P(h, E), P(xq, roof_y(xq)), 1.2, DARK)
    # wall plates, fascia
    for x in (0.0, B):
        sk.rect(gx(x) - 4, gy(E) - 3, 8, 6, DARK, DARK)
    for p in (ov, ov2):
        sk.line(P(p[0], p[1]), P(p[0], p[1] - 0.25), 2.2, DARK)
    # purlins + sheet line
    n = int(L // s) + 1
    ts = [i * s for i in range(n)]
    if L - ts[-1] > 0.25 * s: ts.append(L)
    for side in (0, 1):
        for t in ts:
            x = t * math.cos(th) if side == 0 else B - t * math.cos(th)
            y = E + t * math.sin(th)
            cx, cy = P(x, y)
            ang = -th if side == 0 else th
            # 7x5pt marker sitting on the rafter
            nx, ny = -math.sin(ang), -math.cos(ang)
            ux, uy = math.cos(ang), -math.sin(ang)
            ux, uy = (math.cos(th), -math.sin(th)) if side == 0 else (-math.cos(th), -math.sin(th))
            nx, ny = (-math.sin(th), -math.cos(th)) if side == 0 else (math.sin(th), -math.cos(th))
            c0 = (cx + nx * 1.5, cy + ny * 1.5)
            pts = [(c0[0] - ux * 3.5, c0[1] - uy * 3.5), (c0[0] + ux * 3.5, c0[1] + uy * 3.5),
                   (c0[0] + ux * 3.5 + nx * 5, c0[1] + uy * 3.5 + ny * 5), (c0[0] - ux * 3.5 + nx * 5, c0[1] - uy * 3.5 + ny * 5)]
            sk.poly(pts, None, INK2)
    off = 7 / k
    def sheet(t, side):
        x = t * math.cos(th) if side == 0 else B - t * math.cos(th)
        y = E + t * math.sin(th)
        nx, ny = (-math.sin(th), math.cos(th)) if side == 0 else (math.sin(th), math.cos(th))
        return P(x + nx * off, y + ny * off)
    sk.poly([sheet(-o, 0), sheet(L, 0), sheet(-o, 1), sheet(-o, 1)], None, None)
    sk.line(sheet(-o, 0), sheet(L, 0), 1.0, BLUE); sk.line(sheet(L, 1), sheet(-o, 1), 1.0, BLUE)

    # dimensions
    yb = gy(0) + 34
    for i, a in enumerate(across):
        dim_h(sk, gx(xs[i]), gx(xs[i + 1]), yb, fmt(a), ticks=[gx(xs[i]), gx(xs[i + 1])])
    dim_h(sk, gx(0), gx(B), yb + 20, fmt(B), 9, True)
    dim_v(sk, gx(xmin) - 26, gy(0), gy(E), f"สูงชายคา {fmt(E)}", -1)
    dim_v(sk, gx(xmax) + 26, gy(E), gy(E + R), f"R {fmt(R)}", 1)
    sk.line((gx(xmax) + 18, gy(E + R)), (gx(h) + 6, gy(E + R)), 0.5, INK2, [2, 2])
    # pitch arc
    sk.arc(P(0, E), 44, 360 - 15, 360, 0.8)
    sk.text("15°", (gx(0) + 50, gy(E) - 6), 9, True)
    # slope length
    mx, my = P(h * 0.62, E + h * 0.62 * math.tan(th))
    sk.text(f"L = {fmt(L)} ม.", (mx - 4, my - 22), 8.5, False, INK2, "center", -15)
    # tags
    sk.tag(1, sheet(3.0, 0), (gx(2.6) - 30, gy(roof_y(2.6)) - 40))
    sk.tag(2, P(h * 1.3, roof_y(h * 1.3)), (gx(h * 1.3) + 40, gy(roof_y(h * 1.3)) - 34))
    sk.tag(3, P(B, E), (gx(B) + 36, gy(E) + 26))
    sk.tag(4, P(B * 0.62, E), (gx(B * 0.62) + 10, gy(E) + 26))
    sk.tag(5, P(h * 0.75, E + (h * 0.75 - h / 2 * 0) * 0 + (roof_y(h / 2) - E) * 0.5), (gx(h * 0.6) - 10, gy(E) + 26))
    sk.tag(6, P(*ov), (gx(ov[0]) - 26, gy(ov[1]) + 22))
    sk.tag(7, P(h, E + R * 0.45), (gx(h) + 30, gy(E + R * 0.45) + 4))
    # legend
    ly = yb + 50
    sk.line((14, ly - 10), (W - 14, ly - 10), 0.5, RULE)
    colw = (W - 28) / 2
    for i, (n, (name, size, sp)) in enumerate(MEMBERS.items()):
        cx = 14 + (i % 2) * colw; cy = ly + (i // 2) * 16
        sk.rect(cx, cy - 6, 12, 12, TAG, "white", 0.8); sk.text(str(n), (cx + 6, cy), 8.5, True, TAG, "center")
        sk.text(f"{name}  {size}" + (f" @{fmt(sp)} ม." if sp else ""), (cx + 18, cy), 9)
    sk.text(f"แป {len(ts)} ตัว/ด้าน · ความยาวลาดหลังคา {fmt(L)} ม. · สูงสันหลังคาจากพื้น {fmt(E + R)} ม.", (14, ly + 70), 8.5, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ly + 70), 8, False, RED, "right")
    H = ly + 84
    sk.render(H, path)


# ---------------------------------------------------------------- framing plan
def framing_plan(path):
    sx, sy = [1.5, 4, 4, 4, 4, 1.5], [1.5, 4.5, 4, 4.5, 1.5]
    TW, TH = sum(sx), sum(sy); th = math.radians(15); s = 1.0
    W = 690; sk = Sk(W)
    title_strip(sk, "แปลนโครงหลังคา — C1.1 หลังคา · 1 โรงกรอง", "หน่วย: ม. · ทรงจั่ว · สันหลังคาแนวนอน")
    padL, padT, padR = 70, 104, 110
    k = min((W - padL - padR) / TW, 300 / TH); w, h = TW * k, TH * k
    ox = padL + ((W - padL - padR) - w) / 2; oy = padT
    xs = [0.0]
    for a in sx: xs.append(xs[-1] + a)
    ys = [0.0]
    for a in sy: ys.append(ys[-1] + a)
    for x in xs:
        X = ox + x * k; sk.line((X, oy - 18), (X, oy + h + 8), 0.6, INK2, DASHDOT); sk.circle((X, oy - 18), 2.4, BLACK, "white", 0.8)
    for y in ys:
        Y = oy + y * k; sk.line((ox - 18, Y), (ox + w + 8, Y), 0.6, INK2, DASHDOT); sk.circle((ox - 18, Y), 2.4, BLACK, "white", 0.8)
    # purlins parallel to ridge, projected spacing
    half = TH / 2; L = half / math.cos(th)
    t = 0.0
    while t <= L + 1e-9:
        d = t * math.cos(th)
        for yy in (d, TH - d):
            sk.line((ox, oy + yy * k), (ox + w, oy + yy * k), 0.7, INK2)
        t += s
    # rafters at grid lines (along slope = vertical in plan)
    for x in xs:
        sk.line((ox + x * k, oy), (ox + x * k, oy + h), 2.0, DARK)
    # ridge
    sk.line((ox - 10, oy + half * k), (ox + w + 10, oy + half * k), 1.6, BLACK, DASHDOT)
    sk.text("สันหลังคา", (ox + w + 12, oy + half * k), 8.5, True, BLACK)
    # columns
    for x in xs[1:-1]:
        for y in ys[1:-1]:
            sk.rect(ox + x * k - 3, oy + y * k - 3, 6, 6, BLACK, BLACK)
    sk.rect(ox, oy, w, h, BLACK, None, 1.3)
    # obstacle
    r = (ox + 12.5 * k, oy + 10.5 * k, 1.2 * k, 1.2 * k)
    sk.rect(*r, None, "white"); sk.hatch(*r, RED); sk.rect(*r, RED, None, 1)
    sk.text("ปล่องระบาย 1.2x1.2", (r[0] + r[2] + 3, r[1] + r[3] - 3), 8, False, DARK)
    # dims
    dy = oy - 34
    for i, a in enumerate(sx): dim_h(sk, ox + xs[i] * k, ox + xs[i + 1] * k, dy, fmt(a))
    dim_h(sk, ox, ox + w, dy - 18, fmt(TW), 9, True)
    dx = ox - 34
    for i, a in enumerate(sy):
        sk.line((dx, oy + ys[i] * k), (dx, oy + ys[i + 1] * k), 0.6)
        sk.text(fmt(a), (dx - 8, oy + (ys[i] + a / 2) * k), 8.5, False, BLACK, "center", -90)
    sk.text(fmt(TH), (dx - 24, oy + h / 2), 9, True, BLACK, "center", -90)
    ly = oy + h + 26
    sk.line((ox, ly), (ox + 26, ly), 2.0, DARK); sk.text("จันทัน 2C-150x50x20x3.2 @4.00 ม. (ตามแนวเสา)", (ox + 32, ly), 9)
    sk.line((ox, ly + 18), (ox + 26, ly + 18), 0.7, INK2); sk.text(f"แป C-100x50x20x3.2 @1.00 ม. (ระยะในแปลน {fmt(s*math.cos(th))} ม.)", (ox + 32, ly + 18), 9)
    sk.rect(ox + 8, ly + 33, 6, 6, BLACK, BLACK); sk.text("เสา", (ox + 32, ly + 36), 9)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ly + 36), 8, False, RED, "right")
    sk.render(ly + 50, path)


# ---------------------------------------------------------------- tank
def tank(path):
    Lx, Wy, Ht, cover = 12.0, 8.0, 4.5, 0.5
    W = 690; sk = Sk(W)
    title_strip(sk, "ถังน้ำใส 1 (ใหม่) — แปลนและรูปตัด", "หน่วย: ม. · ค.ส.ล. · ฝังดิน · มาตราส่วนโดยประมาณ")
    # plan (left)
    top = 70
    k = min(270 / Lx, 200 / Wy)
    ox, oy = 60, top + 14
    w, h = Lx * k, Wy * k
    sk.rect(ox, oy, w, h, BLACK, None, 1.3); sk.rect(ox + 3, oy + 3, w - 6, h - 6, BLACK, None, 0.8)
    for x in (0, 4, 8, 12): sk.line((ox + x * k, oy - 10), (ox + x * k, oy + h + 6), 0.6, INK2, DASHDOT)
    for y in (0, 4, 8): sk.line((ox - 10, oy + y * k), (ox + w + 6, oy + y * k), 0.6, INK2, DASHDOT)
    for (x, y, ww, hh, lab) in ((1.5, 1.5, 1.0, 1.0, "ช่องเซอร์วิส"), (9.5, 5.5, 0.6, 0.6, "ท่อระบายอากาศ")):
        r = (ox + x * k, oy + y * k, ww * k, hh * k)
        sk.rect(*r, None, "white"); sk.hatch(*r, RED); sk.rect(*r, RED, None, 1)
        sk.text(lab, (r[0] + r[2] + 3, r[1] + r[3] / 2), 8, False, DARK)
    dim_h(sk, ox, ox + w, oy - 22, fmt(Lx), 9, True)
    sk.line((ox - 22, oy), (ox - 22, oy + h), 0.6); sk.text(fmt(Wy), (ox - 30, oy + h / 2), 9, True, BLACK, "center", -90)
    sk.text("แปลนหลังคาถัง", (ox + w / 2, oy + h + 20), 9, True, BLACK, "center")
    # section (right)
    sx0 = 400; ks = min(200 / Lx, 150 / (Ht + cover + 0.6))
    gy0 = top + 22 + (cover + 0.4) * ks
    sw, sh = Lx * ks, Ht * ks
    ground = gy0
    # soil cover
    sk.rect(sx0 - 20, ground - cover * ks, sw + 40, cover * ks, None, "#EFE6D6")
    sk.hatch(sx0 - 20, ground - cover * ks, sw + 40, cover * ks, FAINT, 6)
    sk.line((sx0 - 30, ground - cover * ks), (sx0 + sw + 30, ground - cover * ks), 1.2, DARK)
    sk.text("▽ ระดับดิน", (sx0 - 20, ground - cover * ks - 10), 8, False, INK2)
    # tank body below
    sk.rect(sx0, ground, sw, sh, BLACK, "white", 1.4)
    sk.rect(sx0 + 4, ground + 4, sw - 8, sh - 8, INK2, None, 0.6)
    sk.hatch(sx0 - 20, ground, 20, sh + 10, FAINT, 6); sk.hatch(sx0 + sw, ground, 20, sh + 10, FAINT, 6)
    sk.hatch(sx0 - 20, ground + sh, sw + 40, 10, FAINT, 6)
    sk.line((sx0 + 6, ground + sh * 0.25), (sx0 + sw - 6, ground + sh * 0.25), 0.8, BLUE, [6, 3])
    sk.text("ระดับน้ำ (โดยประมาณ)", (sx0 + sw / 2, ground + sh * 0.25 + 9), 7.5, False, BLUE, "center")
    dim_h(sk, sx0, sx0 + sw, ground + sh + 26, fmt(Lx), 9, True)
    dim_v(sk, sx0 + sw + 34, ground, ground + sh, f"H {fmt(Ht)}", 1)
    dim_v(sk, sx0 - 36, ground - cover * ks, ground, f"ดินกลบ {fmt(cover)}", -1, 7.5)
    sk.text("รูปตัดถัง", (sx0 + sw / 2, ground + sh + 46), 9, True, BLACK, "center")
    # summary strip
    ys = max(oy + h + 40, ground + sh + 66)
    sk.rect(14, ys, W - 28, 30, RULE, "#E2EFDA", 0.6)
    sk.text(f"ขนาด {fmt(Lx)} × {fmt(Wy)} × {fmt(Ht)} ม.   ·   พื้นที่หลังคาถัง {fmt(Lx*Wy)} ม²   ·   ปริมาตรภายนอกโดยประมาณ {fmt(Lx*Wy*Ht)} ม³",
            (W / 2, ys + 15), 10, True, BLACK, "center")
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ys + 44), 8, False, RED, "right")
    sk.render(ys + 56, path)


roof_section("roof_section.png")
framing_plan("framing_plan.png")
tank("tank.png")
print("done")
