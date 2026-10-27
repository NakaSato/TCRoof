# Claude Code task: iPad install tracking overview, compact documents and site row

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-overview-v3` and
> type `Follow docs/ui/install-tracking-ipad-overview-v3/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

> On the board the plan card runs down to 8 pt above the dock, as the app's card already does (`fittedHeight`, which
> ends `dockClearance` above it); keep the app's value. Only the row under the card changes. This task is that row.

**Do only what this task lists.** It is a layout change of the iPad `ภาพรวม` tab's bottom row (`siteRow`) only. Do not
refactor, rename or restyle anything outside the change list in §5. Do not touch:

- the KPI strip and the plan card (`kpiStrip`, `progressCard`, `fittedHeight`, the Gantt and S-curve drawing)
- the other tabs, the iPhone page (`InstallTrackingPage+Phone*.swift`)
- the sheets the tiles open, `InstallPageData`, any model, sync or rule

**Example data.** The values in the states are the board's examples (`assets/sample-data.json`, the same file as
`docs/ui/install-tracking-ipad-overview`). Never hard-code them.

## 1. Context

- `InstallTrackingPage` (`TCRoof/Views/Install/Tracking/`) shows the overview as `kpiStrip`, `progressCard` (as tall as
  what is left above the dock) and `siteRow` (`เอกสารโครงการ` and the site panel), in the page's `ScrollView`. The person
  scrolls down to reach `siteRow`. That stays.
- The board **`iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)`** (`iPadInstall.dc.html`, 1366 × 1024, menu
  `ov`) makes `siteRow` one compact band of fixed height (258 pt on the board), so that one short scroll shows all of
  it, under the plan card's last row.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `InstallTrackingPage+Site` (`siteRow`, `card`, `docsCard`, `docTile`, `chip`, `sitePanel`, `siteInfo`,
  `siteInfoBody`, `kpiTile`, `siteRisks`, `siteLabour`)
- `tests_for` on them, plus `InstallTrackingUITests`

Then read the source and open `iPadInstall.dc.html` as text: the row is the `<div style="flex:none;height:258px…">`
inside the `{{isOv}}` section.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadInstall.dc.html`, `grf.css` | The board (the whole install page; this task is the overview's bottom row) |
| `preview.png` = `states/01-overview-gantt.png` | The overview as it opens: strip, plan card to the dock (unchanged). @2x (2732 × 2048) |
| `states/02-overview-scrolled-end.png` | Scrolled to the end: the new row with documents in 3 columns and the site panel |
| `states/03-site-risk-end.png` | The same, site panel on `ความเสี่ยง` |
| `states/04-site-labour-end.png` | The same, site panel on `แรงงาน` |
| `states/05-overview-scurve.png` | `S-Curve` (unchanged, for reference) |
| `states/06-actions-sheet.png` | `ต้องดำเนินการ` sheet (unchanged, for reference) |
| `states/07-doc-devices.png` | `อุปกรณ์ที่ติดตั้ง`'s sheet (unchanged, for reference) |
| `assets/sample-data.json` | The board's example values |
| `screenshots/` | Put your simulator screenshots here, named like `states/` |

## 4. The row

- Fixed height **258 pt**, two cards side by side at **1.45 : 1** (documents wider), 14 pt apart.
- **`เอกสารโครงการ`:** header line as today, then the tiles in **3 columns** (today 2), 6 pt gaps; all 13 tiles fit
  without scrolling inside the card. Tile title 13.5–14 pt bold, the chip keeps its priority so the title truncates
  first. The board draws 34 pt tiles; keep a 44 pt hit area (§7 Q1).
- **Site panel:** the tab segment and the date on one line, then the tab's content filling the rest:
  - `ข้อมูลหน้างาน`: two equal columns. Left: `ความคืบหน้าตามงาน MP` bars as today, spaced to fill the height. Right:
    the four tiles become **four rows** (label and note on the left, the value large on the right, its tone kept), each
    a quarter of the column, in place of the 2 × 2 grid of 104 pt tiles. Move `รายละเอียดงาน` into the panel's header
    line (a 44 pt secondary button before the date) so it doesn't take a row.
  - `ความเสี่ยง` and `แรงงาน`: unchanged content, fitted to the height (the risk rows share it; the labour chart's height
    comes from it).

## 5. Change list

Do these in order, and nothing else.

1. **Row height and split.** In `InstallTrackingPage+Site`, add `static let siteRowHeight: CGFloat = 258` and give
   `siteRow` that height and the 1.45 : 1 split (no `fixedSize(vertical:)`). When only one of the two cards exists it
   takes the full width, as today.
2. **Documents card:** 3 columns, the tile of §4, hit area kept.
3. **Site panel `ข้อมูลหน้างาน`:** the two-column body of §4, `kpiTile` as a row variant (`kpiRow`), and
   `รายละเอียดงาน` in the header line. `ความเสี่ยง` / `แรงงาน` fitted to the height.
4. **Tests.** Keep every assertion of `InstallTrackingUITests` (it already scrolls to the end with
   `-installScrollEnd YES`); fix only what the new layout moves (the `รายละเอียดงาน` button is now in the header line).

## 6. Rules and check list

- Colours from `Theme`, buttons `TCButtonStyle`, hit areas ≥ 44 pt, accessibility labels unchanged.
- Split new views into computed properties / functions as the file already does.
- [ ] `swift test` in `TCRoofKit` passes (nothing there should change).
- [ ] The xcodebuild app build passes with your own `-derivedDataPath` (in the background).
- [ ] Simulator screenshots at 1366 × 1024 (`-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES`,
      with `-installScrollEnd YES` and `-installSite risk|labour`) saved to `screenshots/` named like `states/`, compared
      side by side.
- [ ] `InstallTrackingUITests` passes.
- [ ] Every item of §5 ticked in your report.

## 7. Open questions (answer in your report; do not block on them)

1. **Tile height.** The board's tiles are 34 pt; the app's rule is 44 pt hit areas. Did an invisible inset keep both?
   If not, what height did you use and do 13 tiles still fit in 258 pt?
2. **More tiles.** If a station shows more than 15 document tiles, the card scrolls inside. Should tiles beyond the
   first 15 move to a `ดูทั้งหมด` sheet instead?
