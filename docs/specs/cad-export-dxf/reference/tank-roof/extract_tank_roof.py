#!/usr/bin/env python3
"""Extract the PWA clear-water-tank roof PV layout (Top.dxf) into TCRoof components.

Usage: python3 extract_tank_roof.py <Top.dxf> <out-dir>

Writes (relative to <out-dir>):
  roofs/pwa-tank-roof-40x26-240.json   layout: roof, tables, posts, rafters, rails, bracing, modules, obstacles, BOQ
  catalog-tank-roof.json               new component entries to merge into catalog.json
  svg/<id>-<view>.svg                  one symbol per component view (mm, origin bottom-left, black strokes)
  svg/pwa-tank-roof-40x26-240-plan.svg whole roof layout
  tcroof-tank-mount-blocks.dxf         blocks TCR_<ID>_<VIEW> in mm + the roof layout rebuilt from them

The source is drawn in metres (one drawing unit = 1 m although $INSUNITS = 4/mm).
All output is mm, origin = bottom-left corner of the roof outline (layer กรอบหลังคา).
"""
import json, math, sys, collections
from pathlib import Path
import ezdxf
from ezdxf import path as ezpath
from ezdxf.math import Matrix44

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])
(OUT / "svg").mkdir(parents=True, exist_ok=True)
(OUT / "roofs").mkdir(parents=True, exist_ok=True)

doc = ezdxf.readfile(SRC)
msp = doc.modelspace()
M = 1000.0  # m -> mm

roof = next(e for e in msp.query('LWPOLYLINE[layer=="กรอบหลังคา"]') if len(e) == 4 and e.dxf.color == 1)
rp = [v[:2] for v in roof.get_points()]
X0, Y0 = min(p[0] for p in rp), min(p[1] for p in rp)
ROOF_W = round((max(p[0] for p in rp) - X0) * M)
ROOF_D = round((max(p[1] for p in rp) - Y0) * M)


def mm(x, y):
    return round((x - X0) * M), round((y - Y0) * M)


def bbox(e):
    p = [v[:2] for v in e.get_points()]
    xs, ys = [q[0] for q in p], [q[1] for q in p]
    a, b = mm(min(xs), min(ys))
    c, d = mm(max(xs), max(ys))
    return a, b, c, d


# ---------------------------------------------------------------- members
posts = [(*mm(e.dxf.insert.x, e.dxf.insert.y), e.dxf.xscale < 0)
         for e in msp.query('INSERT[name=="G$C91944CF8"]')]
pv = [bbox(e) for e in msp.query('LWPOLYLINE[layer=="PV"]')]
mt = list(msp.query('LWPOLYLINE[layer=="MT PV Tank"]'))
rafters = [bbox(e) for e in mt if e.dxf.color == 1]
rails = [bbox(e) for e in mt if e.dxf.color == 2]
brace = [bbox(e) for e in mt if e.dxf.color == 4]

# group into tables by rail x-span (4 rails per table)
rail_x = sorted(set(r[0] for r in rails))
tables_x = [rail_x[i:i + 4] for i in range(0, len(rail_x), 4)]
assert all(len(t) == 4 for t in tables_x), tables_x

MOD_W, MOD_D = (pv[0][2] - pv[0][0]), (pv[0][3] - pv[0][1])
DATASHEET_L = 2278  # ZNShine ZXM7-UHLDD144-570 long side
tilt = math.degrees(math.acos(min(1, MOD_W / DATASHEET_L)))

