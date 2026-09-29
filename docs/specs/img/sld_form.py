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


TR_REQ = [("kva", "ขนาด kVA"), ("type", "ชนิด"), ("hv", "แรงดันแรงสูง"), ("lv", "แรงดันแรงต่ำ"), ("vector", "Vector group"),
          ("z", "%Z"), ("brand", "ยี่ห้อ"), ("serial", "Serial no."), ("year", "ปีผลิต"), ("cond", "สภาพ")]
BRK_REQ = [("type", "ชนิด MCCB/ACB"), ("mount", "Fixed/Draw-out"), ("poles", "จำนวนโพล"), ("at", "AT"), ("af", "AF"), ("ka", "IC kA"), ("brand", "ยี่ห้อ"), ("cond", "สภาพ")]
GREEN, AMBER = "#2F855A", "#B7791F"
COND = {"ดี": GREEN, "พอใช้": AMBER, "ชำรุด": RED}


def breaker(b, miss, where):
    """Normalise one surveyed breaker; every BRK_REQ field is required, gaps go to `miss`."""
    b = {k: str(b.get(k, "")).strip() for k, _ in BRK_REQ} | {"note": str(b.get("note", "")).strip()}
    gaps = [lab for k, lab in BRK_REQ if not b[k]]
    if gaps: miss.append(f"{where}: " + ", ".join(gaps))
    return b


def wrap(s, n):
    """Split a name into lines of about n characters at spaces (Thai names often have few spaces)."""
    out, cur = [], ""
    for w in s.split(" "):
        if cur and len(cur) + 1 + len(w) > n: out.append(cur); cur = w
        else: cur = f"{cur} {w}".strip()
    return out + [cur] if cur else out


def q(v, unit=""):
    """Value for the drawing; '?' marks a field the surveyor left blank."""
    return f"{v}{unit}" if str(v).strip() else "?"


# ---------------------------------------------------------------- form → drawing input
def read_form(form):
    j, secs = form["job"], form["sections"]
    miss, assumed = [], [f"ระบบจำหน่าย {ASSUME['grid_kv']} kV · มิเตอร์ กฟภ. วัดด้าน{ASSUME['meter_at']}"]
    trs = []
    for i, t in enumerate(j.get("trafos", [])):
        brk = t.get("breakers", [])
        mdbs = []
        for k, a in enumerate(t["mdb"]):
            b = dict(brk[k]) if k < len(brk) else {}
            if not num(a) and not b: continue
            b.setdefault("at", a)
            name = str(b.get("name", "")).strip()          # the name written on the panel on site (MDP-1, ตู้ MDB โรงสูบ 2, …)
            if not name: miss.append(f"A3 TR{i + 1} ตู้ที่ {k + 1}: ชื่อตู้ตามหน้างาน"); name = f"ตู้ที่ {k + 1}"
            mdbs.append((name, breaker(b, miss, f"A3 TR{i + 1} {name}")))
        if not num(t["kva"]) and not mdbs: continue
        tr = dict(name=f"TR{i + 1}", kva=num(t["kva"]), mdbs=mdbs, feed=j.get(f"tr{i}_feed", "").strip(), loc=j.get(f"tr{i}_feedLoc", ""),
                  **{k: str(j.get(f"tr{i}_{k}", "")).strip() for k, _ in TR_REQ if k != "kva"}, note=j.get(f"tr{i}_condNote", ""))
        gaps = [lab for k, lab in TR_REQ if not (tr["kva"] if k == "kva" else tr[k])]
        if not tr["feed"]: gaps.append("ตู้ MDB ปลายสาย")
        elif mdbs and tr["feed"] not in [n for n, _ in mdbs]: gaps.append(f"ตู้ปลายสาย \"{tr['feed']}\" ไม่ตรงกับชื่อตู้ที่กรอก")
        if not mdbs: gaps.append("เบรกเกอร์ตู้ MDB")
        if gaps: miss.append(f"A3 TR{i + 1}: " + ", ".join(gaps))
        trs.append(tr)
    if not j.get("meterNo"): miss.append("A3 หมายเลขมิเตอร์")
    panels = []
    for k, sec in enumerate(x for x in secs if x["type"] == "panel"):
        v = sec["values"]; name = sec.get("name") or f"ตู้ไฟฟ้า {k + 1}"
        b = {f: v.get(key, "") for f, key in (("type", "breakerType"), ("poles", "breakerPoles"), ("at", "breakerAT"),
                                              ("af", "breakerAF"), ("ka", "breakerKA"), ("brand", "breakerBrand"), ("mount", "breakerMount"))}
        b.update(cond=v.get("cond", ""), note=v.get("condNote", ""))
        panels.append(dict(name=name, brk=breaker(b, miss, f"B1 {name}"), kw=num(v.get("loadKW")), time=v.get("loadTime", "")))
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
    if panels: assumed.append("ตู้ไฟฟ้าอาคาร (B1) รับไฟจากตู้ปลายสายของ TR1 · เบรกเกอร์ที่แสดงคือเมนของตู้อาคาร")
    return dict(meter=j.get("meterNo", ""), trs=trs, panels=panels, pv=pv, miss=miss, assumed=assumed)


