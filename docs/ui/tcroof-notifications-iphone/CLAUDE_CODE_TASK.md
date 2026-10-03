# Claude Code task: TCRoof system notifications (banner · lock screen · quick actions)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-notifications-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal notification text. Names, numbers and times in the previews are **example data**.

## Goal
The app already has an in-app notification list (`AppNotification` in `TCRoof/Views/Home/NotificationPanel.swift`, kinds `survey / install / syncPending / saved`). It has **no system notifications** yet: no `UNUserNotificationCenter`.

The board `PhoneNotif.dc.html` shows what TCRoof should post as **local notifications**:
- in-app banner while the app is open
- lock screen stack
- long-press quick actions that deep-link into the right screen

Build that with `UserNotifications`. iOS draws the banners itself, so this task is mostly content, categories, actions, scheduling and deep links, not custom UI.

Use code-review-graph first (per `CLAUDE.md`):
- callers of `AppNotification.list`, `SurveyModel.jobsToSync`, `CloudSync`, and the app entry point / scene
- anything tools-related (borrow / return / queue / calibration), if it exists

Then read the source.

## Files in this folder
| File | Shows |
|---|---|
| `states/01-lock-screen.png` (+ `.pdf`) | Lock screen stack: 3 newest, `+ อีก 1 รายการ · รอซิงก์ 2 งาน` |
| `states/02…07-banner-*.png` (`02` + `.pdf`) | In-app banner for each type: survey, queue, late, calibration, sync, saved |
| `states/08…13-actions-*.png` (`08` + `.pdf`) | Long-press expanded notification + quick-action menu for each type |
| `states/14-after-action-toast.png` | After an action: the app opens on that screen (the board shows a hint toast) |
| `PhoneNotif.dc.html` | Board source. `renderVals()` holds the full table `N` of type, title, body, sub, time, category and actions. |
| `grf.css` | Shared board styles |
| `icons/` + `icons/README.md` | Action glyphs (with SF Symbol names) and type colours |
| `assets/tc-renewable-icon-1024.png`, `.svg` | App icon (iOS uses `AppIcon` automatically) |

PNG previews are @3x (1170 × 2532). PDFs are vector 390 × 844.

## Notification content (one row per type)
iOS layout is `APP · …` header, title (1 line), body (2 lines), then a sub line.
- `content.title` = title
- `content.body` = body + `\n` + sub
- `content.subtitle` = empty, so iOS keeps title / body as on the board

`TCROOF · <category>` on the board is the app name plus a coloured category word. iOS can't colour that, so put the category in the **title prefix only if needed**. Prefer the plain title as shown and use `threadIdentifier` per type.

| Type id | Category (thread) | Title | Body | Sub line | When to fire | Actions |
|---|---|---|---|---|---|---|
| `survey` | `สำรวจ` | `นัดสำรวจในอีก 30 นาที` | `NO.224 กปภ. … สถานีผลิตน้ำ 1` | `ต.หนองบัว อ.เมือง · 10:30` | 30 min before each survey appointment (`job.surveyDate`) | `นำทาง` · `เปิดแบบสำรวจ` · `เตือนอีก 10 นาที` |
| `queue` | `เครื่องมือ` | `ถึงคิวคุณ · DJI Mavic 3T` | `สมชายคืนเครื่องและส่งต่อให้คุณ รับได้ที่ห้องเก็บเครื่องมือ` | `งาน NO.230 · ใช้ได้ถึง 9/10` | When a borrowed tool you queued for is returned | `รับเครื่อง · ถ่ายภาพตอนยืม` · `ดูคิว` · `สละคิว` (destructive) |
| `late` | `ด่วน` | `เกินกำหนดคืน · Fluke 376 FC` | `เกิน 1 วัน (กำหนด 29/9) · สมชายรอใช้ต่อ 1/10` | `แตะเพื่อคืนพร้อมถ่ายภาพ 3 ภาพ` | 08:00 each day a borrowed tool is past due | `คืนอุปกรณ์` · `ขอขยายเวลา 1 วัน` · `โทรหาผู้รอคิว` |
| `cal` | `สอบเทียบ` | `ใกล้ครบกำหนดสอบเทียบ` | `Fluke 1587 FC เครื่องวัดฉนวน · ครบ 20/12/2569` | `เหลือ 30 วัน · จองส่งสอบเทียบล่วงหน้า` | 30 and 7 days before a calibration due date | `เปิดทะเบียนเครื่อง` · `เตือนอีก 7 วัน` |
| `sync` | `ซิงก์` | `รอซิงก์ 2 งาน` | `ยังไม่ได้บันทึกขึ้น Google Drive` | `NO.224 · NO.221 · จะซิงก์เองเมื่อมีสัญญาณ` | When jobs have waited more than 2 h offline, and at 20:00 if any are still pending | `ซิงก์ตอนนี้` · `ดูรายการ` |
| `done` | `ส่งออก` | `บันทึกขึ้น Drive แล้ว` | `NO.224 แบบสำรวจ · 4 ไฟล์ (PDF · Excel · CAD · รูป)` | `โฟลเดอร์ TCRoof/2569/NO.224` | Right after a Drive export succeeds, only while the app is in the background | `เปิดใน Drive` · `แชร์ลิงก์` |

