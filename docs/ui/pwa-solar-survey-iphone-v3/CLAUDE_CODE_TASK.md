# Claude Code task: PWA project home (iPhone) v3 — main dock, `โครงการ | แผนงาน | บำรุงรักษา`, install-phase cards (board update 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/pwa-solar-survey-iphone-v3/CLAUDE_CODE_TASK.md`

Board: `iPhone · หน้าแรก PWA Solar Project` (`PhoneHome.dc.html`, 390 × 844). Thai strings in `backticks` are literal UI
labels. Every name, number, date, MP and team in the previews is **example data**; never hardcode it.

## Scope: change only this list

The PWA home on iPhone is built from `docs/ui/pwa-solar-survey-iphone-v2` and `docs/ui/pwa-maintenance-iphone`:
- `SurveyHomeView` (`TCRoofKit/Sources/TCRoofUI/Survey/Home/`: `SurveyHome+Phone`, `+Header`, `+Overviews`, `JobCard`)
- inside `PWAPhoneTabs`, which has its own dock

A text diff of the board against `docs/ui/pwa-maintenance-iphone/PhoneHome.dc.html` shows **only** the six changes below.
Change only these, on iPhone (compact) only.

**Do not touch:**
- the install overview body and the maintenance overview body (summary cards, row filters, rows' content)
- `PWAPlanPhoneView`, `StationDocsScreen`, the survey wizard
- the iPad
- the iPhone home (`PhoneHome`, v4)
- data models, `Values`, field ids, Excel cells

Before editing, use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep. Look at:
- `PWAPhoneTabs`, `PhoneTabs` (`.pwa` case), `TCTabBar`
- `SurveyHomeView.header` / `stagePills` / `filterPopover`, `TCCountSegments`, `TCPhoneSearchHeader`
- `JobCard` (`Mode.install`), `InstallOverview.pace`, `InstallStationSummary`, `maintenanceRow`

Then run `tests_for` on what you touch (`PhoneSurveyUITests`, `HomeNavbarUITests`, `PWAOverviewTests`).

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01-projects.png` (@2x) |
| `states/01-projects.png` | `โครงการ` selected: survey cards and install-phase cards, main dock with `กปภ.` selected |
| `states/02-maintenance.png` | `บำรุงรักษา` selected (overview body unchanged from `pwa-maintenance-iphone`) |
| `states/03-install-overview.png` | The install overview, now reached from the filter's `ประเภทงาน → ติดตั้ง` (body unchanged) |
| `states/04-filter-open.png` | Filter popover on `โครงการ`: new `ประเภทงาน` section above `สถานะงาน` and `เรียงตาม` |
| `states/05-filter-open-maintenance.png` | Filter popover on `บำรุงรักษา`: only `ประเภทงาน` |
| `states/06-search-open.png` | Search open in the header (title hidden, bell stays) |
| `states/07-projects-all-cards-tall.png` | Every card of the project list on a tall canvas |
| `states/08-card-survey-vs-install-crop.png` | Survey card vs. the two install-phase cards (late and on plan), close-up |
| `states/09-dock-crop.png` | The main dock as it appears inside the PWA module |
| `states/10-header-nav-crop.png` | Header + segmented nav + filter button, close-up |
| `PhoneHome.dc.html` + `grf.css` | The design source. Read it as text: markup plus `renderVals()` hold every size, colour and rule |
| `icons/badge-install-hardhat.svg` | The hard-hat glyph of the `ติดตั้ง` badge, 13 pt, stroke 2.4 |
| `reference/PhonePwaStation.dc.html` + `station-page.png` | Where a maintenance row leads. **Reference only, not in scope** |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. Dock: the PWA module uses the main dock (`states/01`, `09`)
- The board drops the PWA module's own dock (`PWAPhoneTabs`: `หน้าหลัก · โครงการ · แผนงาน · เอกสาร | ตั้งค่า`).
  - Inside the PWA module the **main dock** stays on screen: `หน้าหลัก · งานบ้าน · กปภ.(badge) · เอกสาร | ตั้งค่า`, with `กปภ.` selected.
  - This is the same `TCTabBar` and the same look as the iPhone home (v3/v4).
- **Implementation:** `PhoneTabs` currently swaps in `PWAPhoneTabs` for `.pwa`. Make `.pwa` an ordinary stack of the main dock instead.
  - Its root is `SurveyHomeView` for the PWA client group, in the state below.
  - The dock shows on that root only and is hidden on pushed screens, the same as the other tabs.
- What the old PWA tabs become:

  | Old PWA tab | Now |
  |---|---|
  | `โครงการ` | the root (section 2, segment `โครงการ`) |
  | `แผนงาน` | segment `แผนงาน` of the new nav: pushes `PWAPlanPhoneView` |
  | `เอกสาร` | the main dock's `เอกสาร` (already built in v4) |
  | `ตั้งค่า` (PWA project settings) | no longer on a dock; see open question 1 |

- Keep `PWAPhoneTabs` compiling if the iPad or tests still use it. If nothing uses it any more, say so. **Do not delete it without asking.**
- Update `-surveyHomeTab` in CLAUDE.md (line ~68): it was `all|install|maintenance|plan|docs|settings`. It becomes `projects|plan|maintenance` plus the new `-surveyHomeType` (section 3).

## 2. Header + segmented nav (`states/10`, `06`)
- **Header** (blue gradient, bottom radius 15, as before):
  - Title `โครงการ PWA`, 22 pt bold, one line. The old title `PWA Solar Project` and the subtitle line `การประปาส่วนภูมิภาค` (with the engineer) are gone on iPhone.
  - Right side:
    - the **search** button, now **round**: 44 × 44, radius 22, white 18 % fill, white 40 % 1 pt border. The search animation is unchanged.
    - a new **bell** button, same size and fill, unread badge 16 pt `Theme.danger` with a 2 pt `#2A84CF` ring. It opens the notifications screen the iPhone home's bell opens (`PhoneNotificationsView`).
  - The board has **no `···` more-menu**. Keep its actions reachable rather than deleting them (see open question 2), and report where they went.
- **Nav row** under the header, 12 pt from it:
  - `TCCountSegments` with three equal segments and no counts: `โครงการ` · `แผนงาน` · `บำรุงรักษา` (14 pt).
  - Then the round 44 pt **filter** button. It is **always shown**; before, it was hidden in the overviews.
  - `โครงการ` selects the project list (the old `ทั้งหมด` stage, plus the install overview when chosen in the filter).
  - `แผนงาน` pushes `PWAPlanPhoneView`. It is a link, not a selected state; the segment stays on what it was.
  - `บำรุงรักษา` selects the maintenance overview.
  - This replaces the stage pills `ทั้งหมด n · ติดตั้ง n · บำรุงรักษา n`.

## 3. Filter popover: `ประเภทงาน` section (`states/04`, `05`)
- A new first section `ประเภทงาน`: radio rows with a count and a ✓ on the selected row:
  - `ทั้งหมด n`: the project list
  - `ติดตั้ง n`: the install overview, same body as today
  - `บำรุงรักษา n`: the maintenance overview
- The counts are those of the old stage pills. Choosing a row closes the popover.
- `สถานะงาน` and `เรียงตาม` show **only** when the type is `ทั้งหมด` (the project list).
- `ล้าง` (reset) also resets the type to `ทั้งหมด`.
- The filter button shows the active state (navy fill + orange dot) when the type is not `ทั้งหมด`, as for a status or sort.
- The nav's `บำรุงรักษา` segment and the filter's `บำรุงรักษา` row are the same state; keep them in sync. `โครงการ` is selected for `ทั้งหมด` and `ติดตั้ง`.
- DEBUG: `-surveyHomeType all|install|maintenance`. Add it to CLAUDE.md.

## 4. Project cards: survey vs. install phase (`states/08`, `07`)
Both cards keep **the same layout**, which is today's `JobCard`:
- `NO.` + badge
- title + place · kWp
- ring on the right
- segmented bar
- the tinted "next" row
- chips
- footer with date · photos · sync

Only the badge, colours and texts differ by phase.

- **Survey** (unchanged, plus a badge): a blue `สำรวจ` badge after `NO.xxx` (11 pt bold, `#E3EEF8` / `Theme.primary`, capsule, 18 pt line).
- **Install phase:** a job whose survey is done and that has an install record / `InstallStationSummary`. This is `JobCard(mode: .install)` or `.locked`; use whichever the code already uses for "moved to installation".
  - **Badge:** green `ติดตั้ง` with the hard-hat glyph (`icons/badge-install-hardhat.svg`), on `#E2EFDA` / `#3B7420`.
  - **Colour rule** (from `InstallOverview.pace` with the default 2 % threshold, the same rule as `แผน MP`): **late** when actual − plan ≤ −2 %; otherwise **on plan**.
  - **Ring:** the actual install %, in red `#D9453B` when late, blue `Theme.primary` when on plan.
  - **Bar:** 10 equal segments for the install tasks of the Master Plan:
    - done = green `#70AD47`
    - current = red when late, blue when on plan
    - late only: segments the plan says should be done but aren't = pale red `#F4B4AE`
    - the rest = grey `#DDE4ED`
  - **Next row:** `กำลังทำ` (11 pt muted) + the current task (13 pt bold, e.g. `2.2 เดินสาย DC`).
    - Right side: `ช้ากว่าแผน n%` in `#B42318`, or `ตามแผน` in `Theme.primary`, then `›`.
    - Row fill `#FDECEA` when late, `#E3EEF8` when on plan.
  - **Chips** (grey `#F3F6FA`, 11 pt): `แผน p% · จริง a%` · `ส่งมอบ dd/mm` · contractor name.
  - **Tap** opens the install record (the install overview's row target).
  - Add a VoiceOver label: `<title> ติดตั้ง กำลังทำ <task> <ช้ากว่าแผน n% | ตามแผน>`.
- The list keeps today's order and filters. An install-phase job counts in `ติดตั้ง`, not in `กำลังสำรวจ`.

## 5. Maintenance rows open the station (`states/02`)
- Each row of the maintenance overview becomes a button (44 pt+, whole row) with a `›` at the end of its last line (17 pt `#9FB3CC`). Pressed state is `#F3F6FA`.
- VoiceOver: `MP n <name> <status> เปิดหน้าสถานี`.
- **Target:** the station page of the board (`reference/PhonePwaStation.dc.html`) is **not built and not in scope**.
  - Open the closest existing screen for that station: the install record or `StationDocsScreen`.
  - Report which one you used. Do not build the station page.

## Check
- [ ] `swift build` + `swift test` in `TCRoofKit/`; xcodebuild with your own `-derivedDataPath`.
- [ ] PWA module shows the main dock with `กปภ.` selected. The dock is hidden on pushed screens. `แผนงาน` pushes the plan. `เอกสาร` / `หน้าหลัก` switch tabs.
- [ ] Header: title, round search, bell with badge opens notifications. Search open/close still animates.
- [ ] Segments + filter. The `ประเภทงาน` rows switch views with the right counts. Reset clears type, status and sort. The active dot shows.
- [ ] Install-phase cards: late (red) and on-plan (blue) look like `states/08`. Survey cards have the `สำรวจ` badge.
- [ ] Maintenance rows are tappable and open a station screen (report which).
- [ ] iPhone home (v4) and the iPad unchanged. `PhoneSurveyUITests` and `HomeNavbarUITests` pass (update the tab names they tap).
- [ ] Simulator screenshots of states 01, 02, 04, 08 in `docs/ui/pwa-solar-survey-iphone-v3/screenshots/`, compared with `states/`. Report the differences.

## Open questions (report, don't decide)
1. **PWA project settings** (`ตั้งค่าโครงการ PWA`, `SurveyHome+Settings`) lost its dock tab. Where should it open from?
   - Suggestion: a row in the main `ตั้งค่า` sheet that shows only while the PWA module is in use.
   - Until the owner decides, put it there and report.
2. The header's `···` menu is not in the board. Which of its actions stay, and where? The sync action is already in PWA settings (`ซิงก์งาน กปภ. ตอนนี้`).
3. When does a job switch from survey to install phase: survey signed off (E1), or install record created? Report what the code uses today.
