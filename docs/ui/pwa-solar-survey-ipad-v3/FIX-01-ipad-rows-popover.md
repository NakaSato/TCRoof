# Fix 01: iPad PWA home v3: station rows, filter popover, survey badge (14 ต.ค. 2569)

**Done 14 ต.ค. 2569.** All four are built; `screenshots/01`–`04` are retaken. §4 is the same change as `docs/ui/pwa-solar-survey-iphone-v3/FIX-01-survey-badge.md`.

The build (commit `874963b`, `screenshots/`) differs from the board (`states/`) in four places. The rest matches: header, nav, dock, project grid, overview summary cards.

The reference crops from the board are in `fix/`:
- `fix-install-rows-crop.png`
- `fix-maintenance-rows-crop.png`
- `fix-popover-crop.png`

Paste into Claude Code in the TCRoof repo:

```
Fix the iPad PWA home to match its board. Read docs/ui/pwa-solar-survey-ipad-v3/FIX-01-ipad-rows-popover.md
and compare screenshots/ (built) with states/ and fix/ (board). The values are in iPadHome.dc.html
(iRows, mRows, iFlt, lType/rowSt). Change ONLY these four things, on iPad (regular width) only:

1. Install overview station rows (states/03, fix/fix-install-rows-crop.png).
   Today they are compact (name, bar, one line). The board's row is a full card:
   - Card: white, 1 pt #DDE4ED border, radius 16, padding 12/14/10, 8 pt between blocks.
   - Top:
     - "MP n" 12 pt bold #5B6B82, then the pace chip:
       - "ช้ากว่า n%" #FDECEA/#B42318
       - "เร็วกว่า n%" #E8F5EE/#1F6B43
       - otherwise "ตามแผน" #EEF4FB/#16325C
     - The name, 16 pt bold, one line.
     - "kWp · ผู้รับเหมา X · ทีม TCRnn", 12 pt muted.
     - A 44 pt ring on the right, in the pace colour, with a navy plan tick.
   - Bar: 8 pt, track #E3E9F1, actual in the pace colour (red when behind, else blue), and a 2×14 navy plan tick.
   - Line: "จริง a% / แผน p%" on the left; "ช้ากว่าแผน n%" / "เร็วกว่าแผน n%" / "ตามแผน" on the right, bold, in the pace colour.
   - Permit block "งานขออนุญาต x/4":
     - Fill #FAFBFD, 1 pt #E6ECF3 border, radius 10, padding 8/10.
     - Overdue: fill #FFF8F7, border #F3C4BF.
     - The note is on the right, one line, coloured by state.
     - Below it, 4 equal chips (26 pt, radius 8, 11.5 pt bold): อปท. · กกพ. · กฟภ. · กว.
       - ✓ done: #E8F5EE/#1F6B43
       - ⏳ submitted: #E3EEF8/#1F6FB5
       - ○ not submitted: #FFF3E6/#9A4A06
       - ! overdue: #FDECEA/#B42318
   - "ขั้นตอนตอนนี้ <task> ›" row: 34 pt, #EEF4FB, radius 9.
   - Footer, above a 1 pt divider:
     - On the left: calendar glyph + "ส่งมอบ dd/mm".
     - On the right: "รายงานวันนี้ ✓" (#E8F5EE/#1F6B43) or "ยังไม่ส่งรายงาน" (#FFF3E6/#9A4A06).
   - Row filters gain "ขออนุญาตค้าง n" between "ยังไม่ส่งรายงาน" and "ทั้งหมด". It means any permit not done.
   - Permit data: RoutineReport.permits(plan:actual:at:) already derives the permit part of the MP plan.
     - Add an optional permits field to InstallStationSummary and fill it in PWARoot from that function.
     - If a station's plan has no permit tasks, hide the block for that row. Do not invent states.
     - Report how the four columns map to the plan's permit tasks.

2. Maintenance overview station rows (states/04, fix/fix-maintenance-rows-crop.png): the same card shape.
   - Top: "MP n" + the status chip, then the name, then "kWp · PR n%", with a 44 pt ring (today ÷ expected) on the right.
   - An 8 pt bar in the status colour.
   - "วันนี้ <e> / คาด <x> kWh".
   - The note row, 34 pt, radius 9:
     - alarm: #FDECEA/#B42318
     - offline: #EEF1F5/#5B6B82
     - otherwise: #EEF4FB/#16325C
   - Footer: "PM ถัดไป dd/mm"; on the right, "แจ้งซ่อม n งาน" (#FFF3E6/#9A4A06) or "ไม่มีงานซ่อม" (#F1F4F8/#9FB3CC).
   - The tap target is unchanged.

3. Filter popover size (states/02, fix/fix-popover-crop.png).
   - Built: about 330 pt wide, with ~58 pt rows and ~18 pt text. Board: 248 pt wide.
   - Rows: 44 pt, text 14 pt (bold when selected), count 13 pt bold, tick 18 pt, row padding 14.
   - Section titles: 11 pt bold #5B6B82. "ล้าง": 13 pt bold.
   - Radius 16, 1 pt #C9D3E0 border, and an arrow under the filter button.
   - iPhone keeps its popover.

4. Survey card badge (states/01).
   - Survey cards show only the blue "สำรวจ" badge. Remove the "ยังขาด n ช่อง" / "ครบ" / "ร่าง" capsule from JobCard's survey branch.
   - JobCard has one layout now, so this also fixes the iPhone. It is the same change as
     docs/ui/pwa-solar-survey-iphone-v3/FIX-01-survey-badge.md: do it once, and mark both done.
   - The .locked branch keeps its badges.

Do not touch:
- the overview summary cards, the header, nav, dock, project grid
- the overview logic and filters (except adding "ขออนุญาตค้าง")
- iPhone rows and the iPhone popover

Before editing:
- Use code-review-graph (CLAUDE.md). Check whether installRow/maintenanceRow and the popover are shared with iPhone, and branch on size class where they are.

Check:
- Build with your own -derivedDataPath. Run swift build + swift test in TCRoofKit/.
- Run on the iPad Pro 13" simulator with -surveyHomeType install, then maintenance, then -surveyHomeFilter YES.
- Replace screenshots 01–04 and compare them with states/ and fix/.
- Run iPhone v3 states 01 and 02 again: they must be unchanged except the survey badge.
- PWAOverviewTests and PhoneSurveyUITests pass.
- Report:
  - the permit mapping
  - any station without permit data
  - what still differs
```

## Not counted as differences
- **Bell with no badge in the build:** there were no unread notifications in the simulator data.
- **`+ เพิ่มโครงการติดตั้ง` under the install rows:** this is in the build but not on the board. It is an existing feature, so keep it.
- **`บำรุงรักษา` selected in the nav on the maintenance view:** same as the iPhone build. The board links that segment to a separate iPad page that isn't built yet.
