# Claude Code task: TCRoof home on iPhone (compact width), new design

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-home-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Names, numbers, times and weather in the previews are **example data**.

## Goal
`HomeView` (`TCRoof/Views/Home/HomeView.swift`) has an `isPhone` branch that is still the iPad layout in one column:
- `HomeHeader` with stats cells
- a big `ModuleCard` per module
- a `งานวันนี้` grid at the bottom

Build the iPhone board `PhoneMenu.dc.html` (390 × 844) for compact width. It fits on **one screen with no scrolling**. From top to bottom:
1. **Brand header**: app icon, an on-device AI greeting, bell, account avatar
2. **`นัดวันนี้` card**: today's appointments as a pager, with progress ring, primary action, navigate and call
3. **Six module rows**: horizontal rows, one per module
4. **Full-screen notifications**: compact rows, tap a row to act, no buttons inside rows

Plus the settings sheet, the logout confirmation and the call action sheet.

Keep the iPad layout unchanged. Use code-review-graph first (per `CLAUDE.md`):
- callers of `HomeView`, `HomeHeader`, `AppModule`, `NotificationPanel`, `NotificationsView`, `AppNotification.list`, `SettingsView`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-home.png` | Home, appointment 1/2 (@2x) |
| `states/02-next-appointment.png` | Pager on appointment 2/2 (not started → `เริ่มสำรวจ A1 ›`) |
| `states/03-notifications.png` | Full-screen notifications, 2 unread |
| `states/04-notifications-todo.png` | Filter `ต้องทำ` |
| `states/05-notifications-all-read.png` | After `อ่านทั้งหมด` and a sync: pill `อ่านครบแล้ว`, sync row green |
| `states/06-settings.png` | Settings sheet |
| `states/07-logout-confirm.png` | Logout confirmation |
| `states/08-call-sheet.png` | Call action sheet from the hero card |
| `states/09-greeting-2.png` | Another AI greeting (tap the greeting to regenerate) |
| `states/*.pdf` | **Vector** 390 × 844 renders: home, notifications, settings. Measure here. |
| `preview.html` | Static home render (uses `grf.css`) |
| `PhoneMenu.dc.html` | Design source. `renderVals()` holds the state logic, the sample data and every style value. |
| `icons/` | Every icon as SVG + its SF Symbol (`icons/README.md`) |
| `assets/tc-renewable-icon-1024.png`, `.svg` | New app icon (same as `AppLogo` on branch `feat/new-app-icon`) |

## Layout (compact, 390 × 844, page background `#F5F8FB`)

### 1. Brand header
- White bar, bottom corners 18, shadow `0 2 8 rgba(22,50,92,0.05)`.
- Status-bar content is dark.
- Row (padding 16, gap 10), left to right:
  - `Image("AppLogo")` 40 × 40, radius 10
  - Greeting
  - Bell
  - Avatar
- **Greeting**:
  - 14 pt bold navy, max 2 lines, no app name, no user name.
  - Tapping it regenerates the line (state `gi` in the board).
  - Accessibility label: `คำทักทายจาก AI ในเครื่อง · แตะเพื่อสุ่มใหม่`.
- **Bell**:
  - 44 pt circle, fill `#EEF2F7`.
  - Red count badge 20 pt with a 2 pt white ring; the count = unread notifications.
  - Opens the full-screen notifications.
- **Avatar**: 44 pt circle `#1F6FB5` with the initials (`WC` in the board). Opens `SettingsView`. It replaces the gear.

#### On-device AI greeting
- Use Apple's **Foundation Models** framework (iOS 26) when `SystemLanguageModel.default.availability == .available`.
- Input context:
  - time of day
  - next appointment (time, job number)
  - % done
  - rain chance today, if a weather source exists
  - missing equipment, if known
  - number of jobs waiting to sync
- Instructions:
  - Thai, one sentence, at most 60 characters
  - playful but polite
  - no user name
  - must mention at least one real fact
- Fallback when the model is unavailable: pick from Thai templates built from the same facts, e.g. `ซิงก์ค้าง {n} งาน Google Drive เริ่มน้อยใจแล้ว`.
- Generate once per day or on tap, and cache it in `@AppStorage`.
- Add a Settings toggle `คำทักทาย AI` (default on). When off, show `สวัสดีตอนเช้า/บ่าย/เย็น`.
- Gate the code with `#if canImport(FoundationModels)` and `@available(iOS 26, *)`, so the deployment target is unchanged.

### 2. `นัดวันนี้` card (hero)
- Gradient 150° `#1F6FB5` → `#16325C`, radius 20, padding 12/14, gap 11, shadow `0 8 18 rgba(22,50,92,0.25)`. All text is white.
- **Top row**:
  - `นัดวันนี้` 12.5 pt bold, 85 % opacity
  - page dots: active 16 × 6, others 6 × 6 at 40 % opacity
  - right: `พุธ 30 ก.ย. · 1/2`
  - `‹` `›` buttons 44 × 44, dimmed to 35 % at the ends
  - Also support swiping (`TabView(.page)` or a drag gesture).
- **Body**:
  - Progress ring 56 pt, stroke 5, `#8FD16A` on white 22 %, `72%` 13 pt bold in the centre.
  - Time 24 pt bold + `นัดสำรวจ · อีก 49 นาที` 12.5 pt.
  - Job name 15 pt bold, max 2 lines.
  - Place line 12.5 pt at 80 % opacity, e.g. `ต.หนองบัว อ.เมือง · 120 kWp`.
- **Actions**:
  - **Primary**: white button 46 high, radius 12, navy 15 pt bold.
    - Text: `ทำต่อ <next step> ›` for a started job, `เริ่มสำรวจ A1 ›` for a new one.
    - Opens the survey at that step.
  - **Navigate**: 44 × 44, radius 12, fill white 16 %. Opens Apple Maps to the job's A1 GPS. Hide it when there is no GPS.
  - **Call**: same style. Opens the call sheet: `โทร <number>` · `ส่งข้อความ` · `ดูรายละเอียดผู้ประสานงานใน A1` · `ยกเลิก`. Hide it when the job has no contact phone.
- **Data**:
  - Today's survey appointments still ahead, sorted by time. Reuse the logic behind `nextAppointment`.
  - `อีก n นาที / ชม.`: same rule as `AppNotification.timeText`.
  - % and next step: from the survey job's completion.
  - **No appointments today**: show a single card with `ไม่มีนัดวันนี้` and a white button `งานสำรวจใหม่ ›`.

### 3. Module rows (replace the big `ModuleCard`s on compact)
- Six rows in one column, gap 8.
- Together the rows fill the remaining height equally, so the page never scrolls on a 6.1" phone. Use a ScrollView fallback for smaller screens or larger Dynamic Type.
- Each row:
  - white, radius 16, 1 pt `#DDE4ED` border
  - padding 0/10/0/12, gap 12, whole row tappable (`NavigationLink`)
  - icon tile 42 × 42, radius 12, `#1F6FB5`, white SF Symbol
  - title 15 pt bold, 1 line; long titles break at the existing `\n` in `AppModule.title`
  - subtitle 12 pt `#5B6B82`, 1 line, tail truncation
  - optional status chip 11 pt bold on `#E3EEF8` / `#1F6FB5`
  - chevron `#AAB6C5`
- Shorter compact subtitles (add `AppModule.shortSubtitle`):
  - survey: `นัดหมาย · หลังคา · ระบบไฟฟ้า`
  - install: `บันทึกประจำวัน · ใบตรวจรับ ICL`
  - The others keep `subtitle`.
- Chips:
  - survey: `n นัดวันนี้` (today's survey appointments; hide when 0)
  - install: `Day d/n` (today's install day; hide when none)
- **Sixth module**: `เครื่องมือและอุปกรณ์วัด`, subtitle `โดรน กล้องถ่ายภาพความร้อน แคลมป์มิเตอร์`, symbol `briefcase.fill`.
  - `AppModule` has five cases today. Look for an existing tools/equipment view (the iPad board is `iPadTools`).
  - If none exists, add `case tools` with a placeholder destination and say so in your summary. Don't build the tools feature in this task.
- The `งานวันนี้` grid is not on the iPhone board. Today's work is now the hero card, so hide that section on compact.

### 4. Notifications: full screen, compact, no buttons in rows
- On compact the bell opens `.fullScreenCover` instead of the popover/panel.
- **Header**:
  - `การแจ้งเตือน` 24 pt bold
  - pill `ใหม่ n`, or green `อ่านครบแล้ว` when n = 0
  - `อ่านทั้งหมด`: hidden when n = 0
  - ✕ in a 44 pt circle `#EEF2F7`
- **Filter chips**, 36 high, capsule:
  - `ทั้งหมด` and `ต้องทำ` + a count chip
  - On: navy fill, white text
  - Off: white, 1 pt `#DDE4ED` border
  - `ต้องทำ` = rows with an action (appointment ahead, sync pending, calibration due).
- **Groups**: `วันนี้` / `เมื่อวาน · d/m` / `ก่อนหน้า`. Header bar 11.5 pt bold `#5B6B82` on `#F5F8FB`.
- **Row**:
  - min height 56, padding 8/12/8/20, bottom hairline `#EEF2F7`
  - 32 pt type tile, radius 9 (colours in `icons/README.md`)
  - title 14 pt, 1 line
  - time 11.5 pt right-aligned
  - detail 12.5 pt, 1 line
- **Unread**: 7 pt `#1F6FB5` dot at the left, row fill `#F3F8FD`, title weight heavy. Read rows have a white fill and semibold title.
- **Tap a row** = do its action and mark it read. Rows with an action show a coloured hint line + a chevron:
  - appointment → open the survey at the next step, hint `แตะเพื่อทำต่อ D1 ถังน้ำใส` (blue)
  - sync pending → run `sync()` immediately, hint `แตะเพื่อซิงก์ตอนนี้` (orange). After the sync the row becomes `ซิงก์ครบแล้ว` with a green tile.
  - calibration due → open tools, hint `แตะเพื่อเปิดเครื่องมือและอุปกรณ์วัด`. Only if a tools data source exists; otherwise skip this kind.
  - info rows: no chevron; tap only marks them read
- **Data**: reuse `AppNotification.list`, `readRaw` and `markRead`. Add a `Kind.calibrationDue` only if tool data exists.
- Keep the iPad `NotificationPanel` as is.

### 5. Settings sheet, logout, call sheet
- `SettingsView` already has the content. On compact, present it as a large sheet with grouped cards that match `states/06-settings.png`:
  - avatar card with `✓ ซิงค์แล้ว`
  - `ผู้ใช้งาน`
  - `GOOGLE DRIVE` (`บัญชี Google` `เชื่อมต่อแล้ว`, `โฟลเดอร์หลัก` `TCRoof Projects ›`, red `ออกจากระบบ`)
  - `ซิงค์ข้อมูลทีม`
  - `เกี่ยวกับ`
- Logout confirmation: `ต้องการออกจากระบบหรือไม่?` / `งานที่ยังไม่ได้ซิงค์จะยังอยู่ในเครื่องนี้` / `ออกจากระบบ` (destructive) / `ยกเลิก`. This is the existing alert.
- Add the `คำทักทาย AI` toggle under `ผู้ใช้งาน`.

## Tokens (board values)
- navy `#16325C`, primary `#1F6FB5`, primary soft `#E3EEF8`
- muted text `#5B6B82`, hairline `#DDE4ED` / `#EEF2F7`
- page `#F5F8FB`, unread `#F3F8FD`
- green `#2E9E5B`, orange `#F08C00` / `#B45309`, red `#D9453B`
- Map these to the existing `Theme` values where they match. Add any that are missing to `Theme.swift`; don't hard-code colours in views.

## Rules
- Compact width only; iPad unchanged. Thai UI text exactly as in the previews. Touch targets ≥ 44 pt.
- No model or sync behaviour changes beyond what is listed: tap-to-sync calls the existing `sync()`.
- Keep the `-homeNotifications YES` debug launch argument working; it should open the full-screen notifications.

## Acceptance
1. An iPhone 15/16 simulator (390 × 844) matches `states/01-home.png` without scrolling.
2. The pager moves between today's appointments. The primary action and ring change per job. Navigate and call are hidden when there is no data.
3. The bell opens full-screen notifications. Filter, row tap actions, read state, `อ่านทั้งหมด` and the sync row all behave as in states 03–05.
4. The greeting comes from Foundation Models on a supported device and from templates elsewhere; tap regenerates; the Settings toggle works.
5. The iPad home looks exactly as before. The app builds without warnings, and the existing tests pass.
6. Finish with a summary: files changed, any `AppModule.tools` placeholder, and remaining differences from the board.
