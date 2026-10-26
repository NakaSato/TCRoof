#!/usr/bin/env python3
"""Thai public holidays from the team's full plan workbook, for every working-day count in the app.

The workbook's `สมมติฐาน` sheet lists them in columns K (วันที่) and L (วันหยุด), the days its plans don't count as
working days. This writes them to TCRoofKit/Sources/TCRoofCore/Resources/public-holidays.json for `PublicHolidays`;
a name saying `ตรวจสอบประกาศ ครม.` is a date still to be confirmed by the cabinet's announcement.

    python3 -I tools/plan-template/holidays.py ["Project_Plan_TCRoof/แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx"]
"""
import datetime, html, json, re, sys, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Project_Plan_TCRoof" / "แม่แบบโครงการ TCRoof (ทุกกรณี).xlsx"
out = root / "TCRoofKit/Sources/TCRoofCore/Resources/public-holidays.json"

z = zipfile.ZipFile(src)
wb = z.read("xl/workbook.xml").decode()
target = {re.search(r'Id="(rId\d+)"', r).group(1): re.search(r'Target="([^"]+)"', r).group(1)
          for r in re.findall(r"<Relationship [^>]*>", z.read("xl/_rels/workbook.xml.rels").decode())}
path = target[dict(re.findall(r'<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"', wb))["สมมติฐาน"]].lstrip("/")
path = path if path.startswith("xl/") else "xl/" + path
strings = [html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S)))
           for si in re.findall(r"<si>(.*?)</si>", z.read("xl/sharedStrings.xml").decode(), re.S)]

days = []
for _, body in re.findall(r'<row [^>]*r="(\d+)"[^>]*>(.*?)</row>', z.read(path).decode(), re.S):
    cells = {}
    for col, attrs, b in re.findall(r'<c r="([A-Z]+)\d+"([^>]*?)(?:/>|>(.*?)</c>)', body, re.S):
        v = re.search(r"<v>(.*?)</v>", b or "")
        if v:
            cells[col] = strings[int(v.group(1))] if 't="s"' in attrs else v.group(1)
    serial, name = cells.get("K"), cells.get("L")
    if serial and name and re.fullmatch(r"\d+(\.0+)?", serial):
        date = datetime.date(1899, 12, 30) + datetime.timedelta(days=int(float(serial)))
        days.append({"date": date.isoformat(), "name": name.strip(), "toConfirm": "ตรวจสอบประกาศ" in name})

days.sort(key=lambda d: d["date"])
out.write_text(json.dumps({"source": src.name, "sheet": "สมมติฐาน", "days": days}, ensure_ascii=False, indent=2) + "\n")
print(out, len(days), days[0]["date"], "…", days[-1]["date"])
