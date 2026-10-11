Follow docs/ui/survey-a1-ipad/CLAUDE_CODE_TASK.md

Update survey step A1 ข้อมูลโครงการ on iPad (`InfoPageWide.padBody` and `InfoPageBar.padBar`) to the board in docs/ui/survey-a1-ipad (`iPadA1.dc.html`, 1366 × 1024). The map, `mapZoom`, the `mapCrop` report frame, GPS, the date picker and the area steppers already exist. Keep their behaviour. Do not change the iPhone layout.

1. **Columns.** Location card on the left at 720 pt, gap 20, right column card gap 14. Both columns have equal height, and the map grows to fill its card (min 232).
2. **`ที่ตั้ง`.** Only these, in order:
   - the map, with zoom chips, `+` / `−` (44 pt hit area), scale, pin and the report frame
   - the hint plus `รีเซ็ตกรอบ`
   - `พิกัดดาวเทียม Google Map *` with the `ตำแหน่งปัจจุบัน` button and the line `ความแม่นยำ ±5 ม. · บันทึกเมื่อ 09:41`

   The station address moves out of this card.
3. **`เอกสาร`.** One row: `เลขที่` · `REV.` · `วันที่สำรวจ` · `วิศวกรผู้สำรวจ *`, ratio 0.8 : 0.6 : 1.35 : 1.25.
4. **New merged card `โครงการ · ผู้ประสานงาน`.** Rows:
   - project name
   - `ขนาดที่ต้องการติดตั้ง` (kWp) | `สัญญาณอินเตอร์เน็ต` `มี` / `ไม่มี`
   - `ที่อยู่สถานี / สถานที่ติดตั้ง`
   - `ชื่อผู้ประสานงาน` | `เบอร์โทร` (1.4 : 1)

   The card spaces its rows to fill the height.
5. **`พื้นที่ติดตั้ง *`.** Unchanged: tiles หลังคา / ถังน้ำใส with steppers, matched to the board.
6. **Styling.** Labels 17 pt semibold; inputs 50 high, radius 12; cards radius 12, 1 pt navy 20% border, padding 16 / 18.
7. **Bottom bar.**
   - Left side: badge plus `ครบ 11/11 ช่องในหน้านี้` only, with no `บันทึกอัตโนมัติ HH:mm`.
   - `บันทึกร่างตอนนี้` (170 × 56) animates like the iPhone `SaveButton`: spinner + `กำลังบันทึก` → green `บันทึกแล้ว` with a pop-in check circle (about 1.35 s) → 2 pt green outline. Any edit resets it to idle.
   - Generalise `SaveButton` (width, height, font and labels as parameters) instead of copying it. Add `-surveySave` support on iPad.

**Open questions (use the defaults):**
- `ที่อยู่สำนักงาน / สาขา` is not on the board: hide it on iPad A1 but keep the field and its export.
- Remove the autosave time line on iPad.

**Rules.**
- Thai text exactly as shown; all values are example data (`assets/sample-data.json`).
- No hex in views.
- Targets ≥ 44 pt.
- Layout only: keep the `Schema.info` ids, `mapZoom` / `mapCrop`, Excel / PDF output and completion counts.
- Use code-review-graph first, then read the source.
- Branch `feat/ipad-a1-v2`.

**Verify.**
- Build and run `swift test`.
- Compare an iPad Pro 13" simulator in landscape with `states/01-landscape.png` (measure in the PDF), the moved frame with `states/02`, and the save states with `03`–`05`.
- Check iPad portrait (one column) and that iPhone A1 is unchanged.
- Finish with a summary of the files changed, your open-question choices and any remaining differences from the board.
