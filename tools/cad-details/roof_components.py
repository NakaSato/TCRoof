#!/usr/bin/env python3
"""Extract the team's roof section components and measurements from their section drawing into the JSON the app's
roof DXF writer and its quality check read (RoofComponents.swift).

    python3 tools/cad-details/roof_components.py "docs/specs/cad-export-dxf/reference/Roof section eave ceiling.dxf" \
        TCRoofKit/Sources/TCRoofCore/Resources/roof-components.json

The source is a gable roof cut across the ridge (ชายคาฝ้า: rafters on RC posts, a collar tie, a boxed eave), drawn in
metres with LINEs only, at a 15° pitch. From it:

- components, each as lines in its own frame (metres), for one block each in the app's DXF:
  - `purlin_c`: one purlin as drawn (C with its wall thickness), from the left slope's middle; origin at the C's
    bottom centre on the rafter's top face, +x where its flanges open, +y square to the slope, away from the rafter.
  - `ridge_cap`: the ridge flashing over the sheet; origin on the sheet's top at the ridge, x and y as drawn.
- `checks`: the measures the app's section must agree with (RoofComponentsTests): the rafter's depth and lip lines,
  the sheet over the purlins and its thickness, the purlin spacing along the slope, the collar tie, the eave strut
  under the post head and the beam with the soffit.

Needs ezdxf (pip install ezdxf).
"""
import json, math, statistics, sys
import ezdxf

