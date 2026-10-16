# Prompt for Claude Code

Check out the design branch, create your own feature branch from it, then open Claude Code in the repo and paste:

```
git fetch origin && git switch -c feat/iec62446-step2-before-vi-ipad origin/design/iec62446-step2-before-vi-ipad
```

```
Follow docs/ui/iec62446-step2-before-vi-ipad/CLAUDE_CODE_TASK.md.

FIRST check the prerequisite:
- TCRoof/Views/Install/IEC/ (IECTestScreen, IECStringGrid, IECStringEntry, IECPhotos …) and
  TCRoofKit/Sources/TCRoofCore/IECReport*.swift must exist in this checkout.
- If they don't, STOP and report. Do not rebuild IECReport.

Then build ONLY step 2/7 "ก่อนออน · แรงดัน / กระแส" of the IEC 62446 test on iPad (regular width).
It replaces the before-phase V/A entry there (IECStringGrid table + IECStringEntry). iPhone keeps today's screens.

1. Frame:
   - Header "IEC 62446 · ก่อนออนระบบ · แรงดัน / กระแส" + station line.
   - "2/7" progress with 7 capsules.
   - Two columns: left 420 pt, right card.
   - Bottom bar: status text, บันทึกร่างตอนนี้, ‹ ก่อนหน้า 1/7, ถัดไป 3/7 (link to existing screens until those steps exist; report).
2. Left column:
   - Inverter cards with progress.
   - The orange banner (rows 12, 16, 18).
   - The DC input map (MPPT × 2 round slots: done / to-do / failed / empty), legend, the ตั้งช่อง n เป็นว่าง link.
   - The selected string bar with ‹ ›.
   - ① ถ่ายรูป → ② ป้อนค่าจากรูป, the continuous-mode button.
   - The red alert with วัดซ้ำ when the string fails.
   - The two photo cards (มิเตอร์ V E16, แคลมป์ A E18), or the empty-slot note.
3. Right column, the table:
   - Filter all / ยังไม่ครบ / ไม่ผ่าน.
   - Columns สตริง, MPPT · ช่อง, แผง, Voc, ต่าง, กระแส, ขั้ว, ผล; empty slots as muted rows; row tap selects.
   - Footer: measured count, median per module-count group, V per module, polarity.
4. The entry dialog:
   - Photo + DC box location strip + ถ่ายใหม่ / ซูมรูป.
   - The value tile, the auto polarity segment (Voc only), "อ่านจากรูป … ใช้ค่านี้" from Vision (reuse LiveTextScanner).
   - Orange warning when the typed value differs > 1 % from the reading.
   - The 4×4 number pad. บันทึก goes V → clamp photo → A → next string.
5. Continuous mode: walks only unfinished strings, with โหมดต่อเนื่อง n/m and หยุด.
6. DEBUG flags -iecStep2 YES and -iecStep2State … (see the task), one line in CLAUDE.md.

Rules:
- Voc ±5 % of the median of strings with the SAME module count; before-energising current must be 0 A;
  polarity from the Voc sign unless set by hand.
- Use docs/forms/iec62446-pwa/excel-cell-map.json; don't change the exporter's map or Excel cells.
- Only add optional IECReport fields (decodeIfPresent).
- Steps 1 and 3–7 and the iPhone are out of scope.

Steps:
1. Read the task, then iPadIECStep2.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test in TCRoofKit with the new tests in the task.
4. Run on an iPad Pro 13" simulator (landscape). Save screenshots 01, 03, 05, 06 and 07 in
   docs/ui/iec62446-step2-before-vi-ipad/screenshots/ and compare them with states/.
5. Commit on feat/iec62446-step2-before-vi-ipad and push it (no merge to main).
6. Report:
   - the differences
   - where ก่อนหน้า / ถัดไป link to
   - what was missing as a data source
   - the open questions
```