tables = []
letters = "ABCDEFGHIJ"
for i, rx in enumerate(tables_x):
    x_lo, x_hi = rx[0] - 500, rx[-1] + 500
    t_rails = [r for r in rails if x_lo <= r[0] <= x_hi]
    t_mods = [m for m in pv if x_lo <= (m[0] + m[2]) / 2 <= x_hi]
    t_posts = [p for p in posts if x_lo - 600 <= p[0] <= x_hi + 600]
    t_raft = [r for r in rafters if x_lo - 600 <= (r[0] + r[2]) / 2 <= x_hi + 600]
    t_br = [b for b in brace if x_lo - 600 <= b[0] <= x_hi + 600]
    post_lines = sorted(set(p[0] for p in t_posts))
    # sub-arrays = distinct rail y-runs
    runs = sorted(set((r[1], r[3]) for r in t_rails))
    subarrays = []
    for (y0, y1) in runs:
        mods = [m for m in t_mods if y0 <= m[1] and m[3] <= y1]
        rows = sorted(set(m[1] for m in mods))
        cols = sorted(set(m[0] for m in mods))
        subarrays.append({
            "railRunMm": {"y0": y0, "y1": y1, "length": y1 - y0},
            "modules": len(mods), "rows": len(rows), "modulesPerRow": len(cols),
            "rowPitchMm": (rows[1] - rows[0]) if len(rows) > 1 else None,
        })
    # bracing: members come in pairs 152 c/c; one set per braced bay
    br_sets = sorted(set((b[1], b[3]) for b in t_br))
    br_line_x = sorted(set(b[0] for b in t_br))
    tables.append({
        "id": f"T{letters[i]}",
        "xRangeMm": [min(m[0] for m in t_mods), max(m[2] for m in t_mods)],
        "postLinesXMm": post_lines,
        "postLineSpacingMm": post_lines[1] - post_lines[0],
        "postsYMm": sorted(set(p[1] for p in t_posts)),
        "postsMirrored": any(p[2] for p in t_posts),
        "posts": len(t_posts),
        "rafters": len(t_raft),
        "rafterXMm": [min(r[0] for r in t_raft), max(r[2] for r in t_raft)],
        "railsXMm": rx,
        "rails": len(t_rails),
        "railRuns": subarrays,
        "modules": len(t_mods),
        "bracedBays": [{"y0": a, "y1": b} for a, b in br_sets],
        "bracingLineXMm": br_line_x,
    })

assert sum(t["modules"] for t in tables) == len(pv)
assert sum(t["posts"] for t in tables) == len(posts)


def bay_list(ys):
    return [ys[i + 1] - ys[i] for i in range(len(ys) - 1)]


for t in tables:
    t["postBaysYMm"] = bay_list(t["postsYMm"])

# ---------------------------------------------------------------- roof items
hatches, vents = [], []
for e in msp.query('LWPOLYLINE[layer=="กรอบหลังคา"]'):
    if e is roof:
        continue
    hatches.append(bbox(e))
for c in msp.query('CIRCLE[layer=="กรอบหลังคา"]'):
    x, y = mm(c.dxf.center.x, c.dxf.center.y)
    vents.append({"x": x, "y": y, "diaMm": round(c.dxf.radius * 2 * M)})
station = bbox(next(iter(msp.query('LWPOLYLINE[layer=="0"]'))))
raceway = [[mm(*v[:2]) for v in e.get_points()] for e in msp.query('LWPOLYLINE[layer=="Raceway"]')]
water = [[mm(*v[:2]) for v in e.get_points()] for e in msp.query('LWPOLYLINE[layer=="Water"]')]
taps = [dict(zip("xy", mm(c.dxf.center.x, c.dxf.center.y))) for c in msp.query('CIRCLE[layer=="Water"]')]


def plen(pts):
    return round(sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)))


rail_len = collections.Counter(r[3] - r[1] for r in rails)
raft_len = collections.Counter(r[2] - r[0] for r in rafters)
brace_len = collections.Counter(b[3] - b[1] for b in brace)
boq = {
    "pvModules": len(pv),
    "posts": len(posts),
    "rafters": {"count": len(rafters), "planLengthMm": dict(raft_len),
                "trueLengthMmAtTilt": round(4000 / math.cos(math.radians(tilt)))},
    "rails": {"count": len(rails), "byLengthMm": {str(k): v for k, v in sorted(rail_len.items())},
              "totalM": round(sum(k * v for k, v in rail_len.items()) / 1000, 2)},
    "bracingMembers": {"count": len(brace), "planLengthMm": dict(brace_len),
                       "totalPlanM": round(sum(k * v for k, v in brace_len.items()) / 1000, 2)},
    "cableRacewayM": round(sum(plen(r) for r in raceway) / 1000, 2),
    "waterPipeM": round(sum(plen(w) for w in water) / 1000, 2),
    "waterTaps": len(taps),
}

