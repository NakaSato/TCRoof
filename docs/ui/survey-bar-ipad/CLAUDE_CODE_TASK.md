# Claude Code task: iPad survey step bottom bar (board update 10 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-bar-ipad/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly. Every value shown (counts, step numbers, page names, missing items) is **example data** (`assets/sample-data.json`). Bind each one to the real job, schema and step list.

## Goal

Every iPad survey step page (A1 … E1, 13 steps) ends with the same bottom bar. Today each page builds its own bar (`InfoPageBar.padBar` on A1, and similar code on the other pages). The goal is **one shared iPad bar component** that matches the boards and is used by every step page. The iPhone bar (`BottomBar`, 104 pt `SaveButton`, `docs/ui/survey-a1-iphone`) is done. **Do not change the iPhone layout.**

**Before reading the source**, use code-review-graph (per `CLAUDE.md`). Look up these symbols:
- `InfoPageBar`, `padBar`, `BottomBar`, `SaveButton`, `TCStepBar`, `PageStepBar`
- every `*PageWide` / `*Page` view that draws its own iPad bottom bar
- `tests_for` on anything you touch

Then read the source.

If `docs/ui/survey-a1-ipad` has already been done (generalised `SaveButton`, `-surveySave` on iPad), build on that work and don't redo it.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | All bar variants stacked, @2x, labelled |
| `states/00-a1-full-page.png` / `.pdf` | Whole A1 page, landscape 1366 × 1024; the PDF is **vector**, so measure there |
| `states/01`–`04-a1-…` | Save button: idle → saving → just saved → saved idle |
| `states/05-a2-…` | Status slot: green chip (required done, optional missing) |
| `states/06-a3-…` | Status slot: orange `!` + red text line |
| `states/07-b1-…` | Status slot: tappable orange gap chip |
| `states/08-e1-…` | Last step: next button reads `ขั้นสุดท้าย` / `สรุปผล · ส่งออก` |
| `boards/*.dc.html` | Board sources. Search for `class="g-bar"`; the inline CSS gives exact values, and the script holds the save states (`save`, `ph`) and B1's gap logic (`gapAny`, `gapT`, `gapS`, `gapGo`). |
| `grf.css` | Shared classes; see `.g-bar`, `.g-save`, `.g-nav` and the "compact bottom bar" overrides at the end |
| `assets/sample-data.json` | Labels and example values |

## Layout (landscape, 1366 wide)

- White bar, top shadow `0 -2 8 rgba(0,0,0,0.08)`, padding **8 top / 24 sides / 12 bottom** plus the bottom safe area. The bar is 73 pt high on the board.
- The content row is centred, **1240 wide** (the same width as the page content), with gap 12. A2's board uses 1318; treat that as a board inconsistency and use 1240.
- Order, left to right: **status slot** (flexible, truncates) · **save** · **‹ previous** · **next ›**.
- An extra **12 pt** after the save button groups the two nav buttons (`margin-right: 12`).
- **All buttons are 53 high, radius 10.**
- Portrait / narrow iPad: keep the order. Let the status slot shrink first (truncate with an ellipsis), then use the narrow widths from the existing code. No new breakpoints are needed.

## 1. Status slot (left)

A small enum drives the slot, and each page supplies its own text:

| Variant | Look | Used on (board) |
|---|---|---|
| `complete(text)` | 24 pt green circle `✓` + 13 pt muted text, e.g. `ครบ 11/11 ช่องในหน้านี้` | A1 |
| `missing(text)` | 24 pt orange circle `!` + 13 pt **red** text, one line, ellipsis, e.g. `ยังขาดภาพ: TX 1 (1) · MDP-1 (1) · TX 5 (4) · ไปต่อได้ แล้วค่อยกลับมาเติม` | A3, E1 |
| `gapChip(title, sub, action)` | Tappable chip, min 53 high, radius 10, orange 45% border, cream fill; `!` circle, bold 14 title (`ยังขาด 7 รายการ ใน 2 อาคาร`), 12.5 muted sub (`อาคารนี้: ภาพเบรกเกอร์`), trailing `›`. Tap = jump to the first missing item. | B1 |
| `okChip(title, sub, action)` | Same chip in green (green 40% border, light green fill): `ครบช่องบังคับแล้ว` / `ยังไม่มี (ไม่บังคับ): รูปป้ายโครงการ`. Tap = jump to that item. | A2 |
| `allDone(text)` | Green `✓` + bold 14 green text, e.g. `ครบทุกอาคารแล้ว` | B1 when nothing is missing |

