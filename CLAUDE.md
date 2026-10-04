# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

TCRoof is an iPad-first SwiftUI app (iOS 17, bundle `com.tcroof.internal`) for a solar installer: jobs, install plans, device scans, install logs, and the **solar site survey** module, which produces the company's PDF report and Excel workbook. UI text is Thai. `SolarSurveyWeb/` is an old web version that is no longer used; do not port changes to it.

## Build and test

- **Package logic and tests (fast, macOS):** run from `TCRoofKit/`
  - `swift build`
  - `swift test`
  - `swift test --filter InverterStationTests` (one class) or `swift test --filter InverterStationTests/testOutdoorRoom` (one test)
- **SurveyUI and the app:** these are wrapped in `#if canImport(UIKit)`, so `swift build` on macOS does **not** compile them. Verify UI changes with xcodebuild:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Always pass your own `-derivedDataPath`. The user keeps Xcode open, and a CLI build in the shared DerivedData locks Xcode's `build.db`. Reuse the same path between builds: a clean build takes over 10 minutes, so run it in the background.
- **Toolchain:** if `swift build` fails on `actool`, or `xcodebuild` says the active developer directory "is a command line tools instance", prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Secrets:** `Config.xcconfig` includes the git-ignored `Secrets.xcconfig` (copy `Secrets.example.xcconfig`) for `GISTDA_API_KEY`. The app builds without it.

### Simulator checks (DEBUG launch arguments)

There is no Simulator.app here, so the simulator can't be rotated; landscape checks rely on these flags. Screenshot with `xcrun simctl io <udid> screenshot`.

```
xcrun simctl launch <udid> com.tcroof.internal -screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage <page>
```

- `-screen <name>` skips sign-in and opens one app screen (`TCRoofApp.swift` `DebugScreen`; `pwa` is the survey module).
- `-surveyDemo YES` opens a demo job; add `-surveyDemoSection YES` to open its first section.
- `-surveyWideA1 YES` forces the two-column (landscape) wide pages and hides the sidebar.
- `-surveyStacked YES` forces the one-column (portrait) layout of the wide pages in a landscape simulator.
- `-surveyPage site|electrical|sld|inverter|panels|flood|water|backfeed|fts|roof|tank|final` opens that page (`JobEditor.openDebugPage`).
- `-surveyB4 lv|lvdone|hv|hvdone` (with `-surveyPage backfeed`) writes that state of `docs/ui/survey-b4/states` into the opened B4, with generated placeholder photos.
- `-surveyB4Render YES` (with `-surveyPage backfeed`) writes B4 offscreen at free widths 1366 / 1180 to `Documents/backfeed-<w>x<h>.png`, and its one-column iPhone layout to `Documents/backfeed-phone.png`.
- `-surveyC1 span|spany|posts|pv|keepout|landscape|ridgev|frame-n|frame-w|frame-c|frame-r|bays12|picker|shape|material|wood` (with `-surveyPage roof`) writes the design's example roof into the opened job and opens that state of `docs/ui/survey-c1/states`.
- `-surveyRoofRender YES` (with `-surveyPage roof`) writes C1 offscreen at several free widths and heights to `Documents/roof-<w>x<h>.png`, for layout checks without rotating. ImageRenderer can't draw menus, text fields or scroll views; they show as placeholders or blank.
- `-surveyD1 default|size|t64|t30|t20|above|buried|custom|compass|span|empty|tab2|obst|obstbottom|obstshade|obstrow|obstfull|obstadded|obstdelete|layout|layoutbottom|layoutedit|layoutask|layoutfull|layoutmax|layoutdrawing` (with `-surveyPage tank`) writes the design's example tank into the opened job and opens that state of `docs/ui/survey-d1-size/states` (`tab2` opens sub-step 2). The `obst…` states seed the standard points as `docs/ui/survey-d1-obstacles-iphone` (8 of 15 checked, V9 moved and selected) and open sub-step 2: scrolled to its end, its shading view, the row question, the plan full screen, a hatch added on site, or the delete question. The `layout…` states check every point and open sub-step 3 (`docs/ui/survey-d1-layout-iphone`) with the automatic layout: scrolled to its end, แก้แผง with a panel off and a table removed, the question before จัดแผงใหม่, the plan full screen, หาผังแผงมากสุด, or the B1-C3 sheet.
- `-surveyTankRender YES` (with `-surveyPage tank`) writes D1 offscreen at free widths 1366 / 1180 / 1100 to `Documents/tank-<w>x<h>.png`, and its iPhone sub-step 1 (step line and cards, no scroll view) to `Documents/tank-phone.png`.
- `-surveyFinalRender YES` (with `-surveyPage final`) writes E1 offscreen at free widths 1366 / 1180 to `Documents/final-<w>x<h>.png`.
- `-surveyE1 two|installable|notrec|alladded|empty|pad|pad2|cleared|complete` (with `-surveyPage final`) writes that state of `docs/ui/survey-e1/states` into the opened job, or opens a signature pad.
- `-surveyExport YES` opens the export sheet.
- `-surveyA2 layers|fullscreen` opens A2's layers menu, or full screen with the first placed building model selected.
- Survey job data is stored at `<app data container>/Documents/SolarSurvey/Jobs/<id>/job.json`, with photos in `photos/`. It can be edited while the app is stopped to seed test data; back it up first.

