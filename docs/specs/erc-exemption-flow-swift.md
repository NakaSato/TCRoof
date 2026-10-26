# ERC exemption flow per station, under 1,000 kVA (Swift dev spec)

**Status:** §3 (`TCRoofCore/ERCFlow.swift`, 12 tests) and §4's tab, step sheet and history built 2026-10-13
(`TCRoof/Views/Job/StationDocs/ERCFlowViews.swift`), with the line on the job's `StationDocsCard` and the links from
steps 3 and 7 to their packages. §5 built the same day: a waiting step with a time limit is a `กำหนดส่ง` row of the
PWA plan page (`PWAPlan.deadlines`, from `ERCFlow.waits`), and `ERCNotification` reminds at 08:00 3 days before the limit
(working days where the limit counts them) and the day after it. The reminders are posted as MP plan notifications (`NotificationType.mp`), so a tap opens the job,
not the tab; a plan-page row opens เอกสารสถานี กปภ. on its first tab. Written from the two diagrams in `docs/permit/`; the open questions (§7) were not
answered, so the build took these defaults: working days are Monday–Friday less the site's own holidays
(`RoutineReport.Settings.holidays`), step 10 is asked per station, and steps 4, 5 and 9 can be recorded or passed over.
2026-10-20: Q1 answered by building the under-200 kVA flow (§1b): every station has the `ลำดับ กกพ.` tab, its size
picks the flow, and a record keeps the flow it was started in. 19 `ERCFlowTests`.
Not built: steps 3 / 7 defaulting to the package's submission day, the two private-network flows (กปภ. stations are
all on กฟภ.'s network).
**Source:** `docs/permit/กกพ. การไฟฟ้า 200–1,000 kVA.pdf` (swim lanes) and `docs/permit/ลำดับ กกพ. การไฟฟ้า 200–1,000 kVA.pdf`
(the same flow as 12 numbered messages). Both redraw the ERC office's infographic for a system on a utility's
network. The diagrams name three more sheets (utility / private network × under 200 kVA / 200–1,000 kVA); the summary of
all four is in `docs/reference/forms/erc/exemption-flow.json` (flows `utility_lt200`, `private_lt200`,
`utility_200_1000`, `private_200_1000`).
**Goal:** for every กปภ. station, show where the station stands in the exemption flow, whose turn it is, and when the
waiting party's time runs out, next to the papers the app already tracks.

---

## 1. The flow

Four parties: the operator (us, for กปภ.), the utility (กฟภ. / กฟน.), the ERC office (สำนักงาน กกพ.) and DEDE (พพ.).

| # | Step | From → to | Time limit | If it fails |
|---|---|---|---|---|
| 1 | ยื่นคำขอตรวจสอบแบบและระบบไฟฟ้า | operator → utility | | |
| 2 | ผลพิจารณาแบบและระบบไฟฟ้า (+ เงื่อนไข) | utility → operator | 15 working days | fix the design, back to 1 |
| – | ติดตั้งเครื่องจักร อุปกรณ์ สายไฟฟ้า | operator | | |
| 3 | ยื่นคำขอ พค.2 | operator → ERC | | |
| 4 | ตรวจเอกสาร ขอความเห็น พพ. | ERC → DEDE | | |
| 5 | ความเห็นต่อสำนักงาน กกพ. | DEDE → ERC | 30 days | |
| 6 | ได้รับ พค.2 ที่ลงนามแล้ว | ERC → operator | | |
| 7 | แจ้งขอตรวจระบบไฟฟ้า | operator → utility | | |
| 8 | ผลตรวจระบบ / อุปกรณ์การเชื่อมต่อ | utility → operator | 30 working days | fix the installation, back to 7 |
| 9 | ส่งข้อมูล / หนังสือพิจารณาการเชื่อมต่อ | utility → ERC | | |
| 10 | ยื่น พค.2 ประกอบการขนานไฟ | operator → utility | | only where the utility asks for it |
| 11 | ขนานไฟ / COD | utility → operator | | |
| 12 | แจ้งผลการแจ้งยกเว้นฯ ทางอิเล็กทรอนิกส์ | ERC → operator | | |

