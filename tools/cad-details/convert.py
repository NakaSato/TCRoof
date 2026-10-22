#!/usr/bin/env python3
"""Turn a team detail drawing (DXF) into the primitives the app's DXF writer draws as one block.

    python3 tools/cad-details/convert.py docs/specs/cad-export-dxf/reference/Walkway.dxf \
        TCRoofKit/Sources/TCRoofCore/Resources/walkway-detail.json

Every block, dimension and leader is exploded into lines, polylines, filled polygons and single-line texts in the
drawing's own units (the walkway sheet is in paper millimetres), moved so its bottom-left corner is (0, 0), each with
its AutoCAD colour index. Arcs, circles, ellipses and splines become polylines. A block clipped by an XCLIP frame keeps only what lies inside the
frame (cut into lines at its edge). Needs ezdxf (pip install ezdxf).
"""
import json, math, sys
import ezdxf
from ezdxf import disassemble, path, xclip
from ezdxf.colors import BYLAYER, BYBLOCK

def clip_segment(a, b, box):
    """Liang–Barsky: the part of a → b inside box (x0, y0, x1, y1), or None."""
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

def aci_of(e, doc):
    c = e.dxf.get('color', BYLAYER)
    if c in (BYLAYER, BYBLOCK, 0, 256):
        layer = doc.layers.get(e.dxf.layer) if doc.layers.has_entry(e.dxf.layer) else None
        c = abs(layer.color) if layer else 7
    return int(c)

def main(src, dst):
    doc = ezdxf.readfile(src)
    lines, polys, fills, texts = [], [], [], []
    # an INSERT with an XCLIP frame shows only what lies inside it (the walkway's DETAIL 1)
    groups = []
    for e in doc.modelspace():
        box = None
        if e.dxftype() == 'INSERT':
            xc = xclip.XClip(e)
            if xc.has_clipping_path:
                v = list(xc.get_wcs_clipping_path().vertices)
                box = (min(q.x for q in v), min(q.y for q in v), max(q.x for q in v), max(q.y for q in v))
        groups.append((e, box))
    def primitives():
        for e, box in groups:
            for p in disassemble.recursive_decompose([e]): yield p, box
    def add_poly(pts, closed, c, box):
        if box is None:
            polys.append([[round(x, 3), round(y, 3)] for x, y in pts] + [1 if closed else 0, c]); return
        seq = pts + ([pts[0]] if closed else [])
        for a, b in zip(seq, seq[1:]):
            seg = clip_segment(a, b, box)
            if seg: lines.append([seg[0][0], seg[0][1], seg[1][0], seg[1][1], c])
    for e, box in primitives():
        t, c = e.dxftype(), aci_of(e, doc)
        try:
            if t == 'LINE':
                a, b = e.dxf.start, e.dxf.end
                seg = clip_segment((a.x, a.y), (b.x, b.y), box) if box else ((a.x, a.y), (b.x, b.y))
                if seg: lines.append([seg[0][0], seg[0][1], seg[1][0], seg[1][1], c])
            elif t in ('LWPOLYLINE', 'POLYLINE', 'ARC', 'CIRCLE', 'ELLIPSE', 'SPLINE'):
                p = path.make_path(e)
                pts = [(v.x, v.y) for v in p.flattening(distance=0.05)]
                if len(pts) >= 2:
                    closed = t == 'CIRCLE' or (t in ('LWPOLYLINE', 'POLYLINE') and e.is_closed)
                    add_poly(pts, closed, c, box)
            elif t in ('SOLID', 'TRACE'):
                v = [e.dxf.vtx0, e.dxf.vtx1, e.dxf.vtx3, e.dxf.vtx2]
                if all(inside((q.x, q.y), box) for q in v): fills.append([[round(q.x, 3), round(q.y, 3)] for q in v] + [c])
            elif t == 'HATCH' and e.dxf.solid_fill:
                for p in path.from_hatch(e):
                    pts = [(v.x, v.y) for v in p.flattening(distance=0.05)]
                    if len(pts) >= 3 and all(inside(q, box) for q in pts): fills.append([[round(x, 3), round(y, 3)] for x, y in pts] + [c])
            elif t == 'TEXT':
                q = e.dxf.align_point if e.dxf.halign or e.dxf.valign else e.dxf.insert
                if inside((q.x, q.y), box): texts.append([q.x, q.y, e.dxf.height, e.dxf.rotation, e.dxf.text, e.dxf.halign, c])
            elif t == 'MTEXT':
                q = e.dxf.insert
                if not inside((q.x, q.y), box): continue
                for i, line in enumerate(e.plain_text().split('\n')):
                    h = e.dxf.char_height
                    texts.append([q.x, q.y - h * (1 + 1.6 * i), h, e.dxf.get('rotation', 0), line, 0, c])
        except Exception as err:
            print('skipped', t, err, file=sys.stderr)
    xs = [p[0] for p in lines] + [p[2] for p in lines] + [q[0] for p in polys for q in p[:-2]] + [q[0] for p in fills for q in p[:-1]]
    ys = [p[1] for p in lines] + [p[3] for p in lines] + [q[1] for p in polys for q in p[:-2]] + [q[1] for p in fills for q in p[:-1]]
    x0, y0 = min(xs), min(ys)
    r = lambda v: round(v, 3)
    out = {
        'source': src.split('/')[-1], 'units': 'drawing units of the source (paper mm)',
        'size': [r(max(xs) - x0), r(max(ys) - y0)],
        'lines': [[r(a - x0), r(b - y0), r(c - x0), r(d - y0), k] for a, b, c, d, k in lines],
        'polylines': [{'points': [[r(x - x0), r(y - y0)] for x, y in p[:-2]], 'closed': bool(p[-2]), 'aci': p[-1]} for p in polys],
        'fills': [{'points': [[r(x - x0), r(y - y0)] for x, y in p[:-1]], 'aci': p[-1]} for p in fills],
        'texts': [{'at': [r(x - x0), r(y - y0)], 'height': r(h), 'rotation': r(a), 'text': s, 'align': al, 'aci': k}
                  for x, y, h, a, s, al, k in texts if s.strip()],
    }
    with open(dst, 'w') as f: json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(dst, {k: len(v) for k, v in out.items() if isinstance(v, list)}, 'size', out['size'])

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
