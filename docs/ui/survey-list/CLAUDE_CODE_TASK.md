# Claude Code task: Survey job list (สำรวจหน้างาน · รายการงานสำรวจ), new card design

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-list/CLAUDE_CODE_TASK.md`

UI text stays in Thai exactly as shown in the previews. This document is in English. Thai strings in `backticks` are the literal labels.

## Goal
Redesign the job cards on `SurveyListView` (`TCRoof/Views/Survey/SurveyViews.swift`). Today the cards come from the shared `JobCard` (`TCRoof/Components/Components.swift`). The board was drawn from origin/main `35ff66b`.

Three changes, all approved by the owner:
1. **Appointment time first-class.** Show the survey time large, with a relative day and the team.
2. **Progress.** Show how far the survey draft has got, and what to do next.
3. **One tap target per action.** Remove the `arrow.right.square.fill` icon. Tapping the card body opens `JobDetailView`; the gradient button opens `SurveyFormView` as before.

Also reorder the card so the job is identified first, then when and where.

The page header, `QueueFilterBar`, search, the empty state, the grid and the `FloatingButton` stay as they are.

Use code-review-graph first, as `CLAUDE.md` says. Check every caller of `JobCard` (the plan, install and history lists also use it) before you change it.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` | default state: `คิวสำรวจใน 7 วัน`, 4 jobs, one draft |
| `states/00-before-current-code.png` | the page as the code draws it today |
| `states/01-week-default.png` | same as preview |
| `states/02-all-jobs.png` | `คิวสำรวจทั้งหมด`: past jobs show `n วันที่แล้ว` in grey, finished surveys show 100 % |
| `states/03-30-days.png` | `คิวสำรวจใน 30 วัน` |
| `preview.html` | open in a browser (uses `ds/` CSS next to it) |
| `iPadSurveyList.dc.html` | design source. `renderVals()` in its `<script type="text/x-dc">` has the reference logic for the relative day, the progress groups and the button title |

The board's sample times (`TIMES`) and the draft progress (`DRAFT_DONE`) are examples. In the app, use the real `surveyDate` and the real draft.

## Card layout (top to bottom)
Card style unchanged (`.cardStyle()`, white, radius 16, shadow). Spacing 6 inside the tappable part, 12 between the tappable part, the progress box and the button.

1. **Title row**
   - `job.projectName`: bold, about 18 pt, navy, one line with a tail truncation.
   - Right side: a team pill showing a dot and `ทีม \(job.team.rawValue)`. The text is in `team.color` on `team.color.opacity(0.1)`, capsule, height 24.
   - After the pill, a small grey `chevron.right` to show the body is tappable.
   - This replaces the old `TeamTag` and the arrow icon. `showTeam: false` no longer applies on this page.
2. **Code row**
   - `job.code`: bold, caption, muted.
   - A status pill with `job.status.title`: `job.status.color` text on `job.status.color.opacity(0.12)`, capsule. This replaces the light-blue `: status` text.
3. **Meta row**
   - `Label(job.customerName, systemImage: "person")`, shown only when it differs from `projectName`.
   - `Label(job.capacityKW.kw, systemImage: "bolt.fill")`.
   - Footnote size.
4. `Divider()`
5. **When row**
   - `calendar` icon plus the relative label, bold, about 15 pt.
   - Then the short date in caption grey, for example `30 ก.ย. 69`.
   - Relative label:
     - `วันนี้ HH:mm น.`, in `Theme.primary`
     - `พรุ่งนี้ HH:mm น.`
     - `เมื่อวาน HH:mm น.`
     - `อีก n วัน · HH:mm น.` for future days
     - `n วันที่แล้ว · HH:mm น.` for past days, in muted grey
   - The time is `surveyDate` formatted `HH:mm` in the Buddhist calendar locale already used in the app. `NewJobView` and the job editor already store a time (`DatePicker("นัดสำรวจ", selection:)` has no `displayedComponents`).
   - Compute days with `Calendar.current.dateComponents([.day], from: today.startOfDay, to: surveyDate.startOfDay)`.
