# iPhone · Monitor entry (design first), CHA-34

Status: **built** (CHA-34), with the answers in §9. Board: `boards/PhoneMonitorEntry.html`
(open it in a browser; `preview.png` is the same board at 1×). Every number on the board is example data
(`-monitoringDemo YES`'s fleet); never hard-code it.

## 1. Why

CHA-29 gave the iPad dock a `Monitor` tab and decided (its question 4) that the iPhone gets a way into Monitor too.
The iPhone dock (`PhoneTabs`, `TCTabBar(size: .phone)`) has fewer slots, so the entry needs a design first.

Since CHA-29 the situation moved: the fleet page that tab was waiting for, CHA-21's `Monitoring ทุกสถานี`
(`MonitoringPage`), is built, with string and PR checks (CHA-92), server readings (CHA-93) and per-station pages
(CHA-73). But `MonitoringPage` is laid out for the iPad's 1366 pt (63 pt margins, a 398 pt `ต้องดำเนินการ` column,
six cards in a row), so the iPhone can't simply push it. This spec covers both **where the entry goes** and **what
it opens on a 375–430 pt screen**.

## 2. What exists (read before building)

| Piece | Where | Note for iPhone |
|---|---|---|
| iPhone dock | `TCRoof/Views/Home/PhoneTabs.swift`: `PhoneTab`, `PhoneTab.stacks`, `PhoneDockBarContent.items`, `availableTabs`, `initialTab` | today `หน้าหลัก \| งานบ้าน \| กปภ. \| เอกสาร ‖ ตั้งค่า`; contractors lose `เอกสาร` |
| Dock control | `TCTabBar`, `TCTabItem`, `TCTabBarSize.phone` (`TCRoofUI/Layout.swift`) | equal-width tabs, 56 pt high, 23 pt glyph, 10.5 pt label, `minimumScaleFactor(0.8)` |
| iPad entry | `PadTabs.swift`: `.monitor`, `MonitoringPoller()` in the dock, badge `MonitoringStore.attentionCount`, a11y `Monitor \| ต้องดูแล n` | the pattern to copy |
| Glyph | `TCRoof/Assets.xcassets/tab-monitor.imageset` (`docs/ui/ipad-dock-monitor/icons`) | already in the app; template, reused as is |
| Store | `TCRoof/Views/Monitoring/MonitoringStore.swift` (`shared`, `fleet`, `awaitingFirstRead`, `feedFailure`, `refresh(jobs:)`, `poll(jobs:)`, `receive(server:)`, `attentionCount`) | shared by both idioms |
| Fleet rules | `TCRoofCore/Monitoring/Monitoring+Fleet.swift` (`Fleet`, `Row`, `Action`, `Filter`, `Sort`, `needingAttention`, `actions`, `rows(_:sort:)`), `+FleetChecks.swift` (`สตริงกระแสต่ำ`, `PR ต่ำ`, `Raised`) | pure values; the iPhone page only lays them out |
| Status words | `MonitoringParts.swift` (`ปกติ \| แจ้งเตือน \| ออฟไลน์`), `MonitoringPage+Stations.swift` (filter titles `ทั้งหมด \| มีปัญหา \| ออฟไลน์`) | same words on iPhone |
| Server readings | `CloudSync.listenMonitoringReadings` → `MonitoringStore.receive(server:)` | runs on every team device, iPhone included |
| Maintenance overview | iPhone `กปภ.` tab → `PWARoot` → stage `บำรุงรักษา` (`docs/ui/pwa-maintenance-iphone`), `PWAMaintenanceStationView` | the iPhone's existing station page |

**Gap found while reading:** on iPhone nothing calls `MonitoringStore.refresh(jobs:)` (only `MonitoringPage` and
the iPad dock do), and `receive(server:)` returns early while `sources` is empty. So today an iPhone ignores the
server's readings and its badge would stay 0. The entry has to start the store on iPhone as the iPad dock does
(`MonitoringPoller()` for non-contractors), see §7.

## 3. Options compared (board row 1)

