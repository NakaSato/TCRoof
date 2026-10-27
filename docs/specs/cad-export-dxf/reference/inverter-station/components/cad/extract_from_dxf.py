"""Extract TCRoof inverter-station CAD components from the three DXF drawings.

Outputs (all lengths in mm, drawings are authored in metres):
  out/components/cad/catalog.json              component library
  out/components/cad/svg/<id>-<view>.svg       vector symbol per component view
  out/components/cad/stations/<id>.json        station templates with placements
  out/components/cad/tcroof-station-blocks.dxf clean block library (mm)
"""
import json, os, sys
from ezdxf import recover, bbox
import ezdxf
from ezdxf.addons.drawing import RenderContext, Frontend, svg, layout
from ezdxf.addons.drawing.config import Configuration, BackgroundPolicy, ColorPolicy, LineweightPolicy
from ezdxf.math import Matrix44

SRC = sys.argv[1]
OUT = sys.argv[2]
FILES = {
    "lv": "1751d41a-Internal_Inverter_Station_EXL-LV.dxf",
    "inv": "b681fdd9-Inverter.dxf",
    "hv": "fd337b54-Inverter_EXL-HV.dxf",
    "part1": "83f3482c-Part_1.dxf",
}
docs = {k: recover.readfile(os.path.join(SRC, f))[0] for k, f in FILES.items()}
M = 1000.0  # m -> mm

def r(v):  # round mm
    return int(round(v))

# ---------------------------------------------------------------- catalog
# (id, view) -> (file, block name, which instance by x-order)
SYMBOLS = [
    ("solar-ac-db",            "front", "inv", "G$CF654F5B4", 0),
    ("enclosure-630x750",      "front", "inv", "G$C6FDF2B68", 0),
    ("solar-dc-db",            "front", "hv",  "G$C1C0043C9", 0),
    ("db-enclosure",           "side",  "inv", "G$CF48E2AB0", 0),
    ("growatt-max-125ktl3-lv", "front", "inv", "MAX60 KTL3-X", 0),
    ("growatt-max-125ktl3-lv", "top",   "inv", "G$CD2F47895", 0),
    ("growatt-max-80ktl3-lv",  "front", "lv",  "G$C1122B4A8", 0),
    ("growatt-max-80ktl3-lv",  "top",   "lv",  "G$C495614EF", 0),
    ("growatt-40ktl3-x",       "front", "hv",  "G$C8D530D04", 0),
    ("inverter-generic",       "side",  "inv", "G$CCD1817F7", 0),
    ("steel-column-150",       "plan",  "inv", "G$C974A1353", 0),
    ("base-plate-200",         "elevation", "inv", "G$CC68670CA", 0),
    ("concrete-footing-200x100", "elevation", "lv", "ขาเก๊าปูน", 0),
    ("door-swing-1100",        "plan",  "inv", "A$C5CD537DB", 0),
    ("cable-gland-ac",         "elevation", "inv", "AC port", 0),
    ("cable-gland-hex",        "plan",  "inv", "G$C71643F1A", 0),
    ("mc4-connector",          "elevation", "inv", "mc4", 0),
    ("grid-bubble",            "annotation", "inv", "spec-col(V)", 0),
    ("column-base-plate-detail", "plan", "part1", None, 0),  # whole modelspace
    ("scale-figure",           "elevation", "inv", "G$C8B47C620", 0),
]

