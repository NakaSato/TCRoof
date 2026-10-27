#!/usr/bin/env python3
"""The team's inverter station components, as the B2 DXF writer (InverterStationDXF.swift) inserts them: one block each.

    python3 tools/cad-details/station_components.py \
        docs/specs/cad-export-dxf/reference/inverter-station/components/cad \
        TCRoofKit/Sources/TCRoofCore/Resources/station-components.json

Reads the component library's clean block files (`tcroof-station-blocks.dxf`, `tcroof-cable-tray-blocks.dxf`, in mm,
each block's base point at its lower-left corner) and writes the blocks the station drawing uses in metres: lines,
polylines (arcs and bulges flattened to 0.5 mm), circles and texts. Detail under 3 mm across is left out (it cannot be
seen at the drawing's 1:50) and so are the trays' hidden lines; a solid hatch keeps its outline. Needs ezdxf.
"""
import json, math, sys
import ezdxf
from ezdxf import path

STATION = [
    'TCR_SOLAR_AC_DB_FRONT', 'TCR_SOLAR_DC_DB_FRONT', 'TCR_ENCLOSURE_630X750_FRONT', 'TCR_DB_ENCLOSURE_SIDE',
    'TCR_GROWATT_MAX_125KTL3_LV_FRONT', 'TCR_GROWATT_MAX_125KTL3_LV_TOP', 'TCR_GROWATT_MAX_80KTL3_LV_FRONT',
    'TCR_GROWATT_MAX_80KTL3_LV_TOP', 'TCR_GROWATT_40KTL3_X_FRONT', 'TCR_INVERTER_GENERIC_SIDE',
    'TCR_STEEL_COLUMN_150_PLAN', 'TCR_COLUMN_BASE_PLATE_DETAIL_PLAN', 'TCR_BASE_PLATE_200_ELEVATION',
    'TCR_CONCRETE_FOOTING_200X100_ELEVATION', 'TCR_DOOR_SWING_1100_PLAN', 'TCR_SCALE_FIGURE_ELEVATION',
]
TRAY_PREFIXES = ('TCR_TRAY_SECTION_', 'TCR_TRAY_PLAN_COVER_W', 'TCR_TRAY_SIDE_PERF_H100', 'TCR_LADDER_SECTION_',
                 'TCR_LADDER_PLAN_W', 'TCR_LADDER_SIDE_H100')
MIN_SIZE = 3.0      # mm
TOL = 0.5           # mm, flattening
K = 0.001           # mm -> m

def r(x):
    return round(x * K, 6)

def extent(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return max(max(xs) - min(xs), max(ys) - min(ys)) if pts else 0

def convert(block, skip_layers=()):
    out = {'lines': [], 'polylines': [], 'circles': [], 'texts': []}
    lo = [math.inf, math.inf]; hi = [-math.inf, -math.inf]
    def cover(x, y):
        lo[0] = min(lo[0], x); lo[1] = min(lo[1], y); hi[0] = max(hi[0], x); hi[1] = max(hi[1], y)
    def poly(pts, closed):
        if len(pts) < 2 or extent(pts) < MIN_SIZE:
            return
        for x, y in pts: cover(x, y)
        out['polylines'].append({'points': [[r(x), r(y)] for x, y in pts], 'closed': closed})
    for e in block:
        if e.dxf.layer in skip_layers:
            continue
        t = e.dxftype()
        if t == 'LINE':
            a, b = e.dxf.start, e.dxf.end
            if math.hypot(b.x - a.x, b.y - a.y) < 1e-6: continue
            cover(a.x, a.y); cover(b.x, b.y)
            out['lines'].append([r(a.x), r(a.y), r(b.x), r(b.y)])
        elif t in ('LWPOLYLINE', 'POLYLINE', 'ARC', 'SPLINE', 'ELLIPSE'):
            p = path.make_path(e)
            pts = [(v.x, v.y) for v in p.flattening(TOL)]
            closed = t in ('LWPOLYLINE', 'POLYLINE') and e.is_closed
            if closed and len(pts) > 2 and math.hypot(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1]) < 1e-6: pts = pts[:-1]
            poly(pts, closed)
        elif t == 'CIRCLE':
            c, rad = e.dxf.center, e.dxf.radius
            if 2 * rad < MIN_SIZE / 2: continue
            cover(c.x - rad, c.y - rad); cover(c.x + rad, c.y + rad)
            out['circles'].append([r(c.x), r(c.y), r(rad)])
        elif t == 'SOLID':
            v = [e.dxf.vtx0, e.dxf.vtx1, e.dxf.vtx3, e.dxf.vtx2]
            poly([(q.x, q.y) for q in v], True)
        elif t == 'HATCH':
            for bp in e.paths:
                p = path.from_hatch_boundary_path(bp)
                pts = [(v.x, v.y) for v in p.flattening(TOL)]
                if len(pts) > 2 and math.hypot(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1]) < 1e-6: pts = pts[:-1]
                poly(pts, True)
        elif t in ('TEXT', 'MTEXT'):
            if t == 'TEXT':
                s, h, ang = e.dxf.text, e.dxf.height, e.dxf.get('rotation', 0)
                halign = e.dxf.get('halign', 0)
                at = e.dxf.align_point if halign and e.dxf.hasattr('align_point') else e.dxf.insert
                align = {1: 'center', 2: 'right', 4: 'center'}.get(halign, 'left')
                middle = e.dxf.get('valign', 0) == 2 or halign == 4
            else:
                s, h, ang = e.plain_text(), e.dxf.char_height, e.dxf.get('rotation', 0)
                at = e.dxf.insert; ap = e.dxf.get('attachment_point', 1)
                align = ['left', 'center', 'right'][(ap - 1) % 3]; middle = ap in (4, 5, 6)
            s = s.strip()
            if not s: continue
            cover(at.x, at.y)
            out['texts'].append({'at': [r(at.x), r(at.y)], 'height': r(h), 'text': s, 'angle': round(ang, 3),
                                 'align': align, 'middle': middle})
    out['box'] = [r(lo[0]), r(lo[1]), r(hi[0]), r(hi[1])]
    return {k: v for k, v in out.items() if v}

def main(src, dst):
    doc = ezdxf.readfile(f'{src}/tcroof-station-blocks.dxf')
    trays = ezdxf.readfile(f'{src}/tcroof-cable-tray-blocks.dxf')
    blocks = {n: convert(doc.blocks[n]) for n in STATION}
    for b in trays.blocks:
        if b.name.startswith(TRAY_PREFIXES):
            blocks[b.name] = convert(b, skip_layers=('TRAY-HIDDEN',))
    meta = json.load(open(f'{src}/catalog.json'))
    json.dump({'source': 'docs/specs/cad-export-dxf/reference/inverter-station/components/cad',
               'generatedFrom': meta.get('generatedFrom', []), 'units': 'm', 'blocks': blocks},
              open(dst, 'w'), ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    n = sum(len(v.get('lines', [])) + len(v.get('polylines', [])) + len(v.get('circles', [])) for v in blocks.values())
    print(f'{len(blocks)} blocks, {n} entities -> {dst}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
