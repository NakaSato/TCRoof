# Claude Code task: iPad home v3: `วันนี้` lists every plan item, segmented feed filter, summary strip, new dock (board update 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/tcroof-home-ipad-v3/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · หน้าหลัก TCRoof` (`iPadMenu.dc.html`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- Every name, number, time, MP, team and count in the previews is **example data**. Never hardcode any of it.

## Scope: change only this list
`PadHome` is built from `docs/ui/tcroof-home-ipad-v2` (commit `1680269`), and its hero became `แผนงานวันนี้` in commit `dbc6cb3`. A text diff of this board against `docs/ui/tcroof-home-ipad-v2/iPadMenu.dc.html` shows **exactly these five changes**. Change only these, on iPad (regular width) only:

1. **`วันนี้` card:** it lists **every** plan item of today (install, inspection, document, test, survey), not only install days and survey appointments. It takes the free height and scrolls.
2. **`งานสำรวจค้างอยู่`:** capped at 2 rows high.
3. **Feed filter:** the chips become a segmented control.
4. **Feed posts:** the coloured category badge next to the author is removed.
5. **Feed post stat tiles:** become one summary strip with icons, coloured values and a progress bar for `x/y` values.

Plus the **dock**, which this board shares with every iPad screen. It is the same change as `docs/ui/pwa-solar-survey-ipad-v3` §1.
- If that hand-off has already been built, **skip the dock**.
- If not, do it here (section 6) and say so, so it isn't done twice.

**Do not touch:**
- the hero (`AppointmentHero`, `แผนงานวันนี้`, from `dbc6cb3`). The board still shows the older `นัดวันนี้` pager there, and the code is ahead. Keep the code.
- the brand header, search and the bell's notification panel
- the feed's posts, order and content, acknowledgements, the issue box, photos and `FeedBuilder`
- the iPhone (`PhoneHome`, `HomeFeed` compact layout, `TCFeedPost` on iPhone)
- data models; add none (see section 1)

**Before editing:** use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep.
- Look at: `PadHome`, `TimelineItem.list`, `TodayTimelineCard`, `PendingSurveysCard`, `HomeFeed` (`chipRow`, `layout: .column`)
- Look at: `TCFeedPost` and `TCFeedTone` in `TCRoofKit/Sources/TCRoofUI/Feed.swift`, `TCCountSegments`, `PadTabs`
- Look at the plan sources: `PWAPlanPhoneView`, `InstallStationSummary`, `InstallOverview`, the IEC test appointments, and the PWA document deadlines (`กำหนดส่ง`)
- Then run `tests_for` on what you touch: `HomeNavbarUITests`, `PhoneHomeFeedUITests` (must still pass unchanged), and any `PadHome` test.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01-home.png` (@2x) |
| `states/01-home.png` | Default: `วันนี้` with the first rows, `งานสำรวจค้างอยู่` 2 rows, segmented feed filter, summary strip on the first post, new dock |
| `states/02-today-scrolled-end.png` | `วันนี้` scrolled to its end: `เอกสาร · MP 189`, `นัดสำรวจ`, `ทดสอบ · MP 77` |
| `states/03-today-test-open.png` | The `ทดสอบ` row opened: `เปิดฟอร์มทดสอบ ›` + navigate + call |
| `states/04-feed-filter-pwa.png` · `05-feed-filter-mine.png` | The segmented filter on `กปภ.` / `ทีมของฉัน` |
| `states/06-left-column-crop.png` | The left column: `วันนี้` (fills, scrolls) and `งานสำรวจค้างอยู่` (2 rows) |
| `states/07-feed-header-crop.png` | `ฟีดโครงการ` header with the segmented filter |
| `states/08-post-summary-strip-crop.png` | A post's summary strip: icons, coloured values, the `8/12` bar; no badge after `TCRoof` |
| `states/09-dock-crop.png` | The dock (only if section 6 applies) |
| `iPadMenu.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule (`TLD`, `fChips`, `rows`) |
| `assets/tc-renewable-icon.png` | The header logo the board uses (already in the app; for rendering the board only) |
| `icons/stat-*.svg` | The strip's three glyphs (15 pt, stroke 2.2): `stat-report` (blue), `stat-trend` (green), `stat-issue` (red) |
| `icons/tab-*.svg` | The dock glyphs (section 6) |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. `วันนี้` lists every plan item (`states/01`, `02`, `03`, `06`)
- **Now:** `TimelineItem.list` builds only install days (`Job.installDay(on:)`) and today's survey appointments.
- **The board:** the card shows all of today's work across the plan, in time order. With the example data that is 8 rows:

  | Time | Tag | Kind | Button when opened | Opens |
  |---|---|---|---|---|
  | 08:00 | `ติดตั้ง · Day 2/5` (home job) | live | `เปิดบันทึกประจำวัน ›` | daily log (as now) |
  | 08:00 | `ติดตั้ง · MP 189` | live | `เปิดบันทึกประจำวัน ›` | that PWA station's daily report |
  | 08:30 | `ติดตั้ง · MP 120` | live | `เปิดบันทึกประจำวัน ›` | the same |
  | 10:30 | `นัดสำรวจ · ถัดไป` | next | `ทำต่อ <step> ›` | the survey (as now) |
  | 10:30 | `ตรวจรับ · MP 154` | later | `เปิดงานตรวจรับ ›` | that station's install record |
  | 13:00 | `เอกสาร · MP 189` | later | `ดูเอกสาร ›` | that station's documents |
  | 14:00 | `นัดสำรวจ` | later | `เริ่มสำรวจ A1 ›` | the survey (as now) |
  | 14:00 | `ทดสอบ · MP 77` | later | `เปิดฟอร์มทดสอบ ›` | that station's IEC 62446 test |

