#!/usr/bin/env python3
"""Extract the team's tank mounting components, one by one, from their section drawings into the JSON the app's DXF
writer turns into one editable block each (TankComponents.swift).

    python3 tools/cad-details/components.py docs/specs/cad-export-dxf/reference \
        TCRoofKit/Sources/TCRoofCore/Resources/tank-components.json

Each component is a block of `Tank mounting Section 1.dxf` / `Section 2.dxf` (or a group of entities inside one, cut
by a box), exploded into lines, polylines and hatches at true size in metres, moved so its base point is (0, 0).
Dimensions, leaders and texts are left out: the app writes its own. A hatch keeps its pattern's lines (angle, base,
offset, dashes) as the source stored them, so concrete stays AR-CONC. Needs ezdxf (pip install ezdxf).
"""
import json, math, sys
import ezdxf
from ezdxf import disassemble, path
from ezdxf.colors import BYLAYER, BYBLOCK
from ezdxf.math import Matrix44

# id: source, block, unit (to metres), base point in the block's own units, optional clip box (same units), mirror x
SPECS = [
    ('module_side', 'Section 1', 'A$C72243465', 0.001, (457.5, -0.5), None, True,
     'PV module side view 2280 mm with its two rail clamps; origin at its low end on the rail bottom, +x up the slope'),
    ('rail_clamp', 'Section 1', 'R30组件', 0.001, (0, 0), None, False, 'Rail R30 with its clamp, section; origin at the rail bottom centre'),
    ('rail_section', 'Section 1', 'R30截面', 0.001, (0, 0), None, False, 'Rail R30, section; origin at its bottom centre'),
    ('base_side', 'Section 1', 'AG5-B03', 0.001, None, None, False, 'Aluminium post base, side; origin at its bottom centre'),
    ('base_front', 'Section 1', 'AG2-B02正视图', 0.001, (0, 0), None, False, 'Aluminium post base, front; origin at its bottom centre'),
    ('anchor_m12', 'Section 2', 'G$C86730ED5', 1, (0, 0), None, False, 'Expansion bolt M12; origin at the slab top'),
    ('base_plan', 'Section 2', 'G$CADFF6009', 1, (0, 0), (-0.09, -0.09, 0.09, 0.09), False, 'Post base on plan; origin at the post centre'),
    ('topping_plan', 'Section 2', 'G$CADFF6009', 1, (0, 0), None, False, 'Concrete topping 300 x 300 with the base on plan; origin at its centre'),
    ('topping', 'Section 1', 'G$C35D9C61C', 1, (0.125, -0.15), (-0.03, -0.155, 0.28, 0.005), False,
     'Concrete topping 300 x 150, section (AR-CONC); origin at its bottom centre'),
    ('topping_detail', 'Section 2', 'G$C4CEE3454', 1, (0.372, 0), (0.15, -0.07, 0.60, 0.31), False,
     'DETAIL 1: topping, base, expansion bolt M12, post and brace stubs on the slab; origin at the topping bottom centre'),
    ('module_plan', 'PV_Panel', 'G$C5CD13CD5', 1, (0, 0), None, 'rot90',
     'PV module on plan with its cells, portrait 0.992 x 1.956 as drawn; origin at its lower-left corner, stretched to the module'),
]
SKIP = {'DIMENSION', 'LEADER', 'MTEXT', 'TEXT', 'ATTRIB', 'ATTDEF', 'MULTILEADER', 'WIPEOUT', 'REGION'}

def aci_of(e, doc):
    c = e.dxf.get('color', BYLAYER)
    if c in (BYLAYER, BYBLOCK, 256, 0):
        return None
    return int(c)

def clip_segment(a, b, box):
    (x0, y0, x1, y1), (ax, ay), (bx, by) = box, a, b
    dx, dy, t0, t1 = bx - ax, by - ay, 0.0, 1.0
    for p, q in ((-dx, ax - x0), (dx, x1 - ax), (-dy, ay - y0), (dy, y1 - ay)):
        if abs(p) < 1e-12:
            if q < 0: return None
        else:
            t = q / p
            if p < 0: t0 = max(t0, t)
            else: t1 = min(t1, t)
            if t0 > t1: return None
    return (ax + t0 * dx, ay + t0 * dy), (ax + t1 * dx, ay + t1 * dy)

def inside(q, box): return box is None or (box[0] - 1e-9 <= q[0] <= box[2] + 1e-9 and box[1] - 1e-9 <= q[1] <= box[3] + 1e-9)

# components that keep only some of the block's own entity types (the topping: its outline and its concrete hatch)
ONLY = {'topping': {'LWPOLYLINE', 'HATCH'}}

