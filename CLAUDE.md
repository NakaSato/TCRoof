# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. It holds what every change needs. Each area's details are in a `CLAUDE.md` in its folder, which Claude Code reads when it works there, and two catalogues are read on demand:

| File | What it has |
|---|---|
| `TCRoof/CLAUDE.md` | the app target (sign-in, sync, Drive, travel log) and roles in full |
| `TCRoofKit/CLAUDE.md` | the package's layers: TCRoofUI, TCRoofCore (DXF, drawings, IEC, MP plan, assistant…), PDFReport, ExcelExport, DriveSync, PVYield, ModuleRules |
| `GrowattAPI/CLAUDE.md` | the Growatt package: the OpenAPI and web portal clients, its rules and tests |
| `TCRoofUITests/CLAUDE.md` | how to run UI tests and their rules |
| `tools/master-plan-sheet/CLAUDE.md` | the Master Plan Google Sheet and its Apps Script |
| `docs/ui/CLAUDE.md` | how to follow the design boards and specs |
| `docs/debug-flags.md` | every DEBUG launch argument (open a screen in a state, for checks and screenshots) |
| `docs/ui-tests.md` | every UI test: what it taps and its launch arguments |

When a change adds a flag, a UI test or a behaviour, document it in the file of the area it belongs to, not here.

## Project

TCRoof is an iPad-first SwiftUI app (iOS 17, bundle `com.tcroof.internal`) for a solar installer: jobs, install plans, device scans, install logs, and the **solar site survey** module, which produces the company's PDF report and Excel workbook. UI text is Thai.

## Build and test

- **Package logic and tests (fast, macOS):** run from `TCRoofKit/`
  - `swift build`
  - `swift test` (or `swift test --parallel`: about half the time, one process per test, so a test can't lean on another's state)
  - `swift test --filter InverterStationTests` (one class) or `swift test --filter InverterStationTests/testOutdoorRoom` (one test)
- **`TCRoofUI` and the app:** these are wrapped in `#if canImport(UIKit)`, so `swift build` on macOS does **not** compile them. Verify UI changes with xcodebuild:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Always pass your own `-derivedDataPath`. The user keeps Xcode open, and a CLI build in the shared DerivedData locks Xcode's `build.db`. Reuse the same path between builds: a clean build takes over 10 minutes, so run it in the background.
- **Linux (cloud sessions):** `TCRoofCore`, `ExcelExport` (with `CZlib`), `PVYield` and `ModuleRules` build there (the rest needs Apple frameworks). `tools/linux-swift/test.sh` (takes `swift test`'s arguments: `--parallel` for everything, about 2 minutes, or `--filter HourlyYieldTests`) links them into a small package (every target line copied from `Package.swift`, with `tools` and `Project_Plan_TCRoof` links where the tests look) and runs their tests at Bangkok time (`TZ`, as the tests assume); the session hook (`.claude/hooks/session-start.sh`) installs Swift in `/opt`, puts it on `PATH` and builds the package once. Keep `TCRoofCore` building there: guard Apple-only imports with `#if canImport(…)` (`DevKey`'s PBKDF2 and `FormHash`'s SHA-256 have pure-Swift fallbacks), and give long numeric expressions explicit types, since Linux's type checker gives up sooner. In tests, don't create a test case to borrow its helpers (`XCTestCase()` doesn't exist there; DXF reading is `DXFRead`). Linux Foundation lists nothing in a folder reached through a symlink, so resolve one first (`MPTemplates.cases`). `FloodLookupStubTests`' cases where the lookup fails skip on Linux: `fetch` then cancels the other years' requests, and Linux Foundation's cancelled `URLSession.data(for:)` never returns.
- **Master Plan sheet script:** `node --test tools/master-plan-sheet/core.test.js` (the Google Sheet's Apps Script, below).
- **Test plans** (`TestPlans/`): the TCRoof scheme's test action runs `Unit` (the app's unit tests) by default; `Package` runs the package's tests and `UI` the UI tests (`xcodebuild test -scheme TCRoof -testPlan UI …`). The Crashlytics symbol upload is skipped for Debug builds.
- **Lint:** there is no SwiftLint or swift-format config; the checks are `swift test` and the xcodebuild build.
- **CI:** `.github/workflows/ci.yml` runs on pull requests and `main`: the Linux package tests (`tools/linux-swift/test.sh` in `swift:6.2-noble`), the Master Plan sheet script, the Cloud Functions and the Firestore rules tests (emulator, Java 21). Every TCRoofKit test on macOS runs on `main` and by hand only (macOS minutes cost more). Nothing in CI builds the app or runs `TCRoofTests` and the UI tests: they need xcodebuild with a simulator, so a decision worth testing goes in TCRoofCore (as `DriveDestination` does for `DriveRoute`).
- **Toolchain:** if `swift build` fails on `actool`, or `xcodebuild` says the active developer directory "is a command line tools instance", prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Secrets:** `Config.xcconfig` includes the git-ignored `Secrets.xcconfig` (copy `Secrets.example.xcconfig`) for `GISTDA_API_KEY`. The app builds without it. A key built in there ships readable in the app, so restrict it at its provider; keys typed in the survey settings (Mapbox, Google Maps, GISTDA) are kept in the device's Keychain (`SurveySettings.secretKeys`), not in the settings JSON.

