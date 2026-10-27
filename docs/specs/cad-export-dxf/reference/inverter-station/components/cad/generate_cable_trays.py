"""Parametric 2D cable tray / cable ladder blocks for TCRoof.

Run after the extractor and mfr.py:  python3 tray.py <out-dir>   (out-dir = .../components/cad)

Geometry set = generic sizes below + every straight-tray size in trays/*.json.
Views are shared where the drawing depends on one dimension only:
  section    per W x H         svg/tray-section-<W>x<H>.svg
  plan       per W (+ perf)    svg/tray-plan-<perforated|solid>-w<W>.svg
  plan-cover per W             svg/tray-plan-cover-w<W>.svg
  side       per H (+ perf)    svg/tray-side-<perforated|solid>-h<H>.svg
Tray plan/side blocks are 1000 mm modules (slot pitch 50); ladder modules are 1200 mm (rung pitch 300). Both tile.
"""
import glob, json, os, re, sys
import ezdxf
from ezdxf import bbox
from ezdxf.addons.drawing import RenderContext, Frontend, svg, layout
from ezdxf.addons.drawing.config import Configuration, BackgroundPolicy, ColorPolicy, LineweightPolicy, LinePolicy

OUT = sys.argv[1]
L = 1000
T = 1.5           # drawn sheet thickness (2D only; real value per manufacturer type)
LIP = 12
SLOT_L, SLOT_W, SLOT_PITCH = 25, 7, 50
COVER_DROP, COVER_GAP = 15, 1
# cable ladder, per the supplier detail drawing (rung C 25x15x1.25, 11 slot, pitch 300;
# rail: 9x15 slots @50, D8.5 @100, D5.4 @50). Rail thickness t is not given -> RAIL_T(H).
LADDER_L = 1200                     # module = 4 rung pitches
RUNG_W, RUNG_D, RUNG_T, RUNG_OPEN, RUNG_PITCH = 25, 15, 1.25, 11, 300
RAIL_TOP_FLANGE, RAIL_TOP_LIP, RAIL_BOTTOM_FLANGE = 12, 6, 30      # assumed from the isometric
RAIL_SLOT = (15, 9); RAIL_SLOT_PITCH = 50                          # 9x15 oblong, long axis along the rail
HOLE_FIX, HOLE_FIX_PITCH = 8.5, 100                                 # bottom flange
HOLE_SMALL, HOLE_SMALL_PITCH = 5.4, 50                              # web, lower row
def RAIL_T(H): return 2.0 if H >= 100 else 1.5

GENERIC_PERFORATED = [(100, 50), (100, 100), (150, 100), (200, 100), (300, 100)]   # (W, H)
LADDER = [(W, H) for H in (60, 100) for W in (200, 300, 400, 500, 600)]

# ---------------------------------------------------------------- size set
mfr_files = sorted(glob.glob(f"{OUT}/trays/*.json"))
geoms = {}  # geometryId -> dict(W, H, perforated, sources=set())
for W, H in GENERIC_PERFORATED:
    geoms[f"perforated-tray-{W}x{H}"] = dict(W=W, H=H, perforated=True, sources=set())
for f in mfr_files:
    m = json.load(open(f))
    short = m["manufacturer"].split()[0]
    for fam in m["families"]:
        for t in fam["types"]:
            gid = t.get("geometryId")
            if gid:
                g = geoms.setdefault(gid, dict(W=t["widthMm"], H=t["heightMm"], perforated=gid.startswith("perforated"), sources=set()))
                g["sources"].add(f"{short} {fam['code']}")

doc = ezdxf.new("R2018", setup=True, units=4)
doc.header["$INSUNITS"] = 4
for name, color, lt in [("TRAY", 7, "Continuous"), ("TRAY-SLOT", 8, "Continuous"),
                        ("TRAY-COVER", 5, "Continuous"), ("TRAY-HIDDEN", 8, "DASHED")]:
    doc.layers.add(name, color=color, linetype=lt)
