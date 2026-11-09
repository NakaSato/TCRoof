# Design specs

How to follow the design boards and specs in `docs/ui/` and `docs/specs/`.

Each wide page has a `CLAUDE_CODE_TASK.md` (what to build, constraints, check list) and a `SPEC.md` (data, rules, UI, tests, open questions), plus `preview*.png` at 1366 × 1024 and an `icons/` folder.
- When asked to "follow" one, compare the result with the previews in the simulator.
- Report the spec's open questions at the end.
- Values in previews are examples; never hardcode them.

`docs/specs/` holds feature specs (auto drawing, roof PV layout, tank mounting, calendar and travel, hardware assist, standard designs, IEC 62446 Excel export and more), with images in `img/` and HTML prototypes in `prototype/`. Some are built by now (routine reports, the ERC exemption flow, the master schedule, hardware assist), so check the code before treating a spec as pending.

UI conventions from the specs:
- Content still being fetched (a list, a station's figures, a page's first data) shows a skeleton in its shape, not a spinner: `TCSkeletonBlock`, `TCSkeletonCard`, `TCSkeletonRow`, `TCSkeletonDiagram` (a single-line diagram while it is drawn) and `.tcShimmer()` (`TCRoofUI/Skeleton.swift`, still with Reduce Motion), or the app's `DataLoadingSkeleton`. Spinners stay for actions (a button working, locating, uploading, drawing).
- Hit areas are at least 44 pt.
- Text keeps WCAG AA contrast, 4.5:1, outdoors being where the app is used: a text colour against `surface` and `background`, and white (`onPrimary`) against a fill it sits on (`warning`, `success`, `danger`, `teal` were darkened for it). A light chip takes `navy` text.
- Text follows the text-size setting: the app's screens use `.sarabun(size, weight)` (capped at `accessibility2` on `RootView`), and rows that must line up take `frame(minHeight:)`, not a fixed height. `.sarabunFixed` is only for the survey's wide pages and paper or slide previews (`IECSheetPreview`, `WeeklySlideView`), and a view drawn into a PDF with `ImageRenderer` gets `.dynamicTypeSize(.large)` so the file is the same on every device.
- Plans and PDF drawings are vector (`Sketch`), never bitmaps of icons.
- Icon catalogs go in `TCRoofKit/Sources/TCRoofUI/Resources/<X>Icons.xcassets` and load through `A2Icon(name:fallback:)`. Asset names are global across catalogs, so avoid duplicates (B1's clashing `ui-*` icons are prefixed `b1-`).
- Very long SwiftUI expressions fail to type-check or crash at runtime in Debug (`View.modifier` SIGSEGV). Split cards into separate computed properties.

<!-- code-review-graph MCP tools -->
