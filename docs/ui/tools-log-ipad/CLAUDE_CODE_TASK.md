# iPad · เครื่องมือ · `บันทึกเครื่องมือและรถ` (tool and vehicle ledger)

Board: `iPadToolsHub.dc.html` (open it in a browser; it reads `ds/tcroofsurvey/tokens.css` and `bundle.css` beside it).
States at 2732 × 2048 (@2x of 1366 × 1024) are in `states/`; `preview.png` is state 01 at 1 ×. Example values are in
`assets/sample-data.json`: they are examples, never hard-code them. The reference day on the board is Wed 30 Sep 2569.

## 1. Goal

Today the iPad `เครื่องมือ` tab (`ToolsView`, regular width) stacks `ToolLogCard` (out-now cards, then the last 7 days
by day) beside the register card and `VehicleCard`. The board turns this into one **ledger screen** that reads like a
logbook:

- **Left, `สมุดบันทึกเครื่องมือและรถ`:** the `ทั้งหมด | เครื่องมือ | รถ` tabs with counts. Under them, a **table** of
  what is out now, then a **table** of the log grouped by day, with a range filter, an action filter, a person / job
  filter, search, `ส่งออก CSV` and `โหลดเพิ่ม`.
- **Right, top: `เครื่องมือวัด`.** Four KPIs and a short chase list. `ทะเบียน ›` opens the full register.
- **Right, below: `บันทึกการใช้รถ`.** One row per vehicle (state, odometer, fuel bar, service). The selected
  vehicle's two actions sit at the bottom.

Everything it shows already lives in `ToolLog` (`TCRoofCore/ToolLog.swift`), `ToolEvent` / `CompanyVehicle` and
`InstrumentStore`. This task is a new layout over the same data, the same forms (`ToolLogFormSheet`) and the same sync.

## 2. Scope

Do only the change list in §5. Out of scope; do not touch these:

- The iPhone layout of `ToolsView`, `ToolLogCard` and `VehicleCard` (compact width keeps them exactly as they are).
- The `เครื่องมือ` tab's landing page (the canvas board `iPadTools`): that is a separate hand-off. The tab keeps
  its module rows and the register as today.
- `ToolLogFormSheet` / `ToolLogForm` fields and validation, `ToolLog.Event` / `Vehicle` storage, `CloudSync`,
  `firestore.rules`. No new stored fields.
- QR scanning (`iPadToolRecord` board), vehicle history (`iPadVehicle` board), the travel claim and the plan calendar.
- Parts of the board that nothing stores today; leave them out (§7):
  - the `หลักฐาน` column (events keep no photos);
  - the `จองแล้ว` vehicle state and its `ดูการจอง` button (there are no bookings).

## 3. Read first

- `TCRoof/Views/Tools/ToolsView.swift`: the regular branch, `showsLog`, `header` / `register`, `InstrumentForm`.
- `TCRoof/Views/Tools/ToolLogViews.swift`:
  - `ToolLogCard`: `keeps`, `outCard`, `remind`, `activityRow`, `clock` / `time` / `dayTitle`;
  - `VehicleCard`.
- `TCRoof/Views/Tools/ToolLogForm.swift`: the `ToolLogForm` cases and its `conditions`.
- `TCRoof/Views/Tools/ToolLogModels.swift`: `ToolEvent`, `CompanyVehicle`, `ToolLogDemo`.
- `TCRoofKit/Sources/TCRoofCore/ToolLog.swift`: `outs`, `out`, `duration`, `days`, `monthKm`, `monthFuel`,
  `lastReading`.
- `TCRoofKit/Sources/TCRoofCore/Instruments.swift`: `calibration(on:)`, `needsAction`, `warningDays`.
- How other iPad screens push from a tab and draw their header: `.tcPadNavBar`, `PadTabs`. Also the shared toast,
  `TCCountSegments` and `TCStatusChip`.

## 4. Layout (1366 × 1024, landscape)

**Header.** The iPad nav bar used by the other pushed iPad screens:
- back to the `เครื่องมือ` tab;
- title `บันทึกเครื่องมือและรถ`;
- a trailing `สแกน / บันทึก` button (see §5 item 2).

**Body.** Two columns: the ledger card fills the left; the right column is 452 pt wide. Padding is 20 / 24 pt, and
the bottom clears the dock.

**Left card.**
- Head: the title, the three tabs as an underlined tab strip (`ทั้งหมด 13 | เครื่องมือ 7 | รถ 6`) and
  `+ บันทึกรายการ`.
- `กำลังใช้อยู่ (n)`: a bordered table with columns `รายการ | ผู้ใช้ | งาน | ออกเมื่อ | กำหนดคืน | ใช้มาแล้ว | action`.
  Rows are 44 pt. A late due date is red and bold, e.g. `29/9 (เกิน 1 วัน)`.
