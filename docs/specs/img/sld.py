"""Single line diagram generated from PWA survey data (A1 capacity, A3 transformers/MDB, B1 panels, B2 inverters, B4 backfeed, B5 FTS).
Existing equipment in black, new PV equipment in blue. Ratings derived; assumptions listed."""
import math
src = open("draw.py").read().split("# ---------------------------------------------------------------- roof section")[0]
exec(src)

NEW = BLUE
STD_AT = [16, 20, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200]

# ---- survey input (sample) -----------------------------------------------------------------
S = dict(
    grid_kv="22", capacity_kwp=500, inverter_count=5, meter_no="PEA 12-345678",
    trafos=[dict(kva=1000, mdb=[1600, 400])],                # A3: TR1 1,000 kVA → MDB1 1600 AT, MDB2 400 AT
    feed="MDB1",                                              # A3: tr0_feed — where PV connects
    panels=[("ตู้ไฟฟ้าอาคาร โรงสูบน้ำ", 400, 180), ("ตู้ไฟฟ้าอาคาร โรงกรอง", 250, 60), ("ตู้ไฟฟ้า อาคารสำนักงาน", 100, 25)],  # B1: name, AT, load kW
    backfeed="กันย้อนที่แรงต่ำ", fts=True,
)
V, K = 400.0, 1.25          # assumed: 400/230 V system, breaker = 1.25 × rated current


def at(i):
    return next(a for a in STD_AT if a >= i)


def breaker(sk, x, y, color=DARK, label=None, side=1):
    """IEC-style circuit breaker on a vertical line: gap + cross."""
    sk.line((x, y - 14), (x, y - 6), 1.4, color)
    sk.line((x, y - 6), (x + 7, y + 8), 1.4, color)
    sk.line((x - 4, y - 10), (x + 4, y - 2), 1.2, color); sk.line((x + 4, y - 10), (x - 4, y - 2), 1.2, color)
    sk.line((x, y + 8), (x, y + 14), 1.4, color)
    if label: sk.text(label, (x + side * 14, y), 8.5, False, color, "left" if side > 0 else "right")


def vline(sk, x, y0, y1, c=DARK, w=1.4):
    sk.line((x, y0), (x, y1), w, c)