- Chips need VoiceOver labels like the boards (`ไปยังรายการที่ขาด …`).
- The texts come from each page's existing completion logic. **Don't change any completion counts.**

## 2. Save button (`บันทึกร่างตอนนี้`)

- **170 × 53**, outlined, 16 pt semibold. A3's board shows 190; use 170 everywhere.
- Use the generalised **`SaveButton`** from `BottomBar.swift`, with the same states as on iPhone (see `states/01`–`04`):
  1. **idle:** `บันทึกร่างตอนนี้`
  2. **tap:** an 18 pt spinner plus `กำลังบันทึก` (muted). Taps are ignored while saving.
  3. **after the save returns (about 0.65 s on the board):** light green fill, green border, and a 22 pt green circle with a white check. The circle pops in (scale 0.6 → 1.15 → 1, 0.35 s), the tick draws in (0.35 s), and a soft pulse ring follows. The label reads `บันทึกแล้ว` in dark green. This state lasts about 1.35 s.
  4. **then:** a white button with a **2 pt** green border, a plain green check and `บันทึกแล้ว`.
  5. Any edit (`job.editVersion` changes) returns it to idle.
- Use the `Home` / `Theme` greens (`okSoftBG`, `okTick`, `stepDone`). Don't add hex literals.
- The save itself stays `model.flush(job.id)` with `savedNow = Date()`.
- **VoiceOver:**
  - idle: `บันทึกแบบร่าง · มีการแก้ไขที่ยังไม่ได้บันทึก`
  - saving: `กำลังบันทึก`
  - saved: `บันทึกล่าสุดแล้ว · ยังไม่มีการแก้ไขใหม่`
- The board keeps `บันทึกอัตโนมัติ HH:mm` off the bar. Remove that line from the iPad bar on every page.

## 3. Previous button (`‹`)

- **230 × 53**, white, 1 pt navy 60% border, navy text.
- Contents: chevron `‹` (20 pt), then two lines aligned left: 12 pt muted `ก่อนหน้า 4/13` and 16 pt semibold page name `A4 น้ำท่วม`.
- **First step (A1):** disabled. Grey outline, grey text, a single line `หัวข้อแรก`.

## 4. Next button (`›`)

- **230 × 53**, blue gradient (`Theme` header gradient), white text.
- Contents: two lines aligned right, 12 pt (90% opacity) `ถัดไป 6/13` and 16 pt semibold page name `B2 พื้นที่อินเวอร์เตอร์`, then chevron `›`.
- **Last step (E1):** `ขั้นสุดท้าย` / `สรุปผล · ส่งออก`, which goes to the summary / export screen it opens today.
- Step numbers and names come from the live step list, so pages C / D that the job adds or removes change the `n/13` total.
- A1 / A2 boards use 210 / 250 for prev / next. Use **230 / 230** everywhere, and make sure long names truncate with an ellipsis instead of wrapping.

## Rules

- Thai text exactly as in the previews; all values are example data.
- Colours come from `Theme` / `Home`; no new hex literals in views.
- Touch targets ≥ 44 pt (the bar's buttons are 53).
- **Layout only:** keep navigation behaviour, completion counts, the save and autosave logic, and Excel / PDF output.
- **iPhone must not change.** Check the iPhone `BottomBar` after any `SaveButton` change.
- Replace each page's own iPad bar with the shared component. Don't copy the bar into each page.
- Work on a new branch `feat/ipad-step-bar`.

## Open questions

Choose the default unless it breaks something, and list your choice in the summary:

1. **Widths differ on the boards** (save 170 / 190, nav 210 / 250 / 230, content 1240 / 1318). The default is save 170, nav 230 / 230 and content 1240 everywhere.
2. **Status slot per page.** Only A1, A2, A3, B1 and E1 boards show their variant. For the other pages, the default is `complete` when nothing is missing and `missing` with the page's existing gap text otherwise. Use a chip only where the page already has jump-to-gap behaviour.

## Done when

- `xcodebuild` builds the app and TCRoofKit, and `swift test` passes.
- On an iPad Pro 13" simulator in landscape, each page's bar matches its crop in `states/` (measure in `00-a1-full-page.pdf`).
- The save button runs through `01`–`04` and resets on edit. Add `-surveySave saving|saved|clean` on iPad so the states can be screenshotted.
- A1's previous button is disabled, and E1's next button reads `ขั้นสุดท้าย`.
- The iPhone bar is unchanged.
- Write a summary of the files changed, the open-question choices and any remaining differences from the boards.
