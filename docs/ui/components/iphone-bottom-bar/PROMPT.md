Follow docs/ui/components/iphone-bottom-bar/CLAUDE_CODE_TASK.md

Make the survey bottom bar on iPhone (horizontalSizeClass == .compact) match docs/ui/components/iphone-bottom-bar/states/*.png. Keep the iPad bar unchanged.

1. InfoPageBar (TCRoofKit/Sources/SurveyUI/InfoPageWide+Sections.swift) on iPhone:
   - Layout: `บันทึก` fills the width (53 pt, r10, white, navy 60% border, 17 semibold), then `‹` and `›` at 72 × 53 (r10, #1F6FB5→#2E8FDB gradient, white chevron, icon only, VoiceOver label = code + step name).
   - Bar: white, padding 8/24/12 + safe area, gap 12, with 12 pt extra after `บันทึก`.
   - Remove the badge, the "บันทึกอัตโนมัติ" line, the status line and the text on next.
2. States:
   - first step: `‹` disabled, grey
   - saving: spinner + `กำลังบันทึก…`, no double tap
   - saved: `✓ บันทึกแล้ว hh:mm` in green for 1.5 s
   - pressed: scale 0.98
   - last step: `›` runs `finish`
3. Variants for the same bar: `.detail` (`ลบ…` outline + `เสร็จ` gradient, 1 : 1.4) and `.pair` (secondary + teal gradient, 1 : 1). Use them on the pages that hand-build those bars.
4. Keep the existing previous / next / finish / index logic and model.flush. Colours from Theme (add okTick #3B7420 and the saved background if missing). No hex literals in views. Touch targets ≥ 44 pt.

Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/iphone-bottom-bar. Build, run every step A1–E1 on an iPhone 16 simulator and compare with states/*.png; check that the iPad is unchanged. Finish with a summary of files changed and any remaining differences.