Rules the diagrams state:
- Steps 3–6 (พค.2) and 7–8 (the utility's inspection) run in parallel after installation.
- The time limits leave out the time the operator spends fixing data or the installation.
- The ERC takes พค.2 **or** the utility's หนังสือพิจารณาฯ, either one, for the exemption result (step 12).
- Whether the utility wants พค.2 before it connects (step 10) depends on that utility's own conditions.
- A project that sells power follows its own announcement's time limits.

## 1b. Under 200 kVA (`utility_lt200`)

`ERCFlow.Variant.under200`, from the JSON's `utility_lt200`. The operator files nothing with the ERC
(`operator_files_with_erc: false`): the utility sends its letter to the ERC after its inspection passes, and the ERC
tells the operator the result. No พค.2 and no DEDE, so the step-10 question isn't asked.

| # | Step | From → to | Time limit | If it fails |
|---|---|---|---|---|
| 1 | ยื่นคำขอตรวจสอบแบบและระบบไฟฟ้า | operator → utility | | |
| 2 | ผลพิจารณาแบบและระบบไฟฟ้า (+ เงื่อนไข) | utility → operator | 15 working days | fix the design, back to 1 |
| – | ติดตั้งเครื่องจักร อุปกรณ์ สายไฟฟ้า | operator | | |
| 3 | แจ้งขอตรวจระบบไฟฟ้า | operator → utility | | |
| 4 | ผลตรวจระบบ / อุปกรณ์การเชื่อมต่อ | utility → operator | 30 working days | fix the installation, back to 3 |
| 5 | ส่งข้อมูล / หนังสือพิจารณาการเชื่อมต่อ | utility → ERC | | |
| 6 | ขนานไฟ / COD | utility → operator | | |
| 7 | แจ้งผลการแจ้งยกเว้นฯ ทางอิเล็กทรอนิกส์ | ERC → operator | | |

- The steps are the same `ERCFlow.Step` cases as the big flow (raw values unchanged), a subset of it;
  `Step.number(in:)` gives each flow's numbers (`Step.number` stays the big flow's).
- 6 (COD) waits once 4 has passed; 7 waits from then too and is done when the ERC answers. 5 can be recorded or passed
  over, as 9 in the big flow. `canConnect` is true once 4 has passed; `exemptionBasis` is the utility's letter.
- The JSON's `erc_publish` (the ERC's web list) is an end, not a step to record, in both flows.

**Which flow.** `ERCFlow.needsPK2(kVA:)` (`kVA >= 200`, `ERCFlow.pk2ThresholdKVA`) is the one threshold:
`StationDocs.Context.over200kVA` (inverter total, or set by hand in แก้ข้อมูลสถานี) and
`MasterSchedule.Input.isOver200kVA` both read it. Before, the MP plan's default used `> 200`, so a station of exactly
200 kVA now gets พค.2 in its plan's default as well. `Job.ercContext` passes the flow the station's size gives
(`Context.variant`).

**Across 200 kVA.** `Record.variant` keeps the flow a record was started in: every change in the tab pins it first
(`Record.pin`). `Record.variant(_ ctx)` decides the flow shown:
1. an event of a step only the big flow has (พค.2, DEDE, step 10) → the big flow, always;
2. else, once anything is recorded, the pinned flow;
3. else (empty, or events with no pin) the station's size.

So records made before this change (no `variant`, only for stations of 200 kVA and over) keep showing as before, and a
station that changes size keeps its flow. Where they differ, the tab says so and offers
`เปลี่ยนเป็นลำดับ…` when nothing recorded would be hidden (`Record.canSwitch(to:)`: always to the big flow, to the small
one only without พค.2 steps). Nothing is ever deleted by a size change. An unknown `variant` from a newer build decodes as
none.

