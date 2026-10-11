# Claude Code task: iPhone "add new customer" sheet (สำรวจหน้างาน · เพิ่มลูกค้าใหม่)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-new-job-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Scope: home / small residential jobs only (งานบ้าน).**
- This sheet belongs to the residential site-survey flow: `PhoneSurveyList` → `NewJobView` → `JobDetailView` → `SurveyFormView`.
- It is **not** part of the PWA / กปภ. project.
- Do not link to, or mention, PWA screens, `SurveyUI.NewJobSheet`, `JobTemplate` or NO.224 here.

**Example data.**
- Every customer name, phone number, address, date and job code in the previews is example data (`assets/sample-data.json` → `exampleCustomer`).
- "Today" is fixed at 30 กันยายน 2569 (2026-09-30) on the board.
- Use the real date and real input in the app.
- The province list is real: all 77 provinces.
- The time, kW and install-offset presets are proposed defaults.

## Context

`NewJobView` (`TCRoof/Views/Job/JobViews.swift`, around line 342) is a plain SwiftUI `Form`:

- **Section `ลูกค้า`:**
  - `TextField`s for customer, project, phone and address
  - a **free-text `TextField` for จังหวัด**
- **Section `แผนงาน`:**
  - kWp `TextField`
  - two `DatePicker`s
  - a `Stepper` for days
  - a team `Picker`
- **Toolbar:** `ยกเลิก` / `บันทึก`

`save()` inserts a `Job` with `status: .interested` and dismisses.

It is presented as a sheet from three places:
- `PhoneSurveyList` (the `TCFab("person.badge.plus")`)
- `HomeView`
- `SurveyViews`

The board `iPhone · สำรวจหน้างาน · เพิ่มลูกค้าใหม่` replaces the **compact** layout with an iOS grouped list. Its changes:

- **Gradient header:** a ✕ to cancel and a subtitle `สำรวจหน้างาน · งานบ้าน`.
- **Two always-visible groups:**
  - `ลูกค้า`: name, phone, address, province
  - `นัดสำรวจ`: date, time
- **A collapsed group** `รายละเอียดงาน · ไม่บังคับ`: kWp, team, project name, install start.
- **One bottom-sheet grid picker** for date, time, kWp, team and install timing.
- **A full-height province sheet** covering all 77 provinces:
  - search
  - frequently-used chips
  - Thai-alphabet groups
- **One large bottom save button** with a live sub-line, replacing the toolbar `บันทึก`.
- **A confirmation banner** `เพิ่มลูกค้าแล้ว` with `เปิดงาน`.

**Compact width only.**
- Branch on `horizontalSizeClass`.
- The iPad presentation of `NewJobView` must stay as it is. Add a compact body or view; do not restyle the shared `Form`.
- See open question 1.

**Before you start.** Use code-review-graph first (per `CLAUDE.md`):
- callers of `NewJobView`, `PhoneSurveyList`, `TCGradientHeader`, `TCToast`, `Job.init`, `SampleData.newJobCode`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` = `states/01-empty.png` | Default empty sheet. @2x (780 × 1688) |
| `states/01-empty.pdf`, `04-province-sheet.pdf` | **Vector** 390 × 844 renders. Measure here. |
| `states/02-filled.png` + crops `02a` / `02b` / `02c` | Filled customer and appointment. Crops: customer group, appointment group with footer, save button with sub-line |
| `states/03-details-open.png`, `03a-details-open-full.png` | `รายละเอียดงาน` expanded (full scroll height at 1x) |
| `states/04-province-sheet.png`, `04a-…crop` | Province sheet: search field, `ใช้บ่อย` chips, `ทั้งหมด 77 จังหวัด`, grouped list with ✓ |
| `states/05-province-search.png` | Search `สมุทร`, which finds 3 provinces; group headers are hidden while searching |
| `states/06-date-picker.png` | Date grid (4 columns, today … +7) |
| `states/07-time-picker.png` | Time grid (3 columns, `ช่วงเช้า` / `ช่วงบ่าย`) |
| `states/08-kw-picker.png` | kWp grid with panel estimate, plus `กำหนดเอง` |
| `states/09-team-picker.png` | Team grid with team dots |
| `states/10-install-picker.png` | Install start offset and duration in one grid |
| `states/11-phone-pad.png`, `12-kw-pad.png` | Number pads. These are **canvas stand-ins** for the keyboard; see "Text input" below |
| `states/13-validation.png` | Save tapped without a name: the name row and the button turn red |
| `states/14-saved.png`, `14a-…crop` | Saved: banner `เพิ่มลูกค้าแล้ว · TCR2569-23411 · อยู่ในรายการงานสำรวจ` + `เปิดงาน` |
| `PhoneSurveyNewJob.dc.html` | Design source; read it as text. Styles are inline, and `renderVals()` holds all logic and copy. It still contains unused `SEEDS` / `SURVEYS` / `PHOTO_TAGS` copied from other boards; ignore them. |
| `preview.html` + `grf.css` | Static render of the default state |
| `icons/` | SVGs with the SF Symbol to prefer (`icons/README.md`) |
| `assets/sample-data.json` | Provinces (77 + frequent), presets, teams, phone rules, example customer |

## Layout (compact), top to bottom

**Page.**
- background `#F7F7FA`: add `Theme.groupedPage` (dark `#000000` / `systemGroupedBackground`)
- one `ScrollView`, padding 16 / 16 / 12, gap 22 between groups
- the save area is pinned below the scroll view

