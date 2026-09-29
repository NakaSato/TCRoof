"""Single line diagram of the EXISTING electrical system (no PV), in the style of a Thai MDP drawing.
Generated only from survey input: upstream (A3) + one MDB schedule (main, CT, meter, busbar, feeders, ground)."""
import math
import os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "draw.py")).read().split("# ---------------------------------------------------------------- roof section")[0]
exec(src)

# ---- survey input (sample = the MDP sheet the user shared; transformer kVA is a sample value) ----
UP = dict(grid_kv="22", tr_name="TR1", tr_kva=250, meter_no="PEA 12-345678")
MDB = dict(
    name="MDP", ic_ka=25, main=(3, 300, 400), ct="300/5A", dp="DP2", pilot=True,
    busbar="4x300A. Cu. BUSBAR W/GROUND BUS",
    feeders=[  # poles, AT, AF, cable, conduit, destination, note
        (3, 100, 100, "4x50,1x10-IEC01", "IN WIRE WAY", "LC11", "1st FL."),
        (3, 100, 100, "4x50,1x10-IEC01", "ø50mm. UPVC", "LC12", "1st FL."),
        (3, 100, 100, "4x50,1x10-IEC01", "ø50mm. UPVC", "LC21", "2nd FL."),
        (3, 50, 100, "4x10,1x4-IEC01", "ø25mm. UPVC", "LC22", "2nd FL."),
        (3, 80, 100, "4x35,1x10-IEC01", "ø40mm. UPVC", "LC31", "3rd FL."),
        (3, 30, 100, "", "", "SPARE", ""),
    ],
    ground="1x35-IEC01 ø20 PVC.",
)


def cb(sk, x, y, label=None, lx=None):
    """Thai-drawing breaker: terminal dot, arc to the right, terminal dot (y = centre)."""
    sk.circle((x, y - 11), 2.2, DARK, "white", 0.9)
    sk.arc((x, y), 9, 270, 90, 1.3, DARK)
    sk.circle((x, y + 11), 2.2, DARK, "white", 0.9)
    if label:
        p, a, f = label
        sk.text(f"{p}P", ((lx or x + 12), y), 8.5, False, DARK)
        sk.text(f"{a}AT", ((lx or x + 12) + 16, y - 6), 8.5, False, DARK)
        sk.line(((lx or x + 12) + 15, y), ((lx or x + 12) + 44, y), 0.6, DARK)
        sk.text(f"{f}AF", ((lx or x + 12) + 16, y + 7), 8.5, False, DARK)


