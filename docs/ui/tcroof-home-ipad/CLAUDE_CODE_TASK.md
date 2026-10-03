# Claude Code task: TCRoof home on iPad (regular width), new design

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-home-ipad/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Names, numbers and times in the previews are **example data**.

## Goal

**Old iPad home** (in `TCRoof/Views/Home/HomeView.swift`):
- `HomeHeader` (user / date / time cells, status strip)
- a 2-column grid of big `ModuleCard`s
- a `งานวันนี้` grid

**New design:** `iPadMenu.dc.html` (1366 × 1024 landscape). It uses the same visual language as the new iPhone home (`docs/ui/tcroof-home-iphone/`), laid out for iPad, on **one screen with no scrolling**:
1. **Brand header**: app icon, on-device AI greeting + date, bell, account avatar
2. **Left column (520 pt)**:
   - `นัดวันนี้` hero card
   - `วันนี้` timeline card
   - `งานสำรวจค้างอยู่` card
3. **Right column**: six module rows filling the height
4. **Notifications**: popover under the bell
5. **Settings**: centred form sheet with logout confirmation
6. **Call**: centred action sheet

**If the iPhone task is already merged (branch `feat/iphone-home`)**, reuse its pieces and don't duplicate them:
- greeting generator
- hero card
- module row
- notification row / filter
- `AppModule.shortSubtitle`
- the `tools` module