| | A. 5th dock tab | B. Row in `กปภ.` | C. Row in the settings sheet |
|---|---|---|---|
| Dock | `หน้าหลัก \| งานบ้าน \| กปภ. \| เอกสาร \| Monitor ‖ ตั้งค่า` | unchanged | unchanged |
| Taps to reach | 1 | 2 (tab, then the card at the top of `บำรุงรักษา`) | 3 (ตั้งค่า, scroll, row) |
| Badge (stations needing someone) | on the dock, seen from every tab, as on iPad | only on the card inside `กปภ.`; the `กปภ.` tab badge already means `นัดวันนี้`, so it can't carry it | only inside the sheet; nothing on the dock |
| Fit | 6 items on a 375 pt phone: 375 − 24 margins − 10 padding − 5 divider − 10 spacing ≈ **54 pt a tab** (≥ 44 pt hit area ✓; `Monitor` at 10.5 pt is about 36 pt wide ✓) | — | — |
| Risk | labels shrink sooner at large text sizes (already true with 5); one more stop for the sideways swipe | Monitor reads as part of PWA projects, not a fleet watch; a new card on a built board | hides a daily-watch screen among account settings |
| Matches iPad | yes (same name, glyph, badge, position after `เอกสาร`) | no | no |

**Recommendation: A.** The badge is the point of the entry (CHA-29 decision 1), and only the dock shows it whatever
tab is open. 54 pt tabs keep the 44 pt minimum. B is the fallback if the user wants the dock kept at five; C is not
recommended.

## 4. Look of option A (board 1-A, state "Dock")

- Item: `TCTabItem(.monitor, title: "Monitor", asset: "tab-monitor", badge: n, accessibilityLabel: n > 0 ? "Monitor | ต้องดูแล \(n)" : "Monitor")`,
  inserted after `.docs`, before the `ตั้งค่า` divider. `Monitor` stays in Latin script, as on iPad.
- Badge: the dock's red count (`Theme.danger`), top right of the glyph, hidden at 0. n = `MonitoringStore.attentionCount`
  (= `Fleet.needingAttention`: paired stations in alarm or offline, or `ปกติ` with a `สตริงกระแสต่ำ` / `PR ต่ำ`
  line). This is wider than CHA-29's "alarm or offline"; the iPad counts it this way since CHA-92, and the iPhone
  should say the same number (question 2).
- Selected: the navy capsule (`Theme.navySolid`), `Theme.onPrimary` glyph and heavy label, as the other tabs.
- `PhoneTab.monitor`: in `stacks`, `fade == Theme.phonePage`, `fadeHeight` 128, `module` nil.
- Contractors (`permissions.role == .external`): no `Monitor`, so their dock stays `หน้าหลัก | งานบ้าน | กปภ. ‖ ตั้งค่า`
  (board state "Dock · ผู้รับเหมา"). Filter it in `availableTabs` and `items`, as `.docs` is. There is no
  `Capability` for monitoring; the iPad gates on the role too, and `firestore.rules` keeps `config/monitoring` and
  `monitoring/{station}` from contractors.

## 5. What the tab opens: `Monitoring ทุกสถานี` (iPhone), boards row 2

A new compact page, `PhoneMonitoringPage` (`TCRoof/Views/Monitoring/Phone/`), that lays out the same
`MonitoringStore.shared.fleet` as the iPad page, one column, 16 pt side margins, 10 pt between cards, bottom inset for
the dock. It reads only; nothing on it writes Firestore.

From the top:

