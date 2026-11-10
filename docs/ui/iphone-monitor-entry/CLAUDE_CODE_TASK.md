# iPhone · `Monitor` entry (CHA-34)

> **Not ready to follow yet.** This change list assumes the recommendations in `SPEC.md` §9 (option A, the compact
> page). Once the user has answered §9, update this file to match, then type
> `Follow docs/ui/iphone-monitor-entry/CLAUDE_CODE_TASK.md` on a new branch `feat/iphone-monitor-entry`.

Board: `boards/PhoneMonitorEntry.html` (390 × 844 frames); `preview.png` is the whole board. Numbers are examples.

## Scope

iPhone (compact) only. Don't touch:
- the iPad (`PadTabs`, `MonitoringPage`, `StationMonitorPage`);
- `TCTabBar` / `TCTabItem` (they already take any number of items);
- `TCRoofCore/Monitoring` rules, `MonitoringStore`'s logic, Firestore, `firestore.rules`;
- the other iPhone tabs' roots and badges.

## Read first

`PhoneTabs.swift` (`PhoneTab`, `availableTabs`, `PhoneDockBarContent`, `initialTab`), `PadTabs.swift` (the iPad's
`.monitor`, `MonitoringPoller`, badge), `MonitoringPage.swift` + `+Loading` + `+Stations`, `MonitoringParts.swift`,
`MonitoringStore.swift`, `Monitoring+Fleet.swift`, `PWARoot.swift` (`PWAMaintenanceStationView`),
`TCRoofUI/Overview.swift` (`TCCountSegments`), `TCRoofUI/Skeleton.swift`, `HomeNavbarUITests`.

## Change list (in order)

1. **Tab.** `PhoneTab.monitor` (raw `monitor`), in `stacks` after `.docs`; `fade` `Theme.phonePage`, `module` nil.
   Filter it out for `permissions.role == .external` in `availableTabs` and `items`, as `.docs`.
2. **Dock item.** After `.docs`: `TCTabItem(.monitor, title: "Monitor", asset: "tab-monitor", badge: n,
   accessibilityLabel: n > 0 ? "Monitor | ต้องดูแล \(n)" : "Monitor")`, n = `MonitoringStore.shared.attentionCount`.
3. **Store start.** In `PhoneDockBarContent`, as `PadDockBarContent`: `MonitoringPoller()` in the background for
   non-contractors, and the demo refresh task. Pull the shared bit into one modifier both docks use.
4. **Page.** `TCRoof/Views/Monitoring/Phone/PhoneMonitoringPage.swift` (+ `+Cards`, `+Loading`): header, failure
   strip, summary card, `ต้องดำเนินการ` (5 lines + `ดูทั้งหมด`), stations card with filter segments and sort, as
   `SPEC.md` §5. Reuse `MonitoringParts` (status words, tones, `MonFormat`); add nothing to TCRoofCore unless a
   formatting rule is missing (then with a test).
5. **States.** Loading skeletons, all normal, no stations, none paired, failure (`SPEC.md` §7).
6. **Station.** A row or an action line pushes `PWAMaintenanceStationView` for that job.
7. **DEBUG + docs.** `-homeTab monitor` on iPhone; list it, and the item order, in `docs/debug-flags.md`.
8. **UI test.** `HomeNavbarUITests` (iPhone), as `SPEC.md` §8; list it in `docs/ui-tests.md`.

## Check list

- [ ] Dock fits at 375 pt (iPhone SE) and at the largest non-accessibility text size; tabs ≥ 44 pt.
- [ ] Contractors: dock unchanged (`หน้าหลัก | งานบ้าน | กปภ. ‖ ตั้งค่า`).
- [ ] iPad unchanged.
- [ ] Colours from `Theme`; skeleton, never a spinner, on the first read.
- [ ] xcodebuild app build (own `-derivedDataPath`) and `swift test` pass.
- [ ] Simulator screenshots of the board's states saved to `screenshots/`
      (`-homeTab monitor -monitoringDemo YES`, `-monitoringLoading YES`, `-role external`).