### 1. Header (`TCGradientHeader`)

- **Leading:** a 44 × 44 `xmark` (22 pt, white, stroke 2.4), label `ยกเลิก`; dismisses without saving.
- **Title:** `เพิ่มลูกค้าใหม่`.
- **Subtitle:** `สำรวจหน้างาน · งานบ้าน`.
- **No trailing button.** The toolbar `บันทึก` moves to the bottom button.

### 2. Group pattern (used by every group)

**Group header.**
- 13 pt, colour `#6D6D72`
- 16 pt leading inset
- 6 pt above the card

**Card.**
- white (`Theme.surface`), radius 12
- clip content; no border, no shadow

**Row.**
- HStack, gap 12, min height 52, padding 0 / 16
- **Label:** fixed width 96, 16 pt, `Theme.navy`. A required field adds ` *` in `#FF3B30`.
- **Value:** flexible, 16 pt, trailing aligned, one line with tail truncation. The address wraps (line height 22, padding 15 / 15, top aligned).
- **Placeholder colour:** `#C4C4C7`. Value colour: `#000` (`Color.primary`).
- **Disclosure** (picker rows only): `chevron.right`, 8 × 13, `#C4C4C7`, stroke 2.6.
- **Separator:** 1 pt `#E5E5EA`, inset 16 on the leading side, none on the last row.

**Group footer** (where shown): 12.5 pt, line height 17, `#8E8E93`, 16 pt inset.

### 3. Group `ลูกค้า`

| Row | Placeholder | Input | Notes |
|---|---|---|---|
| `ชื่อลูกค้า *` | `ชื่อ-นามสกุล` | inline `TextField`, `.name` content type | Required. In the validation state the row background is `#FFF4F3`. |
| `เบอร์โทร` | `0X-XXXX-XXXX` | inline `TextField`, `.phonePad` | Format while typing: 10 digits as `081-234-5678`, 9 digits as `02-555-1234`. Tabular digits. Valid when empty or 9–10 digits. |
| `ที่อยู่` | `บ้านเลขที่ ซอย ถนน ตำบล อำเภอ` | multi-line `TextField(axis: .vertical)`, trailing aligned | wraps |
| `จังหวัด` | n/a | opens the province sheet (§7) | value in `#8E8E93`, default `กรุงเทพมหานคร` |

### 4. Group `นัดสำรวจ`

| Row | Value | Opens |
|---|---|---|
| `วันที่` | `พรุ่งนี้ · พฤ. 1 ต.ค.`: relative label + `·` + short weekday, day and short month. **Blue** `#007AFF` 600. | date grid |
| `เวลา` | `09:00 น.`, **blue** | time grid |

**Footer:** `ทีม TCR01 จะเห็นนัดนี้ในปฏิทินแผนก่อสร้าง`. It uses the selected team and updates live.

**Relative label:**
- `วันนี้` for today
- `พรุ่งนี้` for tomorrow
- otherwise `อีก n วัน`

### 5. Group `รายละเอียดงาน · ไม่บังคับ` (collapsed by default)

**Header row** (not a card):
- the group label, plus a trailing `แสดง` / `ซ่อน` text button: 14 pt, 600 weight, `#007AFF`
- min height 36 (the tap target spans the whole row, so ≥ 44 including padding)