**1,000 kVA and over** needs a generating licence, outside both flows (`ERCFlow.licenceKVA`). As before this change,
such a station shows the 200–1,000 kVA flow: `over200kVA` is true and there is no third flow.

## 2. What the app already has

| Flow | App today |
|---|---|
| 200 kVA picks the flow (§1b) | `StationDocs.Context.over200kVA` (inverter total, or set by hand), from `ERCFlow.needsPK2` |
| Step 3's papers | the `พค.2` package and `StationDocs.pk2Checklist` (23 items) |
| Steps 7–11's papers | the `ขนานไฟ` package (18 kinds, incl. the outage letter the app drafts) |
| Planned days of 3 and 7 | `MasterSchedule.Task.pk2`, `.gridConnection`, `.cop`, and `Station.dueDates` |
| Deadlines on the PWA plan page | `PWAPlan` `กำหนดส่ง`, from `PWAPlan.submissionTask` |
| Reminders | `SystemNotifications` `NotificationPlan`s |

Nothing records what happened after a submission: the day it went in, the answer, a failed round, or how long the
other side has had it. That is the gap.

## 3. Data (`TCRoofCore/ERCFlow.swift`, pure)

```swift
public enum ERCFlow {
    public enum Party { case us, utility, erc, dede }
    public enum Step: String, Codable, CaseIterable {   // raw values are kept in job JSON: never rename
        case designRequest, designResult, install, pk2Request, ercToDede, dedeOpinion, pk2Signed,
             inspectionRequest, inspectionResult, utilityToERC, pk2ToUtility, cod, exemptionResult
    }
    public struct Limit { let days: Int; let working: Bool }   // on Step.limit, counted from the step that asked:
                                                                // 2: 15 wd from 1 · 5: 30 d from 4 · 8: 30 wd from 7
    public enum Result: String, Codable { case passed, failed }

    /// One thing that happened. A failed round is another event of the same step, so the history is kept.
    public struct Event: Codable, Equatable { var step: Step; var day: String /* yyyy-MM-dd */; var result: Result?; var note: String }

    public struct Record: Codable, Equatable {
        public var events: [Event] = []
        /// Step 10: nil = not known yet.
        public var utilityWantsPK2: Bool?
    }
}
```

- Kept on the station: `StationDocs.Station.erc: ERCFlow.Record?`, decoded with `decodeIfPresent`, so old jobs open
  and it syncs inside `stationDocsJSON` with no new Firestore field.
- Derived, never stored:
  - `states(_ record, _ ctx) -> [Step: State]` (`done(day:)`, `waiting(since:due:)` (the party is `step.party`),
    `open`, `blocked`, `notNeeded`). `Context` carries the install day and the holidays.
  - `current(_ record, _ ctx) -> [Step]`: the steps in play, ours or another party's (several at once while 3–6 and
    7–8 run in parallel).
  - `due(_ step, from: asked, _ ctx)`: the limit's last day, counting working days Monday–Friday less the context's
    holidays, from the latest request (so a failed round restarts it).
  - `canConnect(record, ctx)`: true when step 11 (COD) is waiting or done: 8 passed, and 10 done (so 6 too) when
    `utilityWantsPK2 == true`.
  - `exemptionBasis(record)`: พค.2 (6) or the utility's letter (9), whichever is there.
- Step `install` is done when every construction task of the MP plan has a finish date (the day is the latest one),
  or when the team records it by hand (`Job.ercContext`, `ERCFlowViews.swift`).
- The record sheet's day defaults to today. ~~Steps 3 and 7 offer the day their package was set to ยื่นแล้ว as the
  default day~~: not built.

## 4. Screen

A chip `ลำดับ กกพ.` in `StationDocsScreen`'s tab row, for every station (`Check list พค.2` stays for 200 kVA and over
only). The list shows the record's flow (§1b): its sections, numbers and the summary's flow name.

- A vertical step list in the diagram's four sections (ออกแบบและขอความเห็นแบบ · ติดตั้ง · พค.2 และตรวจระบบ · ขนานไฟ
  และผลแจ้งยกเว้น), each row: number, title, the party whose turn it is as a `TCStatusChip`, the day, and for a
  waiting step `เหลือ n วันทำการ` or `เกินกำหนด n วัน`.
