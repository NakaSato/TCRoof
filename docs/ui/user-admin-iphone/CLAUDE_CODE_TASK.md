# Task: user admin on iPhone, plus what contractors must send

Two changes to the developer page จัดการผู้ใช้และสิทธิ์. It is already built for iPad: `TCRoof/Auth/UserAdmin/`, PR #61, from `docs/ui/user-admin-ipad`.

1. **iPhone layout (compact width).** `PhoneUsers.dc.html`, states 00–09.
2. **Contractor duties**, on iPad and iPhone. `iPadUsers.dc.html` (updated) and `PhoneUsers.dc.html`, states 02, 06, 07, 09, 10, 11. A contractor (role `external`) must send three things on the jobs assigned to them:
   - the daily report (`daily.fill`)
   - the weekly request R1 (new capability `weekly.request`)
   - the IEC 62446 results (`iec.fill_submit`)

Files in this folder:
- `PhoneUsers.dc.html`: the iPhone board, 390 × 844.
- `iPadUsers.dc.html`: the iPad board with the duties added. Its script is shared with the phone board.
- `grf.css`, `states/*.png` (@2x), `preview.png`, and `screenshots/`, where your screenshots go.

Read the boards as text. Everything is in `renderVals()`: `GROUPS` is the role table, `U0` the example users, `RU` the rules, and the part after `// ── iPhone:` holds the phone values.

## Data rules (keep these)
- Only data with a source. The iPad hand-off left these hidden: last seen, device, ออกจากระบบทุกเครื่อง, the 30-day idle rule. Keep them hidden on iPhone too, even though the board draws them.
- The developer key is a UI gate. `firestore.rules` decides. Don't change what an existing capability means for manager or internal.
- `docs/reference/roles/user-roles.json` and `UserRoles.swift` stay the same through `RoleTableTests`.
- Old job JSON must decode: new fields use `decodeIfPresent` with defaults.
- Theme tokens only, `TCButtonStyle`, 44 pt hit areas. Split big views into computed properties (the Debug SIGSEGV in CLAUDE.md).

## Change list

### A. Contractor duties
1. **New capability `weekly.request`.** Label: "คำขอรายสัปดาห์ (R1): คน เครื่องมือ แผน ความเสี่ยง · ส่งขออนุมัติ". Put it in the `site_contractor` group, right after `daily.fill`.
   - manager: `allow`
   - internal: `conditional`, note "อนุมัติ / ส่งกลับ"
   - external: `conditional`, note "ต้องส่งทุกสัปดาห์ · งานตัวเอง"

   Add it to `user-roles.json`, to `Capability` with its table row, and to `RoleTableTests`. The matrix shows 36 capabilities.
2. **New external notes. Access stays `conditional`.**
   - `daily.fill`: the label gets " · ส่ง", and the note becomes "ต้องส่งทุกวันที่เข้างาน · งานตัวเอง".
   - `iec.fill_submit`: the note becomes "ต้องทดสอบและส่งผล ก่อน / หลังขนาน · งานตัวเอง".
3. **Contractors send the weekly request (this is the real change).** Today `WeeklyRequestScreen` is the team's: requests live in the job record's `weeklyRequests`, and `firestore.rules` lets an external member change only `iecReport` and `iecState` on `/jobs`. Do the following:
   - **Model.** Add optional `sentAt: Date?` and `sentBy: String` to `RoutineReport.WeeklyRequest`, decoded with `decodeIfPresent`, plus a test that old JSON still decodes.
   - **Screen.**
     - An external member with `weekly.request` on the job fills next week's request and sends it with ส่งขออนุมัติ, which sets `sentAt` and `sentBy`.
     - The team approves it (`approvedAt`, `approvedBy`) or sends it back, which clears `sentAt`.
     - A sent request is read only for the contractor. An approved one is read only for everyone until the team reopens it.
   - **Rules.**
     - Allow an external member on their own job (`listsMe`) to change `weeklyRequests` as well as `iecReport` and `iecState`.
     - A rule can't see inside the JSON string. So team devices drop a contractor's change to a week that was already sent or approved, the way `IECReport.trusting` drops an unrecorded close. Name it `WeeklyRequest.trusting` or similar, and test it.
     - Add rules tests in `tools/firestore-rules-tests`: allowed on their own job, refused on another job, refused for other keys.
   - **Version gate.** If older builds would mishandle the new fields, raise `AppCompat.syncVersion`, and say so in the report.
4. **Duty card in the member detail** (`UserAdminUsers.swift` detail, iPad and iPhone; states 02, 09, 10). It is shown only for `external` members, between the scope and the permission summary.
   - Title "หน้าที่ต้องส่ง · ผู้รับเหมา". Subtitle "ใน n งานที่ได้รับมอบหมาย", or "เริ่มเมื่อได้รับมอบหมายงาน" when n = 0.
   - Three rows: รายวัน / รายงานประจำวัน, R1 / คำขอรายสัปดาห์, IEC / ทดสอบ IEC 62446. Each has its one-line description from the board.
   - Each row has a pill: "ต้องส่ง" when the external cell of its capability (after `config/roleOverrides`) is `allow` or `conditional`, otherwise "ปิดอยู่" in grey. State 09 shows `weekly.request` set to ✕ in the pending matrix.
