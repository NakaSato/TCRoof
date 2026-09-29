"""Single line diagram generated only from the survey form (field ids as in SurveyCore/Schema.swift).

Reads:  job.meterNo · job.capacity (A1 kWp) · job.trafos[i].kva / .mdb[0..5] (A3) · job.tr{i}_feed / _feedLoc (A3)
        sections: panel (B1 name, breakerAT, loadKW, loadTime) · inverter (B2 inverterCount)
                  backfeed (B4 level, pole) · fts (B5 photoFTS, photoEmg)
Anything the form does not ask is a ค่าสมมติ printed under the drawing. Existing = black, new PV = blue.
Run from docs/specs/img/: writes sld_form_hv.png, sld_form_lv.png, sld_form_existing.png."""
import copy, json, math, os
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "draw.py")).read().split("# ---------------------------------------------------------------- roof section")[0])
exec(open(os.path.join(HERE, "sld_meters.py")).read())

NEW = BLUE
STD_AT = [16, 20, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200]
FRAMES = [100, 160, 250, 400, 630, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000]
ASSUME = dict(grid_kv="22", lv="230-400 V", meter_at="แรงสูง", k=1.25, v=400.0)


def at(i): return next(a for a in STD_AT if a >= i)
def af(a): return next(f for f in FRAMES if f >= a)
def num(s):
    try: return float(str(s).strip())
    except ValueError: return None


# ---------------------------------------------------------------- form → drawing input
def read_form(form):
    j, secs = form["job"], form["sections"]
    miss, assumed = [], [f"ระบบจำหน่าย {ASSUME['grid_kv']} kV · แรงต่ำ {ASSUME['lv']} · มิเตอร์ กฟภ. วัดด้าน{ASSUME['meter_at']}"]
    trs = []
    for i, t in enumerate(j.get("trafos", [])):
        mdbs = [(f"MDB{k + 1}", int(num(a))) for k, a in enumerate(t["mdb"]) if num(a)]
        if not num(t["kva"]) and not mdbs: continue
        if not num(t["kva"]): miss.append(f"A3 TR{i + 1} ขนาด kVA")
        if not mdbs: miss.append(f"A3 TR{i + 1} ขนาดเบรกเกอร์ตู้ MDB")
        feed = j.get(f"tr{i}_feed", "").strip()
        if not feed: miss.append(f"A3 TR{i + 1} ตู้ MDB ปลายสาย")
        trs.append(dict(name=f"TR{i + 1}", kva=num(t["kva"]), mdbs=mdbs, feed=feed, loc=j.get(f"tr{i}_feedLoc", "")))
    if not j.get("meterNo"): miss.append("A3 หมายเลขมิเตอร์")
    panels = [dict(name=s.get("name") or f"ตู้ไฟฟ้า {k + 1}", at=num(s["values"].get("breakerAT")), kw=num(s["values"].get("loadKW")),
                   time=s["values"].get("loadTime", "")) for k, s in enumerate(x for x in secs if x["type"] == "panel")]
    inv = sum(num(s["values"].get("inverterCount")) or 0 for s in secs if s["type"] == "inverter")
    bf = next((s["values"] for s in secs if s["type"] == "backfeed"), {})
    fts = any(s["values"].get("photoFTS") or s["values"].get("photoEmg") for s in secs if s["type"] == "fts")
    kwp = num(j.get("capacity"))
    pv = None
    if kwp and inv:
        level = "hv" if bf.get("level") == "กันย้อนที่แรงสูง" else "lv" if bf.get("level") else None
        if level is None: miss.append("B4 ตำแหน่งกันย้อน")
        pv = dict(kwp=kwp, n=int(inv), level=level, pole=bf.get("pole", ""), fts=fts)
        assumed.append(f"PV ต่อที่ตู้ {trs[0]['feed'] or 'MDB'} (ตู้ปลายสายของ TR1) · PF 1 · เบรกเกอร์ {ASSUME['k']} × กระแส")
    elif kwp or inv:
        miss.append("A1 ขนาดติดตั้ง kWp" if not kwp else "B2 จำนวนอินเวอร์เตอร์")
    assumed.append("หลอด R Y B และ VS + V 0-500V หน้าตู้ MDB วาดตามแบบมาตรฐาน ไม่ได้สำรวจ")
    if panels: assumed.append("ตู้ไฟฟ้าอาคาร (B1) รับไฟจากตู้ปลายสายของ TR1 · ขนาดเบรกเกอร์ในตู้ MDB ไม่ได้สำรวจ")
    return dict(meter=j.get("meterNo", ""), trs=trs, panels=panels, pv=pv, miss=miss, assumed=assumed)