def extract(doc, block, unit, base, box, mirror, only=None):
    blk = doc.blocks.get(block)
    ents = [e for e in blk if e.dxftype() not in SKIP and (only is None or e.dxftype() in only)]
    lines, polys, hatches = [], [], []
    flat = 0.0005 / unit   # 0.5 mm chords
    def keep_poly(pts, closed, c):
        if box is None or all(inside(q, box) for q in pts):
            polys.append((pts, closed, c)); return
        seq = pts + ([pts[0]] if closed else [])
        for a, b in zip(seq, seq[1:]):
            s = clip_segment(a, b, box)
            if s: lines.append((s[0], s[1], c))
    for e in disassemble.recursive_decompose(ents):
        t = e.dxftype()
        if t in SKIP: continue
        c = aci_of(e, doc)
        try:
            if t == 'LINE':
                a, b = (e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y)
                s = clip_segment(a, b, box) if box else (a, b)
                if s: lines.append((s[0], s[1], c))
            elif t in ('LWPOLYLINE', 'POLYLINE', 'ARC', 'CIRCLE', 'ELLIPSE', 'SPLINE'):
                pts = [(v.x, v.y) for v in path.make_path(e).flattening(distance=flat)]
                if len(pts) >= 2:
                    keep_poly(pts, t == 'CIRCLE' or (t in ('LWPOLYLINE', 'POLYLINE') and e.is_closed), c)
            elif t == 'HATCH':
                loops = [[(v.x, v.y) for v in p.flattening(distance=flat)] for p in path.from_hatch(e)]
                loops = [l for l in loops if len(l) >= 3 and (box is None or all(inside(q, box) for q in l))]
                if not loops: continue
                lines_def = [] if e.dxf.solid_fill else [
                    {'angle': round(l.angle, 6), 'base': [l.base_point[0], l.base_point[1]], 'offset': [l.offset[0], l.offset[1]],
                     'dashes': list(l.dash_length_items)} for l in e.pattern.lines]
                hatches.append((loops, 'SOLID' if e.dxf.solid_fill else e.dxf.pattern_name, lines_def, c))
        except Exception as err:
            print('skipped', block, t, err, file=sys.stderr)
    # base point: given, or the bottom centre of what is kept
    xs = [p[0] for l in lines for p in l[:2]] + [q[0] for p in polys for q in p[0]]
    ys = [p[1] for l in lines for p in l[:2]] + [q[1] for p in polys for q in p[0]]
    if base is None: base = ((min(xs) + max(xs)) / 2, min(ys))
    sx = -1 if mirror is True else 1
    def tf(q):
        x, y = sx * (q[0] - base[0]) * unit, (q[1] - base[1]) * unit
        if mirror == 'rot90': x, y = -y, x   # turned a quarter counter-clockwise: the long side up
        return [round(x, 5), round(y, 5)]
    out = {
        'lines': [tf(a) + tf(b) + ([c] if c else []) for a, b, c in lines],
        'polylines': [{'points': [tf(q) for q in pts], **({'closed': True} if cl else {}), **({'aci': c} if c else {})} for pts, cl, c in polys],
        'hatches': [],
    }
    for loops, name, defs, c in hatches:
        # pattern lines are in the source's units: scale them to metres (a mirror turns their angles)
        ds = []
        # the source's pattern origin can sit far away; moving every family by the same multiple of its own offsets
        # would be exact, so move them all together to near the component instead (same pattern, phase only)
        if defs:
            o0 = defs[0]['base']; shift = (o0[0] - base[0], o0[1] - base[1])
            defs = [{**d, 'base': [d['base'][0] - shift[0], d['base'][1] - shift[1]]} for d in defs]
        for d in defs:
            a = (180 - d['angle']) % 360 if mirror is True else (d['angle'] + 90) % 360 if mirror == 'rot90' else d['angle']
            bx, by = sx * (d['base'][0] - base[0]) * unit, (d['base'][1] - base[1]) * unit
            ox, oy = sx * d['offset'][0] * unit, d['offset'][1] * unit
            if mirror == 'rot90': bx, by, ox, oy = -by, bx, -oy, ox
            ds.append({'angle': round(a, 6), 'base': [round(bx, 6), round(by, 6)], 'offset': [round(ox, 7), round(oy, 7)],
                       'dashes': [round(x * unit, 7) for x in d['dashes']]})
        out['hatches'].append({'loops': [[tf(q) for q in l] for l in loops], 'pattern': name, 'lines': ds, **({'aci': c} if c else {})})
    allx = [p[0] for l in out['lines'] for p in (l[0:2], l[2:4])] + [q[0] for p in out['polylines'] for q in p['points']]
    ally = [p[1] for l in out['lines'] for p in (l[0:2], l[2:4])] + [q[1] for p in out['polylines'] for q in p['points']]
    out['box'] = [round(min(allx), 4), round(min(ally), 4), round(max(allx), 4), round(max(ally), 4)]
    return out

def main(ref, dst):
    docs = {}
    comps = {}
    for cid, src, block, unit, base, box, mirror, note in SPECS:
        f = f'{ref}/{src}.dxf' if src == 'PV_Panel' else f'{ref}/Tank mounting {src}.dxf'
        docs.setdefault(f, ezdxf.readfile(f))
        c = extract(docs[f], block, unit, base, box, mirror, ONLY.get(cid))
        comps[cid] = {'note': note, 'source': f'{f.split("/")[-1]} / {block}', **c}
        print(cid, {k: len(v) for k, v in c.items() if isinstance(v, list)}, 'box', c['box'])
    with open(dst, 'w') as fh:
        json.dump({'units': 'metres', 'components': comps}, fh, ensure_ascii=False, separators=(',', ':'))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
