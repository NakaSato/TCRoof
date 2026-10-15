# Task: IEC 62446 · step 2/7 "ก่อนออน · แรงดัน / กระแส" (iPad)

Board: `iPadIECStep2.dc.html` (1366 × 1024, iPad landscape). States: `states/*.png`. Assets: `assets/iec/`.

Branch: this hand-off lives on `design/iec62446-step2-before-vi-ipad` (cut from `feat/ipad-home-v3` 3aa7fdb).
Work on your own branch `feat/iec62446-step2-before-vi-ipad` cut from it, and push it. Do not merge.

## Scope: only this

Build the **before-energising voltage / current step** of the IEC 62446 test as a designed iPad page (regular width).
It replaces, for this step only, the "before" table of `IECStringGrid` + the `IECStringEntry` full-screen entry.

Out of scope:
- step 1 (separate branch `design/iec62446-step1-setup-ipad`)
- step 3 IR, 4 after, 5 energy/PR, 6 thermal, 7 export
- the iPhone (compact width keeps today's screens)
- the Excel exporter's cell map and the Word appendix

## Prerequisite (check first)

These exist on `feat/ipad-home-v3` and therefore on this branch:
- `TCRoof/Views/Install/IEC/` (`IECTestScreen`, `IECStringGrid`, `IECStringEntry`, `IECPhotos`, `IECShared`, …)
- `TCRoofKit/Sources/TCRoofCore/IECReport.swift`, `IECReport+Form.swift`
- `docs/forms/iec62446-pwa/excel-cell-map.json`

If they are missing, STOP and report. Do not rebuild `IECReport`.

## Data (reuse, don't duplicate)

| Board | Model |
|---|---|
| Voc (V) | `Slot.vocV` → `INV nn-ก่อน` row 16 |
| กระแส (A), open circuit | `Slot.iBeforeA` → row 18 |
| ขั้ว (polarity) | `Slot.polarityOK` → row 12 |
| photo มิเตอร์ V / แคลมป์ A | `Slot.photos[.voltageBefore]`, `[.currentBefore]` |
| column | slot 1 = E, slot n = column `E + n − 1` (existing map) |
| median / ±5 % | `IECReport.vocDeviation(_:slot:)`, `vocTolerance` |
| string label | `IECReport.label(inverter:seq:)` → `INV1ST5` |
| MPPT of a slot | `IECReport.mppt(slot:)` |

Rules (already in the model where it says so; add the rest to `TCRoofCore`, with tests):
- Voc passes when within ±5 % of the **median of strings with the same module count** on that inverter.
  Check that `vocDeviation` groups by module count; if it doesn't, fix it there (the board has 16- and 12-module strings on INV2).
- Before energising the current must be exactly 0 A (`iBeforeA == 0`); anything else fails.
- Polarity is set automatically from the sign of the typed Voc (negative ⇒ `polarityOK = false`, store the absolute value) unless the user already set it. The ✓ถูกต้อง / ✗กลับขั้ว segment overrides.
- A string is "done" for this step when Voc, current and polarity are all set. "ไม่ผ่าน" when any of them fails.
- An empty slot (`slots[i] == nil`) is shown, never counted, and its column stays blank in Excel.
  "ตั้งช่อง n เป็นว่าง" / "+ มีสตริงในช่อง n" toggles it (same action as step 1's SPARE toggle; confirm before removing a slot that has values).
- The number of slots per inverter: 20 today (`IECReport.slotCount`). If step 1 has landed with MPPT × 2 slots, use it; otherwise use 20 and report.

Add nothing to stored models unless needed; any new field is optional with `decodeIfPresent`. Excel cells don't change.

## Change list

1. **Frame** (as step 1):
   - Header `IEC 62446 · ก่อนออนระบบ · แรงดัน / กระแส` + station line.
   - `2/7` + step name, 7 capsules (current one blue, finished ones green). Tapping a capsule opens that step only if it exists; otherwise disabled.
   - Two columns inside 1240 pt: left 420 pt, right flexible card, 24 pt gap.
   - Bottom bar: status text (what is missing / `มีค่าไม่ผ่าน n สตริง` / all done ✓), `บันทึกร่างตอนนี้`, `‹ ก่อนหน้า 1/7 ตั้งค่าระบบ`, `ถัดไป 3/7 ก่อนออน · ฉนวน (IR) ›`.
     ก่อนหน้า opens step 1 if built, else the existing setup sheet. ถัดไป opens the existing IR entry (current grid, IR rows) until step 3 is built; report what you linked.
2. **Left column, top to bottom:**
   - Inverter cards in a 2-column grid (scroll horizontally if > 2): code, `วัดแล้ว n/m` or `✓ ครบ n/m` (green), a green progress bar, `kW · ช่อง · S/N`. Selected card: 2 pt blue border.
   - Orange banner: `ระบบยังไม่ออน · วัดให้ครบทุกอินเวอร์เตอร์ก่อนออน` / `วงจรเปิด กระแสต้องเป็น 0 A · เติม INV 0n-ก่อน แถว 12, 16, 18`.
   - **DC input map** `ช่อง DC input · MPPT 1–n`: one column per MPPT, two round slots each (`STn` or the slot number when empty). Fill: green done, white + grey ring to-do, red failed, dashed empty. Selected: blue outer ring. Legend under it. Link top right `ตั้งช่อง n เป็นว่าง` / `+ มีสตริงในช่อง n`.
   - Selected string bar: blue chip `INV1ST1`, meta `MPPT 1 · ช่อง 1 · 16 แผง · คอลัมน์ E`, ‹ › buttons (previous / next slot, empty slots included).
   - Flow line `① ถ่ายรูป → ② ป้อนค่าจากรูป` (green ✓ when done) + `ถ่ายแล้ว n/2`, and on the right the continuous-mode button: `▶ วัดต่อเนื่อง · เหลือ n` (blue gradient) or `▶ ครบทุกสตริง` (green, inactive).
   - Red alert when the string fails (state 06): the reason (`Voc 712.0 V ต่างจากมัธยฐาน −5.4% (เกณฑ์ ±5%)` / `กระแส x A · ก่อนออนต้องเป็น 0 A`) + `· รูปเดิมเก็บไว้เทียบ`, and a red `วัดซ้ำ` button that retakes the photo (keep the old photo as history if the photo store allows; otherwise report).
   - Two photo cards side by side: `มิเตอร์ V` (cell `E16`) and `แคลมป์ A` (`E18`). No photo: dashed orange border, `ยังไม่มีรูป`, tap opens the camera (`IECPhotos`, honour `-iecCameraStub`). Photo, no value: blue border, `แตะเพื่อป้อนค่า`. Value: the number + unit and the hint (green ✓ / red ✗).
   - Empty slot selected (state 07): the cards are replaced by the empty-slot note (`ช่อง String n · MPPT m ว่าง` + the Excel column note) with `+ มีสตริงในช่อง n`.
3. **Right column, the table card** `ตารางค่าวัด · INV1 ก่อนออนระบบ`:
   - Segmented filter `20 ช่อง | ยังไม่ครบ n | ไม่ผ่าน n` (state 08).
   - Columns: สตริง · MPPT · ช่อง · แผง · Voc (V) · ต่าง · กระแส (A) · ขั้ว · ผล. Numbers right-aligned, missing `—` light grey, failed values red. ผล pill: ผ่าน green, ไม่ผ่าน red, ยังไม่ครบ grey.
   - Empty slots as a muted row `ช่อง 8 · ว่าง · ไม่มีสตริงต่อเข้าช่องนี้` (only in the "all" filter).
   - Tapping a row selects that slot (light blue row with a 3 pt blue left bar). The table scrolls; the header and footer don't.
   - Footer, 4 cells: `วัดแล้ว n / m สตริง` · `มัธยฐาน 16 แผง x V` (one cell per module-count group if there are several, e.g. INV2 16/12) · `V ต่อแผง x V` · `ขั้วสาย ถูกทุกสตริง` / `กลับขั้ว n`.
4. **Entry dialog** (states 03, 04, 05, 09), a centred sheet ~1000 × 600 over a dimmed page:
   - Header: blue chip `INV1ST1`, `มิเตอร์ V · ก่อนออน` / `แคลมป์ A · ก่อนออน`, sub line `รูป 1/2 · 16 แผง · เติม E16 · INV 01-ก่อน · รูปไปที่รายงาน 6 หน้า n`, close ✕.
   - Left: the photo (aspect fill, label `รูปตัวอย่าง` only in the demo), the DC box location strip (`MPPT n · ฟิวส์ Fn (+/−)`, one cell per slot, the current one yellow), `ถ่ายใหม่` and `ซูมรูป`.
   - Right: the value tile (label, cell, big number, caret, hint). Under it for Voc only: `ขั้วสาย E12` with `อัตโนมัติจากเครื่องหมาย Voc …` and the ✓/✗ segment.
   - `อ่านจากรูป Voc 755.0 V · ใช้ค่านี้` (dashed blue): the value read from the photo with Vision (reuse `LiveTextScanner`'s `VNRecognizeTextRequest` path). When no reading, hide the row. The first time a field opens empty, prefill with the reading and show `✓ อ่านจากรูปแล้ว · ตรวจแล้วกดบันทึก`.
   - If the typed value differs from the reading by more than 1 % (state 09), the tile turns orange: `! ต่างจากค่าที่อ่านได้ในรูป x V`. Saving is still allowed.
   - Number pad 4 × 4: 7 8 9 ⌫ / 4 5 6 ล้างค่า / 1 2 3 บันทึก (2 rows tall, blue, sub-label `→ ถ่ายแคลมป์ A` / `→ INV1ST2` / `→ จบ INV1`) / 0 (2 wide) . — max 6 digits, one dot.
   - บันทึก writes the value and goes on: V → clamp photo (opens the camera if none) → A → next string's photo, or closes on the last.
5. **Continuous mode** (state 05): `วัดต่อเนื่อง` opens the dialog on the next unfinished string at or after the selected one and walks only unfinished strings. The dialog header shows `โหมดต่อเนื่อง · n/m สตริง` with a thin progress bar and `หยุด`.
6. **DEBUG launch arguments** (document them in CLAUDE.md's simulator list, one line):
   `-iecStep2 YES` opens this page with `-iecDemo YES`; `-iecStep2State default|inv2|voc|clamp|continuous|fail|empty|todo|differs` reproduces states 01–09 (nothing extra saved beyond the demo).

## States

| File | What |
|---|---|
| 01-default | INV1, all 16 done, ST1 selected |
| 02-inv2 | INV2 selected (16- and 12-module strings) |
| 03-dialog-voc | Voc dialog, value read from the photo |
| 04-dialog-clamp | clamp dialog, 0.00 A |
| 05-continuous | continuous mode, 13/16, ST14 |
| 06-fail-voc | ST5 Voc 712 V (−5.4 %): red map dot, alert + วัดซ้ำ, red row |
| 07-empty-slot | slot 8 (empty) selected |
| 08-filter-todo | filter ยังไม่ครบ with 3 strings left |
| 09-typed-differs | typed 735 V vs 755 V read from the photo |

Values are the example of `docs/forms/iec62446-pwa/sample-praek-nam-daeng.json`; never hardcode them.

## Constraints

- Colours from `Theme` (navy `#16325C`, primary `#1F6FB5`, ok `#70AD47`/`#2E7D32`, bad `#D9453B`/`#B42318`, warn `#F08C00`, lines `#DDE4ED`); no hex in views, no `Color.white`. Buttons via `TCButtonStyle`. Hit areas ≥ 44 pt.
- Split big views into computed properties (Debug type-check crash rule in CLAUDE.md).
- Keep `IECStringGrid` / `IECStringEntry` for iPhone and for the after phase; branch on horizontal size class.

## Tests (`swift test` in TCRoofKit)

- median by module-count group, ±5 % edge (exactly 5 % passes)
- current ≠ 0 fails before energising
- polarity from a negative Voc, and that a manual setting wins
- done / failed counts with an empty slot in between
- `INV1ST` numbering skips empty slots; Excel column follows the slot, not the sequence

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes.
- [ ] iPad Pro 13" landscape screenshots of 01, 03, 05, 06, 07 in `screenshots/`, compared with `states/`.
- [ ] Excel export of the demo unchanged except the edited values (diff the workbook cells).
- [ ] iPhone IEC screens unchanged.

## Open questions (report)

1. Should `วัดซ้ำ` keep the old photo (history) or replace it? The board says "รูปเดิมเก็บไว้เทียบ".
2. Does a negative Voc get stored as its absolute value, with `polarityOK = false`? (Assumed yes.)
3. The board's photo → report page (`รูปไปที่รายงาน 6 หน้า n`, 3 strings per page): keep as a label, or skip until the Word appendix is built?
4. Tolerance for "typed differs from the photo": 1 % assumed.