def sld(path):
    W = 1000; sk = Sk(W)
    title_strip(sk, f"แผนภาพเส้นเดียว ระบบไฟฟ้าเดิม — {MDB['name']}", "สร้างจากแบบสำรวจ A3 · ตาราง MDB · ไม่มีระบบ PV")
    x0 = 470
    # upstream: grid → DOF → transformer → PEA meter (from A3)
    sk.poly([(x0 - 9, 50), (x0 + 9, 50), (x0, 63)], DARK, None, 1.2)
    sk.text(f"ระบบจำหน่าย กฟภ. {UP['grid_kv']} kV", (x0 + 16, 54), 8.5, True)
    sk.line((x0, 63), (x0, 78), 1.4, DARK)
    sk.rect(x0 - 4, 78, 8, 16, DARK, "white", 1.1); sk.text("ดรอปเอาท์ฟิวส์", (x0 + 14, 86), 8)
    sk.line((x0, 94), (x0, 104), 1.4, DARK)
    sk.circle((x0, 116), 12, DARK, None, 1.3); sk.circle((x0, 134), 12, DARK, None, 1.3)
    sk.text(f"{UP['tr_name']} {UP['tr_kva']:,} kVA · {UP['grid_kv']} kV/400-230 V", (x0 + 20, 125), 8.5, True)
    sk.line((x0, 146), (x0, 158), 1.4, DARK)
    sk.circle((x0, 169), 11, DARK, "white", 1.2); sk.text("kWh", (x0, 169), 6.5, True, DARK, "center")
    sk.text(f"มิเตอร์ กฟภ. {UP['meter_no']}", (x0 + 18, 169), 8)
    sk.line((x0, 180), (x0, 200), 2.2, DARK, [10, 3, 2, 3])
    # MDP enclosure (dashed)
    bx0, by0, bx1, by1 = 40, 200, 900, 490
    for (a, b) in (((bx0, by0), (bx1, by0)), ((bx1, by0), (bx1, by1)), ((bx1, by1), (bx0, by1)), ((bx0, by1), (bx0, by0))):
        sk.line(a, b, 0.9, DARK, [14, 6])
    sk.text(MDB["name"], (bx1 - 8, by0 - 10), 11, True, DARK, "right")
    sk.text(f"IC ไม่น้อยกว่า {MDB['ic_ka']} kA", (bx0 + 12, by0 + 16), 8.5)
    # main line + main breaker
    sk.line((x0, by0), (x0, 232), 2.2, DARK, [10, 3, 2, 3])
    sk.line((x0, 232), (x0, 245), 1.6, DARK)
    sk.circle((x0, 232), 2.2, DARK, DARK)
    cb(sk, x0, 256, MDB["main"])
    sk.line((x0, 267), (x0, 330), 1.6, DARK)
    # pilot lamps via fuse + DP meter
    if MDB["pilot"]:
        sk.line((x0, 232), (x0 + 110, 232), 0.9, DARK)
        sk.rect(x0 + 110, 226, 40, 12, DARK, "white", 0.9); sk.text("3x6A", (x0 + 130, 219), 8, False, DARK, "center")
        sk.line((x0 + 150, 232), (x0 + 250, 232), 0.9, DARK)
        sk.circle((x0 + 258, 232), 7, DARK, "white", 0.9)
        sk.line((x0 + 253, 227), (x0 + 263, 237), 0.8, DARK); sk.line((x0 + 263, 227), (x0 + 253, 237), 0.8, DARK)
        sk.text("x3", (x0 + 270, 232), 8.5)
        sk.line((x0 + 200, 232), (x0 + 200, 270), 0.9, DARK)
        sk.rect(x0 + 186, 270, 28, 18, DARK, "white", 0.9); sk.text("DP", (x0 + 200, 279), 8, True, DARK, "center")
        sk.text(MDB["dp"], (x0 + 220, 279), 8.5)
        sk.line((x0 + 200, 288), (x0 + 200, 305), 0.9, DARK); sk.line((x0 + 200, 305), (x0 + 12, 305), 0.9, DARK)
    # CT
    for dy in (-5, 0, 5):
        sk.arc((x0, 305 + dy), 5, 90, 270, 1.0, DARK)
    sk.text(f"3xCT", (x0 - 14, 300), 8.5, False, DARK, "right"); sk.text(MDB["ct"], (x0 - 14, 312), 8.5, False, DARK, "right")
    # busbar
    n = len(MDB["feeders"]); fx0, fx1 = 170, 800
    xs = [fx0 + i * (fx1 - fx0) / (n - 1) for i in range(n)]
    bus_y = 340
    sk.line((xs[0], bus_y), (xs[-1], bus_y), 3.2, DARK)
    sk.line((x0, 330), (x0, bus_y), 1.6, DARK); sk.circle((x0, bus_y), 2.4, DARK, DARK)
    sk.text(MDB["busbar"], (fx0, bus_y - 26), 8.5, True)
    for i, (p, a, f, cable, conduit, dest, note) in enumerate(MDB["feeders"]):
        x = xs[i]
        sk.text(str(i + 1), (x, bus_y - 10), 8.5, False, DARK, "center"); sk.circle((x, bus_y), 2.4, DARK, DARK)
        sk.line((x, bus_y), (x, bus_y + 28), 1.2, DARK)
        cb(sk, x, bus_y + 40, (p, a, f))
        if dest == "SPARE":
            sk.text("SPARE", (x, bus_y + 70), 8.5, False, DARK, "center"); continue
        sk.line((x, bus_y + 51), (x, 660), 1.2, DARK)
        sk.text(f"{cable}, {conduit}", (x - 8, 590), 8, False, DARK, "center", -90)
        sk.rect(x - 14, 660, 28, 14, None, DARK)
        sk.text(dest, (x, 688), 8.5, True, DARK, "center"); sk.text(f"({note})", (x, 701), 8, False, DARK, "center")
    # N-G bar + ground rod
    gx, gy = 90, 400
    sk.rect(gx - 14, gy - 22, 30, 8, DARK, DARK); sk.text("N", (gx + 22, gy - 18), 8.5)
    sk.rect(gx - 14, gy + 4, 30, 8, DARK, DARK); sk.text("G", (gx + 22, gy + 8), 8.5)
    sk.line((gx - 10, gy - 14), (gx - 10, gy + 4), 1.0, DARK)
    sk.line((gx + 2, gy + 12), (gx + 2, 575), 1.2, DARK)
    for i, wdt in enumerate((18, 12, 6)):
        sk.line((gx + 2 - wdt / 2, 575 + i * 5), (gx + 2 + wdt / 2, 575 + i * 5), 1.2, DARK)
    sk.text(MDB["ground"], (gx - 6, 545), 8, False, DARK, "center", -90)
    sk.text("GROUND ROD", (gx + 2, 600), 8.5, False, DARK, "center")
    # derived info (existing system only)
    i_tr = UP["tr_kva"] * 1000 / (math.sqrt(3) * 400)
    used = [f for f in MDB["feeders"] if f[5] != "SPARE"]
    ty = 730
    sk.line((14, ty - 10), (W - 14, ty - 10), 0.5, RULE)
    sk.text("ค่าที่คำนวณจากข้อมูลสำรวจ", (14, ty + 4), 9.5, True)
    rows = [f"กระแสพิกัดหม้อแปลง {UP['tr_kva']} kVA ที่ 400 V = {i_tr:.0f} A เทียบเมน {MDB['main'][1]} AT",
            f"วงจรย่อย {n} วงจร (ใช้งาน {len(used)} · สำรอง {n - len(used)}) · รวมพิกัดวงจรที่ใช้งาน {sum(f[1] for f in used)} AT"]
    for i, r in enumerate(rows): sk.text("• " + r, (22, ty + 22 + i * 15), 8.5)
    ny = ty + 22 + len(rows) * 15 + 8
    sk.text("หม้อแปลง 250 kVA เป็นค่าตัวอย่าง · ส่วนอื่นตามแบบ MDP ที่ส่งมา", (14, ny), 8, False, INK2)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, ny), 8, False, RED, "right")
    sk.render(ny + 14, path)


sld("sld_existing.png")
print("ok")