layout = {
    "schemaVersion": 1,
    "id": "pwa-tank-roof-40x26-240",
    "name": "PV array on clear-water tank roof 40 x 26 m, 240 modules",
    "nameTh": "แผงโซลาร์บนหลังคาถังน้ำใส 40 x 26 ม. 240 แผง",
    "units": "mm",
    "origin": "bottom-left corner of the roof outline; +x right, +y up as drawn (north not marked)",
    "source": {"file": SRC.name, "lastSavedBy": doc.header.get("$LASTSAVEDBY"),
               "drawingUnits": "metres (header says mm)"},
    "view": "plan only; no elevation or section in the source, so post heights and tilt are not drawn",
    "roof": {"widthMm": ROOF_W, "depthMm": ROOF_D},
    "module": {
        "componentId": "pv-module-plan-2199x1134",
        "moduleSpec": "components/modules/znshine-zxm7-uhldd144-570.json",
        "planMm": {"width": MOD_W, "depth": MOD_D},
        "orientation": "long side along x, 2 modules across each table",
        "inferredTiltDeg": round(tilt, 1),
        "tiltNote": f"Inferred, not drawn: plan length {MOD_W} vs datasheet 2278 gives acos({MOD_W}/2278). "
                    "Valid only if the module is the ZXM7-UHLDD144 and the drawn length is its tilted projection.",
    },
    "mounting": {
        "post": "pv-mount-post-300",
        "rafter": "pv-mount-rafter-4000",
        "rail": "pv-mount-rail-48",
        "bracing": "pv-mount-bracing-pair",
        "railsPerModule": 2,
        "railInsetFromModuleEdgeMm": 400,
        "railSpacingUnderModuleMm": 1400,
        "rafterOverhangPastPostMm": 600,
        "rafterSpacingYMm": "= post bay (2700 typical)",
        "notes": "Two post lines per table, 2800 apart in x (posts mirrored, xscale -1, on tables TF and TG). "
                 "Rafters 4000 (plan) run in x across both posts; 4 rails run in y on top of the rafters. "
                 "Paired members 40 wide at 152 c/c along one post line in alternate bays = bracing (type not stated).",
    },
    "tables": tables,
    "obstacles": {
        "hatches1000": [{"x0": h[0], "y0": h[1], "x1": h[2], "y1": h[3]} for h in hatches],
        "vents": vents,
        "inverterStation": {"x0": station[0], "y0": station[1], "x1": station[2], "y1": station[3],
                            "sizeMm": [station[2] - station[0], station[3] - station[1]],
                            "matchesStation": "pwa-inverter-station-shelter-125k (6.0 x 2.5 m)"},
    },
    "raceway": {"widthDrawnMm": 100, "polylines": raceway},
    "waterCleaning": {"pipe": water, "taps": taps},
    "boq": boq,
}
(OUT / "roofs" / "pwa-tank-roof-40x26-240.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2))

# ---------------------------------------------------------------- symbols
def block_paths(block, xf=Matrix44()):
    out = []
    for e in block:
        if e.dxftype() in ("POINT", "MTEXT", "TEXT", "INSERT", "WIPEOUT"):
            continue
        try:
            p = ezpath.make_path(e).transform(xf)
        except Exception:
            continue
        out.append([(v.x, v.y) for v in p.flattening(0.0005)])
    return out


def svg_write(name, polys, scale=1.0, stroke=1.0):
    xs = [x for p in polys for x, _ in p]; ys = [y for p in polys for _, y in p]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    w, h = (x1 - x0) * scale, (y1 - y0) * scale
    d = []
    for p in polys:
        pts = " ".join(f"{(x - x0) * scale:.2f},{(y1 - y) * scale:.2f}" for x, y in p)
        d.append(f'<polyline points="{pts}"/>')
    (OUT / "svg" / name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.2f} {h:.2f}" width="{w:.0f}mm" height="{h:.0f}mm">'
        f'<g fill="none" stroke="#000" stroke-width="{stroke}" stroke-linejoin="round">{"".join(d)}</g></svg>')
    return round(w), round(h)


