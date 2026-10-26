#!/usr/bin/env python3
"""Each site type's own 2.1 structure sub-tasks, from the team's full plan workbook.

The workbook's `จุดติดตั้ง` sheet keeps, in columns Z–AD (key, ประเภท, ขั้น, งานย่อย, %), the names and the % split
of 2.1.1–2.1.7 for every site type; the 20 import files carry only the generic list. This writes them to
TCRoofKit/Sources/ExcelExport/Resources/site-steps.json for `MPTemplates.siteSteps`.

    python3 -I tools/plan-template/site_steps.py ["Project_Plan_TCRoof/แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx"]
"""
import html, json, re, sys, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Project_Plan_TCRoof" / "แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx"
out = root / "TCRoofKit/Sources/ExcelExport/Resources/site-steps.json"

z = zipfile.ZipFile(src)
wb = z.read("xl/workbook.xml").decode()
rels = z.read("xl/_rels/workbook.xml.rels").decode()
target = {}
for rel in re.findall(r"<Relationship [^>]*>", rels):
    target[re.search(r'Id="(rId\d+)"', rel).group(1)] = re.search(r'Target="([^"]+)"', rel).group(1)
rid = dict(re.findall(r'<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"', wb))["จุดติดตั้ง"]
path = target[rid].lstrip("/")
path = path if path.startswith("xl/") else "xl/" + path
strings = [html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S)))
           for si in re.findall(r"<si>(.*?)</si>", z.read("xl/sharedStrings.xml").decode(), re.S)]
sheet = z.read(path).decode()

sites: dict[str, list] = {}
for _, body in re.findall(r'<row [^>]*r="(\d+)"[^>]*>(.*?)</row>', sheet, re.S):
    cells = {}
    for col, attrs, b in re.findall(r'<c r="([A-Z]+)\d+"([^>]*?)(?:/>|>(.*?)</c>)', body, re.S):
        v = re.search(r"<v>(.*?)</v>", b or "")
        if not v:
            continue
        cells[col] = strings[int(v.group(1))] if 't="s"' in attrs else html.unescape(v.group(1))
    site, step, title, pct = (cells.get(c) for c in ("AA", "AB", "AC", "AD"))
    if not (site and step and title and pct) or not step.isdigit():
        continue
    sites.setdefault(site.strip(), []).append({"step": int(step), "title": title.strip(), "percent": float(pct)})

for site, steps in sites.items():
    steps.sort(key=lambda s: s["step"])
    total = sum(s["percent"] for s in steps)
    assert abs(total - 100) < 1e-6, f"{site}: {total}%"
out.write_text(json.dumps({"source": src.name, "sheet": "จุดติดตั้ง", "sites": sites}, ensure_ascii=False, indent=2) + "\n")
print(out, {k: len(v) for k, v in sites.items()})