5. **Decisions list.** Add "ผู้รับเหมาต้องส่ง: รายงานประจำวันทุกวันที่เข้างาน · คำขอรายสัปดาห์ทุกสัปดาห์ · ผล IEC 62446 ก่อนและหลังขนาน (เฉพาะงานที่ได้รับมอบหมาย)" wherever the app keeps the decisions (the board shows it on iPhone, card ข้อตกลง).
6. The audit log needs nothing new: the matrix and rules writes already log.

### B. iPhone layout (compact width; iPad unchanged)
Settings › นักพัฒนา already opens `UserAdminView` on iPhone (`PhoneSettings`). Give it a compact layout. Branch on `horizontalSizeClass` and reuse the store and the existing sheets.

1. **Lock (00).** Full screen, 76 pt keys, back to settings. Same rules as iPad: 5 tries, then 10 minutes.
2. **Header.** Blue, with:
   - back
   - title "จัดการผู้ใช้และสิทธิ์" ("รายละเอียดผู้ใช้" on the pushed detail)
   - subtitle "นักพัฒนา · ปลดล็อกเหลือ mm:ss"
   - a 44 pt lock button (ล็อกหน้านี้, accessibility label)
3. **Tabs.** A segmented control ผู้ใช้ n / สิทธิ์ 3 / ประวัติ n, hidden on the pushed detail. Changing tab pops the detail and leaves role edit.
4. **ผู้ใช้ (01).**
   - Search, and a 44 pt "+" for เพิ่มผู้ใช้. It asks for the key first, as on iPad.
   - Role chips in a horizontal scroll, with counts.
   - One list card. Each row: avatar with status dot, name (คุณ), email, role pill · team · n งาน, status and last activity on the right (hide last activity: no source), and a chevron.
   - The sync line under the list.
5. **Detail (02, 03, 09).** Push it with `NavigationStack`:
   - head card: avatar, name, email, status
   - บทบาท with "🔒 แก้ไขบทบาท" on the right; after the key it becomes เสร็จ, showing the 3-role segment and the diff box with ยกเลิกการเปลี่ยนบทบาท
   - scope chips
   - duty card (A4)
   - สิทธิ์ summary, the stacked bar, and the collapsible groups
   - ปิดบัญชี · Maintainer as a full-width button (hide ออกจากระบบทุกเครื่อง)
6. **Invite (04).** A large sheet: ยกเลิก / เพิ่มผู้ใช้ / เพิ่ม in the nav bar, plus the iPad fields, 44 pt chips, and the full-width เพิ่มในรายชื่อ at the end.
7. **Key confirm (05).** A bottom sheet with the dark gradient, 72 pt keys, and ยกเลิก.
8. **สิทธิ์ (06, 07).** Too narrow for three columns, so show one role at a time:
   - a role segment with name, English name and count
   - แก้ไขสิทธิ์และกฎ (key) / เสร็จ, and เฉพาะที่แก้ (n)
   - a card "สิทธิ์ของ<role>", rows grouped; each row has the label, the id, the note, and the access pill on the right
   - a tap cycles the cell while editing; locked cells toast as on iPad
   - the legend, then กฎการใช้งาน with switches, then ข้อตกลง (A5)
   - a changed cell gets the yellow ring
9. **ประวัติ (08).** Rows: avatar, title, detail, kind pill and time, from `auditLog`.
10. **Pending bar.** Floating 12 pt from the edges, 24 pt from the bottom, in two lines: the text, then ยกเลิกทั้งหมด and บันทึกและซิงก์. Lists get bottom padding so nothing hides under it. Toasts sit above it.

### C. DEBUG and tests
- The existing `-screen useradmin` and `-userAdmin…` flags must work on an iPhone simulator. `-userAdminUser <email>` pushes the detail in compact width.
- Add `-userAdminRole manager|internal|external` to pick the role shown on the compact สิทธิ์ tab.
- Add a demo stage for state 09 (`-userAdminStage weeklyOff`, the external `weekly.request` cell set to deny).
- Update the `-screen useradmin` line in CLAUDE.md.
- Extend `UserAdminUITests` with an iPhone test:
  - unlock
  - open a contractor
  - the duty card shows three ต้องส่ง
  - edit the matrix: the external `weekly.request` goes to ✕
  - the card shows ปิดอยู่
  - discard
- Add a test for the contractor sending a weekly request (the screen or the store), including that a sent request is read only for the contractor.

## Check list
- [ ] `swift test`, `RoleTableTests`, the rules tests (`npm test`), `UserAdminUITests`, `RoleUITests`
- [ ] xcodebuild with your own `-derivedDataPath`
- [ ] iPhone 16 simulator, with `-screen useradmin -userAdminDemo YES` and the flags: screenshots 00–09 in `screenshots/`, compared with `states/`
- [ ] iPad: states 10 and 11 match, and nothing else changed on iPad
- [ ] `AppCompat.syncVersion` raised or not, with the reason

## Open questions (report them)
1. Should a contractor's weekly request also need our engineer's signature (`engineerSignedAt`) before the team approves it, or is approval enough?
2. When is a weekly request due? The board says only "ทุกสัปดาห์". A reminder (`NotificationScheduler`) needs a deadline: before the week starts, or a weekday?
3. Should "ต้องส่ง" also show on the contractor's own home or install page? This hand-off only covers the admin page.
