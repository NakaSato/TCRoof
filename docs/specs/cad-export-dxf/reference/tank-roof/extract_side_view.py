#!/usr/bin/env python3
"""Add the side view / section across the tilt (Side_View.dxf) to the tank-roof extraction.

Usage: python3 extract_side_view.py <Side_View.dxf> <out-dir>
Run after extract_tank_roof.py and extract_back_side.py. Updates roofs/pwa-tank-roof-40x26-240.json,
catalog-tank-roof.json and tcroof-tank-mount-blocks.dxf, writes the new SVGs.
Drawing units are metres; output mm. Origin: foot of the rear (high) post of the first table, z = 0 on the tank roof slab.
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

slab = max((e for e in msp.query('LINE') if e.dxf.color == 8 and abs(e.dxf.start.y - e.dxf.end.y) < 1e-9 and abs(e.dxf.start.x - e.dxf.end.x) > 5),
           key=lambda e: e.dxf.start.y)  # upper of the two long grey lines = slab top
G = slab.dxf.start.y
rear_feet = sorted(e.dxf.insert.x for e in msp.query('INSERT') if e.dxf.name == 'G$C519ED97B')
X0 = rear_feet[0]
P = lambda v: (round((v.x - X0) * M), round((v.y - G) * M))


def ext(e):
    b = bbox.extents([e])
    return (*P(b.extmin), *P(b.extmax))


def first(name, k=0):
    return sorted((e for e in msp.query('INSERT') if e.dxf.name == name), key=lambda e: e.dxf.insert.x)[k]


raf = first('*U11')            # rafter, rotation 345 => 15 deg
tilt = round((360 - raf.dxf.rotation) % 360, 3)
raf_bb = ext(raf)
rear_post = ext(first('*U13'))
struts = {n: ext(first(n)) for n in ('*U15', '*U17', '*U21')}
modules = sorted((ext(e) for e in msp.query('INSERT') if e.dxf.name == 'A$C72243465'), key=lambda b: b[0])[:2]
front_foot = ext(first('AG5-B03'))
rear_foot = ext(first('G$C519ED97B'))

dims = []
for e in msp.query('DIMENSION'):
    a, b = P(e.dxf.defpoint2), P(e.dxf.defpoint3)
    dims.append({"value": round(e.get_measurement() * M), "p1": a, "p2": b})
dv = sorted({d["value"] for d in dims})

table_x = sorted({round((x - X0) * M) for x in rear_feet})

sec = {
    "source": {"file": SRC.name, "drawingUnits": "metres"},
    "view": "side view across the tilt, looking along y; two tables (rear post lines 5504 apart), high side on the left (-x in plan is the high side)",
    "datum": "x = 0 at the rear post of the first table, z = 0 = tank roof slab",
    "tiltDeg": tilt,
    "tiltSource": "rafter and module blocks inserted at 345 deg",
    "tablePitchMm": table_x[1] - table_x[0] if len(table_x) > 1 else None,
    "postLineSpacingMm": 2800,
    "gapBetweenTablesMm": 2704,
    "rearPost": {"heightFromSlabMm": rear_post[3] - rear_post[1], "dimensioned": 1998,
                 "note": "vertical, on 300x300x150 topping; the only vertical post in the frame"},
    "frontSupport": {"note": "no vertical post on the front (low) line: a V of two struts springs from one foot",
                     "footBracket": "AG5-B03", "footBracketMm": [front_foot[2] - front_foot[0], front_foot[3] - front_foot[1]]},
    "struts": [
        {"id": "rear-diagonal", "block": "*U15", "lengthMm": 2038, "from": "rear post foot", "toRafterNodeX": 1319, "bboxMm": struts['*U15']},
        {"id": "front-back", "block": "*U17", "lengthMm": 1396, "from": "front foot", "toRafterNodeX": 2285, "bboxMm": struts['*U17']},
        {"id": "front-forward", "block": "*U21", "lengthMm": 1148, "from": "front foot", "toRafterNodeX": 3348, "bboxMm": struts['*U21']},
    ],
    "rafter": {"lengthMm": 4000, "bboxMm": raf_bb, "highEndZMm": raf_bb[3], "lowEndZMm": raf_bb[1],
               "nodeSpacingAlongSlopeMm": [1400, 1000, 1100], "lowEndOverhangMm": 457,
               "note": "nodes: rear post top, then struts at 1400 / +1000 / +1100 along the slope"},
    "modules": {"count": 2, "orientation": "portrait, 2 up along the slope", "lengthAlongSlopeMm": 2280,
                "lowEdgeZMm": 985, "dimensionedLowEdge": "1.00", "topEdgeZMm": max(m[3] for m in modules),
                "bboxesMm": modules},
    "upstand": {"note": "same 1500 x 600 box on 600 x 400 base (1000 high) as in Back_Side.dxf, under the second table between its post lines",
                "x0": 6368, "x1": 7868},
    "dimensionsFound": dv,
}

lay_p = OUT / "roofs" / "pwa-tank-roof-40x26-240.json"
lay = json.loads(lay_p.read_text())
lay["section"] = sec
lay["source"]["sectionFile"] = SRC.name
lay["view"] = "plan (Top.dxf) + back-side elevation (Back_Side.dxf) + side section (Side_View.dxf)"
m = lay["module"]
m["tiltDeg"] = tilt
m["tiltNote"] = (f"{tilt:g} deg from Side_View.dxf (blocks at 345 deg). Cross-checks: plan length 2199 = 2280 x cos 15 (2202); "
                 f"Back_Side module rise gives {m.get('tiltFromElevationDeg')} deg.")
m.pop("inferredTiltDeg", None)
m["orientation"] = "portrait, 2 up along the slope (long side 2280 down the tilt, x in plan), 2 modules per rafter"
mt = lay["mounting"]
mt["frame"] = "per rafter: 1 vertical rear post (1998) + 3 struts (2038 rear diagonal, 1396 and 1148 from one front foot)"
mt["rafterOverhangPastPostMm"] = "457 at the low end (section); plan draws 600 each side"
mt["highSide"] = "the post line with the X-bracing (lower x in plan)"
mt["notes"] = ("Two support lines per table, 2800 apart in x: the rear (high) line has vertical posts with X-bracing in alternate bays; "
               "the front (low) line has a single foot carrying a V of two struts. Rafters 4000 at 15 deg; 4 rails along y on the rafters.")
lay["elevation"]["conflicts"] = lay["elevation"].get("conflicts", [])
lay.setdefault("conflicts", [])
lay["conflicts"] = [
    "Rafter is 4000 true length in the section but also drawn 4000 in plan; its plan projection at 15 deg would be 3864. Modules are projected in plan (2199), rafters are not.",
    "Rail positions: plan puts 2 rails per module 1400 apart and 820 between modules; the section only dimensions rafter nodes (1400 / 1000 / 1100 along slope). Rail-to-rafter clamp points are not dimensioned.",
    "Rear post: 1851 above the 150 topping (Back_Side) = 2001 from slab; Side_View dimensions 1998 / 2000. Use 2000 from slab.",
    "Plan bracing pair (40 wide, 152 c/c) sits on the rear post line; the section shows no bracing on the front line.",
] + lay["elevation"].pop("conflicts")
fr = lay["boq"]["rafters"]["count"]
b = lay["boq"]
b["rafters"]["trueLengthMm"] = 4000
b["rafters"].pop("trueLengthMmAtTilt", None)
b["frames"] = fr
b["rearPosts"] = {"count": fr, "lengthFromSlabMm": 1998}
b["struts"] = {"rearDiagonal2038": fr, "frontBack1396": fr, "frontForward1148": fr,
               "totalM": round(fr * (2038 + 1396 + 1148) / 1000, 2)}
b["postsNote"] = "plan 'posts' = 112 support points = 56 rear posts + 56 front strut feet"
b["footBrackets"] = {"AG2-B02 (rear post)": fr, "AG5-B03 (front strut foot)": fr}
lay_p.write_text(json.dumps(lay, ensure_ascii=False, indent=2))


# ---------------------------------------------------------------- symbols
def polys_of(ents, xf):
    out = []
    for e in disassemble.recursive_decompose(ents):
        if e.dxftype() in ("POINT", "MTEXT", "TEXT", "WIPEOUT", "HATCH", "REGION", "ATTRIB", "LEADER", "DIMENSION"):
            continue
        try:
            p = ezpath.make_path(e).transform(xf)
        except Exception:
            continue
        pts = [(v.x, v.y) for v in p.flattening(0.5)]
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
frame_names = {'*U11', '*U13', '*U15', '*U17', '*U21', 'AG5-B03', 'G$C519ED97B', 'A$C72243465'}
xmax = X0 + 4.2
frame = [e for e in msp.query('INSERT') if e.dxf.name in frame_names and e.dxf.insert.x < xmax and
         bbox.extents([e]).extmax.x < xmax]
frame += [e for e in msp.query('LWPOLYLINE') if e.dxf.color == 256 and e.dxf.layer == '0'
          and max(v[0] for v in e.get_points()) < xmax]
SYM = {
    "pv-mount-frame-section": polys_of(frame, XF),
    "pv-mount-strut-foot-ag5-b03-elevation": polys_of([first('AG5-B03')],
        Matrix44.translate(-first('AG5-B03').dxf.insert.x, -first('AG5-B03').dxf.insert.y, 0) @ Matrix44.scale(M, M, 1)),
    "pwa-tank-roof-40x26-240-side-section": polys_of([e for e in msp if e.dxftype() not in ("MTEXT", "LEADER", "DIMENSION", "HATCH")], XF),
}
sizes = {k: svg_write(f"{k}.svg", v, 10 if "roof" in k else 2) for k, v in SYM.items()}

cat_p = OUT / "catalog-tank-roof.json"
cat = json.loads(cat_p.read_text())
comps = cat if isinstance(cat, list) else cat["components"]
v = lambda k, view, blk: {view: {"svg": f"svg/{k}.svg", "dxfBlock": "TCR_" + k.upper().replace("-", "_"),
                                 "bboxMm": {"width": sizes[k][0], "height": sizes[k][1]}, "source": {"file": SRC.name, "block": blk}}}
for c in comps:
    if c["id"] == "pv-mount-post-300":
        c["name"] = "PV mounting support point, 300 base plate (plan)"
        c["notes"] = ("Plan symbol G$C91944CF8 marks every support point: on the rear (high) line it is a vertical post 1998 from slab "
                      "(AG2-B02 foot), on the front line a single foot (AG5-B03) carrying two struts. Inserted at 270 deg; mirrored on TF/TG. "
                      "Both sit on 300x300x150 concrete toppings.")
        c["heightMm"] = {"rearPostFromSlab": 1998, "rearPostAboveTopping": 1851,
                         "sources": ["Side_View.dxf", "Back_Side.dxf"]}
    if c["id"] == "pv-mount-rafter-4000":
        c["dimensionsMm"] = {"length": 4000, "planLengthDrawn": 4000, "width": 50}
        c["tiltDeg"] = tilt
        c["notes"] = "True length 4000 at 15 deg (Side_View); high end z=2091, low end z=1055, 457 overhang past the front strut. Plan also draws it 4000 (not projected)."
        c["views"].update(v("pv-mount-frame-section", "section", "*U11 + struts + feet"))
    if c["id"] == "pv-module-plan-2199x1134":
        c["notes"] = "Drawn 2199 x 1134 in plan = 2280 x cos 15 deg; ZXM7-UHLDD144 is 2278 x 1134. Portrait, 2 up the slope."
comps += [
    {"id": "pv-mount-frame", "kind": "mounting", "name": "PV mounting frame, 15 deg, 2 modules portrait", "nameTh": "โครงขาตั้งแผง เอียง 15 องศา",
     "tiltDeg": tilt, "postLineSpacingMm": 2800, "baysAlongYMm": 2700,
     "members": {"rafter": {"lengthMm": 4000}, "rearPost": {"heightFromSlabMm": 1998},
                 "struts": [{"lengthMm": 2038, "from": "rear foot"}, {"lengthMm": 1396, "from": "front foot"}, {"lengthMm": 1148, "from": "front foot"}]},
     "modulesPerFrame": 2, "moduleLowEdgeZMm": 985, "moduleTopEdgeZMm": sec["modules"]["topEdgeZMm"],
     "footings": "2 x concrete-topping-300x300x150",
     "notes": "Assembled from Side_View.dxf. Member sections and connection hardware are not labelled.",
     "views": v("pv-mount-frame-section", "section", "*U11 *U13 *U15 *U17 *U21 AG5-B03 G$C519ED97B A$C72243465")},
    {"id": "pv-mount-strut-foot-ag5-b03", "kind": "mounting", "name": "Front strut foot bracket AG5-B03", "nameTh": "ขายึดฐานค้ำยันด้านหน้า AG5-B03",
     "dimensionsMm": {"width": sizes["pv-mount-strut-foot-ag5-b03-elevation"][0], "height": sizes["pv-mount-strut-foot-ag5-b03-elevation"][1]},
     "notes": "Supplier block 'AG5-B03'; base of the two front struts.",
     "views": v("pv-mount-strut-foot-ag5-b03-elevation", "elevation", "AG5-B03")},
]
cat = {"schemaVersion": 1, "units": "mm", "extends": "catalog.json",
       "generatedFrom": ["Top.dxf", "Back_Side.dxf", SRC.name],
       "layouts": ["roofs/pwa-tank-roof-40x26-240.json"],
       "components": sorted(comps, key=lambda c: (c["kind"], c.get("name", "")))}
cat_p.write_text(json.dumps(cat, ensure_ascii=False, indent=2))

dxf_p = OUT / "tcroof-tank-mount-blocks.dxf"
out = ezdxf.readfile(dxf_p)
for k, polys in SYM.items():
    name = "TCR_" + k.upper().replace("-", "_")
    if name not in out.blocks:
        blk = out.blocks.new(name)
        for p in polys:
            blk.add_lwpolyline(p)
if "SECTION" not in out.layers:
    out.layers.add("SECTION", color=7)
out.modelspace().add_blockref("TCR_PWA_TANK_ROOF_40X26_240_SIDE_SECTION", (14000, -6000), dxfattribs={"layer": "SECTION"})
out.saveas(dxf_p)
print(json.dumps({"tilt": tilt, "rafter": raf_bb, "rearPost": rear_post, "struts": struts, "modules": modules,
                  "frontFoot": front_foot, "rearFoot": rear_foot, "tables": table_x}, indent=1))
print(sizes, dv)
