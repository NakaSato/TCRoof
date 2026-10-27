"""Build manufacturer cable-tray catalogues from Revit .rvt content projects.

python3 -I mfr.py <niedax.bin> <excel.bin> <out-dir>
(*.bin = decompressed RVT partition data from rvt_dump.py)

Writes <out-dir>/trays/niedax.json and <out-dir>/trays/excel-ezfit.json.
Only facts present in the RVT are recorded; derived values are labelled as such.
"""
import json, os, re, sys
from collections import defaultdict

STEEL = 7.85  # kg/dm3

def strings(path):
    b = open(path, "rb").read()
    s = [x.decode("utf-16-le") for x in re.findall(rb"(?:[\x20-\x7e]\x00){2,}", b)]
    return [x for x in s if not x.startswith("autodesk.")]

def schedule_rows(S, type_re):
    rows = {}
    for i, s in enumerate(S[:-6]):
        if re.fullmatch(type_re, s):
            w = S[i + 1:i + 5]
            km = [x for x in w if x.endswith("kg/m")]
            ln = [x for x in w if re.fullmatch(r"[\d.]+ m", x)]
            if km:
                rows[s] = dict(kgPerM=float(km[0].split()[0]), sampleLengthM=float(ln[0].split()[0]) if ln else None)
    return rows

def kind_of(desc):
    d = desc.lower()
    if "cable-tray" in d: return "straight"
    if "cover" in d: return "cover"
    if any(k in d for k in ("elbow", "tee", "cross", "reducer")): return "fitting"
    if any(k in d for k in ("connector", "coupler", "divider")): return "accessory"
    if any(k in d for k in ("bracket", "plate", "profile")): return "support"
    return "other"

FINISH = {"": "Pre Galvanized", "F": "Hot-dip Galvanized", "E3": "Stainless Steel E3", "E5": "Stainless Steel E5", "OV": "Pre Galvanized (OV)"}

def is_perforated(code):
    return "U" not in code  # RLU, RLUC, RSU: unperforated (see notes)

# ---------------------------------------------------------------- Niedax
def niedax(path):
    S = strings(path)
    fams = {}
    for s in set(S):
        m = re.fullmatch(r"Electrical_Distribution_Niedax_([A-Z0-9+]+)_(.+)", s)
        if m:
            code, desc = m.group(1), m.group(2)
            f = fams.setdefault(code, dict(code=code, families=set(), kind=kind_of(desc), description=None))
            f["families"].add(s)
            f["description"] = re.sub(r"_(Pre Galvanized|Hot-dip Galvanized|Stainless Steel E3)$", "", desc).replace("_", " ")
    # per-family available size lists (Revit parameters NX_Available Heights/Widths)
    avail = defaultdict(lambda: dict(heights=set(), widths=set()))
    for i, s in enumerate(S):
        if s in ("CABLETRAYSEGMENT", "CABLETRAYFITTING"):
            pre = [c for c in S[i - 14:i] if re.fullmatch(r"[A-Z]{1,7}", c)]
            mm = [c for c in S[i + 1:i + 6] if c.endswith(" mm") and "," in c or re.fullmatch(r"\d+ mm", c)]
            if pre and len(mm) >= 2:
                avail[pre[-1]]["heights"] |= {int(x) for x in re.findall(r"\d+", mm[0])}
                avail[pre[-1]]["widths"] |= {int(x) for x in re.findall(r"\d+", mm[1])}
    types = defaultdict(set)
    for s in set(S):
        m = re.fullmatch(r"([A-Z]{1,7}) (\d{2,3})\.(\d{3})(?: (F|E3|E5|OV))?", s)
        if m:
            types[m.group(1)].add((int(m.group(2)), int(m.group(3)), m.group(4) or ""))
        m = re.fullmatch(r"([A-Z]{1,7}) (\d{2,3})(?: (F|E3|E5))?", s)  # covers etc. by width
        if m and m.group(1) in fams:
            types[m.group(1)].add((None, int(m.group(2)), m.group(3) or ""))
    sched = schedule_rows(S, r"[A-Z]{1,7} \d{2,3}\.\d{3}( (F|E3|E5))?")

    # sheet thickness from schedule weight: developed width = W + 2H + 2x12 lip
    def est_t(code):
        out = []
        for name, r in sched.items():
            m = re.fullmatch(rf"{code} (\d+)\.(\d+)( F| E3)?", name)
            if not m: continue
            h, w = int(m.group(1)), int(m.group(2))
            dev = (w + 2 * h + 24) / 1000
            t = r["kgPerM"] / (dev * STEEL)
            if is_perforated(code):  # perforated: ~15 % open area (RL vs RLU, RS vs RSU)
                t /= 0.85
            out.append(t)
        return round(sum(out) / len(out) * 4) / 4 if out else None

    families = []
    for code, f in sorted(fams.items()):
        tl = []
        for h, w, fin in sorted(types.get(code, set()), key=lambda t: (t[0] or 0, t[1], t[2])):
            name = f"{code} {h}.{w:03d}" if h else f"{code} {w}"
            name += f" {fin}" if fin else ""
            t = dict(type=name, heightMm=h, widthMm=w, finish=FINISH[fin])
            if f["kind"] == "straight":
                perforated = is_perforated(code)
                t["geometryId"] = f"{'perforated' if perforated else 'solid'}-tray-{w}x{h}"
            if name in sched:
                t.update(sched[name])
            tl.append(t)
        desc = f["description"]
        if f["kind"] == "cover":
            base = re.sub(r"D?DV?$", "", code)
            desc = ("Cover for straight trays" if base == "R" else f"Cover for {base}") + (" (DV variant)" if code.endswith("DV") else "")
        fam = dict(code=code, kind=f["kind"], description=desc, revitFamilies=sorted(f["families"]),
                   finishes=sorted({FINISH[x[2]] for x in types.get(code, set())}), types=tl)
        if code in avail:
            fam["availableHeightsMm"] = sorted(avail[code]["heights"])
            fam["availableWidthsMm"] = sorted(avail[code]["widths"])
        if f["kind"] == "straight":
            fam["standardLengthM"] = 6.0
            th = est_t(code)
            if th:
                fam["sheetThicknessMmEstimated"] = th
            fam["perforated"] = is_perforated(code)
        families.append(fam)
    return dict(schemaVersion=1, manufacturer="Niedax GmbH & Co. KG", website="https://www.niedax.de/en/home/",
                productDatabase="https://products.niedax.de/", bimContact="bim@niedax-group.com",
                etimClass="EC000047", source="Electrical_Distribution_Niedax_Cable_Trays_2022.rvt",
                typeNaming="<CODE> <height>.<width> [F = hot-dip galvanized | E3/E5 = stainless]; no suffix = pre-galvanized",
                notes=["Sizes, finishes, family names and sample weights come straight from the Revit content.",
                       "sheetThicknessMmEstimated is derived from the schedule kg/m (steel 7.85, ~15 % open area for perforated) and is not a catalogue value.",
                       "'perforated' is inferred: RLU/RSU weigh ~15 % more than RL/RS of the same size at the same derived thickness, consistent with unperforated bases. Confirm against the Niedax catalogue."],
                families=families)