CATALOG = {
    "solar-ac-db": dict(kind="distributionBoard", name="SOLAR AC-DB", nameTh="ตู้ AC-DB โซลาร์",
        dimensionsMm=dict(width=900, height=1400, depth=400),
        notes="Front face carries 'PV SOLAR SUPPLY / MAIN SWITCH' and the 2-way-supply warning label (มีไฟฟ้า 2 ทาง). Depth is 400 in the LV and 125k drawings, 300 in EXL-HV."),
    "solar-meter-db": dict(kind="distributionBoard", name="SOLAR METER-DB", nameTh="ตู้มิเตอร์โซลาร์",
        symbol="enclosure-630x750", dimensionsMm=dict(width=630, height=750, depth=200)),
    "solar-sem-db": dict(kind="distributionBoard", name="SOLAR SEM-DB", nameTh="ตู้ Smart Energy Meter",
        symbol="enclosure-630x750", dimensionsMm=dict(width=630, height=750, depth=200),
        notes="Only in the internal (EXL-LV) station."),
    "enclosure-630x750": dict(kind="enclosure", name="Wall enclosure 630x750", dimensionsMm=dict(width=630, height=750, depth=200),
        notes="Shared symbol for METER-DB and SEM-DB."),
    "solar-dc-db": dict(kind="distributionBoard", name="SOLAR DC-DB", nameTh="ตู้ DC-DB โซลาร์",
        dimensionsMm=dict(width=700, height=1000, depth=250)),
    "db-enclosure": dict(kind="enclosure", name="DB enclosure (side view)", dimensionsMm=dict(width=250, height=1000)),
    "growatt-max-125ktl3-lv": dict(kind="inverter", name="Growatt MAX 125KTL3-X LV", inverterSpec="components/inverters/growatt-max-125ktl3-x-lv.json",
        dimensionsMm=dict(width=970, height=640, depth=365),
        notes="Front block in the DXF is named 'MAX60 KTL3-X' but its text and labels say MAX125KTL3-LV. Top-view block is 1075 wide (includes side handles). EXL-HV inserts it at 0.9 scale."),
    "growatt-max-80ktl3-lv": dict(kind="inverter", name="Growatt MAX 80KTL3 LV", inverterSpec="components/inverters/growatt-max-80ktl3-lv.json",
        dimensionsMm=dict(width=860, height=628, depth=301)),
    "growatt-40ktl3-x": dict(kind="inverter", name="Growatt 40KTL3-X", inverterSpec=None,
        dimensionsMm=dict(width=580, height=600),
        notes="Labelled 'GROWATT 40kTL3-X' in EXL-HV; no inverter spec JSON exists yet in components/inverters/. Depth not drawn."),
    "inverter-generic": dict(kind="inverter", name="Inverter (side view)", dimensionsMm=dict(depth=382, height=710),
        notes="Generic side profile; LV drawing inserts it smaller (329x611)."),
    "steel-column-150": dict(kind="structure", name="Steel column 150x150", dimensionsMm=dict(width=150, depth=150),
        notes="Simplified plan symbol used on the station grids (150 plate + 75 tube). Detailed version: column-base-plate-detail."),
    "column-base-plate-detail": dict(kind="structure", name="Column base plate with anchor bolts (plan detail)",
        nameTh="แผ่นเพลทฐานเสาพร้อมพุก",
        dimensionsMm=dict(width=150, depth=150),
        plate=dict(widthMm=150, depthMm=150),
        column=dict(section="SHS", outerMm=75, wallMm=2.4, layerName="S-100X100X3-2"),
        anchorBolts=dict(count=4, spacingMm=105, edgeDistanceMm=22.5, holeDiaMm=18, boltDiaMm=9,
                         washerDiaMm=14.5, nutAcrossFlatsMm=15),
        usedBy="steel-column-150",
        notes="From Part_1.dxf, measured as drawn. The tube layer is named S-100X100X3-2 (100x100x3.2) but the tube is drawn 75x75x2.4, exactly 0.75x. At 1:0.75 the plate would be 200x200, matching base-plate-200 in the station elevations. Confirm the true size before using it for BOQ or fabrication."),
    "base-plate-200": dict(kind="structure", name="Base plate 200", dimensionsMm=dict(width=200, height=10)),
    "concrete-footing-200x100": dict(kind="structure", name="Concrete footing", nameTh="ขาเก๊าปูน", dimensionsMm=dict(width=200, height=100)),
    "door-swing-1100": dict(kind="architectural", name="Door + swing", dimensionsMm=dict(width=1125, depth=1120)),
    "cable-gland-ac": dict(kind="accessory", name="AC cable gland"),
    "cable-gland-hex": dict(kind="accessory", name="Cable gland (plan)"),
    "mc4-connector": dict(kind="accessory", name="MC4 connector"),
    "grid-bubble": dict(kind="annotation", name="Grid bubble", notes="Attribute tag '8' holds the grid label (1..5 / A, B)."),
    "scale-figure": dict(kind="annotation", name="Human scale figure"),
    # linear items (not blocks in the drawings)
    "ac-perforated-tray-100x100": dict(kind="cableway", name="AC perforated tray 100x100 with cover", crossSectionMm=dict(width=100, height=100), cover=True),
    "ac-perforated-tray-200x100": dict(kind="cableway", name="AC perforated tray 200x100 with cover", crossSectionMm=dict(width=200, height=100), cover=True),
    "dc-perforated-tray-100x100": dict(kind="cableway", name="DC perforated tray 100x100 with cover", crossSectionMm=dict(width=100, height=100), cover=True),
    "ac-cable-ladder-200x100": dict(kind="cableway", name="AC cable ladder 200x100 (no cover)", crossSectionMm=dict(width=200, height=100), cover=False),
    "t8-led-lamp": dict(kind="lighting", name="T8 LED lamp"),
    "existing-type-c-cabinet": dict(kind="existing", name="Existing electrical cabinet TYPE C", nameTh="ตู้ไฟฟ้า TYPE C",
        notes="Existing utility cabinet the station ties into; drawn as context, not supplied."),
}

