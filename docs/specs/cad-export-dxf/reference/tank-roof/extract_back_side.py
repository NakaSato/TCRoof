#!/usr/bin/env python3
"""Add the back-side elevation (Back_Side.dxf) to the tank-roof extraction.

Usage: python3 extract_back_side.py <Back_Side.dxf> <out-dir>
Run after extract_tank_roof.py; it updates roofs/pwa-tank-roof-40x26-240.json,
catalog-tank-roof.json and tcroof-tank-mount-blocks.dxf in <out-dir>, and writes the new SVGs.
Drawing units are metres; output mm, elevation 0 = top of the tank roof slab (red line).
"""
import json, math, sys
from pathlib import Path
import ezdxf
from ezdxf import path as ezpath, disassemble, bbox
from ezdxf.math import Matrix44

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])
doc = ezdxf.readfile(SRC)
msp = doc.modelspace()
M = 1000.0

roof_line = max((e for e in msp.query('LINE') if e.dxf.color == 1 and abs(e.dxf.start.y - e.dxf.end.y) < 1e-9),
                key=lambda e: abs(e.dxf.start.x - e.dxf.end.x))
G = roof_line.dxf.start.y
post_bb = []
for e in msp.query('LWPOLYLINE'):
    if e.dxf.color != 7:
        continue
    p = [v[:2] for v in e.get_points()]
    xs, ys = [q[0] for q in p], [q[1] for q in p]
    post_bb.append((min(xs), (min(ys) - G) * M, (max(ys) - G) * M, (max(xs) - min(xs)) * M))
post_bb.sort()
X0 = post_bb[0][0] + post_bb[0][3] / 2 / M
post_x = [round((b[0] - X0) * M + b[3] / 2) for b in post_bb]

dims = sorted(round(e.get_measurement() * M) for e in msp.query('DIMENSION'))
notes = sorted({e.plain_text().replace("\n", " ").strip() for e in msp.query('MTEXT')})


def ext(e):
    b = bbox.extents([e])
    return ((b.extmin.x - X0) * M, (b.extmin.y - G) * M, (b.extmax.x - X0) * M, (b.extmax.y - G) * M)


rails = []
for p in disassemble.recursive_decompose([e for e in msp.query('INSERT') if e.dxf.name == '*U38']):
    if p.dxftype() == 'LWPOLYLINE':
        ys = [v[1] for v in p.get_points()]
        rails.append((round((min(ys) - G) * M), round((max(ys) - G) * M)))
rails.sort()
mods = []
for p in disassemble.recursive_decompose([[e for e in msp.query('INSERT') if e.dxf.name == 'G$CE4CDAED9'][0]]):
    if p.dxftype() == 'LWPOLYLINE':
        pts = [v[:2] for v in p.get_points()]
        mods.append((round((min(q[1] for q in pts) - G) * M), round((max(q[1] for q in pts) - G) * M)))
mods = sorted(set(mods))
mod_rise = mods[0][1] - mods[0][0]
tilt = math.degrees(math.asin(mod_rise / 2278))
braces = [tuple(round(v) for v in ext(e)) for e in msp.query('INSERT') if e.dxf.name == '*U6']
feet = [tuple(round(v) for v in ext(e)) for e in msp.query('INSERT') if e.dxf.name == 'AG2-B02正视图']
upstand = [tuple(round(v) for v in ext(e)) for e in msp.query('LWPOLYLINE') if e.dxf.color == 8]

