#!/usr/bin/env python3
"""The WBS Dictionary's done criteria and rules of credit, for the app (CHA-84).

The Master Plan's `WBS Dictionary` sheet (in the template `แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx` and the Master Plan
itself) has one row per WBS code with what "done" means (`เกณฑ์เสร็จ / Deliverable`), how it earns credit (`Rules of
credit`: `0/100`, `ร่าง 10% → ยื่น 50% → อนุมัติ 100%`, `50/50 (S = เริ่ม, Y = เสร็จ)` …), the documents that prove it
(`หลักฐาน (เอกสาร)`), the photos and the app record that stands for it. This writes them, by code, to
TCRoofKit/Sources/TCRoofCore/Resources/wbs-dictionary.json for `MasterSchedule.WBSDictionary`. A credit with steps
gives them as `steps` ({label, percent}, the last 100); any other keeps only its text, and a tick is then all or nothing.

    python3 -I tools/plan-template/wbs_dictionary.py ["<workbook with a WBS Dictionary sheet>"]
"""
import html, json, re, sys, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
book = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Project_Plan_TCRoof" / "3_แม่แบบ 20 กรณี" / "แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx"
out = root / "TCRoofKit/Sources/TCRoofCore/Resources/wbs-dictionary.json"


# the same reader as wbs_roles.py (importing it would run it)
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


def steps(credit: str):
    """`ร่าง 10% → ยื่น 50% → อนุมัติ 100%` → [{label, percent}]; `50/50 (S = เริ่ม, Y = เสร็จ)` → เริ่ม 50, เสร็จ 100."""
    if credit.startswith("50/50"):
        return [{"label": "เริ่ม", "percent": 50}, {"label": "เสร็จ", "percent": 100}]
    if "→" not in credit:
        return None
    out = []
    for part in credit.split("→"):
        m = re.fullmatch(r"\s*(.+?)\s+(\d+)\s*%\s*", part)
        if not m:
            return None
        out.append({"label": m.group(1), "percent": int(m.group(2))})
    return out if out and out[-1]["percent"] == 100 and all(a["percent"] < b["percent"] for a, b in zip(out, out[1:])) else None


def text(c, col):
    v = (c.get(col) or "").strip()
    return v or None


rows = sheet_rows(book, "WBS Dictionary")
header = rows.get(4, {})
assert header.get("A") == "WBS" and header.get("J", "").startswith("เกณฑ์เสร็จ") and header.get("K") == "Rules of credit", header
version = next((v for r, c in sorted(rows.items()) if r < 4 for v in [c.get("A", "")] if "REV" in v), "")
entries = {}
for r, c in sorted(rows.items()):
    code = (c.get("A") or "").strip()
    if r <= 4 or not code:
        continue
    # the dictionary ends at the first row that isn't a code: the tables under it (2.1's steps by point type) are laid
    # out differently
    if not re.fullmatch(r"\d+(\.\d+)+", code):
        break
    e = {"title": text(c, "D")}
    for key, col in (("done", "J"), ("credit", "K"), ("photos", "M"), ("record", "N")):
        if text(c, col):
            e[key] = text(c, col)
    if text(c, "L"):
        e["evidence"] = [s.strip() for s in text(c, "L").split(",") if s.strip()]
    s = steps(e.get("credit", ""))
    if s:
        e["steps"] = s
    entries[code] = e

rev = re.search(r"REV \d+", version)
out.write_text(json.dumps({"source": book.name, "revision": rev.group(0) if rev else None, "entries": entries},
                          ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
print(out, len(entries), "rows,", sum("steps" in e for e in entries.values()), "with steps")