- `บันทึก`: two segmented controls (range and action), then `ผู้ใช้ · งาน ▾` and a search button on the right.
- The log table, columns `เวลา | ประเภท | รายการ | ผู้ใช้ | รายละเอียด`:
  - a full-width day header row before each day (`วันนี้ · พ. 30 ก.ย.`, `อ. 29 ก.ย.`);
  - the action as a chip: borrow and car out are info, give back and car in are done, fuel is pending.
- The card scrolls inside; a footer is fixed at its bottom: `แสดง n จาก m รายการ`, the empty note,
  `ส่งออก CSV` and `โหลดเพิ่ม`.

**Right top, `เครื่องมือวัด`.**
- Head: green tile, title, `n เครื่อง · ยืม-คืน · สอบเทียบ`, and `ทะเบียน ›`.
- Four KPI cells: `ใช้งานอยู่ | เกินกำหนดคืน (danger) | สอบเทียบใกล้ครบ (pending) | งดใช้ / ซ่อม (muted)`.
- The chase list: rows of at least 56 pt with a danger chip each.

**Right below, `บันทึกการใช้รถ`.**
- Head: blue tile, title, the month summary line, and `ประวัติ`.
- A scrolling list of vehicle rows:
  - first line: name, an outlined plate tag, and the state chip;
  - second line: who and where;
  - third line: `ไมล์ n`, a 56 pt fuel bar (danger under 35 %), and the service text on the right (pending and bold
    when due).
  - The selected row has a light fill and a 3 pt leading primary bar.
- Under the list, a primary button and a secondary `เติมน้ำมัน`, both 48 pt.

## 5. Change list (in order)

1. **Screen and route.**
   - Add `ToolLogPadScreen` in a new `TCRoof/Views/Tools/ToolLogPadScreen.swift`, team only (`showsLog`).
   - In `ToolsView`'s regular-width branch, replace the `HStack` that holds `ToolLogCard`, the register card and
     `VehicleCard` with:
     - one row `บันทึกเครื่องมือและรถ` (a `NavigationLink` to the screen) whose subtitle reads
       `ใช้งานอยู่ n · เกินกำหนดคืน n`;
     - the register card, kept as it is.
   - The compact branch does not change.
   - DEBUG: add `-screen toollog` to `DebugScreen`.
2. **Header actions.** `สแกน / บันทึก` and `+ บันทึกรายการ` open the same menu, `ยืมเครื่องมือ | ออกรถ | เติมน้ำมัน`,
   which presents `ToolLogFormSheet` with `.borrow`, `.carOut(nil)` or `.fuel(selected vehicle)`. `ออกรถ` is disabled
   when there are no vehicles, as today.
3. **Kind tabs.** `ทั้งหมด | เครื่องมือ | รถ` with counts, using the same logic as `ToolLogCard.keeps`. The tab filters
   both tables.
4. **Out-now table.**
   - Rows come from `ToolLog.outs(events, now:)`:
     - `ออกเมื่อ`: `time(at)`, prefixed with `วันนี้` when it is today;
     - `กำหนดคืน`: the event's `due`, or `—` (a car out shows `วันนี้`);
     - `ใช้มาแล้ว`: `ToolLog.duration`.
   - Action: a tool row's `บันทึกคืน` opens `.giveBack(e)`; a car row's `บันทึกคืนรถ` opens `.carIn(e)`.
   - A late row's due cell is red with `(เกิน n วัน)`.
   - Empty table: `ไม่มีรายการที่ยืมหรือออกใช้อยู่`.
5. **Log filters** (in memory, reset when the screen opens):
   - range `วันนี้ | 7 วัน | 30 วัน | ทั้งหมด`, default `7 วัน`;
   - action `ทั้งหมด | ยืม | คืน | ออกรถ | คืนรถ | เติมน้ำมัน`;
   - `ผู้ใช้ · งาน ▾`: a menu of the distinct people and jobs in the events, plus `ทั้งหมด`;
   - search: a field over item name, person, job and plate.
   - All filters combine. Changing a filter resets the shown count to 10.
6. **Log table.**
   - Rows are grouped by day (`dayTitle`).
   - `รายละเอียด` is the job, then any of these that apply: `ไมล์ n`, `วิ่ง n กม.` (car in), `n ลิตร`, `n บาท`, and
     the note.
   - Show at most `shown` rows (10, then `โหลดเพิ่ม` adds 10). The footer reads `แสดง n จาก m รายการ`; when m is 0
     it adds `· ไม่มีรายการตามตัวกรองนี้` (state 06).
   - `ทวงคืน` (remind) events show only under the action filter `ทั้งหมด`.
7. **Pure helpers in `TCRoofCore/ToolLog.swift`, with tests in `ToolLogTests`.**
   - `driven(_ carIn: Event, in:) -> Int?`: km since the matching car out, reusing `monthKm`'s pairing.
   - `filter(_:kind:range:action:person:job:query:now:)`: the log rows.
   - `csv(_ events:) -> String`: the header `วันที่,เวลา,ประเภท,รายการ,ผู้ใช้,งาน,ไมล์,วิ่ง (กม.),ลิตร,บาท,หมายเหตุ`,
     UTF-8 with BOM, fields quoted.
   - `ToolLogCard` keeps working unchanged.
