#!/usr/bin/env python3
"""Whose job each WBS row is, from the 20 install cases.

The cases' `แผนโครงการ` sheet names a role, not a person, in `ผู้รับผิดชอบ`: `วศ.` / `วศ.01` (the team's engineer),
`Admin`, `ผรม.` / `ผรม. 01` (the subcontractor). The 102 station files put that station's people in the same rows.
This writes code → role (`engineer`, `admin`, `contractor`) for every row all 20 cases agree on to
TCRoofKit/Sources/ExcelExport/Resources/wbs-roles.json for `MPTemplates.roles`, which export uses to write the job's
own people into those rows. Rows of the utility (`กฟภ.`, `พพ.`) and rows without an owner are left out.

    python3 -I tools/plan-template/wbs_roles.py ["Project_Plan_TCRoof/3_แม่แบบ 20 กรณี/แผนโครงการ นำเข้า TCRoof"]
"""
import html, json, re, sys, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
folder = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Project_Plan_TCRoof" / "3_แม่แบบ 20 กรณี" / "แผนโครงการ นำเข้า TCRoof"
out = root / "TCRoofKit/Sources/ExcelExport/Resources/wbs-roles.json"


def sheet_rows(path: Path, name: str) -> dict[int, dict[str, str]]:
    z = zipfile.ZipFile(path)
    wb = z.read("xl/workbook.xml").decode()
    rels = z.read("xl/_rels/workbook.xml.rels").decode()
    target = {}
    for rel in re.findall(r"<Relationship [^>]*>", rels):
        target[re.search(r'Id="(rId\d+)"', rel).group(1)] = re.search(r'Target="([^"]+)"', rel).group(1)
    rid = dict(re.findall(r'<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"', wb))[name]
    p = target[rid].lstrip("/")
    p = p if p.startswith("xl/") else "xl/" + p
    strings = [html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S)))
               for si in re.findall(r"<si>(.*?)</si>", z.read("xl/sharedStrings.xml").decode(), re.S)]
    rows = {}
    for r, body in re.findall(r'<row [^>]*r="(\d+)"[^>]*>(.*?)</row>', z.read(p).decode(), re.S):
        cells = {}
        for col, attrs, b in re.findall(r'<c r="([A-Z]+)\d+"([^>]*?)(?:/>|>(.*?)</c>)', body, re.S):
            v = re.search(r"<v>(.*?)</v>", b or "") or re.search(r"<t[^>]*>(.*?)</t>", b or "", re.S)
            if v:
                cells[col] = strings[int(v.group(1))] if 't="s"' in attrs else html.unescape(v.group(1))
        rows[int(r)] = cells
    return rows


def role(text: str) -> str | None:
    t = text.strip()
    if t.startswith("วศ"):
        return "engineer"
    if t == "Admin":
        return "admin"
    if t.startswith("ผรม"):
        return "contractor"
    return None


files = sorted(folder.glob("*.xlsx"))
assert len(files) == 20, f"{len(files)} case files in {folder}"
seen: dict[str, set] = {}
for f in files:
    rows = sheet_rows(f, "แผนโครงการ")
    head = next(r for r, c in sorted(rows.items()) if c.get("A", "").strip() == "WBS")
    owner = next(col for col, v in rows[head].items() if v.strip() == "ผู้รับผิดชอบ")
    for r, c in rows.items():
        code = c.get("A", "").strip()
        if r <= head or not re.fullmatch(r"\d+(\.\d+)*", code):
            continue
        seen.setdefault(code, set()).add(role(c.get(owner, "")))

roles = {code: next(iter(v)) for code, v in seen.items() if len(v) == 1 and None not in v}
mixed = sorted(code for code, v in seen.items() if len(v - {None}) > 1)
assert not mixed, f"the cases disagree on {mixed}"
ordered = dict(sorted(roles.items(), key=lambda kv: [int(p) for p in kv[0].split(".")]))
out.write_text(json.dumps({"source": folder.name, "sheet": "แผนโครงการ", "column": "ผู้รับผิดชอบ", "roles": ordered},
                          ensure_ascii=False, indent=2) + "\n")
print(out, len(ordered), "rows")
