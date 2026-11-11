# O&M-1: branch plan and Claude Code prompts

Spec: `docs/specs/om-maintenance-orders-swift.md`. One branch per feature, merged in this order (each builds on the one
before). Every prompt assumes the session has read the root `CLAUDE.md` and the area `CLAUDE.md` files it names.

| # | Branch | What | Checks |
|---|---|---|---|
| 1 | `feat/om-1a-core` | `TCRoofCore/Maintenance/` values, rules, PM templates, KPIs, tests | `swift test --parallel` in `TCRoofKit/`, `tools/linux-swift/test.sh` |
| 2 | `feat/om-1b-roles-sync` | roles, SwiftData model, `Job.pmPlanJSON`, Firestore sync and rules | rules tests, xcodebuild build |
| 3 | `feat/om-1c-ipad` | alarm → order, station page, order list, editor, PM plan (iPad) | xcodebuild build, DEBUG flags, screenshots |
| 4 | `feat/om-1d-iphone` | contractor งานของฉัน and editor on iPhone, offline photos | xcodebuild build, UI test |
| 5 | `feat/om-1e-pdf` | order PDF and Drive filing | `swift test` (PDF layout values), build |

---

## 1. `feat/om-1a-core`

```
Read CLAUDE.md, TCRoofKit/CLAUDE.md and docs/specs/om-maintenance-orders-swift.md §3 and §5.

Build the pure model in TCRoofKit/Sources/TCRoofCore/Maintenance/ (no UIKit, must build on Linux):
- MaintenanceOrder (§3.1) with nested Kind, Origin (alarm/plan/manual, AlarmRef copied from Monitoring.Alarm),
  Target, Priority, State, Reading, Times; Codable with hand-written init(from:) using decodeIfPresent defaults.
- The state machine as MaintenanceOrder.apply(_:by:at:) -> Result<MaintenanceOrder, MaintenanceError> (§3.2):
  assign, start (safety gate), submit, sendBack, close (CM needs rca), cancel. Reuse SiteICL.Result and SiteICL.Mark.
- SafetyCheck (§3.4) with required rules by target kind (electrical / height).
- RootCause (§3.5) with the component and category enums.
- PMTemplate decoded from a bundled Resources/pm-templates.json (§3.3 table as the first version, items in the
  SiteICL.Item shape), and PMPlan with due(task:handover:) and nextPM.
- Priority defaults and response targets (§5) counting working days with PublicHolidays.
- MaintenanceKPI (§3.6).
- MaintenanceOrder.number(mp:date:sequence:) -> "TK-P3005-261111-1".

Tests (XCTest, Bangkok time as the other tests assume): every allowed and refused transition, MTTD/MTTR, due dates
across a holiday, template decoding, decoding an order JSON with fields missing. Run swift test --parallel in
TCRoofKit/ and tools/linux-swift/test.sh. Do not touch the app target in this branch.
```

## 2. `feat/om-1b-roles-sync`

```
Read CLAUDE.md, TCRoof/CLAUDE.md, tools/master-plan-sheet/CLAUDE.md (do not change fields it reads) and
docs/specs/om-maintenance-orders-swift.md §4. Branch from feat/om-1a-core.

- Roles: add om.order_create, om.order_work (external: conditional, assigned to me), om.order_close, om.pm_plan to
  docs/reference/roles/user-roles.json and TCRoofCore/UserRoles.swift; keep RoleTableTests passing.
- SwiftData: new @Model MaintenanceOrderRecord in TCRoof/Models/, built like ICLSheet (orderJSON, updatedAt, job,
  syncID, photos with a cascade relationship, @Transient ModelJSONCache). Add Job.pmPlanJSON: String? and the
  relationship on Job, optional with defaults (additive only, no VersionedSchema).
- Sync: collection "maintenanceOrders" in CloudRecords, pushed in its own batch like iclSheets in CloudSync+Push,
  with jobID, state and assignee beside the JSON; pull and merge as ICL sheets do.
- firestore.rules: team read/write; external read assigned or readsMine(); external update only when assignee is
  them, the old state is assigned/inProgress/submitted and the new state is inProgress/submitted; no create.
  Add tests in tools/firestore-rules-tests and run them.
- Raise AppCompat.syncVersion to 10 (note it in the AppCompat comment).
Build with xcodebuild (own -derivedDataPath).
```

## 3. `feat/om-1c-ipad`

```
Read CLAUDE.md, TCRoof/CLAUDE.md, TCRoofKit/CLAUDE.md (design system), docs/ui/CLAUDE.md and
docs/specs/om-maintenance-orders-swift.md §6 (1–5). Branch from feat/om-1b-roles-sync.

- Alarm rows (station monitor and fleet alarms): a "เปิดใบงาน" button when om.order_create allows it, opening the
  editor prefilled from the alarm; after saving, set Alarm.workOrder and show the order chip instead.
- Station page: tickets / nextPM / pmHistory and the fleet's openRepairs / nextPM come from real orders and the PM
  plan. MaintenanceMock.fill fills a station only when it has no orders and no plan.
- "ใบงาน O&M" list under บำรุงรักษา with filters (สถานะ, CM/PM, ผู้รับเหมา, เกินกำหนด), sorted by priority then
  energy lost, KPI strip on top.
- Order editor: header, safety gate, checklist or diagnosis, readings, photos ก่อน/หลัง, RCA (CM), sign row.
  Locks fields by state as the site ICL does; every action goes through MaintenanceOrder.apply.
- PM plan editor in station settings (om.pm_plan) with "เปิดใบงาน PM" for due tasks.
Colours from Theme, TCButtonStyle, 44 pt hit areas, skeletons while loading. Add the DEBUG flags -omOrderDemo and
-omOrderEditor <state> to docs/debug-flags.md. Build with xcodebuild; screenshot each state.
```

## 4. `feat/om-1d-iphone`

```
Read CLAUDE.md, TCRoof/CLAUDE.md, TCRoofUITests/CLAUDE.md and docs/specs/om-maintenance-orders-swift.md §6.6.
Branch from feat/om-1c-ipad.

- iPhone "งานของฉัน" for external members: orders assigned to me, grouped by state, due first.
- The editor in its phone layout; works offline; photos queue as site ICL photos do; submit only (no close).
- A UI test: a contractor opens an assigned PM order, ticks the safety gate, fills the checklist, adds an after
  photo and submits; document it in docs/ui-tests.md.
```

## 5. `feat/om-1e-pdf`

```
Read CLAUDE.md, TCRoofKit/CLAUDE.md (PDFReport, DriveSync) and docs/specs/om-maintenance-orders-swift.md §6.7.
Branch from feat/om-1c-ipad.

- A4 ใบงาน O&M PDF in PDFReport: header, safety gate with who/when, checklist results, readings with instrument
  serials, photos before/after, RCA, submit and close signatures.
- File it on close to the station's Drive folder (HandoverFolders: add "6. O&M/<yyyy-MM>" after confirming the name)
  and keep pdfDriveID on the order.
- Layout values tested in TCRoofCore where possible; build with xcodebuild.
```