SYM = {}
S = Matrix44.scale(M, M, 1)
post_blk = doc.blocks["G$C91944CF8"]
SYM["pv-mount-post-300"] = block_paths(post_blk, S)
inv_blk = doc.blocks["G$C144A2F4D"]
SYM["inverter-symbol-plan"] = block_paths(inv_blk, S)
rect = lambda w, h: [[(0, 0), (w, 0), (w, h), (0, h), (0, 0)]]
SYM["pv-module-plan-2199x1134"] = rect(MOD_W, MOD_D)
SYM["tank-roof-hatch-1000"] = rect(1000, 1000) + [[(0, 0), (1000, 1000)], [(0, 1000), (1000, 0)]]
SYM["tank-roof-vent-1600"] = [[(800 * math.cos(a / 64 * 2 * math.pi), 800 * math.sin(a / 64 * 2 * math.pi)) for a in range(65)]]
SYM["pv-mount-rafter-4000"] = rect(4000, 50)
SYM["pv-mount-rail-48"] = rect(1000, 48)
SYM["pv-mount-bracing-pair"] = rect(40, 1000) + [[(x + 152, y) for x, y in rect(40, 1000)[0]]]

bboxes = {k: svg_write(f"{k}-plan.svg", v) for k, v in SYM.items()}

# ---------------------------------------------------------------- block library + rebuilt layout
out = ezdxf.new("R2018", setup=True)
out.header["$INSUNITS"] = 4
for lay, col in [("PV", 5), ("PV-MOUNT-POST", 3), ("PV-MOUNT-RAFTER", 1), ("PV-MOUNT-RAIL", 2),
                 ("PV-MOUNT-BRACING", 4), ("ROOF", 7), ("ROOF-OBSTACLE", 8), ("RACEWAY", 210),
                 ("WATER", 90), ("STATION", 6)]:
    out.layers.add(lay, color=col)
blk_layer = {"pv-mount-post-300": "PV-MOUNT-POST", "pv-module-plan-2199x1134": "PV",
             "tank-roof-hatch-1000": "ROOF-OBSTACLE", "tank-roof-vent-1600": "ROOF-OBSTACLE",
             "pv-mount-rafter-4000": "PV-MOUNT-RAFTER", "pv-mount-rail-48": "PV-MOUNT-RAIL",
             "pv-mount-bracing-pair": "PV-MOUNT-BRACING", "inverter-symbol-plan": "STATION"}
for k, polys in SYM.items():
    b = out.blocks.new(f"TCR_{k.upper().replace('-', '_')}_PLAN")
    for p in polys:
        b.add_lwpolyline(p, dxfattribs={"layer": "0"})
lm = out.modelspace()
lm.add_lwpolyline([(0, 0), (ROOF_W, 0), (ROOF_W, ROOF_D), (0, ROOF_D)], close=True, dxfattribs={"layer": "ROOF"})
for m in pv:
    lm.add_blockref("TCR_PV_MODULE_PLAN_2199X1134_PLAN", (m[0], m[1]), dxfattribs={"layer": "PV"})
for e in msp.query('INSERT[name=="G$C91944CF8"]'):
    x, y = mm(e.dxf.insert.x, e.dxf.insert.y)
    lm.add_blockref("TCR_PV_MOUNT_POST_300_PLAN", (x, y),
                    dxfattribs={"layer": "PV-MOUNT-POST", "rotation": e.dxf.rotation, "xscale": e.dxf.xscale})
