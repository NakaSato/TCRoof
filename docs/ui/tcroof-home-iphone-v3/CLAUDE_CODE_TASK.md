# Claude Code task: iPhone home v3: floating tab dock and a project feed in place of the module rows

> How to use: open Claude Code in the `TCRoof` repo and paste the prompt in `PROMPT.md`, or type
> `Follow docs/ui/tcroof-home-iphone-v3/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Every name, number, date, team and
photo in the previews is **example data**; never hardcode it.

## Context
Board: `iPhone · หน้าหลัก TCRoof` (`PhoneMenu.dc.html`, 390 × 844), owner's changes up to 12 ต.ค. 2569.

v2 (`docs/ui/tcroof-home-iphone-v2`) is built in `TCRoof/Views/Home/PhoneHome.swift`. It has
`HomeBrandHeader`, `AppointmentHero` (the `นัดวันนี้` pager), the `moduleRows` list of `AppModule` rows, and the
`PhoneTabs` tab bar. **This task covers only the differences below, on iPhone (compact) only.** `PadHome` stays as it is.

The tab bar in this hand-off **replaces** both the v2 tab bar and the earlier `docs/ui/tcroof-tools-tab-iphone` hand-off.
If that one is not built yet, skip it. Its `tab-tools` asset and the `-homeTab tools` rename are part of section 0 below.

Start with code-review-graph (callers of `PhoneHome`, `AppointmentHero`, `ModuleRow`, `AppModule`, `TodayAppointment`).
If the server is not available, use grep. Read the source before changing it.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | Default: appointment card + feed (same as `states/01-home.png`), @2x |
| `states/01-home.png` | Today has appointments: `นัดวันนี้` card, then the feed |
| `states/02-no-appointment.png` | No survey today: the card is hidden and the feed moves up |
| `states/03-filter-pwa.png` | Feed filter `กปภ.` |
| `states/04-filter-home-issue.png` | Filter `งานบ้าน`, with the issue post open (`ยังค้าง`) |
| `states/05-issue-fixed-acked.png` | Issue marked `แก้แล้ว`; summary post acknowledged (`คุณและอีก 5 คนรับทราบ`) |
| `states/06-notifications.png` | Bell panel (unchanged from v2, for reference) |
| `states/07-feed-all-posts-tall.png` | The whole feed on a tall canvas, so every post type is visible |
| `states/08-dock-crop.png` | The floating tab dock close-up (@2x) |
| `PhoneMenu.dc.html` + `grf.css` | Design source. Read it as text: markup plus `renderVals()` hold every size, colour and rule |
| `icons/` | Vectors for the new parts: the five tab glyphs `tab-*.svg`, the acknowledge thumb, and example photos (`icons/README.md`) |

## Changes (compact only)

### 0. Tab bar: floating dock, new tabs
`TCTabBar` (`TCRoofKit/Sources/TCRoofUI/Layout.swift`) and `PhoneTabs` (`TCRoof/Views/Home/PhoneTabs.swift`) change on iPhone:
- **Order and targets:**

  | Tab | Label | VoiceOver | Glyph | Opens |
  |---|---|---|---|---|
  | 1 | `หน้าหลัก` | `หน้าหลัก` | SF `house` | home (this page) |
  | 2 | `งานบ้าน` | `งานบ้าน` | asset `tab-homework` (`icons/tab-homework.svg`) | the residential (HomeWork) survey list, today's `.survey` tab |
  | 3 | `กปภ.` | `กปภ. · นัดวันนี้ n` | asset `tab-pwa` (`icons/tab-pwa.svg`, water drop) | the PWA module (`AppModule.pwa`, PWA survey home) |
  | 4 | `เครื่องมือ` | `เครื่องมือวัด` | asset `tab-tools` (`icons/tab-tools.svg`) | `AppModule.tools` |
  | 5 | `ตั้งค่า` | `ตั้งค่า` | SF `gearshape` | settings sheet (action tab, as today) |

  `แผนงาน` is no longer a tab. Keep the plan calendar reachable (it was a v2 tab; ask the owner where it goes, see open question 1).
- **Badge:** the red count moves to `กปภ.`, because today's appointments in the example are PWA jobs. In code, count today's appointments per tab:
  residential ones on `งานบ้าน`, PWA ones on `กปภ.`.
- **Look (state `08`):** a floating capsule, not a full-width bar.
  - 12 pt from the left and right edges, 22 pt above the bottom edge (keep it clear of the home indicator).
  - Radius 28, opaque `Theme.surface`, 1 pt `Theme.borderOutdoor`, padding 5.
  - Equal-width items 56 pt high: glyph 23 pt over a 10.5 pt label.
  - Selected: the item is a `Theme.navySolid` capsule (radius 22) with a white glyph and an 800-weight label. Others: `Theme.inkTab`.
  - A 1 pt `borderSubtle` divider before `ตั้งค่า`. The badge is 17 pt, `Theme.danger`, with a 2 pt white ring, top right of the glyph.
- **Content under the dock:** the page scrolls behind the dock, ending 104 pt above the bottom.
  - Above the dock, a 128 pt gradient fades from clear to `Theme.phonePage` (clear → 85 % at 38 % → solid at 62 %), so posts fade out instead of showing through or being cut off.
  - The gradient takes no touches (`allowsHitTesting(false)`).
- Replace `PhoneTab.survey` / `.plan` / `.install` with `.homeWork` / `.pwa` / `.tools`, and update the `-homeTab` DEBUG values
  (`home|homework|pwa|tools`) in CLAUDE.md. Update `HomeNavbarUITests` / `PhoneSurveyUITests` where they tap the old tabs.
- Add the three template image assets (`tab-homework`, `tab-pwa`, `tab-tools`) from `icons/` the same way `tab-install` is set up (vector, template rendering).

### 1. Remove the module rows
- `PhoneHome` no longer shows `moduleRows`; the six `ModuleRow`s are gone from the iPhone home.
- **Ask the owner before deleting any route.** `AppModule.plan`, `.scan` and `.install` have no tab. Keep them reachable somewhere
  (feed post links already open install records). Report where you put them. Don't remove `AppModule` or `ModuleRow`,
  because `PadHome` still uses them.

### 2. `นัดวันนี้` card only when there is an appointment
- Show `AppointmentHero` only when `appointments` is not empty (states `01` vs `02`). When it is hidden there is no empty state.
  The feed starts right under the header.
- Today `AppointmentHero` shows a `newSurvey` empty state; on iPhone, drop it (the survey tab has the add button).

### 3. Project feed (new) under the card
A social-style feed of **what happened on site today**. **Nobody posts by hand.** Every post is generated from records the
app already has, for every project the user can see.

**Filter chips** (horizontal scroll, 40 pt high; give them a 44 pt hit area): `ทั้งหมด` · `กปภ.` · `งานบ้าน` · `ทีมของฉัน`,
each with a count chip. Selected: `Theme.navySolid` fill, white bold; others: surface with `borderSubtle`.
- `กปภ.` = PWA project records; `งานบ้าน` = residential (HomeWork) records; `ทีมของฉัน` = records of the signed-in user's team.
- The daily summary post shows under every filter.

**Post card** (surface, radius 18, 1 pt `borderSubtle`, no shadow):
- Header: 40 pt round avatar with the team initial (team colour), `who` 14 pt bold, a small badge, then `where · when` 11.5 pt
  `inkMuted`, and a `⋯` button (44 × 44, menu: hide this post / open the source record).
- Text: 13.5 / 20 pt.
- Optional photo: the record's photo, radius 12, 330 × 170 aspect. Overlay chips bottom-left (e.g. `+6% วันนี้` green,
  `38% / แผน 50%` red when behind) and a `1/4` photo counter top-right. Swipe through the record's photos.
- Optional stat tiles (3 columns) instead of a photo, for system posts.
- Footer line: `n คนรับทราบ` (or `คุณและอีก n คนรับทราบ`).
- Action row (top hairline): `รับทราบ` (thumb icon, toggles; bold `Theme.primary` when on) · `<go> ›` link
  (`ดูรายงาน` / `ดูผลทดสอบ` / `ดูงาน` / `ดูสรุป`) that opens the source record.
- **No comments.** The owner removed them, so add no comment button or count.

**Post types and where they come from** (find each source in the code, and report any that has no model yet):
| Type | Badge | Source | Example in the board |
|---|---|---|---|
| Daily progress | `รายงานวันนี้` (blue) | A signed daily report (`docs/specs/routine-reports-swift.md`, `DailyReportScreen`), with photo and MP progress delta | Team A, MP 189, 2.3 ติดตั้งแผง |
| Waiting for inspector | `รอผู้ตรวจ` (orange) | Daily report or install log that requests an inspection | Team C, MP 154, 2.5 Inverter |
| Test result | `อัตโนมัติ` (green) | IEC 62446 test record (`forms/iec62446-pwa`, the IEC screens) | MP 77, 12/12 strings |
| Site issue | `ปัญหา` (red), red avatar | An install-log entry flagged as a problem (`InstallLog`, HomeWork site-change views) | TC-0012, leak at B3 |
| Daily summary | `สรุปวันนี้` (blue) | Generated at 18:00 from that day's reports: reports sent x/n, overall progress delta, open issues | 8/12 · +2% · 1 |

**Issue post extra** (states `04`, `05`): a tinted box under the text. It shows `ผู้รับผิดชอบ <name>` and
`กำหนด <date> · ยังค้าง` (red tint). A green `แก้แล้ว` button (44 pt) marks the issue fixed in its source record. Once fixed,
the box turns green with `แก้แล้ว ✓` and a `เปิดอีกครั้ง` button. Use the record's own status field. If there is none,
add an optional one (decodeIfPresent with a default) and report it.

**Order:** newest first, but the daily summary stays on top on the day it is made. Show the last 7 days, then
`ดูโพสต์ก่อนหน้า`. Empty feed: one line in `inkMuted`, e.g. `ยังไม่มีความคืบหน้าวันนี้`.

**Acknowledgements:** store who acknowledged which post, so `n คนรับทราบ` is shared. Use the existing Firestore sync. A new
synced collection needs a rule in `firestore.rules` (see CLAUDE.md). If that is too big for this task, store it locally and
report it.

### 4. Implementation notes
- Build the feed from small views in `TCRoofUI` (`TCFeedPost`, `TCFeedChip`, `TCIssueBox`). Add them to `ComponentGallery`.
  Colours come from `Theme` only (no hex, no `Color.white`); split long bodies into computed properties.
- A pure `FeedBuilder` in `TCRoofCore` turns records into `[FeedPost]` (value types, unit-tested in `TCRoofKit` with
  `swift test`). The app passes its SwiftData and survey records in.
- Example photos in the board are vector illustrations (`icons/example-photo-*.svg`), for layout only. The app shows real photos.

### 5. DEBUG launch arguments (add to CLAUDE.md, next to `-homeDemo`)
- `-homeFeed demo` seeds the board's five posts.
- `-homeFeedFilter all|pwa|home|mine` picks a filter.
- `-homeNoAppointments YES` hides the appointment card.
- `-homeFeedIssue fixed` opens the issue post already fixed.

## Keep
- Data rules from CLAUDE.md: no change to `Values`, field ids or Excel cells. New fields are optional, and old JSON and SwiftData stores
  still open.
- Hit areas ≥ 44 pt. Light mode only, like the rest of the app.

## Check list
- [ ] `swift build` + `swift test` in `TCRoofKit/` (FeedBuilder tests); xcodebuild with your own `-derivedDataPath`
- [ ] Tab dock matches `states/08-dock-crop.png`; every tab ≥ 44 pt; the badge sits on `กปภ.`; the feed fades under the dock
- [ ] iPhone simulator screenshots of states `01`–`05` with the new launch arguments, compared with `states/`
- [ ] With no appointments, the card is gone and nothing is left blank
- [ ] `รับทราบ` toggles and the count updates; `แก้แล้ว` / `เปิดอีกครั้ง` round-trips to the source record
- [ ] iPad home unchanged; `HomeNavbarUITests` still pass (bell, settings, search)
- [ ] Every module that lost its home row is still reachable (report where)

## Open questions (report back)
1. Where should the plan calendar, scan and install modules live on iPhone now that the module rows and the `แผนงาน` tab are gone? (`กปภ.` and `เครื่องมือ` are now tabs.)
2. Who can acknowledge a post (any signed-in member, or only supervisors and inspectors)?
3. Should the issue post notify the owner (push) and appear in the bell panel?
4. Is the 18:00 summary time fixed, or a setting (it matches the daily report deadline)?
5. Should `ทีมของฉัน` use the signed-in user's team from Settings, or the teams on today's appointments?