## Architecture

**App target (`TCRoof/`)** handles Google sign-in (`Auth/`), SwiftData models, Firestore sync (`Sync/CloudSync.swift`) and the non-survey screens. Firestore access is limited by `firestore.rules` (Firebase project `tcroof-1564c`): only accounts with a `members/<email>` document, and only the collections the app syncs, so a newly synced collection needs a rule. It hosts the survey module via `Views/Survey/` (`SolarSurveyEntry`, `PWASurveyLink`).

**`TCRoofKit` Swift package** holds all survey work, layered as follows:
- `TCRoofCore`: pure values and rules, no UI.
  - `Models.swift`: `Job`, `SurveyModule`, `Values` / `FieldValue`, `Transformer` / `Board` / `Breaker`.
  - `Schema.swift`: every page and section as `ModuleSpec` / `GroupSpec` / `FieldSpec` with field ids.
  - `Progress.swift`: completion, section numbering (`sectionsByCategory`: B1, B1.2 …), `steps`.
  - Feature calculators: `SingleLine` (SLD), `InverterStation` (B2), `BuildingPanels` (B1), `Flood`, `SiteShapes`, `EquipmentCatalog` (bundled JSON).
  - `Sketch` / `DrawOp` vector drawing, shared by the screen and the PDF.
- `PDFReport`: `ReportLayout` turns a `Job` into pages of `DrawOp`s (`ReportLayout+*.swift` per area); `PDFRenderer` draws them. The SLD page is A3.
- `ExcelExport`: fills `Resources/template.xlsx` by cell address (`ExcelExporter`, `template_meta.json`). Section slots are fixed (`ExcelExporter.slots`); extra sections get a copied sheet.
- `DriveSync`: Google Drive upload of report files and photos.
- `SurveyUI`: the editor.
  - `SurveyModel` (job storage, photos) and `JobEditorView` (sidebar, page routing, `cardBar` bottom bar).
  - The generic schema form `groupPage` is used on iPhone and wherever a wide page doesn't apply.
  - Designed "wide" pages: `InfoPageWide` (A1), `SitePageWide` (A2), `ElectricalPageWide` (A3), `FloodPageWide` (A4), `PanelsPageWide` (B1), `InverterPageWide` (B2), `WaterPageWide` (B3), `FtsPageWide` (B5), `RoofPageWide` (C1), `TankPageWide` (D1), `FinalPageWide` (E1), `SingleLinePage`.

**Data rules every change must keep:**
- Answers live in `Values` keyed by schema field id. Existing ids, labels and Excel cells must not change.
- New fields are optional and usually hidden from the form page (`when: { _ in false }`), so section completion counts as before.
- Old job JSON must still decode: hand-written `init(from:)` with `decodeIfPresent` defaults. Wide pages write legacy fields back so Excel, PDF and `Progress` keep working (B2 writes `sizeLWH` and `inverterCount`; B1 writes `breakerAT`).
- Pages share data across sections. For example, B1's `a3Breaker` link writes A3 `Breaker.target`, the SLD reads B1 loads and B2 sizes, and B2 writes B4 `level`. Before editing, find every reader of a field: the SLD, `Progress`, the PDF, Excel and `Flood` often read the same field.

## Design specs (`docs/ui/survey-*`)

Each wide page has a `CLAUDE_CODE_TASK.md` (what to build, constraints, check list) and a `SPEC.md` (data, rules, UI, tests, open questions), plus `preview*.png` at 1366 × 1024 and an `icons/` folder.
- When asked to "follow" one, compare the result with the previews in the simulator.
- Report the spec's open questions at the end.
- Values in previews are examples; never hardcode them.

`docs/specs/` holds feature specs that are not built yet (auto drawing, cable route, roof PV layout, tank mounting, site logistics, calendar and travel, hardware assist, presentation mode, review lock, standard designs), with images in `img/` and HTML prototypes in `prototype/`.

UI conventions from the specs:
- Hit areas are at least 44 pt.
- Plans and PDF drawings are vector (`Sketch`), never bitmaps of icons.
- Icon catalogs go in `TCRoofKit/Sources/SurveyUI/Resources/<X>Icons.xcassets` and load through `A2Icon(name:fallback:)`. Asset names are global across catalogs, so avoid duplicates (B1's clashing `ui-*` icons are prefixed `b1-`).
- Very long SwiftUI expressions fail to type-check or crash at runtime in Debug (`View.modifier` SIGSEGV). Split cards into separate computed properties.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

The server runs the `code-review-graph` binary from `.mcp.json`; install it with `uv tool install code-review-graph`. If it fails to connect, use grep and Read instead.

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".
  Uncommitted new files are often missing; fall back to grep.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->