# ---------------------------------------------------------------- symbols
def cb(sk, x, y, label=None, c=DARK, lx=None):
    """Thai-drawing breaker: terminal dot, arc, terminal dot (y = centre); label 'nP AT/AF' to the right (or at lx)."""
    sk.circle((x, y - 11), 2.2, c, "white", 0.9); sk.arc((x, y), 9, 270, 90, 1.3, c); sk.circle((x, y + 11), 2.2, c, "white", 0.9)
    if label:
        p, a, f = label; lx = x + 12 if lx is None else lx
        sk.text(f"{p}P", (lx, y), 8.5, False, c); sk.text(f"{a}AT", (lx + 16, y - 6), 8.5, False, c)
        sk.line((lx + 15, y), (lx + 44, y), 0.6, c); sk.text(f"{f}AF", (lx + 16, y + 7), 8.5, False, c)


def brk_label(sk, x, y, b, c=DARK, new=False):
    """Full breaker label: type,poles / AT over AF / IC kA / brand / condition. Blank fields print '?' in red."""
    def t(s, yy, col=c, bold=False):
        sk.text(s, (x, yy), 8.5, bold, RED if "?" in s else col)
    t(f"{q(b['type'])},{q(b['poles'])}P", y - 16)
    t(f"{q(b['at'])}AT", y - 3); sk.line((x - 1, y + 4), (x + 34, y + 4), 0.6, c); t(f"{q(b['af'])}AF", y + 12)
    if new: t("(ใหม่)", y + 26); return
    t(f"IC {q(b['ka'])} kA", y + 26); t(b["brand"] or "ยี่ห้อ ?", y + 40, INK2)
    cond_label(sk, x, y + 54, b["cond"], b["note"], wrap=True)


def cond_label(sk, x, y, cond, note="", align="left", wrap=False):
    col = COND.get(cond, RED)
    if wrap and note:
        sk.text(f"สภาพ: {q(cond)}", (x, y), 8.5, True, col, align); sk.text(note, (x, y + 14), 8, False, col, align)
    else:
        sk.text(f"สภาพ: {q(cond)}" + (f" — {note}" if note else ""), (x, y), 8.5, True, col, align)


def drawout(b):
    return str(b.get("mount", "")).lower().startswith("draw")


def lvbrk(sk, x, y, b, c=DARK):
    """LV breaker symbol by mounting: fixed = terminals + arc; draw-out = double chevrons above and below the arc.
    Returns the half-height the caller's lines must stop at (11 fixed, 22 draw-out)."""
    if not drawout(b):
        cb(sk, x, y, c=c); return 11
    sk.arc((x, y), 9, 270, 90, 1.3, c)
    for cy in (y - 22, y - 16):                                             # pointing up
        sk.line((x - 5, cy + 5), (x, cy), 1.1, c); sk.line((x, cy), (x + 5, cy + 5), 1.1, c)
    for cy in (y + 16, y + 22):                                             # pointing down
        sk.line((x - 5, cy - 5), (x, cy), 1.1, c); sk.line((x, cy), (x + 5, cy - 5), 1.1, c)
    sk.line((x, y - 22), (x, y - 16), 1.1, c); sk.line((x, y + 16), (x, y + 22), 1.1, c)
    return 22


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


def inv_ctrl(sk, route, ix, sb):
    """Export-limit control to the inverters: `route` ends on the right at y = sb + 92; a dashed control bus runs left
    under the inverter boxes with a stub into each one."""
    y = sb + 92
    ctrl(sk, route + [(ix[0] - 10, y)])
    for x in ix:
        ctrl(sk, [(x - 10, y), (x - 10, sb + 84)]); sk.circle((x - 10, y), 1.8, NEW, NEW)
    sk.text("สั่งควบคุมกำลังผลิต", (ix[0] - 26, y), 7.5, False, NEW, "right")