To open a screen in a given state (screenshots, checks), read `docs/debug-flags.md`; to write or run UI tests, `TCRoofUITests/CLAUDE.md` and `docs/ui-tests.md`. Screenshot a simulator with `xcrun simctl io <udid> screenshot`, a paired device with `xcrun devicectl device capture screenshot`.

## Architecture

- **App target (`TCRoof/`):** Google sign-in, SwiftData models, Firestore sync (`Sync/CloudSync.swift`, limited by `firestore.rules`, project `tcroof-1564c`), Google Drive for photos and files, and the non-survey screens. Details: `TCRoof/CLAUDE.md`.
- **`TCRoofKit` package:** all survey work and shared logic: `TCRoofUI` (design system and the survey editor), `TCRoofCore` (pure values and rules), `PDFReport`, `ExcelExport`, `DriveSync`, `PVYield`, `ModuleRules`, `TCRoofMCP`. Details: `TCRoofKit/CLAUDE.md`.
- **`GrowattAPI` package** (`GrowattAPI/`, its own `Package.swift`): Growatt's server OpenAPI v1, read calls only, Foundation only; `TCRoofKit` depends on it by path and `TCRoofCore` re-exports it. `swift test` there. Endpoints, Growatt's web portal calls and what is unconfirmed: `docs/specs/growatt-api.md`.
- **Master Plan sheet** (`tools/master-plan-sheet`): a Google Sheet that reads Firestore; renaming or re-encoding the fields it reads breaks it. Details: its CLAUDE.md.
- **Roles:** `members/<email>.role` is `manager`, `internal` or `external` (`docs/reference/roles/user-roles.json`, `TCRoofCore/UserRoles.swift`, kept the same by `RoleTableTests`). Check `permissions.can(.capability, on: job.access)` before showing an action; `firestore.rules` enforces it (tests in `tools/firestore-rules-tests`), and a newly synced collection needs a rule. Raise `AppCompat.syncVersion` when a change needs every device on it before its rules go live. Details: `TCRoof/CLAUDE.md`.

**Data rules every change must keep:**
- Answers live in `Values` keyed by schema field id. Existing ids, labels and Excel cells must not change.
- New fields are optional and usually hidden from the form page (`when: { _ in false }`), so section completion counts as before.
- SwiftData models change only additively: a new property that is optional or has a default, which SwiftData migrates on its own. A rename, a type change or a relationship change needs a `VersionedSchema` and a `SchemaMigrationPlan` in `AppStore`, with frozen copies of the models in each version (and from then on every model change is a new version). A store that still won't open shows `StoreRecoveryView` instead of the app: try again, or set the store aside under `Application Support/StoreBackups` (`StoreBackup`) and start empty, with sync's `known` forgotten first so the empty store deletes nothing in Firestore.
- Old job JSON must still decode: hand-written `init(from:)` with `decodeIfPresent` defaults. Wide pages write legacy fields back so Excel, PDF and `Progress` keep working (B2 writes `sizeLWH` and `inverterCount`; B1 writes `breakerAT`).
- Pages share data across sections. For example, B1's `a3Breaker` link writes A3 `Breaker.target`, the SLD reads B1 loads and B2 sizes, and B2 writes B4 `level`. Before editing, find every reader of a field: the SLD, `Progress`, the PDF, Excel and `Flood` often read the same field.

UI conventions (all screens): colours from `Theme`, never hex or `Color.white`; buttons with `TCButtonStyle`; hit areas at least 44 pt; content being fetched shows a skeleton in its shape, spinners only for actions; plans and PDF drawings are vector (`Sketch`); split long SwiftUI expressions into computed properties. Details: `TCRoofKit/CLAUDE.md` (design system) and `docs/ui/CLAUDE.md` (boards).

## Code search

If the `code-review-graph` MCP server from `.mcp.json` is connected (`uv tool install code-review-graph`), narrow scope with it (`semantic_search_nodes_tool`, `query_graph_tool`, `get_impact_radius_tool`, `detect_changes_tool`), then read the source; the source wins when they disagree. If it isn't connected, use grep and Read.
