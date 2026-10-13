# Claude Code task: iPhone home v4 — `เอกสาร` tab, `แผนงานถัดไป` fallback, segmented feed filter (board update 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/tcroof-home-iphone-v4/CLAUDE_CODE_TASK.md`

Board: `iPhone · หน้าหลัก TCRoof` (`PhoneMenu.dc.html`, 390 × 844). Thai strings in `backticks` are literal UI labels.
Every name, number, date and team in the previews is **example data**; never hardcode it.

## Scope: change only these three things

v3 (`docs/ui/tcroof-home-iphone-v3`) is built: `PhoneHome`, `AppointmentHero`, `HomeFeed` / `TCFeedPost` / `TCFeedChip`,
`PhoneTabs` + `TCTabBar`. The board differs from v3 in **exactly three places** (a diff of the two `PhoneMenu.dc.html`
files shows nothing else). Change only these, on iPhone (compact) only:

1. **Dock: the 4th tab `เครื่องมือ` becomes `เอกสาร`.**
2. **No survey appointment today: the hero shows `แผนงานถัดไป`.** In v3 it was hidden.
3. **Feed filter: the chip row becomes a segmented control.**

**Do not touch:**
- the header (logo, bell, notification panel)
- the feed posts, acknowledgements, the issue box, `FeedBuilder` and the post order
- the dock's look, size, badge and fade
- the hero when there *are* appointments today
- the iPad (`PadHome`, `PadTabs`)
- the PWA module's own dock (`PWAPhoneTabs`)

