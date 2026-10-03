Follow docs/ui/pwa-solar-survey-iphone/CLAUDE_CODE_TASK.md

Make SurveyHomeView on iPhone (horizontalSizeClass == .compact) match docs/ui/pwa-solar-survey-iphone/preview.png and states/*.png at 390 × 844:
1. Header: title 22 pt, subtitle 13 pt on one line (subtitle only), search 44 high with the placeholder `ค้นหาเลขที่ ชื่อโครงการ…`, keep the ••• menu at 44 × 44.
2. Replace the 2 × 2 filter boxes with three 44 pt pills, `ทั้งหมด` / `กำลังทำ` / `ร่าง`, each with a count chip (add Filter.shortTitle). No `รอซิงก์` pill on compact.
3. List heading on one row: heading + `n งาน` + a `แก้ไขล่าสุด ▾` sort Menu (44 pt). Remove the segmented picker on compact.
4. Tighter cards: padding 12/14/10, spacing 8, 16 pt name, 44 pt ring (new PercentRing style), 34 pt continue strip on Home.primarySoft. Card gap 10, FAB 60 pt.
5. On all widths (the iPad board uses the same values):
   - step bar 6 pt: #70AD47 / #B45309 / #1F6FB5 / #DDE4ED
   - badges `ยังขาด n ช่อง` / `ครบ` / `ร่าง` in the board colours
   - section chips on Home.primarySoft
   - sync status as an icon only: icloud.and.arrow.up #B45309 (waiting) / checkmark.icloud #3B7420 (synced), with the Thai text kept as the accessibility label

Keep the stage tabs on compact and the iPad layout unchanged. This is a visual pass only: no model, sync or flow changes. Thai UI text exactly as in the previews. Use code-review-graph first, then read the source. Finish with a summary of the files changed, what changed on the iPad, and the remaining differences from the board.