doc.header["$LTSCALE"] = 8

def slot(blk, cx, cy, length, width, horizontal=True, layer="TRAY-SLOT"):
    r, s = width / 2, (length - width) / 2
    if horizontal:
        pts = [(cx - s, cy - r, 0), (cx + s, cy - r, 1), (cx + s, cy + r, 0), (cx - s, cy + r, 1)]
    else:
        pts = [(cx + r, cy - s, 0), (cx + r, cy + s, 1), (cx - r, cy + s, 0), (cx - r, cy - s, 1)]
    blk.add_lwpolyline(pts, format="xyb", close=True, dxfattribs={"layer": layer})

def rect(blk, x0, y0, x1, y1, layer="TRAY"):
    blk.add_lwpolyline([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], close=True, dxfattribs={"layer": layer})

def line(blk, a, b, layer="TRAY"):
    blk.add_line(a, b, dxfattribs={"layer": layer})

def slot_rows(W):
    n = max(1, int((W - 40) // 30) + 1)
    return [W / 2] if n == 1 else [20 + i * (W - 40) / (n - 1) for i in range(n)]

def side_rows(H):
    return [H * 0.5] if H <= 60 else [H * 0.3, H * 0.65]

shared = {}  # view key -> block name

def section_block(W, H):
    key = f"tray-section-{W}x{H}"
    if key in shared: return key
    b = doc.blocks.new(f"TCR_TRAY_SECTION_{W}X{H}")
    b.add_lwpolyline([(LIP, H), (0, H), (0, 0), (W, 0), (W, H), (W - LIP, H), (W - LIP, H - T),
                      (W - T, H - T), (W - T, T), (T, T), (T, H - T), (LIP, H - T)], close=True, dxfattribs={"layer": "TRAY"})
    g, c = COVER_GAP, T
    b.add_lwpolyline([(-g - c, H - COVER_DROP), (-g - c, H + c), (W + g + c, H + c), (W + g + c, H - COVER_DROP),
                      (W + g, H - COVER_DROP), (W + g, H), (-g, H), (-g, H - COVER_DROP)], close=True, dxfattribs={"layer": "TRAY-COVER"})
    shared[key] = b.name
    return key

def plan_block(W, perforated):
    key = f"tray-plan-{'perforated' if perforated else 'solid'}-w{W}"
    if key in shared: return key
    b = doc.blocks.new(f"TCR_TRAY_PLAN_{'PERF' if perforated else 'SOLID'}_W{W}")
    rect(b, 0, 0, L, W)
    for y in (T, LIP, W - LIP, W - T):
        line(b, (0, y), (L, y))
    if perforated:
        for y in slot_rows(W):
            for i in range(L // SLOT_PITCH):
                slot(b, SLOT_PITCH / 2 + i * SLOT_PITCH, y, SLOT_L, SLOT_W)
    shared[key] = b.name
    return key

def plan_cover_block(W):
    key = f"tray-plan-cover-w{W}"
    if key in shared: return key
    b = doc.blocks.new(f"TCR_TRAY_PLAN_COVER_W{W}")
    rect(b, 0, -COVER_GAP - T, L, W + COVER_GAP + T, layer="TRAY-COVER")
    for y in (0, W):
        line(b, (0, y), (L, y), layer="TRAY-HIDDEN")
    shared[key] = b.name
    return key

def side_block(H, perforated):
    key = f"tray-side-{'perforated' if perforated else 'solid'}-h{H}"
    if key in shared: return key
    b = doc.blocks.new(f"TCR_TRAY_SIDE_{'PERF' if perforated else 'SOLID'}_H{H}")
    rect(b, 0, 0, L, H)
    line(b, (0, H - T), (L, H - T))
    if perforated:
        for y in side_rows(H):
            for i in range(L // SLOT_PITCH):
                slot(b, SLOT_PITCH / 2 + i * SLOT_PITCH, y, SLOT_L, SLOT_W)
    rect(b, 0, H - COVER_DROP, L, H + T, layer="TRAY-COVER")
    shared[key] = b.name
    return key

def circle(blk, cx, cy, d, layer="TRAY-SLOT"):
    blk.add_circle((cx, cy), d / 2, dxfattribs={"layer": layer})

def rung_profile_block():
    key = "ladder-rung-profile"
    if key in shared: return key
    w, d, t, o = RUNG_W, RUNG_D, RUNG_T, RUNG_OPEN
    lip = (w - o) / 2
    b = doc.blocks.new("TCR_LADDER_RUNG_PROFILE")
    b.add_lwpolyline([(0, 0), (w, 0), (w, d), (w - lip, d), (w - lip, d - t), (w - t, d - t), (w - t, t),
                      (t, t), (t, d - t), (lip, d - t), (lip, d), (0, d)], close=True, dxfattribs={"layer": "TRAY"})
    shared[key] = b.name
    return key

def ladder_blocks(W, H):
    t = RAIL_T(H)
    tf, tl, bf = RAIL_TOP_FLANGE, RAIL_TOP_LIP, RAIL_BOTTOM_FLANGE
    LL = LADDER_L
    rungs = [RUNG_PITCH / 2 + i * RUNG_PITCH for i in range(LL // RUNG_PITCH)]
    keys = dict(**{"rung-profile": rung_profile_block()})

    # section: rails = web + outward top flange with down-turned lip + inward bottom flange;
    # rung (seen beyond the cut) sits on the bottom flanges between the webs
    key = f"ladder-section-{W}x{H}"
    b = doc.blocks.new(f"TCR_LADDER_SECTION_{W}X{H}")
    rail = [(-tf, H - tl), (-tf, H), (t, H), (t, t), (bf, t), (bf, 0), (0, 0), (0, H - t), (-tf + t, H - t), (-tf + t, H - tl)]
    b.add_lwpolyline(rail, close=True, dxfattribs={"layer": "TRAY"})
    b.add_lwpolyline([(W - x, y) for x, y in rail], close=True, dxfattribs={"layer": "TRAY"})
    rect(b, t, t, W - t, t + RUNG_D)
    line(b, (t, t + RUNG_D - RUNG_T), (W - t, t + RUNG_D - RUNG_T))
    shared[key] = b.name; keys["section"] = key

    # plan: top flanges + lips, bottom flanges with D8.5 fixing holes, rungs with their 11 mm slot
    key = f"ladder-plan-w{W}"
    if key not in shared:
        b = doc.blocks.new(f"TCR_LADDER_PLAN_W{W}")
        for side in (0, 1):
            f = (lambda y: y) if side == 0 else (lambda y: W - y)
            rect(b, 0, f(-tf), LL, f(0) if side == 0 else f(0))            # top flange outline (outside the web)
            line(b, (0, f(-tf + 2)), (LL, f(-tf + 2)))                       # lip edge
            line(b, (0, f(2)), (LL, f(2)))                                   # web inner face
            line(b, (0, f(bf)), (LL, f(bf)))                                 # bottom flange edge
            ycen = f((2 + bf) / 2)
            for x in range(HOLE_FIX_PITCH // 2, LL, HOLE_FIX_PITCH):
                if all(abs(x - r) > RUNG_W / 2 + HOLE_FIX for r in rungs):
                    circle(b, x, ycen, HOLE_FIX)
        for x in rungs:
            x0, x1 = x - RUNG_W / 2, x + RUNG_W / 2
            rect(b, x0, 2, x1, W - 2)
            for xo in (x - RUNG_OPEN / 2, x + RUNG_OPEN / 2):
                line(b, (xo, 2), (xo, W - 2))
        shared[key] = b.name
    keys["plan"] = key

    # side (outer face of the rail): top lip band, 9x15 slots @50, D5.4 @50 lower row, rungs behind (hidden)
    key = f"ladder-side-h{H}"
    if key not in shared:
        b = doc.blocks.new(f"TCR_LADDER_SIDE_H{H}")
        rect(b, 0, 0, LL, H)
        line(b, (0, H - tl), (LL, H - tl))
        y_slot = (H - tl + RUNG_D + t) / 2 + 3
        for x in range(RAIL_SLOT_PITCH // 2, LL, RAIL_SLOT_PITCH):
            slot(b, x, y_slot, RAIL_SLOT[0], RAIL_SLOT[1])
        y_small = t + RUNG_D / 2
        for x in range(HOLE_SMALL_PITCH // 2, LL, HOLE_SMALL_PITCH):
            if all(abs(x - r) > RUNG_W / 2 + HOLE_SMALL for r in rungs):
                circle(b, x, y_small, HOLE_SMALL)
        for x in rungs:
            rect(b, x - RUNG_W / 2, t, x + RUNG_W / 2, t + RUNG_D, layer="TRAY-HIDDEN")
        shared[key] = b.name
    keys["side"] = key
    return keys

# ---------------------------------------------------------------- build
comps = {}
for gid, g in sorted(geoms.items(), key=lambda kv: (not kv[1]["perforated"], kv[1]["W"], kv[1]["H"])):
    W, H, perf = g["W"], g["H"], g["perforated"]
    views = dict(section=section_block(W, H), plan=plan_block(W, perf), **{"plan-cover": plan_cover_block(W)},
                 side=side_block(H, perf))
    comps[gid] = dict(id=gid, kind="cableway", trayType="perforated" if perf else "solid",
                      name=f"{'Perforated' if perf else 'Solid-bottom'} cable tray {W}x{H}",
                      nameTh=f"รางเคเบิล{'แบบเจาะรู' if perf else 'ทึบ'} {W}x{H}",
                      crossSectionMm=dict(width=W, height=H), moduleLengthMm=L,
                      manufacturerSeries=sorted(g["sources"]), viewKeys=views,
                      notes="2D symbol. The cross-section and slot pattern are generic; real thickness and weight are on the manufacturer type in trays/*.json.")
for W, H in LADDER:
    gid = f"cable-ladder-{W}x{H}"
    comps[gid] = dict(id=gid, kind="cableway", trayType="ladder", name=f"Cable ladder {W}x{H}", nameTh=f"รางบันไดเคเบิล {W}x{H}",
                      crossSectionMm=dict(width=W, height=H), moduleLengthMm=LADDER_L, rungPitchMm=RUNG_PITCH,
                      rung=dict(profile="C", widthMm=RUNG_W, depthMm=RUNG_D, thicknessMm=RUNG_T, slotOpeningMm=RUNG_OPEN, pitchMm=RUNG_PITCH),
                      rail=dict(thicknessMm=RAIL_T(H), thicknessSource="assumed (t not dimensioned on the supplier drawing)",
                                webSlots=dict(sizeMm=list(RAIL_SLOT), pitchMm=RAIL_SLOT_PITCH),
                                fixingHoles=dict(diaMm=HOLE_FIX, pitchMm=HOLE_FIX_PITCH, location="bottom flange (interpreted)"),
                                smallHoles=dict(diaMm=HOLE_SMALL, pitchMm=HOLE_SMALL_PITCH, location="web, lower row (interpreted)"),
                                topFlangeMm=RAIL_TOP_FLANGE, bottomFlangeMm=RAIL_BOTTOM_FLANGE, flangeSource="estimated from the isometric"),
                      manufacturerSeries=[], viewKeys=ladder_blocks(W, H),
                      notes="Drawn to the supplier ladder detail (rung C 25x15x1.25 with 11 mm slot at 300; rail 9x15 slots at 50, D8.5 at 100, D5.4 at 50). Rail thickness and flange widths are not dimensioned there and are assumed. Plan/side module 1200 mm (4 rungs) tiles.")

cfg = Configuration(background_policy=BackgroundPolicy.OFF, color_policy=ColorPolicy.BLACK,
                    lineweight_policy=LineweightPolicy.RELATIVE_FIXED, min_lineweight=0.25,
                    line_policy=LinePolicy.ACCURATE, min_dash_length=0.1)

def to_svg(block_name, path):
    ents = list(doc.blocks.get(block_name))
    b = bbox.extents(ents)
    be = svg.SVGBackend()
    Frontend(RenderContext(doc), be, config=cfg).draw_entities(ents)
    page = layout.Page(max(b.size.x, 1), max(b.size.y, 1), layout.Units.mm, margins=layout.Margins.all(0))
    s = be.get_string(page, settings=layout.Settings(fit_page=True))
    s = re.sub(r'<rect fill="#[0-9a-fA-F]+" x="0" y="0"[^>]*/>', "", s, count=1)
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', s).group(1).split()]
    sw = min(max(vb[2], vb[3]) * (0.0015 if b.size.x > 650 else 0.012 if b.size.x < 60 else 0.003), 1000)
    s = re.sub(r"stroke-width: [0-9.]+;", f"stroke-width: {sw:.0f};", s)
    open(path, "w").write(s)
    return round(b.size.x), round(b.size.y)

os.makedirs(f"{OUT}/svg", exist_ok=True)
for old in glob.glob(f"{OUT}/svg/perforated-tray-*.svg") + glob.glob(f"{OUT}/svg/cable-ladder-*.svg"):
    os.remove(old)  # replaced by shared view files
sizes = {key: to_svg(bname, f"{OUT}/svg/{key}.svg") for key, bname in shared.items()}

for c in comps.values():
    c["views"] = {v: dict(svg=f"svg/{key}.svg", dxfBlock=shared[key], bboxMm=dict(width=sizes[key][0], height=sizes[key][1]),
                          source=dict(file="tcroof-cable-tray-blocks.dxf", block=shared[key]))
                  for v, key in c.pop("viewKeys").items()}

cat = json.load(open(f"{OUT}/catalog.json"))
keep = [c for c in cat["components"] if not re.match(r"(perforated|solid)-tray-|cable-ladder-", c["id"])]
allc = {c["id"]: c for c in keep}
allc.update(comps)
USAGE = {"ac-perforated-tray-100x100": ("perforated-tray-100x100", "AC", True),
         "ac-perforated-tray-200x100": ("perforated-tray-200x100", "AC", True),
         "dc-perforated-tray-100x100": ("perforated-tray-100x100", "DC", True),
         "ac-cable-ladder-200x100": ("cable-ladder-200x100", "AC", False)}
for uid, (pid, service, cover) in USAGE.items():
    allc[uid].update(productId=pid, service=service, withCover=cover, symbol=pid)
    allc[uid].pop("crossSectionMm", None); allc[uid].pop("cover", None)
cat["components"] = sorted(allc.values(), key=lambda c: (c["kind"], c["id"]))
cat["manufacturerCatalogues"] = [os.path.relpath(f, OUT) for f in mfr_files]
json.dump(cat, open(f"{OUT}/catalog.json", "w"), ensure_ascii=False, indent=2)

# readable DXF layout: one row per view family
msp = doc.modelspace()
rows = {}
for key, bname in shared.items():
    rows.setdefault(re.sub(r"-(w|h)?\d+(x\d+)?$", "", key), []).append(bname)
y = 0
for row, names in rows.items():
    msp.add_text(row, height=60, dxfattribs={"insert": (0, y + 250)})
    x = 0
    for n in names:
        bb = bbox.extents(doc.blocks.get(n))
        msp.add_blockref(n, (x - bb.extmin.x, y - bb.extmin.y))
        msp.add_text(n.replace("TCR_", ""), height=14, dxfattribs={"insert": (x, y - 40)})
        x += bb.size.x + 150
    y -= 900 if "section" not in row else 400
doc.saveas(f"{OUT}/tcroof-cable-tray-blocks.dxf")
print(len(comps), "tray/ladder components;", len(shared), "shared blocks/SVGs")
