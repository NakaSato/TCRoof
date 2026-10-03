# Task: iPhone bottom bar for survey steps

**Source:** the bottom bar of `iPhone · ขั้น 1/13 A1 ข้อมูลโครงการ` on the TCRoof Design canvas. The same bar appears on every iPhone survey step (A1–E1).

**Goal:** make `InfoPageBar` on iPhone (`horizontalSizeClass == .compact`) match this design. iPad stays as it is.

Text in the images is example data.

## Files

| Path | What |
|---|---|
| `states.png` / `states.pdf` | All 8 states on one sheet (PNG @3x, PDF vector) |
| `states/01…08-*.png` | One bar per state, @3x, 390 pt wide |
| `states.html` + `grf.css` | Static source of the sheet. Open it to inspect sizes; classes `g-bar`, `g-save`, `g-nav`, `g-go` are in `grf.css`. |
| `in-context-A1.png` | Full A1 screen at 390 × 844 @2x, showing the bar in place |
| `PhoneA1.dc.html` | Board source (read as text) |
| `icons/chevron-left.svg`, `chevron-right.svg`, `spinner.svg` | Glyphs. Use SF Symbols `chevron.left` / `chevron.right` and `ProgressView`. |

## What the code does today (read first)

`TCRoofKit/Sources/SurveyUI/InfoPageWide+Sections.swift` → `struct InfoPageBar`.

On iPhone it currently shows:
- the status badge + `บันทึกอัตโนมัติ hh:mm` + status line
- a 48 × 50 save **icon** button
- a 48 × 50 `‹`
- a 108 × 50 `ถัดไป n/13 + code ›`

It is used by every `*PageWide` page through `PageStepBar` / `InfoPageBar`. Use code-review-graph (`code-review-graph build` if empty) to list the call sites before changing anything.

## Design (iPhone)

**Bar**
- White, top shadow `0 -2 8 rgba(0,0,0,.08)`.
- Padding 8 top, 24 sides, 12 bottom, plus the safe area.
- Gap 12. Total height 73 + safe area.

**Order:** `บันทึก` · `‹` · `›`. The extra 12 pt after `บันทึก` groups `‹` and `›` together.

**`บันทึก` button**
- Fills the remaining width, height 53, radius 10.
- White background, 1 pt border navy 60%.
- Text 17 semibold navy.

**`‹` / `›` buttons**
- 72 × 53, radius 10.
- Gradient `#1F6FB5 → #2E8FDB`.
- White chevron 18 pt, stroke 2.75.
- Icon only.
- VoiceOver label: `ก่อนหน้า A1 ข้อมูลโครงการ` / `ถัดไป A3 หม้อแปลง` (code + `barTitle`).

**Removed on iPhone:**
- the status badge and status line (the step line at the top already shows the `ครบ n/n ช่อง` / `ขาด n` chip)
- `บันทึกอัตโนมัติ hh:mm`
- the text inside next/previous

## States

| # | State | Look |
|---|---|---|
| 01 | Default (steps A2–D1) | As above |
| 02 | First step A1 | `‹` disabled: background `rgba(142,142,147,0.4)`, label `ก่อนหน้า (ขั้นแรก)`, hint `ไม่มีหัวข้อก่อนหน้า` |
| 03 | Saving | Spinner + `กำลังบันทึก…` in ink-muted on `#F3F6FA`. Can't be tapped again until done. |
| 04 | Saved | `✓ บันทึกแล้ว hh:mm`: text `#3B7420`, background `#F1F8EC`, border `rgba(59,116,32,.5)`. Returns to default after 1.5 s. Post a VoiceOver announcement. |
| 05 | Pressed | Darker and `scaleEffect(0.98)` (button style) |
| 06 | Last step E1 | `›` goes to `สรุปผล · ส่งออก` (the current `finish` action). Still icon only, with label `ถัดไป สรุปผล · ส่งออก`. |
| 07 | Detail page (e.g. A3 transformer / MDB) | Two buttons replace the bar contents (see below) |
| 08 | Two equal actions (e.g. SLD) | Two buttons replace the bar contents (see below) |

**State 07 buttons**
- Destructive outline `ลบหม้อแปลง`: flex 1, border danger 50%, text `#C0392B` 15 bold.
- Primary gradient `เสร็จ`: flex 1.4.
- The delete button keeps its confirmation dialog.

**State 08 buttons**
- `แก้ข้อมูลใน A3`: secondary outline.
- `ส่งออก PDF (A3)`: teal gradient `#27A99A → #4DB6E0`.
- Both flex 1, 16 pt, height 53.

## Behaviour

- `บันทึก` calls `model.flush(job.id)` and shows states 03 then 04.
  - If the flush finishes in under 300 ms, skip state 03.
  - Keep `savedNow` so the iPad still shows the time.
- `‹` / `›` keep the existing `previous` / `next` / `finish` actions and the `previousIndex` / `nextIndex` overrides.
- `gaps` and `statusAction` (missing-item shortcuts) are not shown in the iPhone bar. The page's step-line chip already shows the gap.
  - If the step line in a page doesn't yet open the first gap on tap, add that there.
- Make a reusable `BottomBar` (or a `variant` on `InfoPageBar`): `.steps(save:previous:next:)`, `.detail(destructive:primary:)`, `.pair(secondary:primary:)`. Pages that hand-build a bar for detail or SLD then use it.
- Colours from `Theme` (add `okTick #3B7420`, `okSoftBG #F1F8EC` if missing). No hex literals in views.
- Touch targets ≥ 44 pt. Dynamic Type: `บันทึก` may scale down to 0.8; chevrons stay fixed.

## Done when

- `xcodebuild` builds the app and TCRoofKit, and tests pass.
- On an iPhone 16 simulator, every survey step A1–E1 shows the bar as in `states/01` (A1 = `02`, E1 = `06`).
- The A3 detail page matches `07`, and SLD matches `08` (if present).
- Screenshots compared with `states/*.png`; differences listed.
- iPad bar unchanged (check an iPad Pro 13" screenshot).
- Summary of files changed.