elev = {
    "source": {"file": SRC.name, "drawingUnits": "metres"},
    "view": "back side (high side), looking along +x. 4 rear posts of one table with a break line between posts 2 and 3.",
    "datum": "0 = top of tank roof slab",
    "postXMm": post_x,
    "postBayMm": "2700 (drawn 2693)",
    "concreteToppingMm": {"width": 300, "depth": 300, "height": 150, "note": notes},
    "postFootBracket": {"block": "AG2-B02正视图", "widthMm": feet[0][2] - feet[0][0], "heightMm": feet[0][3] - feet[0][1]},
    "postMm": {"width": round(post_bb[0][3]), "bottom": round(post_bb[0][1]), "top": round(post_bb[0][2]),
               "aboveTopping": round(post_bb[0][2] - 150), "dimensioned": 1851},
    "overallHeightMm": {"dimensioned": 2248, "topOfModulesDrawn": mods[-1][1]},
    "railsDrawnMm": [{"bottom": a, "top": b} for a, b in rails],
    "railSectionHeightDrawnMm": rails[0][1] - rails[0][0],
    "modulesDrawnMm": [{"bottom": a, "top": b} for a, b in mods],
    "moduleLowEdgeMm": mods[0][0],
    "tiltFromElevationDeg": round(tilt, 1),
    "xBracing": {"block": "*U6", "diagonals": len(braces), "lowNodeMm": braces[0][1], "highNodeMm": braces[0][3],
                 "spanMm": braces[0][2] - braces[0][0], "bays": "alternate (bay 1-2 and 3-4)"},
    "unidentifiedUpstand": {"note": "hatched box 1500 x 600 on a 600 x 400 base, 1000 high, sitting on the roof next to post 1; not labelled",
                            "boxesMm": [{"x0": u[0], "z0": u[1], "x1": u[2], "z1": u[3]} for u in upstand]},
    "dimensionsFound": dims,
    "conflicts": [
        "The 4 horizontal members are drawn evenly 340 apart in height (1015-2095); Side_View.dxf puts the rafter nodes at z = 2091 / 1625 / 1356 / 1072. Treat the back-view heights as schematic.",
        "The posts shown are the rear (high) vertical posts: 1851 above the topping here, 1998 from the slab in Side_View.dxf (1998 - 150 = 1848). The front line has no vertical post, only a V of struts (see section).",
        "Module width along y is drawn 1303 here vs 1134 in plan (hidden dashed outline).",
    ],
}
lay_p = OUT / "roofs" / "pwa-tank-roof-40x26-240.json"
lay = json.loads(lay_p.read_text())
lay["elevation"] = elev
lay["view"] = "plan (Top.dxf) + back-side elevation (Back_Side.dxf); no section across the tilt"
lay["module"]["tiltFromElevationDeg"] = round(tilt, 1)
lay["module"]["tiltNote"] = (f"Plan projection gives {lay['module']['inferredTiltDeg']} deg (2199 vs 2278); the back-side elevation gives "
                             f"{tilt:.1f} deg (vertical rise {mod_rise} per module). Agree on ~15 deg; tilt is not dimensioned.")
lay["mounting"]["bracing"] = "pv-mount-x-bracing"
lay["mounting"]["concreteTopping"] = "concrete-topping-300x300x150"
lay["mounting"]["footBracket"] = "pv-mount-foot-bracket-ag2-b02"
lay["source"]["elevationFile"] = SRC.name
lay["boq"]["concreteToppings"] = lay["boq"]["posts"]
lay["boq"]["concreteM3"] = round(lay["boq"]["posts"] * 0.3 * 0.3 * 0.15, 3)
lay["boq"]["footBrackets"] = lay["boq"]["posts"]
lay["boq"]["xBracingSets"] = lay["boq"]["bracingMembers"]["count"] // 2
lay["boq"]["rearPostAboveToppingMm"] = 1851
lay_p.write_text(json.dumps(lay, ensure_ascii=False, indent=2))


# ---------------------------------------------------------------- symbols
def polys_of(entities, xf):
    out = []
    for e in disassemble.recursive_decompose(entities):
        if e.dxftype() in ("POINT", "MTEXT", "TEXT", "WIPEOUT", "HATCH", "REGION", "ATTRIB", "LEADER", "DIMENSION"):
            continue
        try:
            p = ezpath.make_path(e).transform(xf)
        except Exception:
            continue
        pts = [(v.x, v.y) for v in p.flattening(0.0005 * M)]
        if len(pts) > 1:
            out.append(pts)
    return out


def svg_write(name, polys, stroke=1.0):
    xs = [x for p in polys for x, _ in p]; ys = [y for p in polys for _, y in p]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    d = "".join('<polyline points="' + " ".join(f"{x - x0:.2f},{y1 - y:.2f}" for x, y in p) + '"/>' for p in polys)
    (OUT / "svg" / name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {x1 - x0:.2f} {y1 - y0:.2f}" width="{x1 - x0:.0f}mm" height="{y1 - y0:.0f}mm">'
        f'<g fill="none" stroke="#000" stroke-width="{stroke}" stroke-linejoin="round">{d}</g></svg>')
    return round(x1 - x0), round(y1 - y0)


XF = Matrix44.translate(-X0, -G, 0) @ Matrix44.scale(M, M, 1)
foot = [e for e in msp.query('INSERT') if e.dxf.name == 'AG2-B02正视图' and e.dxf.xscale > 0][0]
fx = foot.dxf.insert
SYM = {
    "pv-mount-foot-bracket-ag2-b02-elevation": polys_of([foot], Matrix44.translate(-fx.x, -fx.y, 0) @ Matrix44.scale(M, M, 1)),
    "concrete-topping-300x300x150-elevation": [[(0, 0), (300, 0), (300, 150), (0, 150), (0, 0)]],
    "pv-mount-post-elevation": [[(0, 0), (50, 0), (50, 1851), (0, 1851), (0, 0)]],
}
br = [e for e in msp.query('INSERT') if e.dxf.name == '*U6'][0]
bb = bbox.extents([br])
SYM["pv-mount-x-bracing-elevation"] = polys_of([br], Matrix44.translate(-bb.extmin.x, -bb.extmin.y, 0) @ Matrix44.scale(M, M, 1))
skip = {"MTEXT", "LEADER", "DIMENSION", "HATCH", "REGION"}
SYM["pwa-tank-roof-40x26-240-back-elevation"] = polys_of([e for e in msp if e.dxftype() not in skip], XF)
sizes = {k: svg_write(f"{k}.svg", v, 10 if "roof" in k else 1) for k, v in SYM.items()}

