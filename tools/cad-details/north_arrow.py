#!/usr/bin/env python3
"""Extract the team's north arrow from their drawing into the JSON the app's DXF writers read (NorthArrow.swift).

    python3 tools/cad-details/north_arrow.py docs/specs/cad-export-dxf/reference/North_Arrow.dxf \
        TCRoofKit/Sources/TCRoofCore/Resources/north-arrow.json

The source holds one block (a circle, the N / S and E / W cross, the arrow head, a hatched box and the letters N E S W),
inserted turned. The block is written as drawn, without the insert's turn, with its circle's centre as the origin and
its radius as 1, so N points up (+y). Each letter is kept as its centre and height, written upright and centred by the
app (the source letters carry mirror flags). Colours are left out: the app's CAD export is ByLayer.

Needs ezdxf (pip install ezdxf).
"""
import json, sys
import ezdxf
from ezdxf import bbox


def main(src, out):
    doc = ezdxf.readfile(src)
    block = next(b for b in doc.blocks if not b.name.startswith('*') and len(b) > 0)
    circle = next(e for e in block if e.dxftype() == 'CIRCLE')
    cx, cy, r = circle.dxf.center.x, circle.dxf.center.y, circle.dxf.radius

    def p(x, y): return [round((x - cx) / r, 5), round((y - cy) / r, 5)]

    polylines, texts, hatches = [], [], []
    for e in block:
        t = e.dxftype()
        if t == 'LWPOLYLINE':
            pts = [p(*q[:2]) for q in e.get_points()]
            polylines.append({'points': pts, 'closed': bool(e.closed)})
        elif t == 'TEXT':
            box = bbox.extents([e])
            mid = box.center
            texts.append({'text': e.dxf.text.upper(), 'at': p(mid.x, mid.y), 'height': round(e.dxf.height / r, 5)})
        elif t == 'HATCH':
            loops = [[p(*v[:2]) for v in path.vertices] for path in e.paths]
            lines = [{'angle': round(l.angle, 6), 'base': p(*l.base_point), 'offset': [round(l.offset[0] / r, 7), round(l.offset[1] / r, 7)],
                      'dashes': [round(d / r, 7) for d in l.dash_length_items]} for l in e.pattern.lines]
            hatches.append({'pattern': e.dxf.pattern_name, 'loops': loops, 'lines': lines})
    data = {'source': src.split('/')[-1], 'note': 'Origin at the circle centre, radius 1, N up (+y).',
            'circles': [[0, 0, 1]], 'polylines': polylines, 'hatches': hatches, 'texts': texts}
    with open(out, 'w') as f: json.dump(data, f, indent=1, ensure_ascii=False)
    print(len(polylines), 'polylines,', len(hatches), 'hatches,', [t['text'] for t in texts])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