8. **`ส่งออก CSV`.** Writes the filtered rows (all of them, not only those shown) to a temporary
   `บันทึกเครื่องมือและรถ-<yyyy-MM-dd>.csv` and opens the share sheet. The shared toast says what was exported.
9. **`เครื่องมือวัด` card.**
   - KPIs:
     - `ใช้งานอยู่`: tool outs;
     - `เกินกำหนดคืน`: late tool outs;
     - `สอบเทียบใกล้ครบ`: instruments in `.dueSoon`;
     - `งดใช้ / ซ่อม`: instruments in `.overdue`, plus log items whose latest event is a give-back with the note
       `ชำรุด / ต้องซ่อม`.
   - Chase list:
     - a late out: `เกิน n วัน`; tap asks `ทวงคืน <person>?`, then runs the existing `remind` and shows the toast;
     - an overdue instrument: `สอบเทียบเกิน n วัน`; tap opens `InstrumentForm`.
     - At most 3 rows, the most overdue first.
   - `ทะเบียน ›` pushes the register as its own screen: let `ToolsView` take `registerOnly: true`, showing only
     `header` and `register`.
10. **`บันทึกการใช้รถ` card** (iPad only; a new view or a `layout: .ledger` on `VehicleCard`; the iPhone look stays).
    - Rows:
      - out: `person · job · ออก HH:mm`, chip `ออกใช้งาน`;
      - free: `จอดที่สำนักงาน · คืน d/m HH:mm โดย person` from the last car in, chip `ว่าง`;
      - `ไมล์` and fuel from `lastReading`;
      - service: `เช็กระยะอีก n กม.`, or `ถึงรอบเช็กระยะ n กม.` in pending bold when 500 km or less is left (one named
        constant).
    - Summary: `n คัน · ออกอยู่ n · เดือนนี้ <monthKm> กม. · น้ำมัน <monthFuel> บาท`.
    - The selected vehicle defaults to the first out, else the first.
    - Primary button: `คืนรถ · บันทึกไมล์` (`.carIn`) when out, `ออกรถคันนี้` (`.carOut(v)`) when free. Secondary:
      `เติมน้ำมัน` (`.fuel(v)`).
    - `ประวัติ` sets the left card to `รถ`, range `ทั้งหมด`, and the search to the plate.
    - No vehicles: the existing empty text and `เพิ่มรถ`.
11. **Demo and states.**
    - `-toolLogDemo YES` drives it from `ToolLogDemo`.
    - New flags:
      - `-toolLogFilter all|tool|car`;
      - `-toolLogRange today|7|30|all`;
      - `-toolLogAction borrow|giveBack|carOut|carIn|fuel`;
      - `-toolLogVehicle <id>`;
      - `-toolLogMore YES` (range `ทั้งหมด`).
    - With these flags, states 01–07 and 09 can be opened (state 08 is `จองแล้ว`, left out; state 10 is the toast).
    - Write them into CLAUDE.md's simulator list, next to `-toolLogDemo`.
12. **UI test** `TCRoofUITests/ToolLogPadUITests.swift` (iPad, `-screen toollog -toolLogDemo YES`):
    - the `รถ` tab narrows both tables;
    - `วันนี้` + `เติมน้ำมัน` shows the empty note;
    - `โหลดเพิ่ม` adds rows;
    - `บันทึกคืน` opens the give-back form and `ยกเลิก` closes it;
    - tapping `Toyota Commuter` makes the primary button read `ออกรถคันนี้`;
    - `ส่งออก CSV` opens the share sheet.
    - Nothing is saved (demo).

## 6. Check list

- [ ] iPhone `เครื่องมือวัด` (compact `ToolsView`, `ToolLogCard`, `VehicleCard`) looks and behaves as before.
- [ ] Contractors (`-role external`) don't see the row or the screen.
- [ ] Colours from `Theme`, buttons `TCButtonStyle`, hit areas ≥ 44 pt, no hex in views; each card is its own
      computed property.
- [ ] `swift test` (TCRoofKit) passes, including the new `ToolLogTests` cases; on Linux, `tools/linux-swift/test.sh
      --filter ToolLogTests`.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath`.
- [ ] Simulator screenshots named like `states/` are saved to `screenshots/`, compared with the board.

## 7. Open questions (answer in your report; don't build these)

1. `หลักฐาน`: events keep no photos. Should give-back, car-in and fuel store photo ids (`PhotoAsset`) so the column
   can show `3 ภาพ`, `ภาพหน้าปัด`, `ใบเสร็จ`?
2. `จองแล้ว`: should vehicles be bookable for a day and a job (a new event or record)?
3. `งดใช้ / ซ่อม`: is "overdue calibration + returned damaged" the right rule, or should an instrument carry its own
   status?
4. The service warning threshold: is 500 km right?
5. Should `ทวงคืน` events get their own action filter?
