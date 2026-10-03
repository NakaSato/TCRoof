Follow docs/ui/tcroof-home-iphone/CLAUDE_CODE_TASK.md

Make HomeView on iPhone (horizontalSizeClass == .compact) match docs/ui/tcroof-home-iphone/preview.png and states/*.png at 390 × 844, on one screen with no scrolling:
1. Brand header (white, bottom radius 18):
   - AppLogo 40 pt
   - On-device AI greeting, 14 pt bold, 2 lines. Foundation Models on iOS 26 when available, Thai templates otherwise. Tap regenerates. No user name.
   - Bell 44 pt circle with an unread badge
   - Initials avatar 44 pt that opens SettingsView (replaces the gear)
2. `นัดวันนี้` hero card:
   - gradient #1F6FB5→#16325C, radius 20
   - pager over today's survey appointments (‹ › 44 pt + swipe, dots)
   - 56 pt progress ring, time 24 pt, job name 2 lines, place line
   - white primary button `ทำต่อ <step> ›` / `เริ่มสำรวจ A1 ›`
   - Navigate (Apple Maps to A1 GPS) and Call (action sheet) as 44 pt icon buttons, hidden without data
   - Empty state `ไม่มีนัดวันนี้` + `งานสำรวจใหม่ ›`
3. Replace the big ModuleCards with six horizontal rows filling the remaining height:
   - each row: 42 pt icon tile, 15 pt title, 12 pt one-line subtitle (add AppModule.shortSubtitle), status chip, chevron
   - chips `n นัดวันนี้` and `Day d/n`
   - add the sixth module `เครื่องมือและอุปกรณ์วัด` (placeholder destination if no tools view exists; say so)
   - hide the `งานวันนี้` grid on compact
4. Bell → .fullScreenCover notifications:
   - header: title 24 pt, `ใหม่ n` / `อ่านครบแล้ว`, `อ่านทั้งหมด`, ✕
   - filter chips `ทั้งหมด` / `ต้องทำ n`
   - groups วันนี้ / เมื่อวาน / ก่อนหน้า
   - compact 56 pt rows with 32 pt type tiles and unread dot + tint
   - **no buttons in rows**: tapping a row does its action (open survey step / sync() / open tools) and marks it read, with a coloured hint line + chevron
   - reuse AppNotification.list, readRaw and markRead
5. SettingsView as a grouped large sheet matching states/06; add the `คำทักทาย AI` toggle. Keep the logout confirmation.

Keep the iPad layout unchanged. Map colours to Theme (add missing tokens there). Thai UI text exactly as in the previews; touch targets ≥ 44 pt. Use code-review-graph first, then read the source. Work on a new branch feat/iphone-home. Build, run on an iPhone simulator and compare with the states. Finish with a summary of files changed and the remaining differences from the board.