Time labels (`ตอนนี้`, `2 นาทีที่แล้ว`, `เมื่อวาน`) are drawn by iOS.

### Interruption level
| Types | Level |
|---|---|
| `late` | `.timeSensitive` (needs the Time Sensitive capability) |
| `survey`, `queue` | `.active` |
| `cal`, `sync`, `done` | `.passive` |

## Implementation
1. **`NotificationService`** (new, `TCRoof/Notifications/`):
   - Requests authorization on first launch after login, with `.alert, .sound, .badge, .timeSensitive` only if the capability is set.
   - Registers 6 `UNNotificationCategory`s, one per type id above. Each action is a `UNNotificationAction` with `UNNotificationActionIcon(systemImageName:)` from `icons/README.md`:
     - `.foreground` for anything that opens a screen
     - `.destructive` for `สละคิว`
     - background for `เตือนอีก 10 นาที` / `เตือนอีก 7 วัน` / `ซิงก์ตอนนี้`
   - Schedules and cancels with stable identifiers, e.g. `survey-<jobKey>-<yyyy-MM-dd>`, reusing the ids `AppNotification.list` already builds. The bell list and the system notifications then refer to the same events, and reading one marks the other read.
2. **Scheduling**:
   - **survey**: on app launch, on job save and on sync, (re)schedule today's and tomorrow's appointments (`UNCalendarNotificationTrigger`, appointment time − 30 min). Cancel when the appointment changes or the survey is complete.
   - **sync**: from `SurveyModel.jobsToSync` / `CloudSync`. Post or replace one notification, id `sync-pending`, when the count changes. Remove it when the count reaches 0.
   - **done**: post from the Drive export success path (`UNTimeIntervalNotificationTrigger` 1 s) when the scene is not active.
   - **queue / late / cal**: tools data. If the app has no tools/equipment loan model yet, add the categories and a small `ToolNotification` API (`notifyQueueReached`, `notifyOverdue`, `scheduleCalibration`) with unit tests, and **say so in your summary**. Don't build the tools feature here.
3. **Foreground presentation**: `userNotificationCenter(_:willPresent:)` returns `[.banner, .list, .sound]`, so the banner shows while the app is open (`states/02–07`).
4. **Actions and deep links**: in `userNotificationCenter(_:didReceive:)`, route through one `DeepLink` enum on the app's navigation state:
   - default tap / `เปิดแบบสำรวจ` → open the survey at its next step
   - `นำทาง` → Apple Maps to the A1 GPS
   - `เตือนอีก 10 นาที` → reschedule +10 min
   - `รับเครื่อง · ถ่ายภาพตอนยืม` / `คืนอุปกรณ์` → tools screen with the camera for 3 photos
   - `ดูคิว` → tools queue
   - `สละคิว` → leave the queue (confirm in the app)
   - `ขอขยายเวลา 1 วัน` → request extension
   - `โทรหาผู้รอคิว` → `tel:`
   - `เปิดทะเบียนเครื่อง` → tool record
   - `เตือนอีก 7 วัน` → reschedule
   - `ซิงก์ตอนนี้` → `CloudSync` now (background)
   - `ดูรายการ` → pending list
   - `เปิดใน Drive` → Drive folder URL
   - `แชร์ลิงก์` → share sheet
   - Mark the matching `AppNotification` id read.
5. **Badge**: set it to the unread count from `AppNotification` (same number as the bell). Clear it when everything is read.
6. **Settings**: add a `การแจ้งเตือน` group to `SettingsView`:
   - one toggle per type: `นัดสำรวจ`, `คิวและกำหนดคืนเครื่องมือ`, `สอบเทียบ`, `ซิงก์และส่งออก`
   - a row that opens the system notification settings when permission is denied

## Rules
- Thai text exactly as in the table and states. Use the app's `ThaiFormat` for dates (Buddhist year).
- Never post more than one `sync` notification, and use thread identifiers so the lock screen groups by type (`states/01`).
- No hex literals in views; type colours go to `Theme` if the in-app list uses them.
- Keep the in-app bell list working as it does now.

## Done when
- `xcodebuild` builds the app and TCRoofKit, and tests pass. Add tests for scheduling ids and for the deep-link routing.
- On an iPhone 16 simulator:
  - a survey appointment 31 min ahead fires the banner at −30 min (`states/02`)
  - long-press shows the 3 actions (`states/08`)
  - each action opens the right screen
- Lock-screen grouping checked with 3+ notifications (`states/01`).
- Summary of files changed, which types are fully wired, and which are API-only because tools data doesn't exist yet.