# ---------------------------------------------------------------- symbols
def cb(sk, x, y, label=None, c=DARK, lx=None):
    """Thai-drawing breaker: terminal dot, arc, terminal dot (y = centre); label 'nP AT/AF' to the right (or at lx)."""
    sk.circle((x, y - 11), 2.2, c, "white", 0.9); sk.arc((x, y), 9, 270, 90, 1.3, c); sk.circle((x, y + 11), 2.2, c, "white", 0.9)
    if label:
        p, a, f = label; lx = x + 12 if lx is None else lx
        sk.text(f"{p}P", (lx, y), 8.5, False, c); sk.text(f"{a}AT", (lx + 16, y - 6), 8.5, False, c)
        sk.line((lx + 15, y), (lx + 44, y), 0.6, c); sk.text(f"{f}AF", (lx + 16, y + 7), 8.5, False, c)


def ct(sk, x, y, c=DARK, n=3, lead=22):
    """CT: circle on the line, slash with the CT count, signal lead to the right. Returns the lead end."""
    sk.circle((x, y), 10, c, "white", 1.1)
    sk.line((x, y - 10), (x, y + 10), 1.2, c)
    sk.line((x - 5, y + 5), (x + 3, y - 3), 1.0, c); sk.text(str(n), (x + 6, y - 2), 8.5, True, c, "center")
    sk.line((x + 10, y), (x + 10 + lead, y), 1.0, c)
    return (x + 10 + lead, y)


def dof(sk, x, yt, label=None):
    sk.circle((x, yt), 2.2, DARK, "white", 0.9)
    sk.line((x - 5, yt + 4), (x + 5, yt + 20), 1.2, DARK); sk.arc((x + 5, yt + 17), 3, 270, 90, 1.0, DARK)
    sk.line((x, yt + 20), (x, yt + 24), 1.2, DARK)
    if label: sk.text(label, (x + 14, yt + 11), 8.5)
    return yt + 24


def ground(sk, x, y, name=None):
    for i, w in enumerate((12, 8, 4)): sk.line((x - w / 2, y + i * 3), (x + w / 2, y + i * 3), 1.0, DARK)
    if name: sk.text(name, (x - 10, y + 2), 8, False, DARK, "right")


def relay(sk, x, y, w, t1, t2):
    sk.rect(x, y, w, 34, NEW, "white", 1.2)
    sk.text(t1, (x + w / 2, y + 12), 8.5, True, NEW, "center"); sk.text(t2, (x + w / 2, y + 25), 7.5, False, NEW, "center")


def ctrl(sk, pts):
    for a, b in zip(pts, pts[1:]): sk.line(a, b, 0.9, NEW, [4, 3])


def dashed_box(sk, x0, y0, x1, y1, w=0.9):
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        sk.line(a, b, w, DARK, [14, 6])


