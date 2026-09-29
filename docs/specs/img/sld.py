"""Single line diagram in the style of a Thai MDP drawing, generated only from survey input.
Existing equipment in black; new PV equipment and export limiting (LV or HV) in blue.
Run from docs/specs/img/: writes sld_existing.png, sld_pv_lv.png, sld_pv_hv.png."""
import math, os
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "draw.py")).read().split("# ---------------------------------------------------------------- roof section")[0])

NEW = BLUE
STD_AT = [16, 20, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200]
FRAMES = [100, 160, 250, 400, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000]
V, K = 400.0, 1.25          # assumed: 400/230 V system, breaker = 1.25 x rated current

# ---- survey input (sample = the MDP sheet the user shared; transformer and PV sizes are sample values) ----
UP = dict(grid_kv="22", tr_name="TR1", tr_kva=250, meter_no="PEA 12-345678", pole="เสา 22 kV หน้าสถานี")
MDB = dict(
    name="MDP", ic_ka=25, main=(3, 300, 400), ct="300/5A", dp="DP2", pilot="3x6A",
    busbar="4x300A. Cu. BUSBAR W/GROUND BUS",
    feeders=[  # poles, AT, AF, cable, conduit, load, location  (load "SPARE" = spare breaker)
        (3, 100, 100, "4x50,1x10-IEC01", "IN WIRE WAY", "LC11", "1st FL."),
        (3, 100, 100, "4x50,1x10-IEC01", "ø50mm. UPVC", "LC12", "1st FL."),
        (3, 100, 100, "4x50,1x10-IEC01", "ø50mm. UPVC", "LC21", "2nd FL."),
        (3, 50, 100, "4x10,1x4-IEC01", "ø25mm. UPVC", "LC22", "2nd FL."),
        (3, 80, 100, "4x35,1x10-IEC01", "ø40mm. UPVC", "LC31", "3rd FL."),
        (3, 30, 100, "", "", "SPARE", ""),
    ],
    ground="1x35-IEC01 ø20 PVC.",
)
PV = dict(kwp=120, inverters=4, fts=True)       # A1 capacity, B2 inverter count, B5 FTS present


def at(i): return next(a for a in STD_AT if a >= i)
def af(a): return next(f for f in FRAMES if f >= a)


def cb(sk, x, y, label=None, lx=None, c=DARK):
    """Thai-drawing breaker: terminal dot, arc to the right, terminal dot (y = centre). Label 'nP AT/AF'."""
    sk.circle((x, y - 11), 2.2, c, "white", 0.9)
    sk.arc((x, y), 9, 270, 90, 1.3, c)
    sk.circle((x, y + 11), 2.2, c, "white", 0.9)
    if label:
        p, a, f = label
        lx = lx if lx is not None else x + 12
        sk.text(f"{p}P", (lx, y), 8.5, False, c)
        sk.text(f"{a}AT", (lx + 16, y - 6), 8.5, False, c)
        sk.line((lx + 15, y), (lx + 44, y), 0.6, c)
        sk.text(f"{f}AF", (lx + 16, y + 7), 8.5, False, c)


def ct(sk, x, y, c):
    for dy in (-5, 0, 5): sk.arc((x, y + dy), 5, 90, 270, 1.0, c)


def relay(sk, x, y, w, t1, t2):
    sk.rect(x, y, w, 34, NEW, "white", 1.2)
    sk.text(t1, (x + w / 2, y + 12), 8.5, True, NEW, "center"); sk.text(t2, (x + w / 2, y + 25), 7.5, False, NEW, "center")


def ctrl(sk, pts):
    for a, b in zip(pts, pts[1:]): sk.line(a, b, 0.9, NEW, [4, 3])