def instances(doc, name):
    ins = [e for e in doc.modelspace().query("INSERT") if e.dxf.name == name]
    out = []
    for e in ins:
        b = bbox.extents(e.virtual_entities())
        if b.has_data:
            out.append((b, e))
    return sorted(out, key=lambda t: (t[0].extmin.x, t[0].extmin.y))

def render_svg(ents, path):
    ents = [e for e in ents if e.dxftype() not in ("WIPEOUT", "ATTDEF")]
    b = bbox.extents(ents)
    w, h = max(b.size.x, 1), max(b.size.y, 1)  # entities already in mm
    cfg = Configuration(background_policy=BackgroundPolicy.OFF, color_policy=ColorPolicy.BLACK,
                        lineweight_policy=LineweightPolicy.RELATIVE_FIXED, min_lineweight=0.25)
    be = svg.SVGBackend()
    Frontend(RenderContext(ents[0].doc), be, config=cfg).draw_entities(ents)
    page = layout.Page(w, h, layout.Units.mm, margins=layout.Margins.all(0))
    s = be.get_string(page, settings=layout.Settings(fit_page=True))
    import re
    s = re.sub(r'<rect fill="#[0-9a-fA-F]+" x="0" y="0"[^>]*/>', '', s, count=1)
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', s).group(1).split()]
    sw = max(vb[2], vb[3]) * 0.004  # ~0.4 % of the symbol's longest side
    s = re.sub(r'stroke-width: [0-9.]+;', f'stroke-width: {sw:.0f};', s)
    with open(path, "w") as f:
        f.write(s)
    return r(w), r(h)

os.makedirs(f"{OUT}/svg", exist_ok=True)
os.makedirs(f"{OUT}/stations", exist_ok=True)

lib = ezdxf.new("R2018", units=4)
lib.header["$INSUNITS"] = 4
for cid, view, fk, blk, idx in SYMBOLS:
    if blk is None:  # part drawn loose in modelspace
        ents = [e.copy() for e in docs[fk].modelspace()]
        b = bbox.extents(ents)
    else:
        b, ins = instances(docs[fk], blk)[idx]
        ents = list(ins.virtual_entities())
    # normalise: move bbox min to origin, scale m -> mm
    xf = Matrix44.translate(-b.extmin.x, -b.extmin.y, 0) @ Matrix44.scale(M, M, M)
    for e in ents:
        try: e.transform(xf)
        except Exception: pass
    w, h = render_svg(ents, f"{OUT}/svg/{cid}-{view}.svg")
    # DXF block library
    bname = f"TCR_{cid}_{view}".upper().replace("-", "_")
    nb = lib.blocks.new(bname)
    for e in ents:
        if e.dxftype() in ("WIPEOUT",): continue
        try: nb.add_entity(e.copy())
        except Exception: pass
    c = CATALOG.setdefault(cid, {})
    c.setdefault("views", {})[view] = dict(svg=f"svg/{cid}-{view}.svg", dxfBlock=bname, bboxMm=dict(width=w, height=h),
                                           source=dict(file=FILES[fk], block=blk or "modelspace"))