6. **Place row:** `Label(job.province, systemImage: "mappin.and.ellipse")`, as today.
7. **Progress box** (new): rounded 10, padding 10×12.
   - Background: `#EEF4FB` while a draft is in progress, otherwise `#F3F6FA`.
   - Line 1:
     - Caption muted key: `ยังไม่เริ่ม`, `ทำต่อ n/4` or `สำรวจครบ`.
     - Bold value: `เริ่มที่ หลังคา`, the next group's name, or `มีแบบสำรวจแล้ว`.
     - Right-aligned bold percent: grey at 0 %, `Theme.primary` while in progress, green `#2E7D32` at 100 %.
   - Line 2: 4 segments, height 6, gap 3, radius 3. Done groups `#70AD47`, the current group `Theme.primary`, the rest `#DDE4ED`.
8. **Footer:** the existing `GradientButtonLabel` with `buttonTitle(job)`, unchanged.

## Progress rules
Use the same checklist the editor already uses, `SurveyOptions.missing(_:)` (same file, used by `SurveyEditor`) (11 required items). Group them in this order:

| # | Group (exact text) | Items from `missing()` |
|---|---|---|
| 1 | `หลังคา` | ประเภทหลังคา, พื้นที่หลังคา, ทิศทางหลังคา, เงาบัง |
| 2 | `ระบบไฟฟ้า` | การไฟฟ้า, ระบบมิเตอร์, เมนเบรกเกอร์ |
| 3 | `ค่าไฟ` | ค่าไฟหรือหน่วยต่อเดือน |
| 4 | `รูปบังคับ` | the 3 required photo tags (`meter`, `mdb`, `roof`) |

- **No draft and no saved survey:** 0 %, `ยังไม่เริ่ม · เริ่มที่ หลังคา`, all segments grey.
- **Draft exists** (`job.surveyDraft`):
  - percent = (11 − `missing(draft).count`) / 11, rounded.
  - A group is done when none of its items are missing.
  - The current group is the first group that is not done.
  - Show `ทำต่อ \(index)/4` and that group's name.
- **No draft but at least one saved survey:** 100 %, `สำรวจครบ · มีแบบสำรวจแล้ว`, all segments green.
- Put the grouping in `SurveyOptions` (for example a `static func progress(_ form: SurveyForm) -> (done: Int, total: Int, groups: [Bool])`), so the list and the editor never disagree. Do not duplicate the field checks.

## How to build it
- Prefer a new `SurveyJobCard(job:)` view used only by `SurveyListView`. Keep `JobCard` unchanged for the other lists, unless the graph shows the change is safe and the owner wants it everywhere.
- Keep the `NavigationLink` to `JobDetailView` on the body (rows 1–6) and the separate `NavigationLink` to `SurveyFormView` on the button. Do not nest one link inside the other.
- Touch targets ≥ 44 pt. The body link covers the whole upper area.
- Accessibility: give the card body a combined label, for example `"\(projectName), \(relative time), \(progress text)"`.

## Rules
- Don't change models, field ids, sync, export or the other pages.
- Old jobs with no time in `surveyDate` show `00:00 น.`. That is acceptable; don't add a migration.
- Never put the GISTDA key or any secret into code, fixtures or docs.

## Tests
- Unit test the progress function: an empty draft is 0/11 with group 1 current; roof filled is 4/11 with group 2 current; all filled except the photos is 8/11 with group 4 current; everything filled is 11/11.
- Unit test the relative-day label for −2, −1, 0, 1 and 5 days.
- Run `swift build` and `swift test`, and the `CLAUDE.md` `xcodebuild` with your own `-derivedDataPath`.
- On the iPad simulator at 1366 × 1024 (landscape), compare with `preview.png` and `states/02-all-jobs.png`.

## Finish with
A summary listing the files changed, the new view and helper names, where the progress grouping lives, the test results, and any caller of `JobCard` you chose not to touch.