Before editing, use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep. Look at:
- `PhoneTabs`, `PhoneTab`, `TCTabItem`, `ToolsView`, `PWAPhoneTabs` (its `.docs` tab), `StationDocsScreen`
- `PhoneHome`, `AppointmentHero`, `HeroItem`, `TimelineItem`, and `PadHome.plan` (the iPad's `แผนงานวันนี้` hero, commit `dbc6cb3`)
- `HomeFeed.chips` / `chipRow`, `TCFeedChip`, `TCCountSegments` (`TCRoofKit/Sources/TCRoofUI/Overview.swift`)

Then run `tests_for` on what you touch (`HomeNavbarUITests`, `PhoneHomeFeedUITests`, `PhoneSurveyUITests`).

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01-home.png` (@2x) |
| `states/01-home.png` | Appointments today: `นัดวันนี้` hero (unchanged), then the segmented filter and the feed |
| `states/02-no-survey-plan-1.png` | No survey today: `แผนงานถัดไป` 1/3, an install task, button `ดูแผนงาน ›` |
| `states/03-no-survey-plan-2.png` | 2/3, an IEC test, button `เปิดฟอร์มทดสอบ ›` |
| `states/04-no-survey-plan-3.png` | 3/3, a document deadline, button `ดูเอกสาร ›` |
| `states/05-feed-filter-pwa.png` · `06-…-home` · `07-…-mine` | The segmented filter on `กปภ.` / `งานบ้าน` / `ทีมของฉัน` |
| `states/08-dock-crop.png` | The dock close-up with `เอกสาร` in 4th place |
| `states/09-feed-filter-crop.png` | The segmented filter close-up |
| `states/10-docs-tab-target.png` · `PhonePwaDocsV2.dc.html` | The page the `เอกสาร` tab opens (for reference: not in this task's scope beyond the link) |
| `PhoneMenu.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule |
| `assets/tc-renewable-icon.png` | The header logo the board uses (already in the app; for rendering the board only) |
| `icons/tab-docs.svg` | The `เอกสาร` glyph: a document with a tick, 24 pt, stroke 2.1 (the same drawing as the existing `tab-docs` asset) |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. Dock: `เครื่องมือ` → `เอกสาร` (`states/08`)
- In `PhoneTabs`, the 4th `TCTabItem` becomes title `เอกสาร`, VoiceOver `เอกสาร`.
- **Glyph:** asset `tab-docs`. It is already in `Assets.xcassets` (used by `PWAPhoneTabs`); compare it with `icons/tab-docs.svg` and add nothing if they match.
- **Opens:** the PWA document overview `เอกสาร PWA`. In the board this is `PhonePwaDocsV2.dc.html`, see `states/10-docs-tab-target.png`. It has three panes: `ตามสถานี` · `ต้องทำ` · `คลังกลาง`, an approved-count summary and per-station step rows. The owner confirmed it on 14 ต.ค.: "this is the เอกสาร page". It is **not** the residential `HomeLibraryView`.
  - That overview is **not built yet**. The code has only the per-station `StationDocsScreen`, which `PWAPhoneTabs`' `เอกสาร` shows.
  - For this task, make the tab open what the PWA module's own `เอกสาร` tab opens today, so both docks lead to the same place.
  - Building the cross-station overview is a separate hand-off, so do not build it here. Report what the tab opens.
  - Rename the case `PhoneTab.tools` → `.docs`, and update the `-homeTab` DEBUG value (`home|homework|pwa|docs`) in CLAUDE.md line ~79 and any UI test that taps `เครื่องมือ`.
  - On the `เอกสาร` page the main dock shows `เอกสาร` selected; `กปภ.` is not selected there.
- **Badge:** none on `เอกสาร` in the board. The calibration-due badge left with the tools tab.
- **Do not delete `ToolsView` or its modules.** The `เครื่องมือ` tab also carried the plan calendar, scan and install rows (CLAUDE.md line 79).
  - Until the owner decides, keep them reachable with one row `เครื่องมือวัด` in the settings sheet (`PhoneSettings`). The row carries the calibration-due count and pushes `ToolsView(modules: [.plan, .scan, .install])`.
  - Report where you put it (open question 1).

## 2. No survey today → `แผนงานถัดไป` (`states/02`–`04`)
- When today has no survey appointment (`shown.isEmpty` in `PhoneHome`, or `-homeNoAppointments YES`), **show the hero**, with:
  - title `แผนงานถัดไป` instead of `นัดวันนี้`
  - VoiceOver label `แผนงานถัดไป · ไม่มีนัดสำรวจวันนี้`
  - pager buttons read `แผนงานก่อนหน้า` / `แผนงานถัดไป`
- **Pages:** the next upcoming plan items after now, the nearest first. Show at most 3 pages, with dots and `‹ ›` as in v3.
  - Each page is a `HeroItem`: time 24 pt, kind (`ติดตั้ง · พรุ่งนี้`, `ทดสอบ · พรุ่งนี้`, `ยื่นเอกสาร · อีก 2 วัน`), name, place/sub line, and the ring = that job's progress %.
  - **Reuse `AppointmentHero` with `title:`.** Do not build a second card. Build the items the way `PadHome.plan` / `TimelineItem.heroItem` do.
- **Top-right text:** the item's own date + position, e.g. `พฤ 1 ต.ค. · 1/3`. With appointments it stays today's date (`พุธ 30 ก.ย. · 1/2`).
- **Sources:**
  - install days ahead (the plan calendar's install bars / `TimelineItem` with `isInstall`)
  - IEC 62446 test appointments
  - PWA document deadlines (the PWA plan's `กำหนดส่ง`)

  Use whichever of these already have a model with a date. Report any that has none, and do not add models for it in this task.
- **Primary button, by type:**

  | Type | Button | Opens |
  |---|---|---|
  | install | `ดูแผนงาน ›` | the plan calendar on that day |
  | test | `เปิดฟอร์มทดสอบ ›` | the IEC test of that station |
  | document | `ดูเอกสาร ›` | that station's documents |

  Navigate and call stay as in v3, using the job's site and phone.
- **Nothing upcoming at all:** hide the card as v3 did (no empty state).
- Add DEBUG `-homeHeroPlan demo`: with `-homeNoAppointments YES`, it seeds the three example plan items, dated from tomorrow. Add it to CLAUDE.md next to `-homeNoAppointments`.

## 3. Feed filter: chips → segmented (`states/09`)
- Replace the horizontal `TCFeedChip` row on iPhone with **`TCCountSegments`**: equal widths, 4 segments `ทั้งหมด n` · `กปภ. n` · `งานบ้าน n` · `ทีมของฉัน n`.
  - It is the PWA home's control, already matching the board:
    - track `Theme.track` (#E6ECF3), padding 3, capsule
    - segments 38 pt, selected white with a soft shadow
    - title 13 pt, count 12 bold; the count is `Theme.primary` when selected, `inkMuted` otherwise
  - No horizontal scroll; the row spans the content width (358 pt).
- **The rules do not change:** the counts, filter rules and `-homeFeedFilter all|pwa|home|mine` stay as they are. Map the selection index to the existing filter enum.
- The iPad column header (`layout: .column`) keeps its chips. **Change iPhone only.** If `chipRow` is shared, split it rather than changing the iPad.
- If `TCFeedChip` is left with no caller, keep it (it is in `ComponentGallery`) and say so.

## Check
- [ ] Build with your own `-derivedDataPath`. `swift build` + `swift test` in `TCRoofKit/` if you touched it.
- [ ] Dock shows `หน้าหลัก · งานบ้าน · กปภ.(badge) · เอกสาร | ตั้งค่า`. `เอกสาร` opens the PWA module's docs screen (report which). The tools modules are still reachable (say where).
- [ ] `-homeNoAppointments YES -homeHeroPlan demo` shows `แผนงานถัดไป` with 3 pages and the right buttons. With appointments the hero is unchanged.
- [ ] The segmented filter filters, the counts match the posts, and each segment's hit area is ≥ 44 pt (the track padding counts).
- [ ] iPad home and the PWA module unchanged. `HomeNavbarUITests`, `PhoneHomeFeedUITests` pass (update tab names they tap).
- [ ] Simulator screenshots of states 01, 02, 05 and 08 in `docs/ui/tcroof-home-iphone-v4/screenshots/`, compared with `states/`. Report the differences.

## Open questions (report, don't decide)
1. Where should `เครื่องมือวัด` (calibration, plan calendar, scan, install) live now that its tab is `เอกสาร`? The settings row is temporary.
2. When should the cross-station `เอกสาร PWA` overview (`PhonePwaDocsV2`) be built? Until then the tab opens the PWA module's docs screen.
3. `แผนงานถัดไป`: should it look only at the user's own team, and how far ahead (the board shows the next 2 days)?