for r in rafters:
    lm.add_lwpolyline([(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])], close=True, dxfattribs={"layer": "PV-MOUNT-RAFTER"})
for r in rails:
    lm.add_lwpolyline([(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])], close=True, dxfattribs={"layer": "PV-MOUNT-RAIL"})
for b in brace:
    lm.add_lwpolyline([(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])], close=True, dxfattribs={"layer": "PV-MOUNT-BRACING"})
for h in hatches:
    lm.add_blockref("TCR_TANK_ROOF_HATCH_1000_PLAN", (h[0], h[1]), dxfattribs={"layer": "ROOF-OBSTACLE"})
for v in vents:
    lm.add_blockref("TCR_TANK_ROOF_VENT_1600_PLAN", (v["x"], v["y"]), dxfattribs={"layer": "ROOF-OBSTACLE"})
lm.add_lwpolyline([(station[0], station[1]), (station[2], station[1]), (station[2], station[3]), (station[0], station[3])],
                  close=True, dxfattribs={"layer": "STATION"})
for r in raceway:
    lm.add_lwpolyline(r, dxfattribs={"layer": "RACEWAY", "const_width": 100})
for w in water:
    lm.add_lwpolyline(w, dxfattribs={"layer": "WATER", "const_width": 100})
for t in taps:
    lm.add_circle((t["x"], t["y"]), 235, dxfattribs={"layer": "WATER"})
out.saveas(OUT / "tcroof-tank-mount-blocks.dxf")

# whole-roof overview svg (scale 1 svg unit = 1 mm)
over = [rect(ROOF_W, ROOF_D)[0]]
over += [rect(m[2] - m[0], m[3] - m[1])[0] for m in []]
def box(a, b, c, d): return [(a, b), (c, b), (c, d), (a, d), (a, b)]
over += [box(*m) for m in pv] + [box(*r) for r in rafters] + [box(*r) for r in rails] + [box(*b) for b in brace]
over += [box(*h) for h in hatches] + [box(*station)]
over += [[(v["x"] + 800 * math.cos(a / 48 * 2 * math.pi), v["y"] + 800 * math.sin(a / 48 * 2 * math.pi)) for a in range(49)] for v in vents]
for e in msp.query('INSERT[name=="G$C91944CF8"]'):
    over += [[(x + (e.dxf.insert.x - X0) * M, y + (e.dxf.insert.y - Y0) * M) for x, y in rect(300, 300)[0]]]
    over[-1] = [(x - 150, y - 150) for x, y in over[-1]]
over += raceway + water
svg_write("pwa-tank-roof-40x26-240-plan.svg", over, scale=1.0, stroke=20)

# ---------------------------------------------------------------- catalog entries
src_ref = lambda blk: {"file": SRC.name, "block": blk}
view = lambda k, blk: {"plan": {"svg": f"svg/{k}-plan.svg", "dxfBlock": f"TCR_{k.upper().replace('-', '_')}_PLAN",
                                "bboxMm": {"width": bboxes[k][0], "height": bboxes[k][1]}, "source": src_ref(blk)}}
