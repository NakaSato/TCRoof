# Survey appointments in the iPad Calendar, and the travel and expense log (iPad Swift dev spec)

**Status:** Part A built. The manual mode (2026-10-17): `TCRoofCore/SurveyEvent.swift` (§A2 content, the `tcroof://`
links), `TCRoof/Calendar/AddToCalendar.swift` (`เพิ่มลงปฏิทิน`, team only), the `tcroof` URL scheme and `.onOpenURL` (§A4).
Automatic sync and the rest (2026-10-18): `TCRoofCore/CalendarSync.swift` decides what to create, move or remove
(`CalendarSyncTests`), `TCRoof/Calendar/CalendarService.swift` applies it with EventKit, with the links in the device's
`calendar-links.json` (not SwiftData) and Settings › ปฏิทิน (switch, team, calendar, length, the shared-calendar warning);
the reminders are 17:00 the evening before and 1 hour before (`NotificationPlan.surveyEve`, `surveyLead`), scheduled as
system notifications; the job card shows `ซิงก์ลงปฏิทินแล้ว ✓` or `นัดถูกลบจากปฏิทิน · เพิ่มอีกครั้ง`; the plan's
appointment rows have `นำทาง · โทร · ปฏิทิน`; a link to a job not on the device yet shows `งานนี้ยังไม่ซิงก์มาที่เครื่องนี้`
and opens it after sync. Answers: 3 h events, the reminders above, a dedicated `TCRoof นัดสำรวจ` calendar. The pure logic
went into `TCRoofCore`, not a new `FieldOps` target.
Part B built (2026-10-19): `TCRoofCore/TravelClaim.swift` (stamps with the 2-minute undo, legs, mileage, the fuel split,
duplicates, warnings, the month summary and per-job cost) and `ReceiptParser.swift` (`TravelClaimTests`);
`PDFReport/ClaimPages.swift` and `ExcelExport/ClaimExcel.swift` (`ClaimPagesTests`, `ClaimExcelTests`); the app's
`TCRoof/Travel/` (`Trip`, `Expense`, `ClaimMonth` synced to `trips`, `expenses`, `claims`; `TravelStore`, `ClaimScreen`,
`TripEditor`, `ExpenseEditor`, `TravelJobCard`, `ClaimExport`). Differences from the draft below: a trip's stops are
encoded on the trip (no `tripStops` collection); the submit state is a `ClaimMonth` per person and month, not a field on
each expense; mileage is worked out from the trips (km × the trip's rate), not stored as an expense; money is in satang;
the approvers are the managers (no `approvers` list); receipts upload to Drive when the month is submitted. Defaults for
§5 questions 3–6 (the user said "use sensible defaults", 2026-10-19): 5 บาท/กม. for a private car, odometer photos
optional; the company's own A4 layout, managers approve; per diem and lodging by receipt (typed amounts allowed); every
day starts from the office and returns there (a switch in ตั้งค่าการเบิก, and the day's start place can be edited).
Approval built 2026-10-20: `ตรวจใบเบิกของทีม` (`ClaimReviewScreen`, a row at the top of the claim screen for managers)
lists the submitted months (`รออนุมัติ`, `ส่งกลับ`, `อนุมัติแล้ว`), reads each month's trips and expenses from Firestore
without keeping them, and approves it or sends it back with a reason. The decision is a Firestore `claimReviews`
document (`TravelClaim.Review`, one per person and month, `<owner>_<month>`) that only managers write, signed with their
own email and never on their own claim; it counts only for the submission it was made on, so a withdrawn and
resubmitted month waits again. The claimant sees it on the claim screen (`ClaimReviews`), can't withdraw an approved
month, and withdraws a returned one to edit it. A new decision is announced on the claimant's device once sync brings it
in (`ClaimNotification`: `อนุมัติใบเบิกแล้ว` or `ใบเบิกถูกส่งกลับให้แก้` with the reason, Settings' `ผลอนุมัติใบเบิก` switch,
not on the first sync after sign-in, not when over 3 days old), lists in the bell for 7 days (one sent back is to do),
and a tap opens the claim screen on its month. A submitted month's Drive folder is shared read only with
`config/app.claimShareWith` (the approvers' emails), so their review opens the receipts. Not built: the suggested
arrival and departure by region monitoring (§B2, optional), and a notification to the claimant on a decision.
**Platform:** TCRoof on **iPad** (SwiftUI, SwiftData, iPadOS 17+). It also runs on iPhone.
**App target:** the host app `TCRoof` (jobs, plan, Firebase sync). The pure logic is in `TCRoofCore` (no new
`FieldOps` target): `SurveyEvent`, `CalendarSync`, `TravelClaim`, `TravelClaim+Review` and `ReceiptParser`, testable with
`swift test`.
**Not built:** the suggested arrival and departure by region monitoring (§B2), and a notification to the claimant on a
decision.
**No new dependencies:** EventKit, EventKitUI, MapKit, CoreLocation, VisionKit, Vision, UserNotifications, and the
existing `PDFReport` / `ExcelExport` / `DriveSync`.

| # | Feature | In one line |
|---|---|---|
| A | **นัดหมายลงปฏิทิน iPad** | every survey appointment (`Job.surveyDate`) becomes an event in the iPad's Calendar, with address, map location, coordinator and phone, reminders, and a link that opens the job in TCRoof |
| B | **บันทึกการเดินทางและค่าใช้จ่าย** | arrival and departure times per station, route distance, receipts photographed and read; totals become a monthly claim (PDF + Excel) |

---

## 1. What exists today

| Existing | Where | Used for |
|---|---|---|
| `Job` (SwiftData): `code`, `projectName`, `customerName`, `phone`, `address`, `province`, `team`, `surveyDate` (date + time), `installStart`, `syncID` | `TCRoof/Models/Models.swift` | event content (A), trips per job (B) |
| NO.224 survey job linked by `jobSyncID`: `coordinator`, `phone`, `address`, `gps` | `TCRoofCore` cover fields | better coordinator, phone and location when present |
| `PlanCalendarView` shows survey appointments (`surveys(on:)`) | `TCRoof/Views/Plan/PlanViews.swift` | buttons **นำทาง / โทร / เพิ่มลงปฏิทิน** on each appointment row |
| `CloudSynced` protocol: text-only Firestore records per SwiftData model; photos stay on the device and Drive | `TCRoof/Sync/CloudRecords.swift`, `CloudSync.swift` | sync of trips and expenses (B) |
| Firestore rules (before this feature): members only; collections `jobs`, `surveyForms`, `devices`, `installLogs`, `inspections`, `pwaSurveys` | `firestore.rules` | the new collections (§B6) |
| `PhotoAsset` (`@Attribute(.externalStorage)`), `DocumentAsset` | `Models.swift` | receipt images |
| `LocationFetcher` (one-shot, "while using") | `TCRoof/Utilities/LocationFetcher.swift` | arrival stamp |
| `@AppStorage("userName")` | several views | claimant name |
| No URL scheme and no `onOpenURL` yet | — | added (§A4) |

---

## A. Appointments in the iPad Calendar

### A1. Two ways to add events

| Mode | Permission | Behaviour |
|---|---|---|
| **เพิ่มลงปฏิทิน (manual, default)** | **none.** `EKEventEditViewController` runs out of process on iPadOS 17+ | a button on the job and on the Plan row opens the system event editor pre-filled (§A2). The surveyor taps **Add**. The app keeps no link to the event, so later date changes are not followed |
| **ซิงก์นัดอัตโนมัติ (optional, Settings › ปฏิทิน)** | full access (`EKEventStore.requestFullAccessToEvents`) | the app creates, updates and deletes events itself whenever a job's `surveyDate`, address or phone changes, from this device or from sync |

**Why the automatic mode needs full access:** write-only access cannot read back an event to update it. The setting
explains this in one line before asking.

**Automatic mode options:**
- **Which jobs:** "ทีมของฉัน" (a `Team` picked in Settings, stored in `@AppStorage("myTeam")`) or "ทุกทีม". Default:
  my team.
- **Calendar:** a dedicated calendar **"TCRoof นัดสำรวจ"** is created in the default source (iCloud when available,
  else local). Its colour is the team colour, or navy for "ทุกทีม". The surveyor can pick an existing calendar
  instead.
- **Job ↔ event link:** stored **per device** in the app's `calendar-links.json` (`TCRoof/Calendar/CalendarService.swift`),
  not in SwiftData, and not synced. Event identifiers are device-local, so each iPad manages its own events.
- **Deleted events:** if the event was deleted in Calendar (lookup returns nil), the app does **not** recreate it,
  and the job shows "นัดถูกลบจากปฏิทิน · เพิ่มอีกครั้ง".
- **Status change:** when a job becomes `completed`, or its survey date is cleared, its event is deleted. Past events
  are left alone.

### A2. Event content

| Event field | Value |
|---|---|
| Title | `สำรวจ · <projectName> (<code>)`, e.g. "สำรวจ · สถานีผลิตน้ำ (TC-0412)" |
| Start / end | `surveyDate` → + **3 h** (setting: 1–8 h). A date without a time (00:00) becomes an all-day event |
| Location | `EKStructuredLocation`: title = address + province; `geoLocation` from the linked survey's `gps` only; there is no geocoding (`SurveyEvent.swift`) |
| URL | `tcroof://job/<syncID>` (§A4) |
| Notes | see below |
| Alarms | **1 day before at 17:00** (absolute) and **1 hour before** (relative), both settings. With a geo-location, Calendar's own travel-time alert also works |
| Travel time | left to Calendar's travel time setting (a user choice) |

The notes are plain text, so Calendar makes the phone number and links tappable:

```
ผู้ประสานงาน: <coordinator or customerName>
โทร: <phone>
ทีม: <team> · ขนาด <capacityKW> kW
นำทาง (Apple Maps): maps://?daddr=<lat>,<lon>
นำทาง (Google Maps): https://www.google.com/maps/dir/?api=1&destination=<lat>,<lon>
เปิดงานใน TCRoof: tcroof://job/<syncID>
```

**Source priority for each value:** the linked NO.224 form (`coordinator`, `phone`, `address`, `gps`) when filled,
else the TCRoof `Job` fields. The same builder feeds the manual editor and automatic sync.

### A3. Reminders without Calendar sync

When the automatic mode is off, the app can still remind: **Settings › แจ้งเตือนนัดสำรวจ** (default on). It schedules
`UNUserNotificationCenter` requests:
- **17:00 the day before:** "พรุ่งนี้ 09:00 สำรวจ <project> · <address>", with actions **นำทาง** and **โทร**.
- **1 hour before.**

Tapping a notification opens the job. They cover the next three days' appointments whose report isn't finished
(`NotificationScheduler.surveyPlans`), rebuilt as jobs change.

### A4. Opening the job from Calendar (URL scheme)

- **Register the scheme:** `CFBundleURLTypes` gets `tcroof` in the target's Info settings.
- **Handle it:** `.onOpenURL` in `TCRoof/App/TCRoofApp.swift` which routes `tcroof://job/<syncID>` (and `tcroof://job/<syncID>/survey`
  for the NO.224 form) to the job screen through the existing navigation state.
- **Unknown job:** if the id is not on this device yet (not synced), the app shows "งานนี้ยังไม่ซิงก์มาที่เครื่องนี้"
  and retries after sync.

### A5. In the app

- **Job screen:** a new appointment card with date and time, **นำทาง** (Apple Maps / Google Maps), **โทร**
  (`tel:`), **เพิ่มลงปฏิทิน** or "ซิงก์แล้ว ✓", and the travel section (B).
- **`PlanSurveyRow`:** the same three buttons, compact.
- **`PlanCalendarView`:** unchanged.

### A6. Privacy

- **What leaves the app:** the event holds the customer's phone and address in the user's own calendar. If the
  calendar is an iCloud calendar that is shared with others, they see them too.
- **Settings warning:** "ปฏิทินที่เลือกแชร์กับผู้อื่นอยู่ ข้อมูลลูกค้าจะเห็นได้". The app detects this with
  `EKCalendar.allowsContentModifications` and the source type. It can't know sharing for sure, so it warns for
  CalDAV/Exchange sources.

---

## B. Travel and expense log

### B1. Model (SwiftData, synced as text like other models)

Built (`TCRoof/Travel/TravelModels.swift`):
- **`Trip`:** one day of travel by one person: `date`, `ownerEmail`, `person`, `vehicleRaw`, `plate`, `startPlace`,
  the stops as JSON (`stopsJSON`, `[TravelClaim.Stop]`), `backKm`, the trip's `rate`, `odoStart` / `odoEnd` /
  `odoReason`, the odometer photos and their Drive ids, `syncID`.
- **`Expense`:** `date`, `ownerEmail`, `person`, `categoryRaw`, `amount` (satang, `Int`), `vendor`, `taxID`, `note`,
  `jobID`, `receipt` and `receiptDriveID`, `fillSource`, `createdAt`, `syncID`.
- **`ClaimMonth`:** one per person and month: `ownerEmail`, `month`, `submittedAt`, `log`, `signature`, the PDF and
  Excel Drive ids, `driveFolderURL`, `syncID`. Submitting locks the month.

Original draft, superseded:

```swift
@Model final class Trip {                 // one working day of travel by one person
    var date: Date                        // start of day
    var person: String                    // @AppStorage("userName")
    var vehicle: VehicleKind              // .company, .private, .public
    var plate: String = ""
    var odoStart: Int?, odoEnd: Int?      // optional odometer readings (km)
    var odoStartPhoto: PhotoAsset?, odoEndPhoto: PhotoAsset?
    var startPlace: String = "สำนักงาน"   // Settings › ที่ตั้งสำนักงาน
    @Relationship(deleteRule: .cascade) var stops: [TripStop] = []
    var routeKm: Double?                  // computed (§B3), stored for the claim
    var syncID: String?
}
@Model final class TripStop {             // one station visit
    var job: Job?
    var arrivedAt: Date?, departedAt: Date?
    var arrivedLat: Double?, arrivedLon: Double?, arrivedAccuracy: Double?
    var order: Int
    var legKm: Double?                    // from the previous stop
    var trip: Trip?
}
@Model final class Expense {
    var date: Date
    var person: String
    var category: ExpenseCategory         // .fuel, .toll, .parking, .lodging, .perDiem, .mileage, .other
    var amount: Decimal
    var vendor: String = ""
    var taxID: String = ""                // 13 digits when the receipt is a tax invoice
    var note: String = ""
    var job: Job?                         // allocated job (optional; fuel may be per day)
    var trip: Trip?
    @Relationship(deleteRule: .cascade) var receipt: PhotoAsset?
    var fillSource: String = "typed"      // "receipt" when read from the photo (§B4)
    var claimMonth: String                // "2569-09", set from date; editable
    var claimStatus: ClaimStatus = .open  // .open, .submitted (locked)
    var syncID: String?
}
```

- **Sync:** each model conforms to `CloudSynced`, with text and number fields only. Receipt and odometer images
  follow the app's rule: they stay on the device and upload to Drive (§B6).
- **Firestore collections (built):** `trips`, `expenses`, `claims` and `claimReviews`; no `tripStops` (§B6 covers the rules).

### B2. Arrival and departure

- **Manual (always available):** the job screen's `TravelJobCard` has **ถึงสถานีแล้ว** and **ออกจากสถานี** (the Plan
  row doesn't).
  - Each tap stamps the time and the current location through `LocationFetcher` (accuracy kept).
  - It creates today's `Trip` if none exists, and appends a stop for this job to its `stopsJSON`.
  - A second tap within 2 minutes is treated as a mistake and undoes the stamp.
- **Suggested (optional, Settings › ช่วยบันทึกเวลาถึง/ออก, default off; not built):**
  - The app monitors a `CLCircularRegion` of 300 m around each job with a survey appointment **today**.
    Core Location allows up to 20 regions, so only today's appointments are registered.
  - On entry or exit it posts a notification: "ถึง <project> แล้ว? บันทึกเวลา 09:12". Nothing is recorded without
    a tap.
  - This needs "Always" location permission, asked for only when the setting is turned on. On iPads without GPS
    (Wi-Fi models) the setting warns that entry and exit may be late or missed.
- **Time on site:** `departedAt − arrivedAt` is shown on the stop. It feeds the per-job summary (§B5).

### B3. Distance

| Method | When | How |
|---|---|---|
| **Route distance (default)** | always | `MKDirections` (automobile) for each leg: start place → stop 1 → … → last stop → start place (the return leg is a setting). Legs are computed when the stop's location is known, from the arrival stamp or the job's `gps` / geocoded address. `routeKm = Σ legKm`, rounded to 0.1 km and stored, so the claim doesn't change if Maps changes later |
| **Odometer (optional)** | vehicle = private, or company policy requires it | photos of the odometer at start and end of day. VisionKit reads the digits and proposes the value, and the surveyor confirms. `odoEnd − odoStart` is shown next to the route distance. If they differ by more than 20 %, the claim shows both and the reason field is required |

**Each leg can be edited:** road closed, detour. Editing needs a note and is marked "แก้ระยะเอง" in the claim.

**Mileage for a private vehicle:** trip km × the trip's `rate` (Settings › อัตราค่าเดินทาง รถส่วนตัว, บาท/กม., default 5).
It is worked out from the trips in the month summary, not stored as an expense.

### B4. Receipts

1. Tap **ถ่ายใบเสร็จ** to open `VNDocumentCameraViewController`. It crops and flattens automatically, and several
   receipts can be taken in one go.
2. Each page becomes an `Expense` with its `receipt` image (JPEG, `maxSide` 1600).
3. `VNRecognizeTextRequest` (`.accurate`; Thai when `supportedRecognitionLanguages()` includes it) runs on-device.
   `FieldOps/ReceiptParser` then proposes values:

   | Value | Rule |
   |---|---|
   | amount | the number after "รวม", "ยอดรวม", "รวมทั้งสิ้น", "Total", "จำนวนเงิน"; else the largest money-formatted number; `1,234.50` style |
   | date | `dd/mm/yy(yy)`; B.E. years (> 2400) converted |
   | tax ID | a 13-digit run after "เลขประจำตัวผู้เสียภาษี" / "TAX ID" |
   | category | keywords: น้ำมัน / ดีเซล / แก๊สโซฮอล์ / PTT / Bangchak / Shell → fuel; ทางด่วน / ทางพิเศษ / มอเตอร์เวย์ / Easy Pass → toll; จอดรถ → parking; โรงแรม / รีสอร์ท → lodging |
   | vendor | the first line of the receipt |

4. The proposed values show as chips. **ใช้ค่านี้** fills them (`fillSource = "receipt"`), and anything can be edited.
5. **Job allocation:**
   - Receipts taken during a trip default to the stop that was active at that time (between arrival and departure),
     else the day's trip without a job.
   - Fuel can be **split across the day's jobs** by leg distance: one tap on **แบ่งตามระยะทาง**.

### B5. Monthly claim

**Screen:** เดินทางและเบิกค่าใช้จ่าย (`ClaimScreen`), a Home route (a row of the iPad `เครื่องมือ` tab and of the iPhone
`เครื่องมือวัด`, and from the job's `TravelJobCard`), has a month picker. It shows:
- **Days:** date, route (stations by code), km, time on site per station.
- **Expenses:** grouped by category, with totals, receipt thumbnails, and warnings:
  - a receipt without an amount
  - a mileage claim with no distance
  - a duplicate (same amount, date and vendor)
- **Totals:** by category, per job, and the grand total.
- **Actions:**
  - **ส่งออกใบเบิก:** PDF (`PDFReport`, A4) + Excel (`ExcelExport`).
  - **ยื่นเบิก:** submits the month's `ClaimMonth` (`submittedAt`, signature), which locks its trips and expenses
    (edits need **ถอนการยื่น**, a logged undo).

**PDF pages:**
1. Header: company, claimant, month, vehicle, plate.
2. Day-by-day table: date, from → to, km, stations (code + name), mileage.
3. Expense table: date, category, vendor, job, amount, "มีใบเสร็จ".
4. Totals, then signature lines for **ผู้เบิก** and **ผู้อนุมัติ**. The claimant signs on the iPad with PencilKit, the
   same pad as the survey's signatures.
5. Appendix: every receipt image, 2 per page, numbered to match the table. Odometer photos come after them.

**Per-job cost:** the job screen shows the travel and expenses allocated to it ("ค่าเดินทางงานนี้ 1,280 บาท · 3
ครั้ง"). This helps project costing.

### B6. Storage, sync and privacy

- **Firestore:** `trips`, `expenses` and `claims` carry text and numbers only.
- **Rules (built, `firestore.rules`):** `trips`, `expenses` and `claims` are written by their owner and read by the owner
  or `isManager()`. `claimReviews` are written by managers, never on their own claim. There is no `approvers`
  collection and no `tripStops`.
- **Rules (original draft, superseded):** the rules then let every member read every collection. Expenses are personal, so this spec proposes
  new rules that let a member read and write only **their own** trips and expenses, with a list of approvers who can
  read all. The claim owner is stored as the signed-in email (`request.auth.token.email`) in each record:

  ```
  match /expenses/{doc} {
    allow read, write: if isMember() && (resource == null || resource.data.ownerEmail == signedInEmail() || isApprover());
    allow create: if isMember() && request.resource.data.ownerEmail == signedInEmail();
  }
  function isApprover() { return exists(/databases/$(database)/documents/approvers/$(signedInEmail())); }
  ```

  The same pattern was to apply to `trips` and `tripStops`.
- **Drive:** receipt images and claim PDFs upload to `เบิกค่าใช้จ่าย/<ปี-เดือน>/<ชื่อ>/`, using the existing Drive
  session. Receipts are kept on the device until the month is submitted **and** uploaded.
- **Location data:** stored only as the stamps at arrival and departure. There is no continuous tracking.

---

## 2. Files

| File | Contents |
|---|---|
| `TCRoofKit/Sources/TCRoofCore/SurveyEvent.swift` | title, notes, times and alarms from plain values (A2), the `tcroof://` links |
| `TCRoofKit/Sources/TCRoofCore/CalendarSync.swift` | what to create, move or remove |
| `TCRoofKit/Sources/TCRoofCore/TravelClaim.swift`, `TravelClaim+Review.swift` | stamps, legs, mileage, fuel split, duplicates, warnings, month summary, per-job cost; the review |
| `TCRoofKit/Sources/TCRoofCore/ReceiptParser.swift` | §B4 rules |
| `TCRoofKit/Sources/PDFReport/ClaimPages.swift`, `ExcelExport/ClaimExcel.swift` | the claim PDF and Excel |
| `TCRoof/Calendar/AddToCalendar.swift` | `EKEventEditViewController` wrapper (manual mode) |
| `TCRoof/Calendar/CalendarService.swift` | EventKit: permission, calendar creation, create/update/delete, `calendar-links.json` |
| `TCRoof/Notifications/NotificationScheduler.swift` | the appointment reminders (§A3) |
| `TCRoof/App/TCRoofApp.swift` | `.onOpenURL` routing |
| `TCRoof/Travel/TravelModels.swift` | `Trip`, `Expense`, `ClaimMonth` |
| `TCRoof/Travel/TravelStore.swift` | stamps, route distance (`MKDirections` per leg) |
| `TCRoof/Travel/TravelJobCard.swift` | ถึง / ออก on the job screen |
| `TCRoof/Travel/ClaimScreen.swift`, `TripEditor.swift`, `ExpenseEditor.swift`, `ReceiptCapture.swift` | monthly screen, submit / withdraw, editors, receipt capture |
| `TCRoof/Travel/ClaimExport.swift` | PDF, Excel, Drive upload on submit |
| `TCRoof/Travel/ClaimReviewScreen.swift`, `ClaimReviews.swift` | `ตรวจใบเบิกของทีม`, the claimant's view of decisions |
| `TCRoof/Sync/CloudRecords.swift`, `CloudSync.swift` | the new collections |
| `firestore.rules` | §B6 |
| Info settings (`AppInfo.plist`) | `NSCalendarsFullAccessUsageDescription`; `CFBundleURLTypes` `tcroof`. No Always-location key yet: it is needed only once region suggestions (§B2) are built |

## 3. Tests

**Unit (`swift test`, `TCRoofCore`):** built as `SurveyEventTests`, `CalendarSyncTests`, `TravelClaimTests`,
`TravelClaimReviewTests`, `ClaimPagesTests` and `ClaimExcelTests`. The draft's list:
- `EventContent`:
  - title, notes and the source priority (form over job)
  - a date at 00:00 becomes an all-day event
  - alarms at "day before 17:00" and "−1 h"
- `ReceiptParser`: 30 recognised-text fixtures from real receipts collected by the team (fuel, toll, parking, hotel,
  tax invoice), checking amount, date (B.E. and C.E.), tax ID and category.
- `ClaimBuilder`:
  - mileage = km × rate
  - fuel split by leg distance adds up to the receipt amount (rounding to the satang goes to the last job)
  - duplicate detection
  - submitted items refuse edits

**App (XCTest + UI tests on an iPad simulator):**
- A changed `surveyDate` updates the linked event, using a fake `EKEventStore` wrapper.
- A deleted event is not recreated.
- `tcroof://job/<id>` opens the job.
- ถึง → ออก records two stamps, and a double tap within 2 min undoes.
- A month with 3 trips and 5 receipts exports a PDF whose totals equal the screen.

## 4. Done when

- [x] A survey appointment can be added to the iPad Calendar with no permission prompt, with address, map pin,
      phone and a working "open in TCRoof" link.
- [x] With automatic sync on, changing the date on another iPad moves the event on this one after sync.
- [x] A day with 3 stations gives arrival/departure times, route km and the receipts in one place, with no typing
      except to confirm the proposed values.
- [x] The monthly claim PDF and Excel match the screen totals, and include every receipt image.
- [x] No member can read another person's expenses unless they are a manager.

## 5. Open questions

1. ~~**Event length and reminders:** is 3 hours right for a station survey? Are 17:00 the day before and 1 hour before
   the right reminders?~~ Answered: 3 h events, both reminders.
2. ~~**Calendar:** a dedicated "TCRoof นัดสำรวจ" calendar, or the team's shared calendar?~~ Answered: a dedicated
   `TCRoof นัดสำรวจ` calendar.
3. ~~**Mileage:** what rate per km, and must private vehicles show odometer photos?~~ Answered: 5 บาท/กม. for a private
   car, odometer photos optional.
4. ~~**Claim form:** does the company have its own claim form layout that the PDF should copy? Who approves: a list of
   approver emails in Firestore?~~ Answered: the company's own A4 layout; managers approve (no approver list).
5. ~~**Per diem and lodging:** fixed amounts per day or night (settings), or receipts only?~~ Answered: by receipt,
   typed amounts allowed.
6. ~~**Distance:** start from the office every day, or from the previous day's last place (overnight trips)?~~
   Answered: from the office and back every day (a switch in ตั้งค่าการเบิก; the day's start place can be edited).