# lay the library blocks out in a row so the DXF opens readable
x = 0
for blk in lib.blocks:
    if blk.name.startswith("TCR_"):
        bb = bbox.extents(blk)
        lib.modelspace().add_blockref(blk.name, (x, 0))
        lib.modelspace().add_text(blk.name, height=40, dxfattribs={"insert": (x, -120)})
        x += (bb.size.x if bb.has_data else 200) + 400
lib.saveas(f"{OUT}/tcroof-station-blocks.dxf")

for cid, c in CATALOG.items():
    c["id"] = cid
json.dump(dict(schemaVersion=1, units="mm", generatedFrom=list(FILES.values()),
               components=sorted(CATALOG.values(), key=lambda c: (c["kind"], c["id"]))),
          open(f"{OUT}/catalog.json", "w"), ensure_ascii=False, indent=2)

# ---------------------------------------------------------------- stations
def find_pl(doc, w, h, region):
    out = []
    for e in doc.modelspace().query("LWPOLYLINE"):
        b = bbox.extents([e])
        if abs(b.size.x - w) < 0.01 and abs(b.size.y - h) < 0.01 and region(b):
            out.append(b)
    return sorted(out, key=lambda b: b.extmin.x)

def place(doc, spec, region, ox, oz):
    kind, key, n = spec
    if kind == "blk":
        cands = [b for b, _ in instances(doc, key) if region(b)]
    else:
        cands = find_pl(doc, key[0], key[1], region)
    b = cands[n]
    return dict(x=r((b.extmin.x - ox) * M), z=r((b.extmin.y - oz) * M), width=r(b.size.x * M), height=r(b.size.y * M))

