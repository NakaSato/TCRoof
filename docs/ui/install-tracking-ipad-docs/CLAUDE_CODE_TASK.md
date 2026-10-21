# Claude Code task: iPad install tracking, `เอกสาร` tab in the page

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-docs` and type
> `Follow docs/ui/install-tracking-ipad-docs/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** Do not refactor, rename or restyle anything outside the change list in §5. Do not
touch the iPhone, the other tabs of the page, `StationDocsScreen`'s own layout, the PWA `เอกสาร` dock tab
(`PWADocsPadView` / `PWADocsHomeView`), or any stored model.

**Example data.** The board's station, papers, counts and statuses are examples (`assets/sample-data.json`). The app
reads `Job.stationDocs` (`TCRoofCore/StationDocs.swift`), the shared library and the ERC flow. Never hard-code a board value.

## 1. Context

- `InstallTrackingPage` (`TCRoof/Views/Install/Tracking/`) is the iPad page of a PWA station being installed
  (`docs/ui/install-tracking-ipad`, `-v2`). It has these tabs:
  - in the page: `ภาพรวม` · `รายงานประจำวัน` · `แผนก่อสร้าง`
  - pushed screens: `คำขอรายสัปดาห์` · `Weekly Report` · `ทดสอบ IEC 62446` · `เอกสาร`
- Today `เอกสาร` is `Item(id: "docs", … route: .docs)` and pushes `StationDocsScreen(job:)`.
- The board **`iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)`** (`iPadInstall.dc.html`, 1366 × 1024, menu `dc`)
  now draws `เอกสาร` **in the page**: the station's permit papers as a three-step path, the selected package's
  papers, and a detail panel. This task builds that tab.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `InstallTrackingPage` (`items`, `Route`, `Tab`, `go(_:)`), `InstallPageData` (`docs`, `DocTile`, `Target.docs`)
- `StationDocs`:
  - `Package`, `Kind`, `Status`, `DocState`, `Station`, `Library`, `Context`
  - `packages(_:)`, `papers(in:_:)`, `progress(_:station:library:_:)`, `state(_:station:library:)`, `applies`
- `StationDocsScreen` (its sheets for a paper, upload, draft letters) and `ERCFlow` (`Variant.under200`)
- `tests_for` on anything you touch, and `InstallTrackingUITests`