# ---------------------------------------------------------------- drawing
def sld(form, path):
    d = read_form(form); pv = d["pv"]; kv = ASSUME["grid_kv"]
    W = 1300; sk = Sk(W)
    mode = "ไม่มีข้อมูล PV" if not pv else {"hv": "กันย้อนแรงสูง", "lv": "กันย้อนแรงต่ำ", None: "ยังไม่ระบุกันย้อน"}[pv["level"]]
    title_strip(sk, f"แผนภาพเส้นเดียว — {form['job'].get('projectName', '')}", f"สร้างจากแบบสำรวจ A1 · A3 · B1 · B2 · B4 · B5 · {mode}")
    # --- HV service: line → DOF/DS → PEA meter → [HV CT/VT + relay] → customer HV bus
    xs, hy = 330, 62
    sk.line((60, hy), (W - 60, hy), 1.2, DARK)
    for px in (xs - 240, xs, xs + 420, xs + 840): sk.rect(px - 4, hy - 4, 8, 8, INK2, FAINT, 0.6)
    for bx in (xs - 120, xs + 210, xs + 630):
        sk.line((bx - 8, hy + 8), (bx - 2, hy - 8), 0.9, DARK); sk.arc((bx + 6, hy), 8, 110, 250, 0.9, DARK)
    for lx in (xs + 105, xs + 525): sk.text(f"PEA {kv}kV", (lx, hy - 12), 9, False, DARK, "center")
    sk.line((xs, hy), (xs, 80), 1.2, DARK)
    y = dof(sk, xs, 82, "Drop Out Fuse/Disconnecting Switch")
    sk.line((xs, y), (xs, y + 8), 1.2, DARK); sk.rect(xs - 4, y + 8, 8, 8, INK2, FAINT, 0.6)
    sk.line((xs, y + 16), (xs, y + 24), 1.2, DARK)
    sk.circle((xs, y + 34), 10, DARK, "white", 1.1); sk.text("M", (xs, y + 34), 7.5, True, DARK, "center")
    for a, b in zip([(xs + 4, y + 12), (xs + 16, y + 12), (xs + 16, y + 34)], [(xs + 16, y + 12), (xs + 16, y + 34), (xs + 10, y + 34)]):
        sk.line(a, b, 0.8, DARK)
    sk.text(f"PEA METER {d['meter']}".strip(), (xs + 22, y + 48), 8.5)
    hb = y + 110                                                              # customer HV bus
    sk.line((xs, y + 44), (xs, hb), 1.2, DARK)
    relay_box = None
    if pv and pv["level"] == "hv":
        cy = y + 72
        lead = ct(sk, xs, cy, NEW, lead=0)
        sk.line((xs - 10, cy), (xs - 10, cy), 0.1, NEW)
        sk.line((xs, cy + 20), (xs - 40, cy + 20), 0.9, NEW)                 # VT
        sk.circle((xs - 46, cy + 20), 6, NEW, None, 1.1); sk.circle((xs - 56, cy + 20), 6, NEW, None, 1.1)
        sk.text("CT/VT แรงสูง (ใหม่)", (xs + 16, cy + 1), 8, False, NEW)
        relay_box = (70, cy - 8, 170)
        relay(sk, 70, cy - 8, 170, "รีเลย์กันย้อน แรงสูง", pv["pole"] or "เสา (ไม่ระบุ)")
        ctrl(sk, [(xs - 10, cy), (240, cy)]); ctrl(sk, [(xs - 62, cy + 20), (240, cy + 20)])
    # --- transformer blocks (A3)
    blocks, bx = [], 120
    for t in d["trs"]:
        w = max(200, 130 * max(1, len(t["mdbs"])))
        blocks.append((t, bx, bx + w)); bx += w + 30
    txs = [(b0 + b1) / 2 for _, b0, b1 in blocks]
    sk.line((min(txs + [xs]), hb), (max(txs + [xs]), hb), 1.4, DARK)
    feed_x, lvb = None, None
    for (t, b0, b1), tx in zip(blocks, txs):
        sk.circle((tx, hb), 2.2, DARK, DARK)
        y = dof(sk, tx, hb + 4)
        jy = y + 4; sk.line((tx, y), (tx, jy + 22), 1.2, DARK)
        sk.line((tx, jy), (tx - 50, jy), 1.0, DARK); sk.line((tx - 50, jy), (tx - 50, jy + 8), 1.0, DARK)   # lightning arrester
        sk.rect(tx - 56, jy + 8, 12, 22, DARK, "white", 1.0); sk.poly([(tx - 53, jy + 20), (tx - 47, jy + 20), (tx - 50, jy + 27)], DARK, DARK)
        sk.line((tx - 50, jy + 30), (tx - 50, jy + 38), 1.0, DARK); ground(sk, tx - 50, jy + 38, "LA")
        for ay in (jy + 20, jy + 30): sk.poly([(tx - 6, ay), (tx + 6, ay), (tx, ay + 9)], DARK, DARK)
        t1 = jy + 60; r = 17
        sk.line((tx, jy + 39), (tx, t1 - r), 1.2, DARK)
        sk.circle((tx, t1), r, DARK, None, 1.2); sk.circle((tx, t1 + 24), r, DARK, None, 1.2)
        sk.poly([(tx - 7, t1 + 4), (tx + 7, t1 + 4), (tx, t1 - 8)], DARK, None, 0.9)
        sk.line((tx, t1 + 26), (tx, t1 + 34), 0.9, DARK); sk.line((tx, t1 + 26), (tx - 6, t1 + 20), 0.9, DARK); sk.line((tx, t1 + 26), (tx + 6, t1 + 20), 0.9, DARK)
        kva = f"{t['kva']:,.0f} kVA" if t["kva"] else "— kVA"
        sk.text(f"{t['name']} {kva}", (tx + 26, t1 - 2), 9, True); sk.text(f"{kv}k/{ASSUME['lv']}", (tx + 26, t1 + 13), 8.5)
        lvb = t1 + 70
        cols = [tx - 65 * (len(t["mdbs"]) - 1) + 130 * k for k in range(len(t["mdbs"]))] or [tx]
        sk.line((tx, t1 + 24 + r), (tx, lvb), 1.4, DARK)
        if len(cols) > 1: sk.line((cols[0], lvb), (cols[-1], lvb), 2.2, DARK)
        for (name, a), cx in zip(t["mdbs"], cols):
            is_pv = pv is not None and t is d["trs"][0] and name == t["feed"]
            if is_pv or (t is d["trs"][0] and name == t["feed"] and d["panels"]):
                feed_x, feed = cx, (t, name, a); sk.line((cx, lvb), (cx, lvb + 150), 1.4, DARK); continue
            dashed_box(sk, cx - 30, lvb + 14, cx + 88, lvb + 92, 0.8)
            sk.line((cx, lvb), (cx, lvb + 34), 1.2, DARK); cb(sk, cx, lvb + 45, (3, a, af(a)))
            sk.line((cx, lvb + 56), (cx, lvb + 104), 1.2, DARK); sk.poly([(cx - 5, lvb + 104), (cx + 5, lvb + 104), (cx, lvb + 112)], DARK, DARK)
            sk.text(name, (cx - 24, lvb + 82), 8.5, True)
            if name == t["feed"]: sk.text(f"ปลายสาย {t['name']}" + (f" · {t['loc']}" if t["loc"] else ""), (cx + 10, lvb + 106), 7.5, False, INK2)
    # --- expanded MDB: the feed MDB of TR1 (PV connection point, B1 panels)
    bottom = lvb + 130
    if feed_x is not None:
        t, name, a = feed
        E0 = lvb + 150; E1 = E0 + 290
        dashed_box(sk, 60, E0, W - 60, E1)
        sk.text(f"{name} ({t['name']})" + (f" · {t['loc']}" if t["loc"] else ""), (feed_x + 14, E0 - 10), 10.5, True)
        sk.line((feed_x, E0), (feed_x, E0 + 99), 1.4, DARK)
        cb(sk, feed_x, E0 + 110); mccb_label(sk, feed_x + 14, E0 + 110, a, af(a))
        incomer_meters(sk, feed_x, E0 + 50, E0 + 80, E0 + 144)
        bus = E0 + 196
        sk.line((feed_x, E0 + 121), (feed_x, bus), 1.4, DARK)
        feeders = d["panels"]; px = W - 320
        f0 = feed_x + 120
        fxs = [f0 + k * min(170, (px - 150 - f0) / max(1, len(feeders) - 1)) for k in range(len(feeders))]
        right = px if pv else (fxs[-1] if fxs else feed_x)
        sk.line((min(fxs + [feed_x]), bus), (max(right, feed_x), bus), 3.2, DARK); sk.circle((feed_x, bus), 2.4, DARK, DARK)
        for k, (p, x) in enumerate(zip(feeders, fxs)):
            sk.text(str(k + 1), (x, bus - 10), 8.5, False, DARK, "center"); sk.circle((x, bus), 2.4, DARK, DARK)
            sk.line((x, bus), (x, bus + 28), 1.2, DARK); cb(sk, x, bus + 40)
            sk.line((x, bus + 51), (x, E1 + 60), 1.2, DARK)
            sk.rect(x - 14, E1 + 60, 28, 14, None, DARK)
            sk.text(p["name"], (x, E1 + 88), 8.5, True, DARK, "center")
            info = " · ".join(s for s in (f"เมน {p['at']:.0f} AT" if p["at"] else "", f"{p['kw']:g} kW" + (f" @{p['time']}" if p["time"] else "") if p["kw"] else "") if s)
            sk.text(info or "ไม่มีข้อมูล", (x, E1 + 102), 8, False, INK2, "center")
        bottom = E1 + 120
        if pv:
            n = pv["n"]; kw_inv = pv["kwp"] / n; K, V = ASSUME["k"], ASSUME["v"]
            i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = pv["kwp"] * 1000 / (math.sqrt(3) * V)
            a_inv, a_pv = at(i_inv * K), at(i_tot * K)
            sk.text("PV", (px, bus - 10), 8.5, True, NEW, "center"); sk.circle((px, bus), 2.4, NEW, NEW)
            sk.line((px, bus), (px, bus + 28), 1.2, NEW); cb(sk, px, bus + 40, (3, a_pv, af(a_pv)), NEW, lx=px - 66)
            sk.text("PV (ใหม่)", (px - 14, bus + 62), 8, True, NEW, "right")
            sb = E1 + 50; show = min(n, 6)
            ix = [px - 35 * (show - 1) + 70 * k for k in range(show)]
            sk.line((px, bus + 51), (px, sb), 1.2, NEW); sk.line((ix[0] - 20, sb), (ix[-1] + 20, sb), 3.0, NEW)
            sk.text("SMDB-PV (ใหม่)", (ix[-1] + 26, sb), 8.5, True, NEW)
            for k, x in enumerate(ix):
                sk.line((x, sb), (x, sb + 18), 1.2, NEW); cb(sk, x, sb + 30, (3, a_inv, af(a_inv)) if k == show - 1 else None, NEW)
                sk.line((x, sb + 41), (x, sb + 56), 1.2, NEW)
                sk.rect(x - 16, sb + 56, 32, 28, NEW, "white", 1.2); sk.line((x - 16, sb + 84), (x + 16, sb + 56), 0.7, NEW)
                sk.text("=", (x - 7, sb + 64), 9, True, NEW, "center"); sk.text("~", (x + 7, sb + 77), 10, True, NEW, "center")
                sk.line((x, sb + 84), (x, sb + 100), 1.2, NEW)
                if pv["fts"]:
                    sk.circle((x, sb + 100), 1.8, NEW, "white", 0.8); sk.line((x, sb + 100), (x + 8, sb + 113), 1.3, NEW); sk.line((x, sb + 116), (x, sb + 126), 1.3, NEW)
                else: sk.line((x, sb + 100), (x, sb + 126), 1.2, NEW)
                sk.rect(x - 14, sb + 126, 28, 22, NEW, "white", 1.2)
                for tt in (0.33, 0.66): sk.line((x - 14 + 28 * tt, sb + 126), (x - 14 + 28 * tt, sb + 148), 0.6, NEW)
                sk.line((x - 14, sb + 137), (x + 14, sb + 137), 0.6, NEW)
            lx = ix[0] - 26
            sk.text(f"อินเวอร์เตอร์ {n} × {fmt(kw_inv)} kW" + (" (แสดง 6)" if n > 6 else ""), (lx, sb + 70), 8.5, False, NEW, "right")
            if pv["fts"]: sk.text("ตู้ FTS (ตัดวงจร DC)", (lx, sb + 110), 8.5, False, NEW, "right")
            sk.text(f"แผง PV รวม {pv['kwp']:,.0f} kWp", (lx, sb + 137), 8.5, False, NEW, "right")
            if pv["fts"]:
                ex, ey = ix[-1] + 36, sb + 170
                sk.circle((ex, ey), 9, NEW, "white", 1.2); sk.circle((ex, ey), 4, NEW, NEW)
                sk.text("ปุ่ม Emergency", (ex, ey + 18), 8, False, NEW, "center")
                ctrl(sk, [(ex, ey - 9), (ex, sb + 108), (ix[-1] + 6, sb + 108)])
            bottom = max(bottom, sb + 200)
            trip_y = bus + 40
            if pv["level"] == "lv":
                lead = ct(sk, feed_x, E0 + 168, NEW, lead=16)
                sk.text("CT กันย้อน (ใหม่)", (feed_x - 14, E0 + 168), 8, False, NEW, "right")
                rx, ry = px - 330, E0 + 100
                relay(sk, rx, ry, 140, "รีเลย์กันย้อน แรงต่ำ", "Zero export")
                ctrl(sk, [lead, (rx + 40, E0 + 168), (rx + 40, ry + 34)])
                ctrl(sk, [(rx + 140, ry + 17), (px + 40, ry + 17), (px + 40, trip_y), (px + 10, trip_y)])
            elif relay_box:
                x0r, y0r, wr = relay_box
                ctrl(sk, [(x0r, y0r + 17), (40, y0r + 17), (40, E0 - 26), (W - 40, E0 - 26), (W - 40, trip_y), (px + 10, trip_y)])
            sk.text("สั่งปลด", (px + 44, trip_y - 8), 7.5, False, NEW)
    # --- values, assumptions, missing
    ty = bottom + 20
    sk.line((14, ty - 10), (W - 14, ty - 10), 0.5, RULE)
    rows = []
    for t in d["trs"]:
        if t["kva"]:
            i_tr = t["kva"] * 1000 / (math.sqrt(3) * ASSUME["v"])
            rows.append(f"{t['name']} {t['kva']:,.0f} kVA = {i_tr:,.0f} A · ตู้ " + ", ".join(f"{n} {a} AT" for n, a in t["mdbs"]))
    if pv:
        n = pv["n"]; kw_inv = pv["kwp"] / n; K, V = ASSUME["k"], ASSUME["v"]
        i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = pv["kwp"] * 1000 / (math.sqrt(3) * V)
        rows += [f"อินเวอร์เตอร์ {fmt(kw_inv)} kW ÷ (1.732 × 400 V) = {i_inv:.1f} A × {K} ได้ {at(i_inv * K)} AT/{af(at(i_inv * K))} AF",
                 f"PV รวม {pv['kwp']:,.0f} kW = {i_tot:.1f} A × {K} ได้ {at(i_tot * K)} AT/{af(at(i_tot * K))} AF",
                 f"PV ต่อหม้อแปลง {d['trs'][0]['name']}: {pv['kwp'] / d['trs'][0]['kva'] * 100:.0f}%" if d["trs"] and d["trs"][0]["kva"] else "PV ต่อหม้อแปลง: ไม่มีขนาด kVA"]
    sk.text("ค่าที่คำนวณจากข้อมูลสำรวจ", (14, ty + 4), 9.5, True)
    for i, r in enumerate(rows): sk.text("• " + r, (22, ty + 22 + i * 15), 8.5)
    y = ty + 22 + len(rows) * 15 + 6
    sk.text("ค่าสมมติ (แบบสำรวจไม่ได้ถาม)", (14, y + 4), 9.5, True)
    for i, r in enumerate(d["assumed"]): sk.text("• " + r, (22, y + 22 + i * 15), 8.5, False, INK2)
    y += 22 + len(d["assumed"]) * 15 + 6
    if d["miss"]:
        sk.text("ข้อมูลที่ยังขาด", (14, y + 4), 9.5, True, RED)
        sk.text(" · ".join(d["miss"]), (22, y + 22), 8.5, False, RED); y += 40
    if pv:
        sk.line((14, y), (40, y), 1.4, DARK); sk.text("อุปกรณ์เดิม", (46, y), 8.5)
        sk.line((130, y), (156, y), 1.4, NEW); sk.text("อุปกรณ์ใหม่ (PV)", (162, y), 8.5, False, NEW)
        sk.line((280, y), (306, y), 0.9, NEW, [4, 3]); sk.text("สายสัญญาณควบคุม", (312, y), 8.5, False, NEW)
    sk.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", (W - 14, y), 8, False, RED, "right")
    sk.render(y + 14, path)


if __name__ == "__main__":
    form = json.load(open(os.path.join(HERE, "sld_form_sample.json")))
    sld(form, os.path.join(HERE, "sld_form_hv.png"))
    lv = copy.deepcopy(form)
    next(s for s in lv["sections"] if s["type"] == "backfeed")["values"] = {"level": "กันย้อนที่แรงต่ำ"}
    sld(lv, os.path.join(HERE, "sld_form_lv.png"))
    ex = copy.deepcopy(form); ex["job"]["capacity"] = ""
    ex["sections"] = [s for s in ex["sections"] if s["type"] == "panel"]
    sld(ex, os.path.join(HERE, "sld_form_existing.png"))
    print("ok")
