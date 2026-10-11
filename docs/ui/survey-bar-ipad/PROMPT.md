Follow docs/ui/survey-bar-ipad/CLAUDE_CODE_TASK.md

Build one shared iPad bottom bar for every survey step page (A1 … E1). It should match the boards in docs/ui/survey-bar-ipad (`preview.png`, `states/`, `boards/*.dc.html`). Then replace each page's own iPad bar with it (`InfoPageBar.padBar` and the rest). Do not change the iPhone `BottomBar`.

1. **Bar.**
   - White, top shadow, padding 8 / 24 / 12 plus the safe area.
   - A centred 1240-wide row, gap 12: status slot (flexible, truncates) · save · ‹ previous · next ›.
   - An extra 12 pt after save.
   - All buttons 53 high, radius 10.
2. **Status slot** is an enum. Each page supplies its own text, and completion counts stay as they are.
   - `complete`: green ✓ + muted text, e.g. `ครบ 11/11 ช่องในหน้านี้`
   - `missing`: orange ! + red one-line text
   - `gapChip`: tappable orange chip with title, sub and ›, which jumps to the first gap (B1)
   - `okChip`: the same chip in green (A2)
   - `allDone`: green ✓ + bold green text
3. **Save** `บันทึกร่างตอนนี้`, 170 × 53.
   - Use the generalised `SaveButton`: idle → spinner `กำลังบันทึก` → green `บันทึกแล้ว` with a pop-in check (about 1.35 s) → 2 pt green outline.
   - Any edit resets it.
   - Taps are ignored while saving.
   - Remove the `บันทึกอัตโนมัติ HH:mm` line.
   - Add `-surveySave saving|saved|clean` on iPad.
4. **Previous**, 230 × 53, outlined: ‹, then `ก่อนหน้า n/13` over the page name. On A1 it is disabled and reads `หัวข้อแรก`.
5. **Next**, 230 × 53, gradient: `ถัดไป n/13` over the page name, then ›. On E1 it reads `ขั้นสุดท้าย` / `สรุปผล · ส่งออก`. Numbers come from the live step list, and long names truncate.

**Open questions (use the defaults):**
- Board widths differ: use save 170, nav 230 / 230 and content 1240 everywhere.
- Pages without a board variant: use `complete` or `missing`, and a chip only where jump-to-gap already exists.

**Rules.**
- Thai text exactly as shown; all values are example data (`assets/sample-data.json`).
- No hex in views.
- Targets ≥ 44 pt.
- Layout only.
- Use code-review-graph first, then read the source.
- Branch `feat/ipad-step-bar`.

**Verify.**
- Build and run `swift test`.
- Compare an iPad Pro 13" simulator in landscape with `states/01`–`08` (measure in `states/00-a1-full-page.pdf`).
- Check that the iPhone bar is unchanged.
- Finish with a summary of the files changed, your open-question choices and any remaining differences.