When expanded, a card with these rows:

| Row | Value | Opens |
|---|---|---|
| `ขนาดระบบ` | `5 kWp · ~9 แผง`, or the placeholder `ยังไม่ทราบ` | kWp grid |
| `ทีม` | `TCR01`, in the team colour, 700 weight | team grid |
| `ชื่องาน` | inline `TextField`, placeholder `ใช้ชื่อลูกค้า` (empty means use the customer name) | n/a |
| `เริ่มติดตั้ง` | `+14 วัน · 2 วัน` (offset after the survey · duration), blue | install grid |

**Footer:** `ติดตั้งโดยประมาณ พฤ. 15 ต.ค. – ศ. 16 ต.ค. 2569 · ปรับได้ภายหลังในรายละเอียดงาน`.

**Panel estimate:** `round(kWp × 1000 / 570)` (570 W panel).

### 6. Grid picker sheet (one component, five uses)

**Presentation.**
- A bottom sheet over a 30 % black dim.
- Use `.presentationDetents([.height(h)])` sized to the content, or a custom overlay.
- `.presentationDragIndicator(.visible)`.

**Sheet container.**
- background `#F7F7FA`, top radius 16, padding 8 / 16 / 28, gap 12
- grabber 36 × 5, `#C7C7CC`

**Title row.**
- title 17 bold black
- trailing `เสร็จ`: 16 / 600, `#007AFF`, min 44 high; closes the sheet

**Grid** (gap 8). Each option:
- min height 56, padding 6 / 8, radius 12, centred VStack (spacing 2)
- title 16 / 600, optional 10 pt dot before it
- sub 12 pt at 75 % opacity
- **Selected:** 2 pt `#007AFF` border, `#EAF3FF` fill
- **Normal:** 1 pt `#E5E5EA` border, white

Tapping an option sets the value and closes the sheet. The install grid is the exception: it holds two values, so it stays open until `เสร็จ`.

| Use | Title | Columns | Options |
|---|---|---|---|
| date | `วันนัดสำรวจ` | 4 | today … +7. Title `วันนี้` / `พรุ่งนี้` / weekday short (`อา.` … `ส.`); sub `30 ก.ย.` |
| time | `เวลานัด` | 3 | `08:30 น.` `09:00 น.` `10:30 น.` (sub `ช่วงเช้า`); `13:00 น.` `14:00 น.` `15:30 น.` (sub `ช่วงบ่าย`) |
| kWp | `ขนาดระบบโดยประมาณ` | 3 | `3 kWp` … `15 kWp` (sub `~n แผง`); `กำหนดเอง` (sub `แป้นตัวเลข`) opens decimal entry, 1–100, step 0.5 |
| team | `ทีม` | 2 | `TCR01` … `TCR04`, each with a 10 pt dot in `Team.color` |
| install | `เริ่มติดตั้ง (หลังนัดสำรวจ)` | 3 | `+7 วัน` `+14 วัน` `+21 วัน` `+30 วัน` (sub: the resulting date, e.g. `พฤ. 15 ต.ค.`); then `1 วัน` `2 วัน` `3 วัน` (sub `ระยะติดตั้ง`) |

The real app needs dates and times beyond the presets. See open question 2.

### 7. Province sheet

The board's interpretation of the comment "ทุกจังหวัด": every province is selectable.

**Presentation.**
- A tall sheet: top at 56 pt below the screen top on the board. Use the `.large` detent.
- background `#F7F7FA`, top radius 16

**Fixed top area** (padding 8 / 16 / 10, gap 10):
1. Grabber.
2. Title `จังหวัด` with `เสร็จ`.
3. **Search field:**
   - 44 high, radius 10, fill `#EEEEF0`
   - `magnifyingglass` 18 pt `#8E8E93`
   - placeholder `ค้นหาจังหวัด`
   - clear button `xmark.circle.fill`, shown while there is a query
   - use `.searchable` or a custom field
4. **`ใช้บ่อย`** (hidden while searching):
   - 13 pt `#6D6D72` label
   - wrapping chips: 40 high, radius 999, padding 0 / 13, 15 / 600
   - selected chip: `#007AFF` fill, white text
   - other chips: white with a 1 pt `#E5E5EA` border
   - chips: `กรุงเทพมหานคร`, `นนทบุรี`, `ปทุมธานี`, `สมุทรปราการ`, `ชลบุรี`, `ระยอง`