- **Row content:**
  - PWA rows use the MP number in the tag.
  - The name is the plan task, e.g. `2.3 ติดตั้งแผงเซลล์ · ทุ่งน้อย`.
  - The sub line is contractor · team · variance, or place · status.
  - The right-hand text is `กำลังทำ`, a countdown, or `ต้องยื่น` for a document due today.
- **Look:** the same as the existing rows: time, rail dot, card, tag colours by kind (live green, next blue, later grey). Same one-open-at-a-time behaviour, and an opened row shows its button + navigate + call. When an item has no site or phone, hide navigate or call rather than showing a dead button.
- **Default open row:** the `next` item, as now (the board picks it with `findIndex(kind === 'next')`).
- **Subtitle:** `n รายการ · ทุกแผนงาน`.
  - Drop `· ข้อมูลตัวอย่าง`; it is board-only.
  - The empty text becomes `ไม่มีแผนงานในวันนี้`.
- **Sources:** build the extra rows from the plan data that already exists with a date for today:
  - PWA install tasks (MP stations under installation)
  - inspection appointments (`ตรวจรับ`)
  - document deadlines (`กำหนดส่ง` due today)
  - IEC 62446 test appointments

  Use what `PWAPlanPhoneView` already reads for its `ตารางงาน`; it should show the same items for today. **Do not add models.** Report any source that has no model or no date, and leave it out.
- **The hero:** `แผนงานวันนี้` pages through `plan` (built from `timeline`). Decide whether the new item types join the hero too. The board's hero is older, so **report** what you did rather than guessing silently (open question 1). Keep `select(_:)` (a row moves the hero to its page) for items that are in the hero.
- **Layout** (`geo.size.width >= 1000` branch):
  - The `วันนี้` card takes the free height between the hero and `งานสำรวจค้างอยู่`.
  - Its rows scroll inside the card, with no scroll indicator. The card header stays fixed.
  - In the narrow (scrolling page) branch, keep the card at its natural height as now.

## 2. `งานสำรวจค้างอยู่`: 2 rows (`states/06`)
- Its height is capped at **166 pt**: the header and two rows. Rows past two are cut off. `ดูทั้งหมด ›` stays, and opens the list as now.
- It no longer grows to fill the column (it was `flex:1`). Section 1's card takes that space.