# ---------------------------------------------------------------- Excel EZ-FIT
def excel(path):
    S = strings(path)
    fams = {}
    for s in set(S):
        m = re.fullmatch(r"Electrical_Distribution_Excel_(?:Electric_Group_)?(.+)", s)
        if m:
            fams[s] = m.group(1)
    codes = defaultdict(set)
    for s in set(S):
        m = re.fullmatch(r"(M|H)(TX|FB|HB|ET|X|RBI|RBO) ?(\d{2,3})", s)
        if m and int(m.group(3)) in (50, 75, 100, 150, 225, 300, 450, 600):
            codes[m.group(2)].add((m.group(1), int(m.group(3))))
    sched = schedule_rows(S, r"(M|H)TX\d{2,3}")
    series = {"TX": ("straight", "Straight length", "EZ-FIT-Cable_Tray"),
              "FB": ("fitting", "Horizontal elbow 90°", "MFB-HFB_Channel-Elbow_90Deg"),
              "HB": ("fitting", "Horizontal elbow 45°", "MHB-HHB_Channel-Elbow_45Deg"),
              "ET": ("fitting", "Tee", "MET-HET_Channel-Tee"),
              "X": ("fitting", "Cross", "MX-HX_Channel-Cross"),
              "RBI": ("fitting", "Vertical elbow 90° inside", "MRBI-HRBI_Channel-Vertical-Elbow_90Deg Inside"),
              "RBO": ("fitting", "Vertical elbow 90° outside", "MRBO-HRBO_Channel-Vertical-Elbow_90Deg Outside")}
    families = []
    for key, (kind, desc, famkey) in series.items():
        tl = []
        for pre, w in sorted(codes.get(key, set())):
            t = dict(type=f"{pre}{key}{w}", series=pre, widthMm=w, heightMm=None, finish="Hot-dip Galvanized")
            if t["type"] in sched:
                t.update(sched[t["type"]])
            tl.append(t)
        fam = dict(code=key, kind=kind, description=desc,
                   revitFamilies=sorted(f for f in fams if famkey in f), types=tl)
        if kind == "straight":
            fam.update(availableHeightsMm=[25, 50], availableWidthsMm=sorted({t["widthMm"] for t in tl}),
                       maxLengthPerPieceM=2.95)
        families.append(fam)
    return dict(schemaVersion=1, manufacturer="Excel Electric Group", productLine="EZ-FIT", finish="Hot-dip Galvanized",
                source="Electrical_Distribution_Excel_Electric_Group_EZ-FIT_Cable_Tray_2019.rvt",
                typeNaming="<M|H><series><width>, e.g. MTX225 = M-series straight, 225 wide",
                notes=["The RVT lists available heights 25 and 50 mm but doesn't tie them to the M/H prefixes in readable form. heightMm is left null until confirmed (likely M = 25, H = 50).",
                       "Only MTX225 has a schedule weight in the file (4.400 kg/m, 2.95 m pieces)."],
                families=families)

if __name__ == "__main__":
    nb, eb, out = sys.argv[1:4]
    os.makedirs(f"{out}/trays", exist_ok=True)
    n = niedax(nb); e = excel(eb)
    json.dump(n, open(f"{out}/trays/niedax.json", "w"), ensure_ascii=False, indent=1)
    json.dump(e, open(f"{out}/trays/excel-ezfit.json", "w"), ensure_ascii=False, indent=1)
    for d in (n, e):
        print(d["manufacturer"])
        for f in d["families"]:
            print(f"  {f['code']:7s} {f['kind']:9s} types={len(f['types']):3d} {f.get('sheetThicknessMmEstimated','')} {f['description']}")