**Scrolling list** (padding 0 / 16 / 28):
- **Count line:** `ทั้งหมด 77 จังหวัด`, or `พบ n จังหวัด` while searching (13 pt `#6D6D72`).
- **Groups:** one per first consonant, with header letter 13 / 700 `#6D6D72`.
  - Skip a leading vowel `เ แ โ ใ ไ`, so `เชียงใหม่` sorts and groups under `ช`.
  - Hide the headers while searching.
- **Each group** is a white card, radius 12, with 6 pt between groups.
- **Rows:**
  - 48 high, 16 pt text
  - 1 pt `#E5E5EA` separator inset 16
  - selected row: `#007AFF` 600 text and a `checkmark` 18 pt `#007AFF`
- **Matching:** substring match on the Thai name.
- **Empty search:** `ไม่พบจังหวัดที่ค้นหา`, centred, 15 pt `#8E8E93`.
- Tapping a row or chip sets the province and closes the sheet.

**Data.**
- Put the list in `TCRoofCore` as a testable type, e.g. `ThaiProvince.all: [String]`, `.frequent`, `.groupKey(_:)`.
- Copy the list from `assets/sample-data.json`.
- Keep `Job.province` a `String`; no model change.

### 8. Text input (the board's number pads are stand-ins)

The canvas cannot type, so the board fakes keyboards:
- tapping a text row fills an example value
- phone and custom kWp open a number-pad sheet

In the app, use real input:
- name, address and project: inline `TextField`s
- phone: `.phonePad` with live formatting
- custom kWp: a `.decimalPad` field, in a small sheet or an alert with a `TextField`

Keep the board's rules:
- phone: 9–10 digits
- kWp: 1–100, step 0.5; out of range shows `เกินค่าสูงสุด 100` / `ต่ำกว่าค่าต่ำสุด 1` and disables `ตกลง`

### 9. Save area (pinned)

**Layout:** padding 10 / 16 / 26, background `#F7F7FA`.

**Button:**
- full width, 54 high, radius 14
- two lines: title 17 / 700 and sub 12 / 500 at 85 % opacity

| State | Title | Sub | Style |
|---|---|---|---|
| no name yet | `บันทึกลูกค้า` | `ใส่ชื่อลูกค้าอย่างเดียวก็บันทึกได้` | fill `#E5E5EA`, text `#8E8E93`; **still tappable** |
| tapped without a name | `บันทึกลูกค้า` | `ใส่ชื่อลูกค้าก่อน` | fill `#FFE9E7`, text `#C0392B`; the name row turns `#FFF4F3`. Also focus the name field. |
| ready | `บันทึกลูกค้า` | `นัดสำรวจ พรุ่งนี้ 09:00 น.` | gradient `#1F6FB5` → `#2E8FDB` (`Theme.primary` gradient), white, shadow `0 6 16 rgba(31,111,181,0.3)` |
| saved | `✓ บันทึกแล้ว` | n/a | fill `#E2EFDA` (`Theme.okSoft`), text `#3B7420` (`Theme.okTick`) |

**On save:**
- `surveyDate` = the chosen day at the chosen time
- `installStart` = `surveyDate.startOfDay` + offset days
- `installDays` = the chosen duration
- `capacityKW` = kWp, or 0 if unknown
- `projectName` = the project, or the customer name if empty
- `status` = `.interested`
- `code` = `SampleData.newJobCode()`, as today
- haptic `.success`

### 10. Saved banner

**Position:** floats 100 pt above the bottom, 16 pt side insets.

**Style:**
- padding 10 / 8 / 10 / 12, radius 14
- navy fill `#16325C`, shadow `0 10 26 rgba(22,50,92,0.35)`

**Content:**
- a 28 pt green check circle `#70AD47`
- title `เพิ่มลูกค้าแล้ว`, 14 bold white
- sub `TCR2569-23411 · อยู่ในรายการงานสำรวจ`, 12 pt at 85 % opacity; it uses the new code
- trailing `เปิดงาน` button: 44 high, padding 0 / 10, radius 10, fill white 14 %, text `Theme.mint` (`#9EE6D6`) 14 bold

**`เปิดงาน`** dismisses the sheet and opens `JobDetailView(job:)` for the new job. Add an `onCreated: (Job) -> Void` callback, or a navigation path on the caller.

**Without a tap**, the sheet dismisses after about 2.5 s and the new job is in `PhoneSurveyList`.

