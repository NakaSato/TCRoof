Follow docs/ui/tcroof-home-ipad/CLAUDE_CODE_TASK.md

Make HomeView on iPad (horizontalSizeClass == .regular) match docs/ui/tcroof-home-ipad/preview.png and states/*.png at 1366 × 1024 landscape, on one screen with no scrolling. It uses the same design language as the new iPhone home (docs/ui/tcroof-home-iphone). Reuse its shared views if feat/iphone-home is merged; otherwise build them as shared views now.

1. Header (white, bottom radius 22):
   - AppLogo 56
   - On-device AI greeting, 21 pt bold, 1 line, tap regenerates. Thai date under it.
   - Bell 52 pt with unread badge
   - Initials avatar 52 pt that opens Settings
   - This replaces HomeHeader's stats cells and status strip.
2. Left column, 520 pt:
   - a. `นัดวันนี้` hero card: gradient #1F6FB5→#16325C, ring 88, time 38 pt, pager ‹ › + swipe, white primary 56 pt `ทำต่อ <step> ›` / `เริ่มสำรวจ A1 ›`, navigate + call 56 pt.
   - b. `วันนี้` timeline:
     - time + line/dot (live green / next blue / later grey), card with tag chip, name and place
     - tap to expand one card at a time: progress bar + gradient action + navigate + call
     - tapping a survey item moves the hero to it
     - fills the remaining height and scrolls inside
   - c. `งานสำรวจค้างอยู่`:
     - up to 2 open surveys not scheduled today
     - each row: ring of steps/13 + name + status line (orange when something is missing) + pill `ทำต่อ <step> ›` or green `ส่งออก ›`
     - header link `ดูทั้งหมด ›`
     - hidden when empty
3. Right column: six module rows with equal heights:
   - icon tile 56, title 19, subtitle 14, chip (`2 นัดวันนี้`, `Day 2/5`), chevron
   - include the sixth module `เครื่องมือและอุปกรณ์วัด`
   - remove the big ModuleCards and the `งานวันนี้` grid on iPad
4. Bell → popover (440 wide, radius 18) with the same content as the iPhone full-screen notifications:
   - `ใหม่ n` / `อ่านครบแล้ว`, `อ่านทั้งหมด`, filter `ทั้งหมด` / `ต้องทำ n`, groups
   - 56 pt rows with no buttons: tapping a row acts and marks it read
   - use `presentationCompactAdaptation(.fullScreenCover)` so iPhone keeps full screen
   - reuse AppNotification.list, readRaw and markRead
5. Settings as a form-size sheet matching states/07, with the `คำทักทาย AI` toggle and the logout confirmation. Call as a confirmation dialog.

Thai UI text exactly as in the previews. Colours from Theme (add missing tokens). Touch targets ≥ 44 pt. In portrait or Split View under ~1000 pt, stack the left column above the module rows in one ScrollView.

Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/ipad-home. Build, run on an iPad Pro 13" simulator in landscape and compare with states/01–10. Check that the iPhone home is unchanged. Finish with a summary of files changed, what was shared with the iPhone home, and the remaining differences from the board.