def dashed_box(sk, x0, y0, x1, y1, w=0.9):
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        sk.line(a, b, w, DARK, [14, 6])


# ---------------------------------------------------------------- drawing
def sld(form, path):
    d = read_form(form); pv = d["pv"]; kv = ASSUME["grid_kv"]
    # --- layout first: the sheet grows with the number of transformers, MDBs, B1 panels and inverters
    blocks, bx = [], 120
    for t in d["trs"]:
        w = max(270, 120 * max(1, len(t["mdbs"])))
        blocks.append((t, bx, bx + w)); bx += w + 30
    FSP = 105                                                                 # feeder spacing in the expanded MDB
    fx0 = 0
    if blocks:
        t0, b0, b1 = blocks[0]; names = [n for n, _ in t0["mdbs"]]
        k0 = names.index(t0["feed"]) if t0["feed"] in names else 0
        fx0 = (b0 + b1) / 2 - 60 * (len(names) - 1) + 120 * k0
    nfeed = len(d["panels"]); last = fx0 + 110 + FSP * (nfeed - 1) if nfeed else fx0
    show = min(pv["n"], 10) if pv else 0
    PX = max(900, last + 260 + 30 * (show - 1)) if pv else 0
    W = max(1300, bx + 60, PX + 30 * (show - 1) + 170 if pv else last + 220)
    sk = Sk(W)
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
        for ay in (jy + 12, jy + 22, jy + 32): sk.poly([(tx - 6, ay), (tx + 6, ay), (tx, ay + 9)], DARK, DARK)
        t1 = jy + 60; r = 17
        sk.line((tx, jy + 41), (tx, t1 - r), 1.2, DARK)
        sk.circle((tx, t1), r, DARK, None, 1.2); sk.circle((tx, t1 + 24), r, DARK, None, 1.2)
        sk.poly([(tx - 7, t1 + 4), (tx + 7, t1 + 4), (tx, t1 - 8)], DARK, None, 0.9)
        sk.line((tx, t1 + 26), (tx, t1 + 34), 0.9, DARK); sk.line((tx, t1 + 26), (tx - 6, t1 + 20), 0.9, DARK); sk.line((tx, t1 + 26), (tx + 6, t1 + 20), 0.9, DARK)
        lines = [(f"{t['name']} {q(t['type'])}", True), (f"{q(t['hv'])}k/{q(t['lv'])} V", False),
                 (f"{t['vector'] or 'Vector ?'}, Z={q(t['z'])}%", False), (f"{t['kva']:,.0f} kVA" if t["kva"] else "? kVA", False),
                 (f"{q(t['brand'])} · SN {q(t['serial'])} · ปี {q(t['year'])}", False)]
        for k, (txt, bold) in enumerate(lines):
            sk.text(txt, (tx + 26, t1 - 8 + 14 * k), 9 if bold else 8.5, bold, RED if "?" in txt else DARK)
        cond_label(sk, tx + 26, t1 - 8 + 14 * len(lines), t["cond"], t["note"])
        lvb = t1 + 100
        cols = [tx - 60 * (len(t["mdbs"]) - 1) + 120 * k for k in range(len(t["mdbs"]))] or [tx]
        sk.line((tx, t1 + 24 + r), (tx, lvb), 1.4, DARK)
        if len(cols) > 1: sk.line((cols[0], lvb), (cols[-1], lvb), 2.2, DARK)
        for (name, b), cx in zip(t["mdbs"], cols):
            if t is d["trs"][0] and name == t["feed"] and (pv or d["panels"]):
                feed_x, feed = cx, (t, name, b); sk.line((cx, lvb), (cx, lvb + 225), 1.4, DARK); continue
            dashed_box(sk, cx - 14, lvb + 14, cx + 102, lvb + 158, 0.8)
            for li, part in enumerate(wrap(name, 14)[:2]): sk.text(part, (cx + 10, lvb + 26 + 12 * li), 8.5, True)
            h = 22 if drawout(b) else 11
            sk.line((cx, lvb), (cx, lvb + 74 - h), 1.2, DARK); lvbrk(sk, cx, lvb + 74, b); brk_label(sk, cx + 12, lvb + 74, b)
            sk.line((cx, lvb + 74 + h), (cx, lvb + 166), 1.2, DARK); sk.poly([(cx - 5, lvb + 166), (cx + 5, lvb + 166), (cx, lvb + 174)], DARK, DARK)
            if name == t["feed"]: sk.text(f"ปลายสาย {t['name']}" + (f" · {t['loc']}" if t["loc"] else ""), (cx + 8, lvb + 172), 7.5, False, INK2)
    # --- expanded MDB: the feed MDB of TR1 (PV connection point, B1 panels)
    bottom = lvb + 195
    if feed_x is not None:
        t, name, mb = feed
        E0 = lvb + 225; E1 = E0 + 290
        dashed_box(sk, 60, E0, W - 60, E1)
        sk.text(f"{name} ({t['name']})" + (f" · {t['loc']}" if t["loc"] else ""), (feed_x + 14, E0 - 10), 10.5, True)
        h = 22 if drawout(mb) else 11
        sk.line((feed_x, E0), (feed_x, E0 + 40 - h), 1.4, DARK)
        lvbrk(sk, feed_x, E0 + 40, mb); brk_label(sk, feed_x + 14, E0 + 40, mb)
        bus = E0 + 160
        sk.line((feed_x, E0 + 40 + h), (feed_x, bus), 1.4, DARK)
        feeders = d["panels"]; px = PX
        fxs = [feed_x + 110 + FSP * k for k in range(len(feeders))]
        right = px if pv else (fxs[-1] if fxs else feed_x)
        sk.line((min(fxs + [feed_x]), bus), (max(right, feed_x), bus), 3.2, DARK); sk.circle((feed_x, bus), 2.4, DARK, DARK)
        for k, (p, x) in enumerate(zip(feeders, fxs)):
            sk.text(str(k + 1), (x, bus - 10), 8.5, False, DARK, "center"); sk.circle((x, bus), 2.4, DARK, DARK)
            h = 22 if drawout(p["brk"]) else 11
            sk.line((x, bus), (x, bus + 40 - h), 1.2, DARK); lvbrk(sk, x, bus + 40, p["brk"]); brk_label(sk, x + 12, bus + 40, p["brk"])
            sk.line((x, bus + 40 + h), (x, E1 + 60), 1.2, DARK)
            sk.rect(x - 14, E1 + 60, 28, 14, None, DARK)
            for li, part in enumerate(wrap(p["name"], 14)[:2]): sk.text(part, (x, E1 + 88 + 12 * li), 8.5, True, DARK, "center")
            info = f"โหลด {p['kw']:g} kW" + (f" @{p['time']}" if p["time"] else "") if p["kw"] else "โหลด ?"
            sk.text(info, (x, E1 + 114), 8, False, RED if "?" in info else INK2, "center")
        bottom = E1 + 120
        if pv:
            n = pv["n"]; kw_inv = pv["kwp"] / n; K, V = ASSUME["k"], ASSUME["v"]
            i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = pv["kwp"] * 1000 / (math.sqrt(3) * V)
            a_inv, a_pv = at(i_inv * K), at(i_tot * K)
            sk.text("PV", (px, bus - 10), 8.5, True, NEW, "center"); sk.circle((px, bus), 2.4, NEW, NEW)
            sk.line((px, bus), (px, bus + 28), 1.2, NEW); cb(sk, px, bus + 40, c=NEW); brk_label(sk, px - 70, bus + 40, dict(type="MCCB", poles="3", at=a_pv, af=af(a_pv)), NEW, new=True)
            sb = E1 + 50
            ix = [px - 30 * (show - 1) + 60 * k for k in range(show)]
            sk.line((px, bus + 51), (px, sb), 1.2, NEW); sk.line((ix[0] - 20, sb), (ix[-1] + 20, sb), 3.0, NEW)
            sk.text("SMDB-PV (ใหม่)", (ix[0] - 26, sb), 8.5, True, NEW, "right")
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
            sk.text(f"อินเวอร์เตอร์ {n} × {fmt(kw_inv)} kW" + (f" (แสดง {show})" if n > show else ""), (lx, sb + 70), 8.5, False, NEW, "right")
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
                lead = ct(sk, feed_x, E0 + 130, NEW, lead=16)
                sk.text("CT กันย้อน (ใหม่)", (feed_x - 14, E0 + 130), 8, False, NEW, "right")
                rx, ry = px - 330, E0 + 30
                relay(sk, rx, ry, 140, "รีเลย์กันย้อน แรงต่ำ", "Zero export")
                ctrl(sk, [lead, (rx + 40, E0 + 130), (rx + 40, ry + 34)])
                inv_ctrl(sk, [(rx + 140, ry + 17), (ix[-1] + 72, ry + 17), (ix[-1] + 72, sb + 92)], ix, sb)
            elif relay_box:
                x0r, y0r, wr = relay_box
                inv_ctrl(sk, [(x0r, y0r + 17), (40, y0r + 17), (40, E0 - 26), (W - 40, E0 - 26), (W - 40, sb + 92)], ix, sb)
    # --- values, assumptions, missing
    ty = bottom + 20
    sk.line((14, ty - 10), (W - 14, ty - 10), 0.5, RULE)
    rows = []
    for t in d["trs"]:
        if t["kva"]:
            i_tr = t["kva"] * 1000 / (math.sqrt(3) * ASSUME["v"])
            rows.append(f"{t['name']} {t['kva']:,.0f} kVA = {i_tr:,.0f} A · ตู้ " + ", ".join(f"{n} {q(b['at'])} AT" for n, b in t["mdbs"]))
    if pv:
        n = pv["n"]; kw_inv = pv["kwp"] / n; K, V = ASSUME["k"], ASSUME["v"]
        i_inv = kw_inv * 1000 / (math.sqrt(3) * V); i_tot = pv["kwp"] * 1000 / (math.sqrt(3) * V)
        rows += [f"อินเวอร์เตอร์ {fmt(kw_inv)} kW ÷ (1.732 × 400 V) = {i_inv:.1f} A × {K} ได้ {at(i_inv * K)} AT/{af(at(i_inv * K))} AF",
                 f"PV รวม {pv['kwp']:,.0f} kW = {i_tot:.1f} A × {K} ได้ {at(i_tot * K)} AT/{af(at(i_tot * K))} AF",
                 f"PV ต่อหม้อแปลง {d['trs'][0]['name']}: {pv['kwp'] / d['trs'][0]['kva'] * 100:.0f}%" if d["trs"] and d["trs"][0]["kva"] else "PV ต่อหม้อแปลง: ไม่มีขนาด kVA"]
    allb = [(f"{t['name']} {n}", b) for t in d["trs"] for n, b in t["mdbs"]] + [(p["name"], p["brk"]) for p in d["panels"]]
    rows += [f"{w}: AT {b['at']} มากกว่า AF {b['af']} (ตรวจค่าที่อ่านจากป้าย)" for w, b in allb if num(b["at"]) and num(b["af"]) and num(b["at"]) > num(b["af"])]
    sk.text("ค่าที่คำนวณจากข้อมูลสำรวจ", (14, ty + 4), 9.5, True)
    for i, r in enumerate(rows): sk.text("• " + r, (22, ty + 22 + i * 15), 8.5)
    y = ty + 22 + len(rows) * 15 + 6
    eq = [(t["name"], t["cond"], t["note"]) for t in d["trs"]] + [(w, b["cond"], b["note"]) for w, b in allb]
    bad = [e for e in eq if e[1] and e[1] != "ดี"]
    sk.text(f"สภาพอุปกรณ์ · ดี {sum(e[1] == 'ดี' for e in eq)} · พอใช้ {sum(e[1] == 'พอใช้' for e in eq)} · ชำรุด {sum(e[1] == 'ชำรุด' for e in eq)} · ยังไม่ระบุ {sum(not e[1] for e in eq)}", (14, y + 4), 9.5, True)
    for i, (w, c, n) in enumerate(bad): sk.text(f"• {w}: {c}" + (f" — {n}" if n else ""), (22, y + 22 + i * 15), 8.5, False, COND[c])
    y += 22 + len(bad) * 15 + 6
    sk.text("ค่าสมมติ (แบบสำรวจไม่ได้ถาม)", (14, y + 4), 9.5, True)
    for i, r in enumerate(d["assumed"]): sk.text("• " + r, (22, y + 22 + i * 15), 8.5, False, INK2)
    y += 22 + len(d["assumed"]) * 15 + 6
    if d["miss"]:
        sk.text("ข้อมูลที่ยังขาด", (14, y + 4), 9.5, True, RED)
        for i, m in enumerate(d["miss"]): sk.text("• " + m, (22, y + 22 + i * 15), 8.5, False, RED)
        y += 22 + len(d["miss"]) * 15 + 10
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
    sld(json.load(open(os.path.join(HERE, "sld_form_large.json"))), os.path.join(HERE, "sld_form_large.png"))
    print("ok")
