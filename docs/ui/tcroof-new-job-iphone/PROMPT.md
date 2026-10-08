Follow docs/ui/tcroof-new-job-iphone/CLAUDE_CODE_TASK.md

Give the iPhone "add new customer" sheet (`NewJobView`, opened from the `+` FAB on `PhoneSurveyList`) the iOS grouped-list design from docs/ui/tcroof-new-job-iphone.

**Scope.**
- Compact width only; the iPad `NewJobView` must stay as it is.
- Residential jobs only (งานบ้าน): no links to PWA / กปภ. screens.

1. **Header.** `TCGradientHeader`:
   - an `xmark` cancel button (label `ยกเลิก`)
   - title `เพิ่มลูกค้าใหม่`
   - subtitle `สำรวจหน้างาน · งานบ้าน`
   - no toolbar save
2. **Group `ลูกค้า`.** Inset cards (white, r12, 52 pt rows, 96 pt labels, trailing values, 16 pt-inset separators):
   - `ชื่อลูกค้า *`
   - `เบอร์โทร`: phone pad, formatted `081-234-5678`
   - `ที่อยู่`: multi-line
   - `จังหวัด ›`
3. **Group `นัดสำรวจ`.**
   - `วันที่ ›` (`พรุ่งนี้ · พฤ. 1 ต.ค.`) and `เวลา ›` (`09:00 น.`), values in blue
   - footer `ทีม TCR01 จะเห็นนัดนี้ในปฏิทินแผนก่อสร้าง`
4. **Collapsed `รายละเอียดงาน · ไม่บังคับ`** (`แสดง` / `ซ่อน`):
   - rows: `ขนาดระบบ ›` (`5 kWp · ~9 แผง`), `ทีม ›` (team colour), `ชื่องาน` (placeholder `ใช้ชื่อลูกค้า`), `เริ่มติดตั้ง ›` (`+14 วัน · 2 วัน`)
   - footer with the estimated install range
5. **One reusable grid-picker sheet** for date, time, kWp, team and install timing:
   - 56 pt options in 2–4 columns
   - selected: 2 pt `#007AFF` border, `#EAF3FF` fill
   - `เสร็จ` closes
   - presets are in `assets/sample-data.json`
6. **Province sheet** (large detent):
   - search `ค้นหาจังหวัด`
   - `ใช้บ่อย` chips
   - all 77 provinces grouped by first consonant (skip a leading เ แ โ ใ ไ), with ✓ on the selected one
   - put the list in a testable `ThaiProvince` type in TCRoofCore
7. **Pinned save button.**
   - 54 pt, r14
   - title `บันทึกลูกค้า` with a live sub-line
   - states: grey (no name, still tappable) → red validation (`ใส่ชื่อลูกค้าก่อน`) → blue gradient → `✓ บันทึกแล้ว`
8. **Saved banner.**
   - navy banner `เพิ่มลูกค้าแล้ว · <code> · อยู่ในรายการงานสำรวจ`
   - `เปิดงาน` opens `JobDetailView` for the new job; otherwise auto-dismiss

**Input.** The board's number pads are canvas stand-ins. Use real `TextField`s with the right keyboards, and keep the validation rules (phone 9–10 digits; custom kWp 1–100, step 0.5).

**Tokens.** No hex in views:
- prefer iOS system colours
- add the missing ones with dark values: `groupedPage` `#F7F7FA`, `optionSelected` `#EAF3FF`
- team colours come from `Team.color`

**Rules.**
- `.sarabun` fonts.
- Thai UI text exactly as in the previews.
- Touch targets ≥ 44 pt.
- No model or sync changes (`Job.province` stays a String).
- Use code-review-graph first, then read the source.
- Work on a new branch `feat/iphone-new-job`.

**Verify.**
- Build, open the sheet on an iPhone 16 simulator, and compare with `states/*.png` (measure in the PDFs).
- Add `ThaiProvince` unit tests: 77 entries, no duplicates, group keys, search.

**Finish** with a summary:
- the files changed
- tokens and components added
- remaining differences
- answers to the open questions