def main(src, out):
    doc = ezdxf.readfile(src)
    msp = doc.modelspace()
    L = [((e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y), e.dxf.layer) for e in msp if e.dxftype() == 'LINE']
    pts = [p for a, b, _ in L for p in (a, b)]
    apex = max(pts, key=lambda p: p[1])
    th = math.radians(15)
    u, n = (math.cos(th), math.sin(th)), (-math.sin(th), math.cos(th))   # left slope: up it, and square to it
    def off(p): return (p[0] - apex[0]) * n[0] + (p[1] - apex[1]) * n[1]
    def along(p): return (p[0] - apex[0]) * u[0] + (p[1] - apex[1]) * u[1]
    def length(l): return math.dist(l[0], l[1])
    def angle(l): return math.degrees(math.atan2(l[1][1] - l[0][1], l[1][0] - l[0][0])) % 180

    # the long lines along the left slope, by their offset under the apex: sheet top / bottom, rafter top, lip, lip, bottom
    slope = sorted({round(off(l[0]), 4) for l in L if abs(angle(l) - 15) < 0.3 and length(l) > 0.3}, reverse=True)
    sheet_top, sheet_bottom = slope[1], slope[2]          # slope[0] is the ridge flashing's line
    rafter_top, lip_top, lip_bottom, rafter_bottom = slope[3], slope[4], slope[5], slope[6]

    # the short pieces, grouped where their ends touch
    short = [l for l in L if length(l) < 0.2 and l[2] in ('0', 'WALL-HATC')]
    parent = list(range(len(short)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for i in range(len(short)):
        for j in range(i):
            if min(math.dist(p, q) for p in short[i][:2] for q in short[j][:2]) < 0.006:
                parent[find(i)] = find(j)
    groups = {}
    for i, l in enumerate(short): groups.setdefault(find(i), []).append(l)

    # purlins: the 12-line groups sitting on the rafter's top face of the left slope
    purlins = [g for g in groups.values() if len(g) == 12 and all(p[0] < apex[0] for l in g for p in l[:2])
               and abs(min(off(p) for l in g for p in l[:2]) - rafter_top) < 0.01 + 0.12]
    purlins = [g for g in purlins if min(off(p) for l in g for p in l[:2]) > rafter_top - 0.002]
    centres = sorted(statistics.mean(along(p) for l in g for p in l[:2]) for g in purlins)
    spacing = statistics.median(b - a for a, b in zip(centres, centres[1:]))
    mid = min(purlins, key=lambda g: abs(statistics.mean(along(p) for l in g for p in l[:2]) - statistics.median(centres)))
    c = statistics.mean(along(p) for l in mid for p in l[:2])
    local = [[(along(p) - c, off(p) - rafter_top) for p in l[:2]] for l in mid]
    xs = [p[0] for s in local for p in s]
    lo, hi = min(xs), max(xs)
    # the web is the side with the long piece square to the slope: flanges open away from it, toward +x
    web = min(local, key=lambda s: (abs(s[0][0] - s[1][0]) > 0.003, -abs(s[0][1] - s[1][1])))
    flip = -1 if abs(web[0][0] - hi) < abs(web[0][0] - lo) else 1
    centre = (lo + hi) / 2
    purlin_lines = [[round(flip * (x - centre), 6), round(y, 6), round(flip * (x2 - centre), 6), round(y2, 6)] for (x, y), (x2, y2) in local]
    ph = max(p[1] for s in local for p in s)

    # the ridge cap: what lies over the sheet within 0.40 m of the ridge, from its top at the ridge
    top = (apex[0], apex[1] + sheet_top / math.cos(th))
    def over(p): return off(p) > sheet_top + 0.001 if p[0] <= apex[0] else ((apex[0] - p[0]) * n[0] + (p[1] - apex[1]) * n[1]) > sheet_top + 0.001
    cap = [l for l in L if all(abs(p[0] - apex[0]) < 0.4 and over(p) for p in l[:2]) and length(l) < 0.7]
    cap_lines = [[round(a[0] - top[0], 6), round(a[1] - top[1], 6), round(b[0] - top[0], 6), round(b[1] - top[1], 6)] for a, b, _ in cap]

    # horizontals: the collar tie (four lines over the span's middle), the strut under the head, the beam and soffit
    hz = sorted({round(a[1], 4) for a, b, _ in L if abs(a[1] - b[1]) < 1e-6 and length((a, b)) > 0.2 and min(a[0], b[0]) > apex[0] - 2.5
                 and max(a[0], b[0]) < apex[0] + 2.5 and abs((a[0] + b[0]) / 2 - apex[0]) < 0.2})
    tie = hz[-4:]
    # the left post: the two verticals that reach the drawing's bottom; its head is the top of its outer (eave) face
    vert = [(a, b) for a, b, _ in L if abs(a[0] - b[0]) < 1e-6 and abs(a[1] - b[1]) > 0.2 and a[0] < apex[0] - 2]
    low = min(min(a[1], b[1]) for a, b in vert)
    post = sorted({round(a[0], 4) for a, b in vert if min(a[1], b[1]) < low + 0.01})[:2]
    head = max(max(a[1], b[1]) for a, b in vert if abs(a[0] - post[0]) < 1e-3)
    eave = sorted({round(a[1], 4) for a, b, _ in L if abs(a[1] - b[1]) < 1e-6 and length((a, b)) > 0.5
                   and max(a[0], b[0]) <= post[0] + 1e-3 and a[1] > head - 0.6 and a[1] < head})
    strut = [eave[0], eave[-1]]
    # the beam cut on the post's eave side: the horizontals starting at its outer face, and their right ends
    box = [(a, b) for a, b, _ in L if abs(a[1] - b[1]) < 1e-6 and abs(min(a[0], b[0]) - post[0]) < 1e-3 and max(a[0], b[0]) < post[1] - 1e-3]
    beam = sorted({round(a[1], 4) for a, b in box})
    beam_w = max(max(a[0], b[0]) for a, b in box) - post[0]
    out_json = {
        'source': src.split('/')[-1],
        'components': {
            'purlin_c': {'note': 'C purlin as drawn; origin at its bottom centre on the rafter, +x where its flanges open, +y off the rafter',
                         'size': [round(ph, 4), round(hi - lo, 4)], 'lines': purlin_lines},
            'ridge_cap': {'note': 'Ridge flashing over the sheet; origin on the sheet top at the ridge, drawn at 15°', 'pitch': 15,
                          'lines': cap_lines},
        },
        'checks': {
            'pitch': 15,
            'rafterDepth': round(rafter_top - rafter_bottom, 4), 'rafterLip': round(rafter_top - lip_top, 4),
            'rafterLipBottom': round(lip_bottom - rafter_bottom, 4),
            'sheetOverRafter': round(sheet_bottom - rafter_top, 4), 'sheetThickness': round(sheet_top - sheet_bottom, 4),
            'purlinDepth': round(ph, 4), 'purlinSpacing': round(spacing, 4),
            'tieDepth': round(tie[-1] - tie[0], 4), 'tieLip': round(tie[1] - tie[0], 4),
            'strutDepth': round(strut[1] - strut[0], 4), 'strutTopUnderHead': round(head - strut[1], 4),
            'postWidth': round(post[1] - post[0], 4), 'beamDepth': round(beam[-1] - beam[0], 4), 'beamWidth': round(beam_w, 4),
            'soffitUnderHead': round(head - beam[0], 4),
        },
    }
    with open(out, 'w') as f: json.dump(out_json, f, indent=1, ensure_ascii=False)
    print(json.dumps(out_json['checks'], indent=1))
    print('purlin lines', len(purlin_lines), 'ridge cap lines', len(cap_lines))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
