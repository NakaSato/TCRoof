# Prompt for Claude Code

Check out the design branch, create your own feature branch from it, then open Claude Code in the repo and paste:

```
git fetch origin && git switch -c feat/iec62446-step1-setup-ipad origin/design/iec62446-step1-setup-ipad
```

```
Follow docs/ui/iec62446-step1-setup-ipad/CLAUDE_CODE_TASK.md.

FIRST check the prerequisite:
- TCRoof/Views/Install/IEC/ (IECTestScreen, IECSetupSheet, IECStringGrid …) and TCRoofKit/Sources/TCRoofCore/IECReport*.swift
  must exist in this checkout.
- If they don't, STOP and report. Do not rebuild IECReport from scratch.

Then build ONLY step 1/7 "ตั้งค่าระบบ" of the IEC 62446 test on iPad (regular width), replacing IECSetupSheet:

1. Frame:
   - IECHeader "IEC 62446 · ตั้งค่าระบบ" + station line.
   - "1/7" progress with 7 capsules.
   - Two columns: left 420 pt, right card.
   - Bottom bar: status text of what's missing, บันทึกร่างตอนนี้, ‹ กลับ งานติดตั้ง, ถัดไป 2/7.
   - ถัดไป is enabled only when the SLD, date, tester and ≥1 used string exist.
     It goes to the existing next screen (IECStringGrid, before phase).
2. Left column:
   - The orange banner.
   - The Diagram card: SLD preview full-screen + zoom, file row with versions, ดูแบบ / อัปโหลด PDF / อ่านรายการสตริง.
     อ่านรายการสตริง is disabled if there is no reader; report it.
   - วันที่ทดสอบ* and ผู้ทดสอบ*.
   - สภาพการทดสอบ (E29 / E30 / AA30, linked to every inverter sheet).
   - เครื่องมือวัด S/N rows with สแกน (new optional fields).
3. Right column, the string list:
   - Inverter tabs with used/slots, plus a dashed "+ เพิ่มอินเวอร์เตอร์".
   - The inverter row: photo, model, S/N edit, สแกนป้าย, delete.
   - MPPT groups with 2 strings each (slots = MPPT × 2). Each string: a modules stepper, its Wp, and a used/SPARE toggle.
   - Totals: สตริงที่ใช้, แผงรวม, กำลังติดตั้ง (AA9).
4. The เพิ่มอินเวอร์เตอร์ sheet:
   - The model list (EquipmentCatalog if it has MPPT counts, else the board's example).
   - S/N + scan, MPPT from the model, modules per string.
   - 2 required photos + 3 optional.
   - Add creates the tab and the Excel sheet pair.
5. The delete confirmation, with what is removed. The last inverter can't be deleted.

Rules:
- Use docs/forms/iec62446-pwa/excel-cell-map.json for cells and don't change the exporter's map.
- Only add optional IECReport fields (decodeIfPresent).
- Steps 2–7 and the iPhone are out of scope.

Steps:
1. Read the task, then iPadIECStep1.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath. Run swift test in TCRoofKit with new tests (slots, totals, add/delete renumbering,
   old JSON decoding).
4. Run on an iPad Pro 13" simulator (landscape). Save screenshots 01, 03, 04 and 06 in
   docs/ui/iec62446-step1-setup-ipad/screenshots/ and compare them with states/.
5. Commit on feat/iec62446-step1-setup-ipad and push it (no merge to main).
6. Report:
   - the differences
   - what was missing as a data source
   - the open questions
```