cat = [
    {"id": "pv-mount-post-300", "kind": "mounting", "name": "PV mounting post with 300 base plate (plan)",
     "nameTh": "เสาขาตั้งโครงแผงพร้อมเพลทฐาน 300",
     "dimensionsMm": {"width": 300, "depth": 300},
     "basePlateMm": {"width": 299, "depth": 299},
     "cleatMm": {"width": 150, "depth": 112, "cornerRadius": 15, "slots": {"count": 2, "widthMm": 14, "lengthMm": 49, "spacingMm": 114}},
     "columnMm": {"note": "two 50 x 50 boxes with a 12 gap between flanges at ±22 / ±26; reads as 2 x C-channel back-to-back, section not labelled"},
     "notes": "Measured from block G$C91944CF8. Inserted at 270 deg; mirrored (xscale -1) on the two right-hand tables. Height not drawn.",
     "views": view("pv-mount-post-300", "G$C91944CF8")},
    {"id": "pv-mount-rafter-4000", "kind": "mounting", "name": "PV mounting rafter 4000 (plan)",
     "nameTh": "คานรับรางแผง ยาว 4.0 ม.",
     "dimensionsMm": {"planLength": 4000, "width": 50},
     "notes": "Runs in x over both posts of a table (post spacing 2800, 600 overhang each side). Plan length; true length depends on tilt (~4140 at 15 deg).",
     "views": view("pv-mount-rafter-4000", "LWPOLYLINE colour 1 on 'MT PV Tank'")},
    {"id": "pv-mount-rail-48", "kind": "mounting", "name": "PV module rail 48 wide (plan, 1000 module)",
     "nameTh": "รางยึดแผง กว้าง 48 มม.",
     "dimensionsMm": {"width": 48},
     "lengthsDrawnMm": sorted(rail_len),
     "notes": "Drawn 48.1 wide. 2 per module column, 1400 apart, 400 in from the module edges. Run length = rows x 1154 pitch + overhang.",
     "views": view("pv-mount-rail-48", "LWPOLYLINE colour 2 on 'MT PV Tank'")},
    {"id": "pv-mount-bracing-pair", "kind": "mounting", "name": "PV mounting bracing pair (plan)",
     "nameTh": "ค้ำยันโครงแผง (คู่)",
     "dimensionsMm": {"memberWidth": 40, "pairCentres": 152, "planLength": 2747},
     "notes": "Two 40-wide members 152 c/c on one post line, every other bay. Plan only, so it could be X-bracing or a longitudinal tie; section not labelled.",
     "views": view("pv-mount-bracing-pair", "LWPOLYLINE colour 4 on 'MT PV Tank'")},
    {"id": "pv-module-plan-2199x1134", "kind": "pvModule", "name": "PV module (plan, as drawn 2199 x 1134)",
     "moduleSpec": "components/modules/znshine-zxm7-uhldd144-570.json",
     "dimensionsMm": {"width": MOD_W, "depth": MOD_D},
     "notes": f"Drawn 2199 x 1134; ZXM7-UHLDD144 is 2278 x 1134, consistent with a ~{tilt:.0f} deg tilt projection.",
     "views": view("pv-module-plan-2199x1134", "LWPOLYLINE on 'PV'")},
    {"id": "tank-roof-hatch-1000", "kind": "existing", "name": "Tank roof hatch 1000 x 1000", "nameTh": "ฝาช่องเปิดหลังคาถัง",
     "dimensionsMm": {"width": 1000, "depth": 1000},
     "notes": "Existing; keep clear. Drawn as plain 1 m squares (grey) on the roof-outline layer; hatch vs. manhole not labelled.",
     "views": view("tank-roof-hatch-1000", "LWPOLYLINE colour 8 on 'กรอบหลังคา'")},
    {"id": "tank-roof-vent-1600", "kind": "existing", "name": "Tank roof vent D1600", "nameTh": "ช่องระบายอากาศหลังคาถัง",
     "dimensionsMm": {"diameter": 1600},
     "notes": "Existing; four circles R800 on the roof-outline layer, unlabelled (vent/ventilator assumed).",
     "views": view("tank-roof-vent-1600", "CIRCLE colour 8 on 'กรอบหลังคา'")},
    {"id": "inverter-symbol-plan", "kind": "annotation", "name": "Inverter location symbol",
     "views": view("inverter-symbol-plan", "G$C144A2F4D")},
]
(OUT / "catalog-tank-roof.json").write_text(json.dumps(cat, ensure_ascii=False, indent=2))
print(json.dumps({"tables": [(t["id"], t["modules"], t["posts"], t["rafters"], t["rails"], len(t["bracedBays"])) for t in tables],
                  "boq": boq, "tilt": round(tilt, 2), "hatches": hatches, "vents": vents, "station": station}, indent=1))