## 3. Feed filter: chips → segmented (`states/07`, `04`, `05`)
- On iPad (`HomeFeed` with `layout: .column`), replace the `TCFeedChip` row in the `ฟีดโครงการ` header with **`TCCountSegments`**:
  - **440 pt wide**, right-aligned, track `Theme.track` (#E6ECF3), padding 3, capsule
  - 4 equal segments 38 pt: `ทั้งหมด n` · `กปภ. n` · `งานบ้าน n` · `ทีมของฉัน n`
  - titles 14 pt; the count 12.5 pt bold, `Theme.primary` when selected and `#7A8BA3` otherwise; selected = white with a soft shadow
- This is the same control the iPhone home got in v4. **Reuse it.** The counts, filter rules and `-homeFeedFilter` do not change.
- If `TCFeedChip` is left with no caller, keep it (it is in `ComponentGallery`) and say so.

## 4. Feed posts: no category badge (`states/08`)
- On iPad, the coloured capsule after the author's name (`สรุปวันนี้`, `ปัญหา`, `รายงานวันนี้`, …) is gone. The header row is avatar · who · `where · when` · `···`.
- The owner found the coloured badges and bars hard to read.
- **iPhone keeps its badge.** `TCFeedPost` is shared, so add a parameter, e.g. `showsBadge: Bool = true`, and pass `false` from `HomeFeed` when `layout` is `.column`. Do not change the iPhone look.
- Leave the iPad's 4 pt tone edge as it is: the board is unchanged there.

## 5. Post stat tiles → one summary strip (`states/08`)
- **Before (v2):** three separate coloured tiles per post: value 22 pt over label 12 pt, in the tone's fill.
- **Now:** one strip.
  - **Strip:** `#F8FAFC` fill, 1 pt `#DDE4ED` border, radius 14, 16 pt side margins (as before). Cells are equal width, with 1 pt `#DDE4ED` dividers between them.
  - **Each cell**, padding 10 / 14, 4 pt between lines:
    1. a 15 pt glyph in the tone colour + the label, 12.5 pt `#5B6B82`, one line
       - blue: `icons/stat-report.svg`
       - green: `icons/stat-trend.svg`
       - red: `icons/stat-issue.svg`
    2. the value, **24 pt bold**:
       - red tone and value not `0` → `#B42318`
       - green tone → `#1F6B43`
       - otherwise navy
    3. **only when the value is `x/y`:** a 5 pt bar, radius 3, track `#E3E9F1`, fill `Theme.primary` at `x / y`
- Keep the values, labels and tones the posts already carry. This is a look change only.
- **iPad only.** Branch inside `TCFeedPost` on the same parameter or layout as section 4, and keep the iPhone tiles.

## 6. Dock (only if `pwa-solar-survey-ipad-v3` §1 is not built yet) (`states/09`)
- `หน้าแรก · โครงการ(badge) · งานบ้าน · เอกสาร · เครื่องมือ · สแกน | ตั้งค่า`, with `หน้าแรก` selected on this screen.
- `แผนงาน` and `ติดตั้ง` leave the dock.
- Follow `docs/ui/pwa-solar-survey-ipad-v3/CLAUDE_CODE_TASK.md` §1 exactly: targets, badges, `-homeTab`, and keeping the modules reachable.

## Check
- [ ] Build with your own `-derivedDataPath`. If you touched `TCRoofKit/`, run `swift build` + `swift test` there.
- [ ] Run on an iPad Pro 13" simulator, landscape.
- [ ] `วันนี้`:
  - It shows every plan source that has a model, in time order, and scrolls inside the card.
  - The `next` row is open by default.
  - Each type's button opens the right screen.
  - Say which sources had no model.
- [ ] `งานสำรวจค้างอยู่` is 2 rows high.
- [ ] The segmented filter filters, and its counts match the posts.
- [ ] On iPad, posts have no badge and show the summary strip (`8/12` with its bar).
- [ ] The iPhone home is unchanged. Run the screenshots of `docs/ui/tcroof-home-iphone-v4` states 01 and 05 again and compare them.
- [ ] `HomeNavbarUITests` and `PhoneHomeFeedUITests` pass.
- [ ] Simulator screenshots of states 01, 02, 04 and 08 are in `docs/ui/tcroof-home-ipad-v3/screenshots/`, compared with `states/`. Report the differences.

## Open questions (report, don't decide)
1. Should the new item types (PWA install tasks, inspections, documents, tests) also page in the `แผนงานวันนี้` hero, or stay only in `วันนี้`?
2. Which plan sources had no model or date? They are left out until one exists.
3. `วันนี้` mixes the user's own work with the whole PWA project's plan. Should it filter to the user's team?