# ---------------------------------------------------------------- catalog
cat_p = OUT / "catalog-tank-roof.json"
cat = json.loads(cat_p.read_text())
cat = [c for c in cat if c["id"] != "pv-mount-bracing-pair"]
v = lambda k, view, blk: {view: {"svg": f"svg/{k}.svg", "dxfBlock": "TCR_" + k.upper().replace("-", "_"),
                                 "bboxMm": {"width": sizes[k][0], "height": sizes[k][1]}, "source": {"file": SRC.name, "block": blk}}}
for c in cat:
    if c["id"] == "pv-mount-post-300":
        c["heightMm"] = {"aboveTopping": 1851, "source": "Back_Side.dxf, rear (high) post line"}
        c["columnMm"]["elevationWidth"] = 50
        c["views"].update(v("pv-mount-post-elevation", "elevation", "LWPOLYLINE colour 7"))
        c["notes"] += " Sits on a 300x300x150 concrete topping via an AG2-B02 foot bracket."
cat += [
    {"id": "pv-mount-x-bracing", "kind": "mounting", "name": "PV mounting X-bracing (one bay)", "nameTh": "ค้ำยันไขว้ 1 ช่วงเสา",
     "dimensionsMm": {"bay": 2700, "lowNode": elev["xBracing"]["lowNodeMm"], "highNode": elev["xBracing"]["highNodeMm"],
                      "planMemberWidth": 40, "planPairCentres": 152, "planLength": 2747},
     "notes": "Plan shows the two diagonals as 40-wide members 152 c/c; elevation shows an X between posts from z=376 to 1890, in alternate bays on one post line. Member section not labelled.",
     "views": {**v("pv-mount-x-bracing-elevation", "elevation", "*U6"),
               "plan": {"svg": "svg/pv-mount-bracing-pair-plan.svg", "dxfBlock": "TCR_PV_MOUNT_BRACING_PAIR_PLAN",
                        "bboxMm": {"width": 192, "height": 1000}, "source": {"file": "Top.dxf", "block": "LWPOLYLINE colour 4 on 'MT PV Tank'"}}}},
    {"id": "pv-mount-foot-bracket-ag2-b02", "kind": "mounting", "name": "Post foot bracket AG2-B02", "nameTh": "ขายึดฐานเสา AG2-B02",
     "dimensionsMm": {"width": sizes["pv-mount-foot-bracket-ag2-b02-elevation"][0], "height": sizes["pv-mount-foot-bracket-ag2-b02-elevation"][1]},
     "notes": "Supplier block named 'AG2-B02正视图' (front view); inserted at 0.001 (source in mm). Matches the 150x112 slotted cleat in plan.",
     "views": v("pv-mount-foot-bracket-ag2-b02-elevation", "elevation", "AG2-B02正视图")},
    {"id": "concrete-topping-300x300x150", "kind": "structure", "name": "Concrete topping 300x300x150", "nameTh": "ฐานคอนกรีตทับหน้า 300x300x150",
     "dimensionsMm": {"width": 300, "depth": 300, "height": 150},
     "notes": "Labelled 'CONCRETE TOPPING 300X300X150 mm.' under every post; cast on the tank roof slab.",
     "views": v("concrete-topping-300x300x150-elevation", "elevation", "LWPOLYLINE colour 256 + HATCH")},
]
cat_p.write_text(json.dumps(cat, ensure_ascii=False, indent=2))

# ---------------------------------------------------------------- dxf blocks
dxf_p = OUT / "tcroof-tank-mount-blocks.dxf"
out = ezdxf.readfile(dxf_p)
for k, polys in SYM.items():
    name = "TCR_" + k.upper().replace("-", "_")
    if name in out.blocks:
        continue
    b = out.blocks.new(name)
    for p in polys:
        b.add_lwpolyline(p)
# place the elevation below the plan for reference
out.layers.add("ELEVATION", color=7) if "ELEVATION" not in out.layers else None
out.modelspace().add_blockref("TCR_PWA_TANK_ROOF_40X26_240_BACK_ELEVATION", (0, -6000), dxfattribs={"layer": "ELEVATION"})
out.saveas(dxf_p)
print(json.dumps({k: elev[k] for k in ("postXMm", "postMm", "railsDrawnMm", "modulesDrawnMm", "tiltFromElevationDeg", "xBracing", "unidentifiedUpstand")}, ensure_ascii=False, indent=1))
print(sizes)
