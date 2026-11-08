# iPad dock · `Monitor` tab

Component: the iPad main dock (`เมนูหลัก`), as drawn on every iPad board of the design canvas. Reference boards are
in `boards/`; open them in a browser:

- `iPadSurveyHome.dc.html`: the dock with `งานบ้าน` selected;
- `iPadPwaMonitoring.dc.html`: `Monitor` selected;
- `iPadTools.dc.html`: `เครื่องมือ` selected.

Dock crops at 2x (1532 × 208, the dock's 766 × 104 pt area) are in `states/`; `preview.png` is a whole board at 1 ×.
The new glyph is `icons/tab-monitor.svg`, and `icons/tab-monitor.imageset/` is ready to drop into `TCRoof/Assets.xcassets`.
The badge numbers on the boards (`2`, `3`) are examples; never hard-code them.

## 1. Goal

The iPad dock (`PadDockBarContent` in `TCRoof/Views/Home/PadTabs.swift`, drawn by `TCTabBar(size: .pad)`) gets one
more tab, **`Monitor`**, between `เอกสาร` and `เครื่องมือ`. The dock then reads:

`หน้าแรก | โครงการ | งานบ้าน | เอกสาร | Monitor | เครื่องมือ | สแกน ‖ ตั้งค่า`

`Monitor` is where the team watches handed-over PWA stations (production, alarms, data loggers). Its full fleet page,
the canvas board `iPadPwaMonitoring`, is a separate task (Linear CHA-21). In this task the tab opens what the app
already has for those stations: the PWA home's `บำรุงรักษา` overview. The tab's red badge counts the stations that
need attention.

## 2. Scope

Do only the change list in §5. Out of scope; do not touch these:

- The iPhone dock (`PhoneTabs`, `TCTabBar(size: .phone)`) and its items.
- `TCTabBar` / `TCTabItem` in TCRoofUI. The dock already takes any number of items. Change it only if the 8-item dock
  doesn't fit (§5 item 6), and then only its spacing.
- The fleet monitoring page and the per-station monitor page (canvas boards `iPadPwaMonitoring` and
  `iPadPwaStationMonitor`), Growatt API calls, and `MaintenanceStationSummary`'s fields.
- The other tabs' roots, the `โครงการ` and `งานบ้าน` badges, the settings sheet.
- The board's `เอกสาร` link target (on the canvas it still points at a deleted board; the app's `เอกสาร` tab is right).

## 3. Read first

- `TCRoof/Views/Home/PadTabs.swift`: `PadTab`, `stacks`, `fade`, `availableTabs`, `stack(_:)`, `initialTab`,
  `PadDockBarContent.items`.
- `TCRoof/Views/Survey/PWARoot.swift`: how the PWA home is hosted, and `overview` (`PWAOverviewHost`).
- `TCRoofKit/Sources/TCRoofUI/Survey/Home/SurveyHome.swift`: `@AppStorage("solarSurvey.homeTab") var tab` (a
  `JobStage`), and how the nav segment switches `survey | install | maintenance`.
- `SurveyHome+Overviews.swift` (the maintenance overview, `maintenanceStations`) and `PWAPhoneTabs.swift`
  (`Job.maintenanceSummary`).
- `GrowattDemoFeed`: the DEBUG `-growattDemo` plants that give the overview alarms.
- `TCRoofKit/Sources/TCRoofUI/Layout.swift`: `TCTabItem`, `TCTabBar`, `TCTabBarSize.pad`.
- `TCRoofUITests/HomeNavbarUITests.swift`.

## 4. Look (from the boards)

- Same 84 × 58 pt button as the other tabs: 24 pt glyph over an 11.5 pt label, `Monitor` in Latin script (not
  translated).
- Glyph: a monitor with a pulse line on its screen, on a stand (`tab-monitor.svg`, 24 × 24, stroke 2, round caps
  and joins, a template image like `tab-tools`).
- Badge: the red count badge, as on `โครงการ` (top right of the glyph, hidden at 0).
- Selected: the navy capsule, white glyph and bold label (state 02).

## 5. Change list (in order)