STATIONS = [
  dict(id="pwa-inverter-station-internal-80k", file="lv",
       name="Internal inverter station (EXL-LV) — MAX 80KTL3 LV",
       nameTh="สถานีอินเวอร์เตอร์ภายในอาคาร (ติดผนังเดิม)",
       structure=dict(type="wallRack", shelter=False, against="existing wall",
                      postsXMm=[0, 1000, 2000, 3000, 4400, 5500], rackLengthMm=5500, rackHeightMm=2000,
                      sideDepthMm=853, foundation="concrete-footing-200x100"),
       origin=(2375.824, 1062.742), front=lambda b: b.extmin.y < 1066 and b.extmax.x < 2383,
       equipment=[
         ("SOLAR AC-DB-01", "solar-ac-db", ("blk", "G$CF654F5B4", 0)),
         ("SOLAR METER-DB-01", "solar-meter-db", ("blk", "G$C6FDF2B68", 0)),
         ("SOLAR SEM-DB", "solar-sem-db", ("blk", "G$C6FDF2B68", 1)),
         ("INVERTER No.1", "growatt-max-80ktl3-lv", ("blk", "G$C1122B4A8", 0)),
         ("SOLAR DC-DB-01", "solar-dc-db", ("pl", (0.70, 1.00), 0)),
       ],
       cableways=[("ac-cable-ladder-200x100", "TYPE C cabinet → injection point"),
                  ("ac-perforated-tray-100x100", "AC-DB / METER-DB / SEM-DB interconnect"),
                  ("ac-perforated-tray-200x100", "inverter → AC-DB (top run)"),
                  ("dc-perforated-tray-100x100", "PV array → DC-DB")],
       lighting=0, existing=["existing-type-c-cabinet"]),
  dict(id="pwa-inverter-station-shelter-125k", file="inv",
       name="Inverter station with shelter — MAX 125KTL3-X LV",
       nameTh="สถานีอินเวอร์เตอร์มีหลังคา 1 เครื่อง",
       structure=dict(type="shelter", shelter=True, gridXMm=[0, 2000, 4000, 6000], gridYMm=[0, 2500],
                      gridLabelsX=["1", "2", "3", "4"], gridLabelsY=["A", "B"],
                      column="steel-column-150", basePlate="base-plate-200",
                      eaveHeightHighMm=3000, eaveHeightLowMm=2750, roof="mono-pitch",
                      rackPostsXMm=[753, 1753, 2753, 4153, 5253], rackHeightMm=2000, door="door-swing-1100"),
       origin=(2438.686, 831.452), front=lambda b: b.extmin.y < 835 and b.extmax.x < 2446,
       equipment=[
         ("SOLAR AC-DB-01", "solar-ac-db", ("blk", "G$CF654F5B4", 0)),
         ("SOLAR METER-DB-01", "solar-meter-db", ("blk", "G$C6FDF2B68", 0)),
         ("INVERTER No.1", "growatt-max-125ktl3-lv", ("blk", "MAX60 KTL3-X", 0)),
         ("SOLAR DC-DB-01", "solar-dc-db", ("pl", (0.70, 1.00), 0)),
       ],
       cableways=[("ac-cable-ladder-200x100", "TYPE C cabinet → injection point"),
                  ("ac-perforated-tray-100x100", "AC-DB ↔ METER-DB (top run)"),
                  ("ac-perforated-tray-200x100", "inverter → SOLAR AC-DB-01"),
                  ("dc-perforated-tray-100x100", "PV array → DC-DB")],
       lighting=2, existing=["existing-type-c-cabinet"]),
  dict(id="pwa-inverter-station-shelter-125k-40k", file="hv",
       name="Inverter station with shelter (EXL-HV) — MAX 125KTL3-X LV + 40KTL3-X",
       nameTh="สถานีอินเวอร์เตอร์มีหลังคา 2 เครื่อง",
       structure=dict(type="shelter", shelter=True, gridXMm=[0, 2000, 4500, 7000, 9000], gridYMm=[0, 2500],
                      gridLabelsX=["1", "2", "3", "4", "5"], gridLabelsY=["A", "B"],
                      column="steel-column-150", basePlate="base-plate-200",
                      eaveHeightHighMm=3000, eaveHeightLowMm=2750, roof="mono-pitch",
                      rackPostsXMm=[1100, 3100, 4500, 5600, 7000, 8100], rackHeightMm=2000, door="door-swing-1100"),
       origin=(2498.521, 480.528), front=lambda b: b.extmin.y < 484 and b.extmax.x < 2509,
       equipment=[
         ("SOLAR AC-DB-01", "solar-ac-db", ("blk", "G$CF654F5B4", 0)),
         ("SOLAR METER-DB-01", "solar-meter-db", ("pl", (0.63, 0.75), 0)),
         ("INVERTER No.01", "growatt-max-125ktl3-lv", ("blk", "MAX60 KTL3-X", 0)),
         ("SOLAR DC-DB-01", "solar-dc-db", ("blk", "G$C1C0043C9", 0)),
         ("INVERTER No.02", "growatt-40ktl3-x", ("blk", "G$C8D530D04", 0)),
         ("SOLAR DC-DB-02", "solar-dc-db", ("blk", "G$C1C0043C9", 1)),
       ],
       cableways=[("ac-cable-ladder-200x100", "TYPE C cabinet → injection point"),
                  ("ac-perforated-tray-200x100", "inverters → SOLAR AC-DB-01"),
                  ("dc-perforated-tray-100x100", "PV array → DC-DB-01 / DC-DB-02 → inverters")],
       lighting=3, existing=["existing-type-c-cabinet"]),
]

summary = []
for s in STATIONS:
    doc = docs[s["file"]]
    ox, oz = s["origin"]
    eq = []
    for tag, cid, spec in s["equipment"]:
        p = place(doc, spec, s["front"], ox, oz)
        eq.append(dict(tag=tag, componentId=cid, frontView=dict(xMm=p["x"], elevationMm=p["z"], widthMm=p["width"], heightMm=p["height"])))
    out = dict(schemaVersion=1, id=s["id"], name=s["name"], nameTh=s["nameTh"], units="mm",
               source=FILES[s["file"]],
               originNote="frontView.xMm from grid line 1 (or first rack post for wallRack); elevationMm from finished ground to bottom of equipment",
               structure=s["structure"], equipment=eq,
               cableways=[dict(componentId=c, route=rt) for c, rt in s["cableways"]],
               lighting=[dict(componentId="t8-led-lamp", count=s["lighting"])] if s["lighting"] else [],
               existing=[dict(componentId=c) for c in s["existing"]])
    json.dump(out, open(f"{OUT}/stations/{s['id']}.json", "w"), ensure_ascii=False, indent=2)
    summary.append(out)
print(json.dumps([[s["id"], [(e["tag"], e["frontView"]) for e in s["equipment"]]] for s in summary], ensure_ascii=False, indent=1))