Then read the source and open `iPadInstall.dc.html` as text. The tab's logic is the `isDc` block of `renderVals()`
(search for `menu === 'dc'`), and its markup is the `{{isDc}}` section.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadInstall.dc.html`, `grf.css` | The board (the whole install page; this task is its `เอกสาร` tab) |
| `preview.png` = `states/01-docs-building.png` | Default: step 1 `อ.1 / แจ้งเทศบาล` selected, its first paper open. @2x (2732 × 2048) |
| `states/02-docs-grid.png` | Step 2 `ขนานไฟ (กฟภ.)` selected: 11 papers |
| `states/03-docs-grid-item.png` | The same, with paper `4.2-07` selected in the detail panel |
| `states/04-docs-pk2-not-needed.png` | Step 3 `พค.2 (กกพ.)` on a station under 200 kVA: `ไม่ต้องยื่น`, empty list `ชุดนี้ไม่ต้องยื่น` |
| `assets/sample-data.json` | The board's example: the three packages, their papers and statuses |
| `screenshots/` | Put your simulator screenshots here |

## 4. The tab

The page header, tab bar and dock are unchanged. Under the tab bar, top to bottom:

### 4.1 Summary card (full width, one row)

- **Left:** `เอกสารโครงการ` with a link `ทุกสถานี ›`, and the sub-line `เอกสารขออนุญาตของสถานีนี้ · n หมวด · n ฉบับ`. `ทุกสถานี ›` opens the PWA documents for all stations, the same destination as the dock's `เอกสาร`.
- **Middle:** `n / N ฉบับเรียบร้อย`, a full-width stacked bar, and a legend with counts:
  - `ต้องทำ` (orange)
  - `รอผู้อื่น` (purple)
  - `ครบ / อนุมัติ` (green)
  - `ยังไม่ถึง` (grey)
- **Right:** `อัปโหลด` (outline) and `ส่งออกชุดเอกสาร` (primary).
  - Upload goes to the selected package.
  - Export is the station's package export, a ZIP with one folder per package. Use what `StationDocsScreen` / `HandoverFolders` already offer; if no export exists, keep the button and list it in §7.

Map each paper's `StationDocs.Status` to the four legend states:

| Legend | Statuses |
|---|---|
| `ครบ / อนุมัติ` | `approved` |
| `รอผู้อื่น` | `requested`, `submitted` |
| `ต้องทำ` | `missing` and `draft` while it applies, `signed` |
| `ยังไม่ถึง` | not applicable yet (`notNeeded` / not in `papers(in:)`) |

Write the mapping once as a pure function in `TCRoofCore` and test it.

### 4.2 `เส้นทางขออนุญาต` (full width)

- **Title:** `เส้นทางขออนุญาต`, with the hint `ยื่นตามลำดับ · แตะเพื่อดูเอกสารในชุด`.
- **Three cards**, joined by arrows, in filing order:

  | Card | Package | Agency |
  |---|---|---|
  | `ขั้น 1` | `building` | `เทศบาล` |
  | `ขั้น 2` | `gridConnection` | `กฟภ.` |
  | `ขั้น 3` | `pk2` | `กกพ.` |

  Each card shows:
  - a progress ring with `done/total` (green when complete, blue otherwise)
  - the step and agency line
  - the title: `อ.1 / แจ้งเทศบาล`, `ขนานไฟ (กฟภ.)`, `พค.2 (กกพ.)`. Take the building title from `Package.title` and `BuildingRoute`.
  - a status chip (`ครบ n/n`, `กำลังยื่น`, or `ไม่ต้องยื่น`)
  - a note: `ยื่นครบแล้ว`, `n ฉบับยังไม่เสร็จ`, or `ต่ำกว่า 200 kVA` when `!ctx.over200kVA`
- An arrow turns green once the step before it is complete or not needed.
- **Selection:** the selected card has a 2 pt primary border, and tapping a card selects its package. The default is the first package with work to do, else step 1.
- The packages and counts come from `StationDocs.packages(ctx)` and `progress(_:…)`. `commissioning` and `handover` are **not** on this path: they stay on `ภาพรวม`'s document tiles.

### 4.3 Package papers (left, about 2/3 width)

- **Header:** the package title (for example `4.1 อ.1 / แจ้งเทศบาล`), its description line, a small legend `ร่าง → ยื่น → อนุมัติ`, and `+ อัปโหลด`.
- **One row per paper** (`papers(in:)`):
  - A PDF file badge coloured by the legend state.
  - The code (`4.1-01`), the title, and the source line (`ทีมเราทำ`, `ดึงจากคลังกลาง`, `ขอจาก กปภ.สาขา`, `เราร่าง → ผจก.สาขาลงนาม`), which is `Origin.title` plus the kind's note.
  - Three step dots `ร่าง → ยื่น → อนุมัติ`, filled green up to the paper's level (draft / signed = 1, submitted / requested = 2, approved = 3).
  - A status chip (`Status.title`).
- The selected row has a primary inset outline. A tap selects the row.
- **Empty package** (`pk2` under 200 kVA): centred `ชุดนี้ไม่ต้องยื่น` and the reason line.

### 4.4 Detail panel (right, about 1/3 width)

- A page preview: the file's first page when there is a file, else the generic placeholder drawn on the board.
- The code and status line, the title, and the source.
- A vertical three-step flow with names and states:
  - `ร่าง / แนบไฟล์` · `ทีมเรา`
  - `ยื่น กปภ.` · `ผู้ควบคุมงาน กปภ.`
  - `อนุมัติ` · `กปภ.`
- At the bottom:
  - `เปิดเอกสาร` (primary): opens the paper's existing sheet in `StationDocsScreen` (the same sheet `-pwaDocsPaper` opens).
  - A square share / upload button.

Permissions follow `StationDocsScreen` exactly. A contractor sees what `stationdocs.drafts` allows (view only for ภายนอก), with no upload or export when it is not allowed.

## 5. Change list

Work in this order and tick each item in your report.

1. [ ] **Route → tab:** in `InstallTrackingPage`:
   - add `case docs` to `Tab`, and change the `docs` item to `tab: .docs` (in place)
   - keep `Route.docs`, used by `ทุกสถานี ›` and by anything else that pushes `StationDocsScreen`
   - check `InstallPageData.Target.docs` / `go(_:)` still land on the new tab
2. [ ] **Core mapping:** add the status → legend-state function (§4.1) and the path model (packages in order with progress and selection default) to `TCRoofCore` as pure values. Add unit tests.
3. [ ] **View:** add `InstallTrackingPage+Docs.swift` with the summary card, `เส้นทางขออนุญาต`, the papers list and the detail panel (§4.1–§4.4). Fit the page above the dock, as the other tabs do (`dockClearance`). Split cards into computed properties.
4. [ ] **Actions:** wire them to the existing `StationDocsScreen` sheets and flows. Do not build new editors.
   - `อัปโหลด` / `+ อัปโหลด`: the upload sheet
   - `เปิดเอกสาร`: the paper sheet
   - `ส่งออกชุดเอกสาร`: the export
   - `ทุกสถานี ›`: the PWA documents
5. [ ] **DEBUG flags:**
   - `-installTab docs` opens the tab.
   - `-installDocsPackage building|grid_connection|pk2` selects a step, and `-installDocsPaper <kind id>` selects a paper.
   - With `-installDemo YES`, show the board's example (nothing saved).

   Add one line to `CLAUDE.md`'s `-installOpen` item.
6. [ ] **UI test:** extend `InstallTrackingUITests`:
   - `เอกสาร` opens in the page (no push)
   - tapping step 2 lists its papers
   - a row selects and the panel's title follows
   - `เปิดเอกสาร` opens the paper's sheet
   - on a station under 200 kVA, step 3 reads `ไม่ต้องยื่น`
7. [ ] **Build and screenshots:** follow §6.

Out of scope: the iPhone, other tabs, `StationDocsScreen` layout, the PWA docs pages, new stored fields or Firestore rules.

## 6. Check

- `cd TCRoofKit && swift build && swift test`, and an app build:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Use your own `-derivedDataPath`, and run it in the background.
- On an iPad simulator, run:
  ```
  xcrun simctl launch <udid> com.tcroof.internal -screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES -installTab docs [-installDocsPackage grid_connection]
  ```
  Save the screenshots to `screenshots/` with the names of `states/`, and compare them.
- Colours come from `Theme` (no hex, no `Color.white`). Hit areas are ≥ 44 pt. VoiceOver reads each step card as
  `ขั้น n · <title> · done จาก total` and each row as `<code> <title> · <status>`.

## 7. Open questions (report your answers; do not block on them)

1. Is there a station package export (ZIP by package) already, or only per-paper sharing? If none, which should `ส่งออกชุดเอกสาร` do for now?
2. `ทุกสถานี ›`: should it push the PWA documents page inside the install page's stack, or switch the dock to `เอกสาร`?
3. The building step's title depends on `BuildingRoute` (`อ.1` permit vs `แจ้งเทศบาล`). While it is `unknown`, show both (as the board does) or ask?
4. Should `commissioning` and `handover` also join the path later, or stay only as tiles on `ภาพรวม`?
