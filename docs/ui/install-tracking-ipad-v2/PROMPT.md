# Prompt for Claude Code

```
git fetch origin && git switch -c feat/install-tracking-ipad-v2 origin/design/install-tracking-ipad-v2
```

```
Follow docs/ui/install-tracking-ipad-v2/CLAUDE_CODE_TASK.md.

FIRST check that TCRoof/Views/Install/Tracking/InstallTrackingPage.swift (+Progress, +Daily, +Site) exists, with
Tab { overview, daily } and the "แผนก่อสร้าง" item routed to MPScheduleScreen. If not, STOP and report.

Change ONLY what the board changed since v1 (the task's change list):
1. Header subtitle: kWp · team · start · handover (the station name is already the title).
2. Overview Gantt:
   - The card height ends above the dock; rows scroll inside, the header and milestone/payment rows are pinned.
   - Forecast pill in the header.
   - Capsule bars, % pills.
   - Today as a tinted column + solid red line; Sunday tint; current row tint.
3. Overview S-curve v2:
   - Full width, no summary panel.
   - Daily plan/actual bars, area fills.
   - Today band + pill, gap segment, end dot "คาดเสร็จ".
   - Hatched wait band, legend line.
4. Overview and daily tab end above the dock (96 pt bottom padding; cards scroll inside).
5. Daily tab:
   - Fixed-height report table.
   - Bottom row = กำลังคนรายวัน · รูปตามงาน MP · พรุ่งนี้. Remove ความก้าวหน้าสะสม.
6. New in-page tab แผนก่อสร้าง (Tab.plan):
   - Header with Baseline pill and chips, Gantt | ตาราง, แก้ไขแผน → MPScheduleScreen, ส่งออก PDF.
   - WBS Gantt: stages expand; critical outline; float tails; today/Sunday/wait columns; milestone row; legend.
   - Table view.
   - Right column: planned crew per day vs team, milestones, make-ready of the next stage.
   - Critical path in TCRoofCore with a test.
   - DEBUG -installTab plan, -installPlanView gantt|table, -installPlanCollapsed YES (one line in CLAUDE.md).

Rules:
- Only data with a source: hide crew / predecessors / Baseline REV when there's no model, and report it.
- Theme tokens (add installCritical / installFloat / installWait if missing), TCButtonStyle, 44 pt.
- Don't touch the iPhone, MPScheduleScreen, or the routine report / IEC / station docs screens.
- No stored fields change.

Steps:
1. Read the task, then iPadInstall.dc.html as text. Measure on states/*.png and compare with
   docs/ui/install-tracking-ipad/states (v1).
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test and InstallTrackingUITests (with the new plan-tab test).
4. iPad Pro 13" simulator, run with -screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES.
   Save screenshots 01–07 in docs/ui/install-tracking-ipad-v2/screenshots/ and compare them with states/.
5. Commit on feat/install-tracking-ipad-v2 and push it (no merge).
6. Report:
   - the differences
   - what had no data source and was hidden
   - the open questions
```
