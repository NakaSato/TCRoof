Follow docs/ui/tcroof-notifications-iphone/CLAUDE_CODE_TASK.md

Add system notifications to TCRoof (UserNotifications), matching docs/ui/tcroof-notifications-iphone/states/*.png:
- in-app banner (states/02–07)
- lock-screen stack grouped by type (states/01)
- long-press quick actions (states/08–13)

1. NotificationService:
   - request authorization
   - register 6 UNNotificationCategory types — survey, queue, late, cal, sync, done — with the exact Thai titles, bodies and actions from the task table
   - action icons via UNNotificationActionIcon (SF Symbols from icons/README.md)
   - .destructive for `สละคิว`; background actions for remind-later and `ซิงก์ตอนนี้`
   - interruption level: `late` .timeSensitive · `survey`/`queue` .active · `cal`/`sync`/`done` .passive
2. Scheduling, with stable ids shared with AppNotification.list so bell and system stay in sync:
   - survey: 30 min before today's and tomorrow's appointments; reschedule on save and sync
   - sync: one replaceable `sync-pending` from SurveyModel.jobsToSync / CloudSync; removed at 0
   - done: after a Drive export while in background
   - queue / late / cal: wire them if tools data exists; otherwise add the categories plus a small ToolNotification API with tests, and say so
3. willPresent → [.banner, .list, .sound]. didReceive → one DeepLink enum that opens the right screen for every action (survey step, Apple Maps, tools camera, queue, Drive, share, sync now, remind later) and marks the AppNotification read.
4. The badge equals the bell's unread count.
5. Settings: add an `การแจ้งเตือน` group with per-type toggles and a link to the system settings when permission is denied.

Thai text exactly as in the previews. Keep the in-app bell list working. Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/system-notifications. Build, test on an iPhone 16 simulator (schedule an appointment 31 min ahead, long-press, tap each action), and add tests for the ids and the deep-link routing. Finish with a summary of files changed, which types are fully wired vs API-only, and anything that differs from the board.