- Tapping any open or waiting row opens a small sheet: day, note, and for 2 and 8 ผ่าน / ไม่ผ่าน. ไม่ผ่าน adds the
  event and reopens 1 or 7.
- Step 3 links to the พค.2 papers, step 7 to the ขนานไฟ package (`ดูเอกสารชุด…`). A step whose package is not complete
  shows its ready / total beside the tap-to-record prompt, and can still be recorded.
- The job's `StationDocsCard` gets one line: the current step and whose turn it is.
- Built from `TCRoofUI` components; no new colours. Party colours in the diagram are the diagram's, not `Theme`'s.

Launch arguments, as the other screens: `-screen stationdocs -stationDocsERC wait|failed|ready|parallel|done` seeds a
record in that state at 200 kVA; add `-stationDocsERCSize 150` for the under-200 flow (`parallel` is then the
inspection waiting, `done` has no พค.2 steps), or `-stationDocsERC small` for `wait` at 150 kVA.

## 5. Elsewhere

- `PWAPlan` `กำหนดส่ง`: a waiting step with a limit becomes a deadline row (`รอผลตรวจแบบ กฟภ.`), filtered with the
  submissions, for either flow, numbered as its flow (`Wait.number`).
- Notifications (`ERCNotification`, `LiveNotifications.swift`): one at 08:00 3 days before a limit ends (working
  days where the limit counts them) and one at 08:00 the day after, posted with type `.mp`, so a tap opens the job.
  Both flows: the small one's 2 and 4 remind the same way.
- `MasterSchedule`: untouched. The flow reads the plan; it does not move weights or dates.
- No PDF or Excel output in this spec.

## 6. Tests (`ERCFlowTests`)

- A new record: only step 1 is open.
- 1 done → 2 waits on the utility, due 15 working days later across a weekend and a holiday.
- 2 failed → 1 open again; the second request restarts the limit; the first round stays in the history.
- Install done → 3 and 7 both open; 5 due 30 calendar days after 4.
- `canConnect`: false with 8 passed and `utilityWantsPK2 == true` until 6 is done; true when it is `false`.
- `exemptionBasis` with only 9, only 6, both.
- Old station JSON without `erc` decodes; a record round-trips.
- Under 200 kVA: the size picks the flow at 200 (and `isOver200kVA` agrees with `StationDocs.Context`); seven numbered
  steps and no พค.2; the 15 / 30 working-day limits and the waits' numbers; COD and the exemption result waiting once
  the inspection passes, whatever step 10 says; reminders numbered as the small flow; a record keeping its flow across
  200, a legacy record with a พค.2 step staying big; the flow round-tripping and an unknown one decoding as none.
  `PWAPlanTests` checks a small station's deadline row.

## 7. Open questions

1. ~~**Under 200 kVA.** Most กปภ. stations are smaller. Should the screen cover them too?~~ Answered 2026-10-20: yes,
   with the `utility_lt200` flow (§1b).
2. ~~**Holidays.**~~ Answered 2026-10-26: a bundled list (`PublicHolidays`, from the plan workbook's `สมมติฐาน`
   sheet by `tools/plan-template/holidays.py`), skipped by `ERCFlow.isWorking` on top of the site's own days off.
3. **Step 10.** Does กฟภ. ask the กปภ. stations for พค.2 before connecting? If always the same, the per-station
   question can go.
4. **Steps 4, 5 and 9** happen between other parties. Does the team ever learn their days, or should they show only
   as "waiting" until 6 and 12?
5. **Design approval (1–2)** and the MP plan's `Engineering Approve`: the same event, or the utility's review is
   separate from the client's?
6. **Who records it:** the site engineer on the iPad, or the office? That decides whether the iPhone PWA module
   needs the screen.
7. The two PDFs are 4.7 MB together. Keep them in git, or keep a link to the Project and drop them?
