# Claude Code task (v2): PWA Solar Survey home — align with the latest board

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/pwa-solar-survey/CLAUDE_CODE_TASK_v2.md`

This document is in English. Thai strings in `backticks` are literal UI labels.

## Context
The 3-tab home from `CLAUDE_CODE_TASK.md` (v1, 30 ก.ย.) is already in the code:
- `SurveyHome.swift`, `SurveyHome+Header.swift`, `SurveyHome+Sync.swift`
- `JobCard.swift`: modes `survey` / `locked` / `install`
- `JobStage`
- the install picker

Since v1, the owner has edited the board. This task brings `SurveyHomeView` in line with the **current** board (`iPadHome.dc.html` in this folder, refreshed) and these new screenshots. It is a visual pass only: no model, sync or flow changes beyond what is listed.

Use code-review-graph first (callers of `SurveyHomeView`, `JobCard`, `syncButton`, `moreMenu`), then read the source.

## Files added or refreshed in this folder
| File | Shows |
|---|---|
| `preview.png` | survey tab, all jobs (refreshed) |
| `states/01-survey-all.png` … `04-survey-unsynced.png` | the four filter boxes: `ทั้งหมด` / `กำลังสำรวจ` / `ร่าง` / `รอซิงก์` |
| `states/05-install-empty.png` | install tab, empty |
| `states/06-install-picker.png` | `เพิ่มโครงการติดตั้ง` sheet |
| `states/07-maintenance-empty.png` | maintenance tab, empty |
| `iPadHome.dc.html` | current design source (replaces the v1 copy) |
| `icons/` | every vector on the page as SVG, with matching SF Symbols (`icons/README.md`) |

`README.md`, `sample-jobs.json`, `preview-install*.png` and the v1 `CLAUDE_CODE_TASK.md` stay as they were.

## Changes (board vs code today)
1. **Header: no sync button.** The board's blue header has only the title, subtitle and search field.
   - Remove `syncButton` from the header row (both the wide and compact layouts).
   - Sync stays available:
     - Add `ซิงก์ทั้งหมด (n)` as the first item in `moreMenu`, disabled when n = 0. Use the `syncAll()` logic as today.
     - When the `รอซิงก์` filter box is selected, show a small secondary button `ซิงก์ n งาน` at the right of the list heading, before `เรียงตาม`.
   - Keep `moreMenu` (`ellipsis` in a white 18 % circle). The board omits it, but settings and export live there. Owner to confirm if it should move.
2. **Header search.**
   - Placeholder: `ค้นหาเลขที่ ชื่อโครงการ สถานที่…`. The code has `ค้นหาเลขที่ ชื่อโครงการ ที่อยู่`.
   - Width 330 (code: 300), height 46, radius 12, background white at 95 %.
3. **Header spacing:** title 30 pt bold, subtitle 15 pt at 92 % opacity. Padding 22 top, 26 bottom, horizontal inset to match the 1240 content width. The bottom corners keep radius 16.
4. **Card corner radius:** 16 (code: 14). Same for the filter boxes (code: 14) and the stage tab bar container (14, unchanged).
5. **Progress ring:** 58 pt, track `#E6ECF3` 4 pt, arc 4 pt with round caps. Centre text is `72` at 16 pt bold plus `%` at 10 pt regular muted (code: 13 pt for both). See `icons/progress-ring-*.svg`.
6. **Sync status in the card footer:**
   - Pending: an 8 pt orange dot (`#F08C00`) + bold orange `รอซิงก์`. This replaces the `arrow.triangle.2.circlepath` icon.
   - Done: a green `✓` + bold green `ซิงก์แล้ว` (`#2E7D32`). The code uses `icloud.fill` in primary blue.
   - Footer left stays `calendar` + `date · time`. The photo count stays `photo` + n.

Everything else on the board already matches v1. If you find another visible difference, list it in the summary rather than changing it.

## Rules
- Touch targets ≥ 44 pt. Thai text exactly as in the previews.
- Don't change `JobStage`, the install flow, sync logic, export or other pages.
- Never put the GISTDA key or any secret into code, fixtures or docs.

## Checks
- `swift build`, `swift test`, and the `CLAUDE.md` `xcodebuild` with your own `-derivedDataPath`.
- On the iPad simulator at 1366 × 1024, compare with `preview.png` and `states/04-survey-unsynced.png`. Use the existing launch flags (e.g. `-surveyInstallPicker YES`) for `states/06`.

## Finish with
A summary listing the files changed, where sync moved to, and any remaining differences from the board.