Only the layout and sizes differ on iPad. **If it isn't merged**, build those pieces here as shared views, so the iPhone task can reuse them. Read `docs/ui/tcroof-home-iphone/CLAUDE_CODE_TASK.md` for the shared behaviour (greeting rules, data sources, notification rules). This file lists only what is different or new on iPad.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`):
- callers of `HomeView`, `HomeHeader`, `ModuleCard`, `NotificationPanel`, `NotificationsView`, `AppNotification.list`, `SettingsView`, `TodayRow`
- `tests_for` on anything you touch

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` = `states/01-home.png` | Home (@2x) |
| `states/02-timeline-install-open.png` | Timeline row 08:00 expanded |
| `states/03-appointment-2.png` | Appointment 2/2: the hero shows 14:00 with `เริ่มสำรวจ A1 ›`, and the timeline row 14:00 is expanded |
| `states/04-notifications.png` | Bell popover, 2 unread |
| `states/05-notifications-todo.png` | Filter `ต้องทำ` |
| `states/06-notifications-all-read.png` | After `อ่านทั้งหมด` and a sync |
| `states/07-settings.png` | Settings form sheet |
| `states/08-logout-confirm.png` | Logout confirmation |
| `states/09-call-sheet.png` | Call action sheet |
| `states/10-greeting-2.png` | Another AI greeting (tap to regenerate) |
| `states/*.pdf` | **Vector** 1366 × 1024 renders of home, notifications and settings. Measure here. |
| `preview.html` + `grf.css` | Static home render |
| `iPadMenu.dc.html` | Design source. `renderVals()` holds the state logic, sample data and every style value. |
| `icons/` + `icons/README.md` | SVG for every icon + SF Symbol mapping (same set as the iPhone home) |
| `assets/tc-renewable-icon-1024.png`, `.svg` | App icon / `AppLogo` (branch `feat/new-app-icon`) |

## Layout (regular width; board 1366 × 1024; page `#F5F8FB`)

Use the full layout when `horizontalSizeClass == .regular`. Keep the compact (iPhone) layout from the iPhone task.

### 1. Header
- White, bottom corners 22, hairline `#E6EBF2`, padding 18/32/16, gap 16.
- `AppLogo` 56 pt, radius 14.
- **Greeting**: 21 pt bold, 1 line, tail truncation. Tap regenerates it.
- **Date** under the greeting: 14 pt `#5B6B82`, e.g. `พุธ 30 กันยายน 2569`, using the Thai Buddhist calendar.
- **Bell**: 52 pt circle `#EEF2F7`, red count badge.
  - While the popover is open: fill `#E3EEF8` with a 2 pt `#1F6FB5` inner ring.
- **Avatar**: 52 pt `#1F6FB5` circle with the initials. Opens Settings.
- This header replaces `HomeHeader`'s stats cells and status strip on iPad:
  - `นัดสำรวจวันนี้` is now the module chip and the timeline.
  - `งานถัดไป` is now the hero.

### 2. Left column (width 520, gap 16)

**a. `นัดวันนี้` hero**
- Same structure as on iPhone, scaled up:
  - gradient 150° `#1F6FB5 → #16325C`, radius 22, padding 16/20/20, gap 16
  - ring 88 pt
  - time 38 pt bold + kind 14 pt
  - name 19 pt, 2 lines; place 14 pt
  - primary white button 56 high, radius 14, 17 pt
  - navigate / call 56 × 56, radius 14
- Pager `‹ ›` (44 pt) + dots + `พุธ 30 ก.ย. · 1/2`, with swipe as well.

**b. `วันนี้` timeline**
- Card: white, radius 18. Header `วันนี้` 16 bold + `3 รายการ`.
- Data: every item of today, in time order. Sample data:
  - install day (TC-0012 Day 2/5)
  - survey 10:30 (NO.224)
  - survey 14:00 (NO.231)
- **Each item**:
  - time 14 pt; the colour follows the kind
  - a vertical line + dot (13 pt):
    - live = green `#2E9E5B`
    - next = blue `#1F6FB5` with a 4 pt halo
    - later = white with a 2 pt `#AAB6C5` ring
  - card radius 14:
    - tag chip (live `#E2EFDA/#3B7420`, next `#E3EEF8/#1F6FB5`, later `#EEF2F7/#5B6B82`)
    - right text (`กำลังทำ` / `อีก 49 นาที`)
    - name 15 bold, 1 line; place 12.5
- **Expanding**:
  - Tapping a card expands it (one at a time; tap again to collapse). Default: the next survey.
  - The expanded card has a 1.5 pt blue border, a progress bar, and a row with:
    - gradient button (`ทำต่อ … ›` / `เริ่มสำรวจ A1 ›` / `เปิดบันทึกประจำวัน ›`)
    - navigate 46 pt
    - call 46 pt
- Tapping a **survey** item also moves the hero to that appointment, so the two stay in sync.
- The card fills the remaining height. When rows are expanded past the height, it scrolls inside.

**c. `งานสำรวจค้างอยู่`**
- Survey jobs that are open (not complete or not yet exported) and **not** on today's schedule.
- Order: most recently edited first. Show at most 2. The header link `ดูทั้งหมด ›` opens the survey list.
- **Row** (64 high):
  - ring 44 pt: steps done / 13; blue, or green at 13/13
  - name 15.5 bold, 1 line
  - sub line 13 pt: orange `#B45309` when something is missing (`ยังขาดภาพ C1 หลังคา 3 ภาพ · แก้ไขล่าสุด 28/9`), otherwise grey
  - a pill button:
    - `ทำต่อ <step> ›`: blue on `#E3EEF8`
    - `ส่งออก ›`: green on `#E2EFDA`, when all 13 steps are done but the report hasn't been sent
- Hide the card when the list is empty. The timeline then takes the space.

### 3. Right column: module rows
- Six rows, equal heights filling the column, gap 12.
- **Row**: white, radius 18, 1 pt `#DDE4ED`, padding 0/18.
  - icon tile 56, radius 15
  - title 19 bold, 1 line
  - subtitle 14 `#5B6B82`
  - chip 13 bold (`2 นัดวันนี้`, `Day 2/5`)
  - chevron 26 `#AAB6C5`
- **Content**: same titles, short subtitles and chips as on iPhone, including the sixth module `เครื่องมือและอุปกรณ์วัด`. Don't break titles onto two lines on iPad.
- Remove the old big `ModuleCard` and the `งานวันนี้` grid from the iPad layout. The grid's content now lives in the timeline.

### 4. Notifications popover
- Bell → popover anchored to the bell, arrow at the top.
- Use `.popover` with `presentationCompactAdaptation(.fullScreenCover)`, so iPhone keeps the full-screen version.
- Size and shape: width 440, max height 640, radius 18, shadow `0 16 40 rgba(22,50,92,0.28)`. Dim the page behind it only lightly (`rgba(22,50,92,0.12)`).
- **Content is the same as the iPhone full-screen version:**
  - header `การแจ้งเตือน` (21 pt here), pill `ใหม่ n` / `อ่านครบแล้ว`, `อ่านทั้งหมด`, ✕
  - filter chips `ทั้งหมด` / `ต้องทำ n`
  - groups วันนี้ / เมื่อวาน / ก่อนหน้า
  - 56 pt rows with no buttons: tapping a row does its action and marks it read
- Reuse `AppNotification.list`, `readRaw` and `markRead`. Replace the current `NotificationPanel` look; keep its logic.

### 5. Settings and call
- **Settings**: `.sheet` with `.presentationSizing(.form)` (about 560 × 820).
  - Same grouped content as on iPhone: profile card, ผู้ใช้งาน, GOOGLE DRIVE + `ออกจากระบบ`, ซิงค์ข้อมูลทีม, เกี่ยวกับ, and the `คำทักทาย AI` toggle.
  - `เสร็จ` closes it.
  - Logout asks for confirmation (`ต้องการออกจากระบบหรือไม่?`).
- **Call**: from the hero or a timeline row, a `confirmationDialog` / popover with:
  - `โทร <number>`
  - `ส่งข้อความ`
  - `ดูรายละเอียดผู้ประสานงานใน A1`
  - `ยกเลิก`

## Rules
- Thai UI text exactly as in the previews.
- Map colours to `Theme`, adding missing tokens there. No hex literals in views.
- Touch targets ≥ 44 pt. Dynamic Type: rows may grow; if the screen overflows, the left column scrolls, never the header.
- Portrait iPad / Split View: when the width is under about 1000 pt, stack the left column above the module rows inside one ScrollView, keeping the same components.
- Don't change the data layer or the survey/export logic.

## Done when
- `xcodebuild` builds the app and TCRoofKit, and tests pass.
- On an iPad Pro 13" simulator (landscape), the home matches `states/01`–`10`.
- The iPhone home is unchanged, or matches the iPhone board if that task is done.
- Summary of files changed, what was reused from the iPhone work, and the remaining differences from the board.