def sld(path, mode):
    """mode: 'none' (existing only) · 'lv' (PV + export limiting at LV) · 'hv' (PV + export limiting at HV)."""
    pv = mode != "none"
    W = 1240 if pv else 1000; sk = Sk(W)
    sub = {"none": "ระบบไฟฟ้าเดิม · ไม่มีระบบ PV", "lv": "ระบบเดิม + PV · กันย้อนแรงต่ำ", "hv": "ระบบเดิม + PV · กันย้อนแรงสูง"}[mode]
    title_strip(sk, f"แผนภาพเส้นเดียว — {MDB['name']}", f"สร้างจากแบบสำรวจ A1 · A3 · B2 · B4 · B5 · ตาราง MDB · {sub}")
    x0 = 470
    # ---------------- upstream (A3): grid → drop-out fuse → [HV CT/VT] → transformer → PEA meter
    sk.poly([(x0 - 9, 50), (x0 + 9, 50), (x0, 63)], DARK, None, 1.2)
    sk.text(f"ระบบจำหน่าย กฟภ. {UP['grid_kv']} kV", (x0 + 16, 54), 8.5, True)
    sk.line((x0, 63), (x0, 78), 1.4, DARK)
    sk.rect(x0 - 4, 78, 8, 16, DARK, "white", 1.1); sk.text("ดรอปเอาท์ฟิวส์", (x0 + 14, 86), 8)
    y = 94
    if mode == "hv":
        sk.line((x0, y), (x0, y + 40), 1.4, DARK)
        sk.circle((x0, y + 14), 6, NEW, None, 1.2)                           # HV CT
        sk.line((x0, y + 28), (x0 - 40, y + 28), 0.9, NEW)                   # VT branch
        sk.circle((x0 - 46, y + 28), 6, NEW, None, 1.1); sk.circle((x0 - 56, y + 28), 6, NEW, None, 1.1)
        sk.text("CT/VT แรงสูง (ใหม่)", (x0 + 14, y + 14), 8, False, NEW)
        relay(sk, 180, y + 4, 160, "รีเลย์กันย้อน แรงสูง", f"ติดตั้งที่{UP['pole']}")
        ctrl(sk, [(x0 - 6, y + 14), (340, y + 14)]); ctrl(sk, [(x0 - 62, y + 28), (340, y + 28)])
        y += 40
    sk.line((x0, y), (x0, y + 10), 1.4, DARK)
    sk.circle((x0, y + 22), 12, DARK, None, 1.3); sk.circle((x0, y + 40), 12, DARK, None, 1.3)
    sk.text(f"{UP['tr_name']} {UP['tr_kva']:,} kVA · {UP['grid_kv']} kV/400-230 V", (x0 + 20, y + 31), 8.5, True)
    sk.line((x0, y + 52), (x0, y + 64), 1.4, DARK)
    sk.circle((x0, y + 75), 11, DARK, "white", 1.2); sk.text("kWh", (x0, y + 75), 6.5, True, DARK, "center")
    sk.text(f"มิเตอร์ กฟภ. {UP['meter_no']}", (x0 + 18, y + 75), 8)
    B = y + 106                                                              # enclosure top
    sk.line((x0, y + 86), (x0, B), 2.2, DARK, [10, 3, 2, 3])
    # ---------------- MDB enclosure (dashed)
    bx0, bx1, by1 = 40, W - 100, B + 290
    for a, b in (((bx0, B), (bx1, B)), ((bx1, B), (bx1, by1)), ((bx1, by1), (bx0, by1)), ((bx0, by1), (bx0, B))):
        sk.line(a, b, 0.9, DARK, [14, 6])
    sk.text(MDB["name"], (bx0 + 8, B - 10), 11, True, DARK)
    sk.text(f"IC ไม่น้อยกว่า {MDB['ic_ka']} kA", (bx0 + 12, B + 16), 8.5)
    sk.line((x0, B), (x0, B + 32), 2.2, DARK, [10, 3, 2, 3]); sk.circle((x0, B + 32), 2.2, DARK, DARK)
    sk.line((x0, B + 32), (x0, B + 45), 1.6, DARK)
    cb(sk, x0, B + 56, MDB["main"])
    bus_y = B + 140 + (20 if mode == "lv" else 0)
    sk.line((x0, B + 67), (x0, bus_y), 1.6, DARK)
    if MDB["pilot"]:                                                         # fuse → pilot lamps; DP meter from CTs
        sk.line((x0, B + 32), (x0 + 110, B + 32), 0.9, DARK)
        sk.rect(x0 + 110, B + 26, 40, 12, DARK, "white", 0.9); sk.text(MDB["pilot"], (x0 + 130, B + 19), 8, False, DARK, "center")
        sk.line((x0 + 150, B + 32), (x0 + 250, B + 32), 0.9, DARK)
        sk.circle((x0 + 258, B + 32), 7, DARK, "white", 0.9)
        sk.line((x0 + 253, B + 27), (x0 + 263, B + 37), 0.8, DARK); sk.line((x0 + 263, B + 27), (x0 + 253, B + 37), 0.8, DARK)
        sk.text("x3", (x0 + 270, B + 32), 8.5)
    if MDB["dp"]:
        sk.line((x0 + 200, B + 32), (x0 + 200, B + 70), 0.9, DARK)
        sk.rect(x0 + 186, B + 70, 28, 18, DARK, "white", 0.9); sk.text("DP", (x0 + 200, B + 79), 8, True, DARK, "center")
        sk.text(MDB["dp"], (x0 + 220, B + 79), 8.5)
        sk.line((x0 + 200, B + 88), (x0 + 200, B + 102), 0.9, DARK); sk.line((x0 + 200, B + 102), (x0 + 12, B + 102), 0.9, DARK)
    if MDB["ct"]:
        ct(sk, x0, B + 102, DARK)
        sk.text("3xCT", (x0 - 14, B + 96), 8.5, False, DARK, "right"); sk.text(MDB["ct"], (x0 - 14, B + 108), 8.5, False, DARK, "right")
    # ---------------- feeders
    feeders = MDB["feeders"]; n = len(feeders); fx0, fx1 = 170, 800
    xs = [fx0 + i * (fx1 - fx0) / (n - 1) for i in range(n)]
    pvx = 990
    sk.line((xs[0], bus_y), (pvx if pv else xs[-1], bus_y), 3.2, DARK)
    sk.circle((x0, bus_y), 2.4, DARK, DARK)
    sk.text(MDB["busbar"], (fx0, bus_y - 26), 8.5, True)
    for i, (p, a, f, cable, conduit, load, loc) in enumerate(feeders):
        x = xs[i]
        sk.text(str(i + 1), (x, bus_y - 10), 8.5, False, DARK, "center"); sk.circle((x, bus_y), 2.4, DARK, DARK)
        sk.line((x, bus_y), (x, bus_y + 28), 1.2, DARK)
        cb(sk, x, bus_y + 40, (p, a, f))
        if load == "SPARE":
            sk.text("SPARE", (x, bus_y + 70), 8.5, False, DARK, "center"); continue
        sk.line((x, bus_y + 51), (x, B + 460), 1.2, DARK)
        sk.text(f"{cable}, {conduit}", (x - 8, B + 390), 8, False, DARK, "center", -90)
        sk.rect(x - 14, B + 460, 28, 14, None, DARK)
        sk.text(load, (x, B + 488), 8.5, True, DARK, "center"); sk.text(f"({loc})", (x, B + 501), 8, False, DARK, "center")
    # ---------------- N-G bar + ground rod
    gx, gy = 90, B + 200
    sk.rect(gx - 14, gy - 22, 30, 8, DARK, DARK); sk.text("N", (gx + 22, gy - 18), 8.5)
    sk.rect(gx - 14, gy + 4, 30, 8, DARK, DARK); sk.text("G", (gx + 22, gy + 8), 8.5)
    sk.line((gx - 10, gy - 14), (gx - 10, gy + 4), 1.0, DARK)
    sk.line((gx + 2, gy + 12), (gx + 2, B + 415), 1.2, DARK)
    for i, wdt in enumerate((18, 12, 6)):
        sk.line((gx + 2 - wdt / 2, B + 415 + i * 5), (gx + 2 + wdt / 2, B + 415 + i * 5), 1.2, DARK)
    sk.text(MDB["ground"], (gx - 6, B + 350), 8, False, DARK, "center", -90)
    sk.text("GROUND ROD", (gx + 2, B + 440), 8.5, False, DARK, "center")
    # ---------------- PV (new, blue)
    rows = []
    if pv:
        ni = PV["inverters"]; kw_inv = PV["kwp"] / ni
        i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = PV["kwp"] * 1000 / (math.sqrt(3) * V)
        a_inv, a_pv = at(i_inv * K), at(i_tot * K)
        sk.text(str(n + 1), (pvx, bus_y - 10), 8.5, False, NEW, "center"); sk.circle((pvx, bus_y), 2.4, NEW, NEW)
        sk.line((pvx, bus_y), (pvx, bus_y + 28), 1.2, NEW)
        cb(sk, pvx, bus_y + 40, (3, a_pv, af(a_pv)), lx=pvx - 66, c=NEW)
        sk.text("PV (ใหม่)", (pvx - 14, bus_y + 62), 8, True, NEW, "right")
        sb = B + 340                                                         # SMDB-PV bus
        sk.line((pvx, bus_y + 51), (pvx, sb), 1.2, NEW)
        ix = [pvx - 35 * (ni - 1) + 70 * k for k in range(ni)]
        sk.line((ix[0] - 20, sb), (ix[-1] + 20, sb), 3.0, NEW)
        sk.text("SMDB-PV (ใหม่)", (ix[-1] + 26, sb), 8.5, True, NEW)
        lx = ix[0] - 26
        for k, x in enumerate(ix):
            sk.line((x, sb), (x, sb + 18), 1.2, NEW)
            cb(sk, x, sb + 30, (3, a_inv, af(a_inv)) if k == ni - 1 else None, c=NEW)
            sk.line((x, sb + 41), (x, sb + 56), 1.2, NEW)
            sk.rect(x - 16, sb + 56, 32, 28, NEW, "white", 1.2); sk.line((x - 16, sb + 84), (x + 16, sb + 56), 0.7, NEW)
            sk.text("=", (x - 7, sb + 64), 9, True, NEW, "center"); sk.text("~", (x + 7, sb + 77), 10, True, NEW, "center")
            sk.line((x, sb + 84), (x, sb + 100), 1.2, NEW)
            if PV["fts"]:
                sk.circle((x, sb + 100), 1.8, NEW, "white", 0.8)
                sk.line((x, sb + 100), (x + 8, sb + 113), 1.3, NEW); sk.line((x, sb + 116), (x, sb + 126), 1.3, NEW)
            else:
                sk.line((x, sb + 100), (x, sb + 126), 1.2, NEW)
            sk.rect(x - 14, sb + 126, 28, 22, NEW, "white", 1.2)
            for t in (0.33, 0.66): sk.line((x - 14 + 28 * t, sb + 126), (x - 14 + 28 * t, sb + 148), 0.6, NEW)
            sk.line((x - 14, sb + 137), (x + 14, sb + 137), 0.6, NEW)
        sk.text(f"อินเวอร์เตอร์ {ni} × {fmt(kw_inv)} kW", (lx, sb + 70), 8.5, False, NEW, "right")
        if PV["fts"]: sk.text("ตู้ FTS (ตัดวงจร DC)", (lx, sb + 110), 8.5, False, NEW, "right")
        sk.text(f"แผง PV รวม {PV['kwp']:,} kWp", (lx, sb + 137), 8.5, False, NEW, "right")
        if PV["fts"]:
            ex, ey = ix[-1] + 36, sb + 170
            sk.circle((ex, ey), 9, NEW, "white", 1.2); sk.circle((ex, ey), 4, NEW, NEW)
            sk.text("ปุ่ม Emergency", (ex, ey + 18), 8, False, NEW, "center")
            ctrl(sk, [(ex, ey - 9), (ex, sb + 108), (ix[-1] + 6, sb + 108)])
        # export limiting
        trip_y = bus_y + 40
        if mode == "lv":
            ct(sk, x0, B + 125, NEW)
            sk.text("CT กันย้อน (ใหม่)", (x0 - 14, B + 125), 8, False, NEW, "right")
            rx, ry = x0 + 320, B + 50
            relay(sk, rx, ry, 130, "รีเลย์กันย้อน แรงต่ำ", "Zero export · CT ที่เมน")
            ctrl(sk, [(x0 + 6, B + 125), (rx + 40, B + 125), (rx + 40, ry + 34)])
            ctrl(sk, [(rx + 130, ry + 17), (pvx + 40, ry + 17), (pvx + 40, trip_y), (pvx + 10, trip_y)])
        else:
            ctrl(sk, [(260, 94 + 38), (260, B - 14), (bx1 + 30, B - 14), (bx1 + 30, trip_y), (pvx + 10, trip_y)])
        sk.text("สั่งปลด", (pvx + 44, trip_y - 8), 7.5, False, NEW)
        rows = [f"กระแสอินเวอร์เตอร์ {fmt(kw_inv)} kW ÷ (1.732 × 400 V) = {i_inv:.1f} A × 1.25 ได้เบรกเกอร์ {a_inv} AT/{af(a_inv)} AF",
                f"กระแสรวม PV {PV['kwp']} kW = {i_tot:.1f} A × 1.25 ได้เบรกเกอร์ PV {a_pv} AT/{af(a_pv)} AF",
                f"กำลัง PV ต่อหม้อแปลง {PV['kwp']} kW ÷ {UP['tr_kva']:,} kVA = {PV['kwp'] / UP['tr_kva'] * 100:.0f}%",
                f"เบรกเกอร์ PV {a_pv} AT ต่อเข้าบัส {MDB['name']} ที่มีเมน {MDB['main'][1]} AT (ตรวจพิกัดบัสบาร์กับวิศวกร)"]
    # ---------------- derived values
    i_tr = UP["tr_kva"] * 1000 / (math.sqrt(3) * V)
    used = [f for f in feeders if f[5] != "SPARE"]
    rows = [f"กระแสพิกัดหม้อแปลง {UP['tr_kva']} kVA ที่ 400 V = {i_tr:.0f} A เทียบเมน {MDB['main'][1]} AT",
            f"วงจรย่อยเดิม {n} วงจร (ใช้งาน {len(used)} · สำรอง {n - len(used)}) · รวมพิกัดวงจรที่ใช้งาน {sum(f[1] for f in used)} AT"] + rows
    ty = B + 540 + (40 if pv else 0)
    sk.line((14, ty - 10), (W - 14, ty - 10), 0.5, RULE)
    sk.text("ค่าที่คำนวณจากข้อมูลสำรวจ", (14, ty + 4), 9.5, True)
    for i, r in enumerate(rows): sk.text("• " + r, (22, ty + 22 + i * 15), 8.5)
    ny = ty + 22 + len(rows) * 15 + 8
    if pv:
        sk.line((14, ny), (40, ny), 1.4, DARK); sk.text("อุปกรณ์เดิม", (46, ny), 8.5)
        sk.line((130, ny), (156, ny), 1.4, NEW); sk.text("อุปกรณ์ใหม่ (PV)", (162, ny), 8.5, False, NEW)
        sk.line((280, ny), (306, ny), 0.9, NEW, [4, 3]); sk.text("สายสัญญาณควบคุม", (312, ny), 8.5, False, NEW)
        ny += 18
    note = "ค่าสมมติ: 400/230 V · PF 1 · เบรกเกอร์ 1.25 × กระแส · ขนาดสาย PV ยังไม่รวม" if pv else "หม้อแปลง 250 kVA เป็นค่าตัวอย่าง · ส่วนอื่นตามแบบ MDP ที่ส่งมา"
    sk.text(note, (14, ny), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ny), 8, False, RED, "right")
    sk.render(ny + 14, path)


for m, f in (("none", "sld_existing.png"), ("lv", "sld_pv_lv.png"), ("hv", "sld_pv_hv.png")):
    sld(os.path.join(HERE, f), m)
print("ok")
