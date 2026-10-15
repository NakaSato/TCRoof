# Task: IEC 62446 · step 4/7 "หลังออน · แรงดัน / กระแส" (iPad)

Board: `iPadIECStep4.dc.html` (1366 × 1024). States: `states/*.png`. Assets: `assets/iec/`.

Branch: this hand-off lives on `design/iec62446-step4-after-vi-ipad`, cut from `feat/iec62446-step2-before-vi-ipad` (428390e, step 2 built).
Work on `feat/iec62446-step4-after-vi-ipad` cut from it, and push it. Do not merge.

## Scope: only this

Step 4 is the same page as step 2, for the **after-connection** phase: Vmp and Imp while the system feeds power.
The board's script is identical to step 2's; only `step = 4` changes what it shows.

**Do NOT copy the step-2 page.** Generalise it:
- `IECBeforeVIPage`, `IECBeforeVIEntry`, `IECBeforeVIParts`, `IECBeforeVIPage+Actions` take a phase (`IECReport.Phase`). Rename to `IECVIPage…` if it stays readable; report the names.
- Rules: extend `IECReport+BeforeVI.swift` (or a sibling `+AfterVI`) with the after-phase rules below, with tests.

Out of scope: steps 1, 3, 5–7, the iPhone, the Excel cell map, the Word appendix.

## Prerequisite

`TCRoof/Views/Install/IEC/IECBeforeVI*.swift` and `TCRoofKit/Sources/TCRoofCore/IECReport+BeforeVI.swift` exist on this branch. If not, STOP and report.

## Data

| Board | Model | Excel (`INV nn-หลัง`) |
|---|---|---|
| Vmp (V) | `Slot.vmpV` | row 17 |
| Imp (A) | `Slot.impA` | row 19 |
| photo มิเตอร์ V / แคลมป์ A | `photos[.voltageAfter]`, `[.currentAfter]` | Word board 7 "ภาพถ่าย IEC-test After" |
| column | slot 1 = E … (same as step 2) | |
| `ออนระบบแล้ว 13:20 น.` | `IECReport.after.time` (Conditions) | |

## Rules (after phase)

- **Vmp** passes within ±5 % of the median Vmp of the inverter's strings with the **same module count** (same as Voc in step 2; reuse the median helper, add `vmpDeviation`).
- **Imp** has no pass/fail: any value is recorded (`✓ บันทึกแล้ว`); the empty hint is `ใกล้เคียงสตริงอื่น`. Do not apply the 0 A rule.
- **No polarity** in this phase: no ขั้ว column, no ✓ถูกต้อง / ✗กลับขั้ว segment in the dialog.
- A string is done when Vmp and Imp are set; failed when Vmp is off.
- The OCR prefill and the > 1 % "differs from the photo" warning work as in step 2.

## Change list (differences from step 2)

1. **Header** `IEC 62446 · หลังออนระบบ · แรงดัน / กระแส`; `4/7`, the 4th capsule current.
2. **Banner is green** (ok style, ✓ icon): `ออนระบบแล้ว HH:MM น. · วัดขณะจ่ายไฟ` / `แรงดัน Vmp และกระแส Imp · เติม INV 0n-หลัง แถว 17, 19`.
   Without `after.time`, show `ออนระบบแล้ว · วัดขณะจ่ายไฟ` and report it.
3. **Photo cards**: `มิเตอร์ V` → cell `E17`, `แคลมป์ A` → `E19`; the report line `รูปนี้ถ่ายไปที่ 7 · ภาพถ่าย IEC-test After · หน้า n · ช่อง INV1ST1 · Vmp + Imp`.
4. **Dialog**: titles `มิเตอร์ V · หลังออน` / `แคลมป์ A · หลังออน`, tiles `แรงดัน Vmp` (E17) / `กระแส Imp` (E19), no polarity row. Sub line `… เติม E17 · INV 01-หลัง · รูปไปที่รายงาน 7 หน้า n`.
5. **Table** `ตารางค่าวัด · INV1 หลังออนระบบ`, columns: String · MPPT · ช่อง · แผง · Vmp (V) · ต่าง · Imp (A) · ผล.
6. **Footer**, 4 cells: `วัดแล้ว n / m สตริง` · `มัธยฐาน Vmp x V` · `กระแสรวม x A` (sum of Imp) · `Excel แถว 17 · 19`.
7. **Bottom bar**: `‹ ก่อนหน้า 3/7 ก่อนออน · ฉนวน (IR)` and `ถัดไป 5/7 พลังงานและ PR ›` (link to the existing screens until those steps are built; report). Status text: `วัดแล้ว INV1 n/16 · INV2 n/8`, or `มีค่าไม่ผ่าน n สตริง`.
8. **Board updates since step 2 was built** (apply in the shared parts, so step 2 gets them too):
   - Table string column reads `String 1`, `String 2` … (not `INV1ST1`). The chip, dialog and map keep `INV1ST1` / `ST1`.
   - Selected slot in the DC input map: **yellow** highlight. The slot keeps its status fill and gets a white 2 pt gap + 3 pt `#FFD400` ring + 1 pt `#8A6D00` outline. Its MPPT column gets a `#FFF6CC` fill with a 1.5 pt `#E8B21A` inner border and a bold `#7A5B00` number. (Matches the yellow "current slot" in the dialog's DC box strip.) Add `Theme` tokens for these if missing.
9. **DEBUG**: `-iecStep4 YES` and `-iecStep4State default|vmp|imp|partial|fail|continuous|done|todo|inv2` for states 01–09. One line in CLAUDE.md.

## States

| File | What |
|---|---|
| 01-default | nothing measured yet, String 1 selected |
| 02-dialog-vmp | Vmp dialog with the reading from the photo |
| 03-dialog-imp | Imp dialog, next → INV1ST2 |
| 04-partial | 9 of 16 measured, String 10 (slot 11) selected |
| 05-fail-vmp | String 5 Vmp 561 V (−8.5 %): red dot, alert + วัดซ้ำ, red row |
| 06-continuous | continuous mode on the first unfinished string |
| 07-all-done | INV1 16/16 |
| 08-filter-todo | filter ยังไม่ครบ |
| 09-inv2 | INV2 (16- and 12-module groups) |

Values are examples (Vmp ≈ Voc × 0.815); never hardcode them.

## Tests

- Vmp median by module-count group, exactly 5 % passes
- Imp never fails; done needs Vmp and Imp
- no polarity in the after phase
- Excel: after values land in rows 17 / 19 of `INV nn-หลัง` only (cell diff, as step 2's test)
- step 2 still passes (its tests and `IECStep2UITests`) after the generalisation

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes; `IECStep2UITests` passes.
- [ ] iPad Pro 13" landscape screenshots of 01, 02, 05, 06, 07 in `screenshots/`, compared with `states/`.
- [ ] Step 2 re-checked against its `states/01` and `06` with the String labels and the yellow highlight.
- [ ] iPhone IEC screens unchanged.

## Open questions (report)

1. Should step 4 be locked until steps 2–3 are complete (the system can't be switched on before)? The board doesn't show a lock.
2. Where does the connection time `13:20` come from: `after.time`, or a separate "switched on at" field?
3. Should Imp get a soft check (e.g. ±10 % of the group median) like Vmp, or stay record-only as on the board?