1. **Asset.** Add `TCRoof/Assets.xcassets/tab-monitor.imageset` from `icons/tab-monitor.imageset`. It renders as a
   template and keeps its vector representation.
2. **Tab.** Add `case monitor` to `PadTab`, between `docs` and `tools`. It is a stack (`stacks`) with
   `fade == Theme.phonePage`, like `.pwa`, and its `module` is `nil`. Contractors (`permissions.role == .external`)
   don't get it: filter it in `availableTabs` and `items`, as `.docs` is.
3. **Dock item.** In `PadDockBarContent.items`, insert after `.docs`:
   `TCTabItem(.monitor, title: "Monitor", asset: "tab-monitor", badge: n, accessibilityLabel: n > 0 ? "Monitor | ต้องดูแล \(n)" : "Monitor")`.
4. **Root, until CHA-21's page exists.**
   - Add a `MonitorRoot` (`TCRoof/Views/Survey/MonitorRoot.swift`). It shows the PWA home's `บำรุงรักษา` overview with
     the same host data as `PWARoot`; `PWAMaintenanceStationView` opens a station, as it does there.
   - It must not change the PWA home: the `โครงการ` tab keeps its own segment, and opening `Monitor` never writes
     `solarSurvey.homeTab`.
   - Give `SurveyHomeView` / `SolarSurveyEntryView` an optional pinned stage, as an environment value or parameter,
     defaulting to none. When it is set:
     - the stage is `.maintenance`;
     - the `survey | install | maintenance` segment is hidden;
     - the AppStorage tab is read and written as before for everyone else.
   - Share `PWARoot`'s overview host rather than copying it: extract what `MonitorRoot` needs into one helper both use.
5. **Badge count.** n is the number of handed-over PWA stations whose `MaintenanceStationSummary.status` is `.alarm`
   or `.offline`, from the same summaries the overview shows (with `-growattDemo`, the demo plants' statuses too).
   Real stations have no feed yet (`status: .normal`), so n is 0 in production today. Compute it once per change of
   the jobs, not on every dock redraw.
6. **Fit.**
   - 8 tabs + the divider make the dock about 707 pt wide. Check it in landscape (1366) and in portrait at 1024 and
     at the iPad mini's 744.
   - If it doesn't fit at 744, take the narrowest change in `TCTabBar`'s `.pad` size (button width 84 → 78) and say so
     in your report. Nothing else changes.
7. **DEBUG.**
   - `-homeTab monitor` opens with the tab selected (`initialTab`).
   - `-growattDemo YES` gives it alarms for the badge.
   - Add both to CLAUDE.md's simulator list, where `-homeTab` and the dock's items are listed (`หน้าแรก | โครงการ |
     งานบ้าน | เอกสาร | Monitor | เครื่องมือ | สแกน | ตั้งค่า`).
8. **UI test.** Extend `HomeNavbarUITests` (iPad):
   - the dock has a `Monitor` button between `เอกสาร` and `เครื่องมือ`;
   - tapping it shows the maintenance overview, with no segment;
   - going back to `โครงการ` still shows the segment it had;
   - with `-role external`, there is no `Monitor` button.

## 6. Check list

- [ ] iPhone dock unchanged.
- [ ] `โครงการ` tab: segment and `solarSurvey.homeTab` behave exactly as before.
- [ ] Contractors see 6 tabs + settings, as today.
- [ ] Colours from `Theme`; hit areas ≥ 44 pt; the glyph is a template asset, no hex in views.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath`; `swift test` still passes.
- [ ] Simulator dock screenshots like `states/01`–`03` are saved to `screenshots/`: `-homeTab survey`,
      `-homeTab monitor -growattDemo YES`, `-homeTab tools`, with `-homeBoard YES`.

## 7. Open questions (answer in your report; don't build these)

1. Badge: count `.alarm` and `.offline` both (the board's 3 = one fault, one lost logger, one weak string), or only
   faults? A weak string has no status yet.
2. Should contractors who maintain a station see `Monitor` for their own stations?
3. Once CHA-21's fleet page lands, does the `บำรุงรักษา` segment stay on the PWA home or move to `Monitor` only?
4. iPhone: should the `กปภ.` tab get a monitor entry too, or does the phone stay without one?