1. **Header** (navy `Theme.headerGradient`, bottom corners 18, as the iPad header): `Monitoring ทุกสถานี`
   (`.sarabun(22, .bold)`, `onPrimary`); under it `อัปเดต 14:55 · จับคู่แล้ว 6/8 สถานี` (13, white 85 %;
   time = the store's last reading, counts = paired / handed over). `store.sourceNote` replaces the second part when
   set (`สถานีตัวอย่างจากเว็บ Growatt`). No settings button in v1 (question 4).
2. **Failure strip**, only when `store.feedFailure` is set: `Theme.warning` soft fill, ⚠ glyph, the failure text
   (2 lines max), and `แสดงข้อมูลล่าสุดที่อ่านได้`. The figures below stay (the last reading), never zeros.
3. **Summary card** (`Theme.surface`, border `borderSubtle`, radius 16):
   - ring 64 pt = `fleet.yieldShare` (today's energy / expected so far), centre `74%`;
   - right: `กำลังตอนนี้ 412 kW` (17 bold `navy`), `วันนี้ 2,572 / คาด 3,475 kWh` (13), `สูญเสียวันนี้ ~38 kWh · ≈ ฿159`
     (13, `warningInk`; from `lossToday` × `settings.rate`; hidden when nil);
   - three tiles: `ปกติ n` (success soft / `successInk`), `แจ้งเตือน n` (danger soft / `dangerText`), `ออฟไลน์ n`
     (`background` / `inkMuted`); counts from `fleet.rows` by `health`. Unknown figures read `—`, never 0.
4. **`ต้องดำเนินการ n`** card: `fleet.actions`, costliest first, at most 5, then `ดูทั้งหมด n รายการ ›`
   (pushes the full list). A line (min height 56): status dot, `MP 25 · <station name>` (15 bold, one line),
   a source/part chip (`TCRoof` / `Error 102` / `Lost` from `Alarm.label`, then the part: `MPPT 4 b`,
   `INV 1 · MPPT 4 b`, `PR`), the detail (`สตริง 3.1 A จากค่ากลาง 6.2 A · เกณฑ์ 30%`, 13 `inkMuted`, 2 lines), and on
   the right the loss (`~4.2 kWh`, or `—`) over the age (`ตั้งแต่ 11:30 · เกิด 3 ครั้ง`). With none:
   `✓ ทุกสถานีปกติ` (`successInk`).
5. **Stations** card: `TCCountSegments` `มีปัญหา n | ออฟไลน์ n | ทั้งหมด n` (`Monitoring.Filter`, default
   `มีปัญหา`, falling back to `ทั้งหมด` when it is 0), a `เรียง` menu (`สูญเสีย | kWh/kWp | MP`, `Monitoring.Sort`),
   then rows (min height 60): `MP 12` chip, name, `120 kWp`, power now and `kWh/kWp` today, and a status chip
   (`TCStatusChip`, `ปกติ | แจ้งเตือน | ออฟไลน์`, or `ไม่มีข้อมูล` when not paired). A row opens the station (§6).

No chart in v1: the total power chart needs the iPad's width to read (question 5).

## 6. A station from the iPhone

`StationMonitorPage` is iPad-wide too. Until a compact one is designed, a station row (and an `ต้องดำเนินการ` line)
pushes the iPhone's existing **`PWAMaintenanceStationView`** for that job, as `ไปหน้าบำรุงรักษา ›` does on iPad, so
the dock is covered and `กลับ` returns to the list (question 6).

## 7. States (board row 2)

| State | When | Shows |
|---|---|---|
| Loading | `store.awaitingFirstRead` (or `-monitoringLoading YES`) | skeletons in the page's shape: `TCSkeletonCard` for the summary, 3 `TCSkeletonRow` in `ต้องดำเนินการ`, 4 in stations, `.tcShimmer()` (still under Reduce Motion). No spinner. |
| Loaded | normal | §5 |
| All normal | `fleet.actions` empty | `✓ ทุกสถานีปกติ` in `ต้องดำเนินการ`; badge hidden |
| No handed-over stations | `MonitoringStore.handedOver(jobs)` empty | one card: `ยังไม่มีสถานีที่ส่งมอบ` / `สถานีจะขึ้นที่นี่เมื่อส่งมอบงานแล้ว` |
| None paired | stations but none `paired` | stations listed as `ไม่มีข้อมูล`; a note card: `ยังไม่ได้จับคู่สถานีกับ Plant ใน Growatt` / `ผู้จัดการจับคู่ได้ที่ ตั้งค่า Monitoring บน iPad` |
| Read failed / offline | `store.feedFailure` set | the failure strip (§5.2) over the last figures |

Store start on iPhone: `PhoneDockBarContent` gets `.background { if permissions.role != .external { MonitoringPoller() } }`
and the same `.task { if MonitoringStore.demo … refresh }` as `PadDockBarContent`, so the badge and the server's
readings work from any tab. On an iPhone without a token (everyone but a manager who saved one there) the poller
reads only what the server already wrote (`monitoring/{station}`), so it costs no Growatt calls (question 3).

## 8. Rules kept

- Colours from `Theme` only (no hex, no `Color.white`); text `.sarabun`, rows `frame(minHeight:)`; WCAG AA (a chip's
  light fill takes `navy` text).
- Hit areas ≥ 44 pt (dock tabs ~54 pt; rows 56–60 pt; `ดูทั้งหมด` 44 pt).
- Skeletons for the first read, spinners only for actions.
- Long SwiftUI bodies split into computed properties (one per card).
- No new data, no SwiftData or Firestore change, no rule change; `AppCompat.syncVersion` unchanged.
- DEBUG: `-homeTab monitor` on iPhone (add `monitor` to `PhoneTab` raw values); `-monitoringDemo YES`,
  `-monitoringLoading YES`, `-growattDemo YES` work as on iPad. Document them in `docs/debug-flags.md` (iPhone
  `-homeTab` list) and the UI test in `docs/ui-tests.md`.
- UI test (`HomeNavbarUITests`, iPhone): `Monitor` sits between `เอกสาร` and `ตั้งค่า`; tapping it shows
  `Monitoring ทุกสถานี`; with `-role external` there is no `Monitor`; with `-monitoringDemo YES` the button's label
  is `Monitor | ต้องดูแล n` with n > 0.

## 9. Decisions (answered 2026-11-10)

Asked and answered: 1 A, the dock tab; 3 the iPhone reads (`MonitoringPoller` on its dock) but posts no
notifications (`MonitoringStore.postsAlerts` is the iPad only); 4 ตั้งค่า Monitoring hidden on iPhone; 7 the compact
page of §5 straight away. Taken as recommended: 2 the same badge number as the iPad (`needingAttention`); 5 no chart in
v1; 6 a station opens `PWAMaintenanceStationView` (TCRoofKit, `Survey/Home`) through `MonitoringPage.summary`; 8 Monitor
last before `ตั้งค่า`.

Note from building: this version of `MonitoringStore` has no `receive(server:)` (Monitoring reads Growatt on the device
only), so an iPhone shows readings only when a token is saved on that phone; the others show the stations as
`ไม่มีข้อมูล` and the badge stays 0 there.

### The questions as asked

1. **Entry: A (5th dock tab), B (card in `กปภ.` › `บำรุงรักษา`) or C (settings row)?** Recommended A.
2. **Badge count:** the iPad now counts alarm + offline + `ปกติ` with a low string or PR (`needingAttention`), wider
   than CHA-29's "alarm or offline". Keep the iPhone the same as the iPad? (Recommended: yes, one number.)
3. **Polling on iPhone:** start `MonitoringPoller` on the iPhone dock (server readings only unless a token is on that
   phone)? It also means the iPhone posts the local `ออฟไลน์` / `แจ้งเตือน` notifications (`MonitoringNotification`),
   so someone with an iPad and an iPhone may get them twice. Allow, or iPhone shows readings but never notifies?
4. **`ตั้งค่า Monitoring` on iPhone:** hide it (managers use the iPad), or a read-only sheet?
5. **Chart:** leave the total power chart out of the iPhone page in v1, or a small today-only sparkline in the summary
   card?
6. **Station tap:** open the existing `PWAMaintenanceStationView` for now, and design a compact `Monitoring สถานี`
   later (a new issue)?
7. **CHA-34's "until CHA-21 exists, open the pinned บำรุงรักษา overview":** CHA-21's page exists on iPad now. Build the
   compact page of §5 straight away (recommended), or ship the tab first opening the `กปภ.` home pinned on
   `บำรุงรักษา` and do §5 as a second step?
8. **Order:** `… | เอกสาร | Monitor ‖ ตั้งค่า` (as iPad, Monitor last before settings), or Monitor before `เอกสาร`?
