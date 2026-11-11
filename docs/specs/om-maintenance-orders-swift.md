# O&M-1 ใบงานบำรุงรักษา: PM / CM work orders for handed-over PWA stations (iPad + iPhone Swift spec)

**Status:** Proposed 2026-11-11. Spec only, nothing built. Branch plan and Claude Code prompts: `docs/specs/om/prompts.md`.
**Platform:** TCRoof host app (SwiftUI, SwiftData, iPadOS 17+, iPhone for contractors). Pure logic in `TCRoofCore`
(`Maintenance/…`, tested with `swift test` and on Linux); PDF through `PDFReport`.
**Builds on (read before changing):**
- `TCRoofCore/Monitoring/` (issue #259): the fleet, `Monitoring.Alarm` (already has `workOrder: String?`, unused) and
  `Alarm.Loss`.
- `TCRoofCore/PWAMaintenanceDetail.swift`, `PWAOverview.swift`: `MaintenanceStationSummary.openRepairs` / `nextPM`,
  `MaintenanceStationDetail.tickets` / `nextPM` / `pmHistory`. Today `MaintenanceMock.fill` invents these.
- `TCRoofCore/SiteICL.swift` + `TCRoof/Models/ICLSheet.swift`: the pattern this copies. The record is JSON in SwiftData,
  one Firestore document each with its `state` beside it for the rules, and photos as `PhotoAsset` with a tag.
- `docs/specs/user-roles-architecture.md`, `docs/reference/roles/user-roles.json`: capabilities.
- Program context: `research/pv-inverter-predictive-maintenance.md` (project docs) and the PdM development spec. O&M-1
  is the manual base that the PdM alerts (O&M-3) will later open orders into.

**One idea:** every repair and every PM visit is **one ใบงาน** on the iPad or iPhone, opened from an alarm, from the PM
plan, or by hand. The contractor fills it on site, offline, with photos and readings. The team engineer signs it closed.
The station page, the fleet's `openRepairs` / `nextPM` and later the monthly O&M report read these records, never
mock data.

---

## 1. Why: the O&M engineer's duties, and where each lands

| Duty (O&M job description) | O&M-1 (this spec) | Later |
|---|---|---|
| Monitor real-time performance via SCADA / monitoring | Alarm row → **เปิดใบงาน** (prefilled) | O&M-2 real feed for all stations |
| Analyse generation and PR | Order stores the energy lost (from `Alarm.Loss`) and downtime | O&M-2 daily PR, curtailment-aware |
| Execute PM, perform CM and troubleshooting | **PM plan + PM orders with checklists; CM orders** | O&M-3 alert → order automatically |
| Root cause analysis (inverters, transformers, switchgear) | **RCA block on every CM order**, structured categories | RCA statistics feed the PdM labels |
| Supervise subcontractors, quality | Assign to contractor, submit / send back / close, MTTR per contractor | Contractor scorecard |
| Commissioning, power quality testing | Annual test task links the existing IEC 62446 report; PQM reading fields | |
| SH&E | **Safety gate** (permit-to-work items) before work starts | |
| Engineering reports, O&M summaries | Order PDF | O&M-3 monthly O&M report |

## 2. Scope

**In:** CM and PM orders, a PM plan per station, safety gate, checklist, readings, before/after photos, RCA, the
submit → close hand-off, order PDF, and replacing the mock tickets / PM on the station page and fleet rows.
**Out (later specs):** live Growatt polling for all stations (O&M-2), automatic orders from PdM alerts and the monthly
report (O&M-3), spare-parts stock, Master Plan sheet columns for O&M.

## 3. Model (`TCRoofCore/Maintenance/`)

All values are `Codable, Equatable, Sendable`; decoding uses `decodeIfPresent` with defaults so newer fields never
break older JSON (data rules in the root `CLAUDE.md`).

### 3.1 `MaintenanceOrder`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | UUID, also the Firestore document id |
| `number` | `String` | shown as `TK-<MP>-<yyMMdd>-<n>`, e.g. `TK-P3005-261111-1`; `n` counts the station's orders that day on this device (see open question 1) |
| `jobID` | `String` | the PWA station's job |
| `kind` | `.cm` / `.pm` | ซ่อม / บำรุงรักษาตามแผน |
| `origin` | `.alarm(AlarmRef)` / `.plan(taskID: String, due: Date)` / `.manual` | `AlarmRef` keeps `source`, `code`, `part`, `detail`, `since` of the `Monitoring.Alarm` |
| `target` | `Target` | `part` text (`INV 2`, `MPPT 4 b`, `SOLAR AC-DB-01`), optional `inverterSerial` (scanned at WBS 2.5.2), optional `point` (site ICL installation point id) |
| `priority` | `.critical` / `.high` / `.medium` / `.low` | defaults from §5; the team can change it |
| `title`, `detail` | `String` | |
| `state` | `State` | §3.2 |
| `assignee` | `String?` | contractor email (`external` member) |
| `engineer` | `String?` | team member who closes it |
| `safety` | `[SafetyCheck]` | §3.4 |
| `results` | `[String: SiteICL.Result]` | checklist results keyed by item id, same struct as site ICL (value, passed, N/A, instrument serial, note, checkedAt, by) |
| `readings` | `[Reading]` | name, value, unit, instrument serial (ISO MΩ, Voc V, Isc A, IR ΔT °C, earth Ω, torque N·m, PQM THD %) |
| `rca` | `RootCause?` | CM only, required to close (§3.5) |
| `times` | `Times` | `detected` (alarm `since` or open time), `opened`, `started`, `restored`, `closed` |
| `lossKWh` | `Double?` | from `Alarm.Loss.kWh` when opened from an alarm; editable |
| `submission`, `signoff`, `sendBack` | `SiteICL.Mark?` | same marks as the site ICL |
| `pdfDriveID` | `String?` | the filed PDF |

Computed: `timeToDetect` (opened − detected), `timeToRestore` (restored − detected), `isOverdue(now:)` (open past its
priority's target, §5), `canClose` (§3.2).

### 3.2 States

```
open ──assign──▶ assigned ──start (safety gate passed)──▶ inProgress ──submit──▶ submitted ──close──▶ closed
  │                  │                                         ▲                      │
  └──cancel──▶ cancelled                                       └──────send back───────┘
```

- **start** needs every required `SafetyCheck` ticked (§3.4).
- **submit** (contractor or team) needs `restored` set for CM, every required checklist item answered for PM, at least
  one *after* photo.
- **close** (team only, `om.order_close`) needs the submit rules plus `rca` for CM.
- A contractor's device never writes `closed` or `cancelled`; the rules enforce it (§4.2).
- A pure function `MaintenanceOrder.apply(_ action:, by:, at:) -> Result<MaintenanceOrder, MaintenanceError>` holds
  these rules so they are tested in `TCRoofCore`, and the UI only calls it.

### 3.3 PM plan: `PMPlan` and `PMTemplate`

- **`PMTemplate`** (bundled JSON resource `Resources/pm-templates.json`, versioned like the site ICL catalogue): tasks,
  each with an `id`, a title, an interval in months, the mounts / zero-export side it applies to, and checklist items in
  the `SiteICL.Item` shape (criterion, method, hold, evidence, unit).
- **`PMPlan`** per station, stored on the job (§4.1): the template tasks that apply, each with `lastDone`, an optional
  interval override, and `skip`. `due(task)` = `lastDone + interval`, or the hand-over date (PAC, WBS 3.2) + interval
  when never done. `nextPM` for the fleet row = the earliest due task.
- Opening a PM order from the plan copies the task's items into the order; closing it sets the task's `lastDone`.

Starting template (intervals are engineering assumptions; the team edits them in the JSON):

| Task | Every | Key items / readings |
|---|---|---|
| ตรวจสภาพทั่วไป (visual walk-down) | 3 months | modules, frames, cable trays, walkway, lifeline, tank roof drainage, animal damage |
| ล้างแผง | 6 months (dry season Nov–Apr first) | before/after photos, energy the day before and after |
| Inverter: ทำความสะอาดพัดลม / ฟิลเตอร์, อ่าน event log | 3 months | fan noise, filter, error history export |
| ขันขั้ว DC / AC (torque) | 12 months | torque values, marked bolts, DC-DB / AC-DB / MDB |
| ภาพถ่ายความร้อน (IR) | 12 months | ΔT per hotspot, module / connector / breaker |
| ความต้านทานฉนวน (ISO) ต่อสตริง | 12 months, before the rainy season | MΩ per string (links to the IEC 62446 string test fields) |
| ระบบดิน และ SPD | 12 months | earth Ω (< 5 Ω), SPD status windows |
| Zero export และ PQM | 12 months | export ≈ 0 test, PQM readings, comm to every inverter |
| ทดสอบตาม IEC 62446 (ประจำปี) | 12 months | opens the existing IEC report flow (`IECReport`) for the station |

### 3.4 Safety gate: `SafetyCheck`

Items from the site's HSE plan (WBS 0.1.2), shown before **start**:
- ทำ JSA / แจ้งงานกับ กปภ. สาขาแล้ว (required)
- ตัดไฟและล็อก (LOTO), DC isolator เปิด, วัดยืนยันไม่มีไฟ (required for electrical work)
- งานบนที่สูง: Lifeline / harness ตรวจแล้ว (required for roof and tank work)
- PPE ครบ: ถุงมือกันไฟ, แว่น, รองเท้า (required)
- ทำงานอย่างน้อย 2 คน (required for electrical work)

Each tick keeps who and when. Which items are required comes from the task or the target (electrical / height).

### 3.5 RCA: `RootCause`

| Field | Values |
|---|---|
| `symptom` | text, prefilled from the alarm (`Error 124 No AC Connection`) |
| `component` | inverter, string / connector, module, DC-DB, AC-DB / MCCB, transformer, switchgear / MDB, zero-export / SEM, PQM, communication / logger, structure, other |
| `category` | equipment failure, installation defect, environment (humidity, soiling, animal, lightning), grid event, communication, operation, unknown |
| `cause` | text (why it failed) |
| `action` | text (what was done) |
| `prevention` | text (what stops it happening again) |
| `faultCode` | Growatt code, when there is one |
| `replaced` | parts replaced, with serials (old → new) |

These fields are structured on purpose. They are the fault labels the predictive-maintenance models will learn from
(insulation and humidity first, as in the Thai root-cause data).

### 3.6 `MaintenanceKPI`

Pure functions over a station's or the fleet's orders: open CM, overdue CM, overdue PM, mean time to detect, mean time
to restore (per contractor too), energy lost in CM orders this month. The station page and the fleet rows read them.

## 4. Storage, sync and rules

### 4.1 Storage
- **Orders:** a new SwiftData model `MaintenanceOrderRecord` in `TCRoof/Models/`, built like `ICLSheet`: `orderJSON`,
  `updatedAt`, `job`, `syncID`, photos (`PhotoAsset`, tag `MaintenanceOrder.photoTag(order:item:phase:)` with
  `phase` = before / after). This is additive only (a new model, plus a new relationship on `Job` that is optional with a default).
- **PM plan:** JSON on the job, `Job.pmPlanJSON: String?` (optional, additive), like `weeklyRequestsJSON`. It syncs
  with `jobs`, so it needs no new collection.

### 4.2 Firestore
- New collection `maintenanceOrders`, one document per order: the order JSON plus `jobID`, `state`, `assignee` beside
  it for the rules. Push it in its own batch, as `iclSheets` is pushed (`CloudSync+Push.swift`).
- Rules (add tests in `tools/firestore-rules-tests`):
  - team: read and write.
  - external: read where `assignee == me` or the job is theirs (`readsMine()`); update only where
    `assignee == me`, the old state is `assigned`, `inProgress` or `submitted` (sent back), and the new state is
    `inProgress` or `submitted`. The external member never creates, closes or cancels an order.
- New collection + rule ⇒ raise `AppCompat.syncVersion` to 10 and set `minSyncVersion` once the build is out.

### 4.3 Roles (`user-roles.json`, `UserRoles.swift`, `RoleTableTests`)

| Capability | manager | internal | external |
|---|---|---|---|
| `om.order_create`: เปิดใบงาน O&M | allow | allow | deny |
| `om.order_work`: ทำใบงาน (ความปลอดภัย, ผลตรวจ, รูป, ส่ง) | allow | allow | conditional (assigned to me) |
| `om.order_close`: ปิด / ส่งกลับ / ยกเลิกใบงาน | allow | allow | deny |
| `om.pm_plan`: ตั้งแผน PM ของสถานี | allow | allow | deny |

Keep `site.work_order` for the install-phase ใบสั่งงาน (`ContractorWorkView`); it is a different document.

## 5. Priority and response targets

| Priority | Default when | Target to restore |
|---|---|---|
| วิกฤต (critical) | station or an inverter at 0 on a clear day, ISO trip, fire/arc, safety hazard | same day |
| สูง (high) | loss ≥ 5 % of the station's daily energy, repeated ISO warnings | 3 working days |
| ปานกลาง (medium) | loss 1–5 %, string fault, soiling over threshold | next planned visit, ≤ 14 days |
| ต่ำ (low) | cosmetic, documentation, comms loss < 24 h | ≤ 30 days |

Working days skip Thai public holidays (`PublicHolidays`).

## 6. Screens (Thai UI, design system rules in the root `CLAUDE.md`)

1. **Alarm row → เปิดใบงาน** (station monitor page and fleet alarm list). Prefills target, title (`INV 2 · Error 124`),
   detail, detected time, loss and priority. Writes `Alarm.workOrder = order.number`, so the row then shows the order
   chip instead of the button.
2. **Station page** (`PWAMaintenanceStationView` and the iPad station monitor): the repair (`tickets`) and PM
   (`nextPM`, `pmHistory`) parts read real orders and the plan. `MaintenanceMock` keeps filling a station only when it
   has **no** orders and no plan (demo plants), never mixing mock with real records.
3. **ใบงาน O&M list** (iPad, under บำรุงรักษา): filters for สถานะ, ประเภท (CM / PM), ผู้รับเหมา, เกินกำหนด; sorted by
   priority, then the energy lost; KPI strip on top (open, overdue, MTTR this month).
4. **Order editor** (one page, sections in order): header (number, station, target, priority chip, state), safety
   gate, checklist (PM) or diagnosis (CM), readings, photos ก่อน / หลัง, RCA (CM), sign row (submit / send back /
   close). Fields lock by state as the site ICL does.
5. **PM plan** (station settings, `om.pm_plan`): template tasks with interval, last done and due; **เปิดใบงาน PM** for
   due tasks; overdue in the warning colour.
6. **iPhone (contractor):** งานของฉัน, the orders assigned to me. The editor works offline; photos queue for upload as
   the site ICL's do.
7. **PDF** (`PDFReport`): ใบงาน O&M, A4. Header, safety gate, results, readings, photos, RCA, signatures. Filed to the
   station's Drive folder `6. O&M/<yyyy-MM>/<number> <station>.pdf` (confirm the folder name, open question 3).

Add DEBUG launch arguments (`docs/debug-flags.md`): `-omOrderDemo` (a station with one order in each state) and
`-omOrderEditor <state>`.

## 7. Acceptance criteria

- [ ] `swift test` in `TCRoofKit/`: state machine (every allowed and refused action), MTTD / MTTR, PM `due` and `nextPM`,
      template decoding, priority targets with holidays, old-JSON decoding; also passes `tools/linux-swift/test.sh`.
- [ ] Rules tests: an external member cannot create, close, cancel, or edit an order not assigned to them.
- [ ] Opening an order from an alarm sets `Alarm.workOrder`, and the alarm row shows the order chip.
- [ ] A station with real orders shows no mock tickets or PM; a demo plant still looks complete.
- [ ] A contractor completes a PM order offline on iPhone (safety gate, checklist, photos), and it syncs and appears as
      `submitted` on the team iPad.
- [ ] Closing a PM order moves the task's `lastDone` and the station's `nextPM`.
- [ ] The order PDF is filed to Drive and opens.
- [ ] The xcodebuild build passes; no change to existing schema field ids, labels or Excel cells.

## 8. Open questions

1. Order numbers: is `TK-<MP>-<yyMMdd>-<n>` acceptable, given that two offline devices can rarely give the same `n` on one
   day? (The id stays unique; only the display number would repeat.) Alternative: a number assigned at first sync by a
   Cloud Function.
2. PM intervals and the cleaning rule: use the program's O&M contract terms when known. Who pays for cleaning and
   inverter replacement (PEA as PPA seller, TC, or PWA) decides which orders the contractor bills.
3. The Drive folder for O&M records in `HandoverFolders`.
4. Is a transformer or MV switchgear inside any PWA station's scope, or only up to the PEA meter? This sets the RCA
   component list and the PM tasks for HV-side stations (55 of the 102 in phases 3–4 have HV zero-export).