`TCToast` may be reusable; check it first.

## Tokens

No hex in views. Use existing `Theme` tokens and add the missing ones to `TCRoofKit/Sources/TCRoofUI/Theme.swift` with dark values. Prefer the iOS system colours (`Color(.systemGroupedBackground)`, `.secondaryLabel`, `.separator`, `.tint`) where they match; they give correct dark mode for free.

| Use | Light | Token |
|---|---|---|
| page / sheet background | `#F7F7FA` | **new** `groupedPage` (≈ `systemGroupedBackground`) |
| group header / footer text | `#6D6D72` / `#8E8E93` | `.secondaryLabel` / **new** `groupFooter` or `.tertiaryLabel` |
| placeholder, chevron | `#C4C4C7` | `.placeholderText` / `.tertiaryLabel` |
| separator | `#E5E5EA` | `.separator` / `opaqueSeparator` |
| tappable value, `เสร็จ`, `แสดง` | `#007AFF` | `.tint` (or `Theme.iosBlue`) |
| selected option fill | `#EAF3FF` | **new** `optionSelected` |
| search field fill | `#EEEEF0` | `.tertiarySystemFill` |
| required mark | `#FF3B30` | `.red` |
| validation row / button | `#FFF4F3` / `#FFE9E7` + `#C0392B` | `dangerSoft` / `dangerText` (exist) |
| saved | `#E2EFDA` / `#3B7420` | `okSoft` / `okTick` (exist) |
| banner | `#16325C`, `#9EE6D6`, `#70AD47` | `navy`, `mint`, `paperTick` (exist) |

Team colours come from `Team.color`.

## Fonts

The board uses system fonts. Use `.sarabun(size, weight, relativeTo:)` at the sizes above, as the other phone views do. Use digits with `.monospacedDigit()` for phone numbers and times.

## Rules

- **Compact width only;** the iPad `NewJobView` is unchanged.
- **Residential only:** no PWA / กปภ. links.
- Thai UI text exactly as in the previews.
- Touch targets ≥ 44 pt. Group header buttons, chips and grid options already are.
- No model or sync changes; `Job.province` stays a `String`.
- Work on a new branch `feat/iphone-new-job`.

## Acceptance

1. **Matches the board.** On an iPhone 16 simulator (390 × 844), open the sheet from `PhoneSurveyList` (`+` FAB). The screens match:
   - the empty sheet: state 01
   - filled: 02
   - expanded details: 03
   - each picker: 04–10
   - validation: 13
   - saved: 14
2. **Province.**
   - All 77 provinces are listed in Thai order, with correct group keys (`เชียงใหม่` under `ช`, `แพร่` under `พ`).
   - Search `สมุทร` returns 3.
   - Chips set the value.
   - Unit tests cover `ThaiProvince`: count 77, no duplicates, group keys, search.
3. **Saving.**
   - The new `Job` has the chosen date and time, install start, duration, team, kWp and province.
   - It appears in `PhoneSurveyList`, and on the plan calendar on its survey date.
   - `เปิดงาน` opens its `JobDetailView`.
4. **Validation.** Saving without a name shows the red state and does not insert.
5. **iPad unchanged.** Compare iPad screenshots of `NewJobView` before and after.
6. **Builds and tests pass.** `swift build`, `swift test` and the `CLAUDE.md` xcodebuild (with your own `-derivedDataPath`) pass with no new warnings.
7. **Summary.** Finish with:
   - the files changed
   - new tokens and components
   - remaining differences from the board
   - answers to the open questions

## Open questions (report back; don't block on them)

1. **iPad.** Should iPad get this layout too, inside a form sheet? Default: no, compact only.
2. **Dates and times beyond the presets.** The grid covers today … +7 and six times.
   - Default: add a full-width `เลือกวันอื่น` option under the date grid and `เวลาอื่น` under the time grid.
   - Each opens a graphical / wheel `DatePicker` (Thai locale, Buddhist year).
   - A picked custom value shows selected in the grid's place.
3. **Saved banner.** Should it stay inside the sheet with auto-dismiss (default), or dismiss first and show the banner on `PhoneSurveyList`?
4. **Frequent provinces.** The fixed six (Bangkok and its metro area, the east). Alternatively, derive them from the most-used provinces in existing jobs. Default: fixed.
5. **Dark mode.** The board is light only. Propose dark values for the new tokens.