def sld(path):
    W = 1000; sk = Sk(W)
    title_strip(sk, "แผนภาพเส้นเดียว (Single Line Diagram) — สถานีผลิตน้ำ", "สร้างจากแบบสำรวจ A1 · A3 · B1 · B2 · B4 · B5")
    tr = S["trafos"][0]; x0 = 200
    # grid
    sk.poly([(x0 - 10, 52), (x0 + 10, 52), (x0, 66)], DARK, None, 1.2)
    sk.text(f"ระบบจำหน่าย กฟภ. {S['grid_kv']} kV 3 เฟส", (x0 + 18, 56), 9, True)
    vline(sk, x0, 66, 100)
    # HV drop-out fuse
    sk.rect(x0 - 4, 100, 8, 20, DARK, "white", 1.2); sk.line((x0 - 4, 110), (x0 + 4, 110), 0.8, DARK)
    sk.text(f"ดรอปเอาท์ฟิวส์ {S['grid_kv']} kV", (x0 + 14, 110), 8.5)
    vline(sk, x0, 120, 146)
    # transformer
    sk.circle((x0, 160), 15, DARK, None, 1.4); sk.circle((x0, 182), 15, DARK, None, 1.4)
    sk.text(f"TR1 {tr['kva']:,} kVA", (x0 + 24, 164), 9.5, True)
    sk.text(f"{S['grid_kv']} kV / 400-230 V", (x0 + 24, 178), 8.5, False, INK2)
    vline(sk, x0, 197, 222)
    # PEA meter
    sk.circle((x0, 236), 13, DARK, "white", 1.3); sk.text("kWh", (x0, 236), 7.5, True, DARK, "center")
    sk.text(f"มิเตอร์ กฟภ. {S['meter_no']}", (x0 + 20, 236), 8.5)
    vline(sk, x0, 249, 272)
    # CT for export limiting (new)
    sk.circle((x0, 280), 6, NEW, None, 1.2)
    sk.text("CT กันย้อน", (x0 - 12, 280), 8, False, NEW, "right")
    vline(sk, x0, 286, 306)
    # main breaker
    main = tr["mdb"][0]
    breaker(sk, x0, 320, DARK, f"เมน MDB1 3P {main:,} AT")
    vline(sk, x0, 334, 360)
    # MDB1 busbar
    bus_y = 360
    sk.line((80, bus_y), (900, bus_y), 4, DARK)
    sk.text("MDB1 · 400/230 V", (84, bus_y - 12), 9, True)
    # existing feeders
    fx = [150, 290, 430]
    for (name, a, kw), x in zip(S["panels"], fx):
        vline(sk, x, bus_y, bus_y + 26)
        breaker(sk, x, bus_y + 40, DARK, f"3P {a} AT")
        vline(sk, x, bus_y + 54, bus_y + 90)
        sk.poly([(x - 6, bus_y + 90), (x + 6, bus_y + 90), (x, bus_y + 100)], DARK, DARK)
        sk.textBox if False else None
        sk.text(name, (x, bus_y + 114), 8.5, False, DARK, "center")
        sk.text(f"โหลด {kw} kW", (x, bus_y + 128), 8, False, INK2, "center")
    # PV: sizes
    n = S["inverter_count"]; kw_inv = S["capacity_kwp"] / n
    i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = S["capacity_kwp"] * 1000 / (math.sqrt(3) * V)
    br_inv, br_pv = at(i_inv * K), at(i_tot * K)
    # PV incomer on MDB1 (new)
    px = 640
    vline(sk, px, bus_y, bus_y + 26, NEW)
    breaker(sk, px, bus_y + 40, NEW, f"PV 3P {br_pv:,} AT (ใหม่)", side=-1)
    vline(sk, px, bus_y + 54, bus_y + 96, NEW)
    # AC combiner SMDB-PV
    cb_y = bus_y + 96
    xs = [px - 150 + i * 75 for i in range(n)]
    sk.line((xs[0] - 30, cb_y), (xs[-1] + 30, cb_y), 3.5, NEW)
    sk.text("ตู้รวมไฟ AC ของ PV (SMDB-PV)", (xs[-1] + 36, cb_y), 8.5, True, NEW)
    for i, x in enumerate(xs):
        vline(sk, x, cb_y, cb_y + 22, NEW)
        breaker(sk, x, cb_y + 36, NEW, f"{br_inv} AT" if i == 0 else None)
        vline(sk, x, cb_y + 50, cb_y + 66, NEW)
        # inverter box
        sk.rect(x - 18, cb_y + 66, 36, 30, NEW, "white", 1.3)
        sk.line((x - 18, cb_y + 96), (x + 18, cb_y + 66), 0.7, NEW)
        sk.text("=", (x - 8, cb_y + 74), 9, True, NEW, "center"); sk.text("~", (x + 8, cb_y + 89), 10, True, NEW, "center")
        vline(sk, x, cb_y + 96, cb_y + 114, NEW)
        # FTS (DC fire switch)
        if S["fts"]:
            sk.line((x, cb_y + 114), (x + 8, cb_y + 128), 1.4, NEW); sk.line((x, cb_y + 132), (x, cb_y + 144), 1.4, NEW)
            sk.circle((x, cb_y + 114), 1.8, NEW, "white", 0.8)
        # PV array
        sk.rect(x - 14, cb_y + 144, 28, 22, NEW, "white", 1.2)
        for t in (0.33, 0.66): sk.line((x - 14 + 28 * t, cb_y + 144), (x - 14 + 28 * t, cb_y + 166), 0.6, NEW)
        sk.line((x - 14, cb_y + 155), (x + 14, cb_y + 155), 0.6, NEW)
    sk.text(f"อินเวอร์เตอร์ {n} × {fmt(kw_inv)} kW", (xs[-1] + 36, cb_y + 81), 8.5, False, NEW)
    if S["fts"]:
        sk.text("ตู้ FTS (ตัดวงจร DC)", (xs[-1] + 36, cb_y + 128), 8.5, False, NEW)
    sk.text(f"แผง PV รวม {S['capacity_kwp']:,} kWp", (xs[-1] + 36, cb_y + 155), 8.5, False, NEW)
    # zero-export relay (new) + control lines
    rx, ry = 820, 250
    sk.rect(rx, ry, 130, 34, NEW, "white", 1.2)
    sk.text("รีเลย์กันย้อน", (rx + 65, ry + 12), 8.5, True, NEW, "center"); sk.text("Zero export · แรงต่ำ", (rx + 65, ry + 25), 7.5, False, NEW, "center")
    sk.line((x0 + 6, 280), (rx, 280), 0.9, NEW, [4, 3])
    sk.line((rx + 20, ry + 34), (rx + 20, bus_y + 40), 0.9, NEW, [4, 3]); sk.line((rx + 20, bus_y + 40), (px + 10, bus_y + 40), 0.9, NEW, [4, 3])
    sk.text("สั่งปลด", (rx + 24, bus_y + 30), 7.5, False, NEW)
    # emergency button
    if S["fts"]:
        ex, ey = xs[-1] + 24, cb_y + 186
        sk.circle((ex, ey), 9, NEW, "white", 1.2); sk.circle((ex, ey), 4, NEW, NEW)
        sk.text("ปุ่ม Emergency (สั่งตู้ FTS ตัดวงจร)", (ex + 14, ey), 8.5, False, NEW)
        sk.line((ex, ey - 9), (ex, cb_y + 124), 0.9, NEW, [4, 3]); sk.line((ex, cb_y + 124), (xs[-1] + 6, cb_y + 124), 0.9, NEW, [4, 3])
    # calc + checks
    ty = cb_y + 214
    sk.line((14, ty - 12), (W - 14, ty - 12), 0.5, RULE)
    sk.text("ค่าที่คำนวณจากข้อมูลสำรวจ", (14, ty), 9.5, True)
    rows = [
        f"กระแสอินเวอร์เตอร์ {fmt(kw_inv)} kW ÷ (1.732 × 400 V) = {i_inv:.1f} A × 1.25 ได้เบรกเกอร์ {br_inv} AT",
        f"กระแสรวม PV {S['capacity_kwp']} kW = {i_tot:.1f} A × 1.25 ได้เบรกเกอร์ PV {br_pv:,} AT",
        f"กำลัง PV ต่อหม้อแปลง {S['capacity_kwp']} kW ÷ {tr['kva']:,} kVA = {S['capacity_kwp'] / tr['kva'] * 100:.0f}%",
        f"เบรกเกอร์ PV {br_pv:,} AT ต่อเข้าบัส MDB1 ที่มีเมน {main:,} AT (ตรวจพิกัดบัสบาร์กับวิศวกร)",
    ]
    for i, r in enumerate(rows): sk.text("• " + r, (22, ty + 18 + i * 15), 8.5)
    ny = ty + 18 + len(rows) * 15 + 10
    sk.line((14, ny), (40, ny), 1.4, DARK); sk.text("อุปกรณ์เดิม", (46, ny), 8.5)
    sk.line((130, ny), (156, ny), 1.4, NEW); sk.text("อุปกรณ์ใหม่ (PV)", (162, ny), 8.5, False, NEW)
    sk.line((280, ny), (306, ny), 0.9, NEW, [4, 3]); sk.text("สายสัญญาณควบคุม", (312, ny), 8.5, False, NEW)
    sk.text("ค่าสมมติ: ระบบ 400/230 V · PF 1 · เบรกเกอร์ 1.25 × กระแส · ขนาดสายไฟยังไม่รวม (ต้องใช้ระยะสาย)", (14, ny + 18), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ny + 18), 8, False, RED, "right")
    sk.render(ny + 32, path)


sld("sld.png")
print("ok")
