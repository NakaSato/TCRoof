# Claude Code task: iPad home v2 — feed + floating dock (board update 13 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-home-ipad-v2/CLAUDE_CODE_TASK.md`

Board: `iPad · หน้าหลัก TCRoof` (`iPadMenu.dc.html`, 1366 × 1024 landscape). Thai strings in `backticks` are literal UI
labels. Names, numbers and posts are **example data** (`assets/sample-data.json`).

## Scope — change only these four things

The iPad home is already built (`TCRoof/Views/Home/PadHome.swift`, from `docs/ui/tcroof-home-ipad` and
`docs/ui/home-navbar-ipad`). **Do not rework** the hero `นัดวันนี้`, the `วันนี้` timeline, `งานสำรวจค้างอยู่`, the
notification panel or the settings sheet — they match the board. Only:

1. **Right column: six module rows → `ฟีดโครงการ`** (the project feed)
2. **New floating dock** at the bottom (8 buttons)
3. **Navbar: remove the account avatar** (settings moves to the dock)
4. **Two small fixes** (hero title one line; `ดูทั้งหมด` target)

Before editing, use code-review-graph (per `CLAUDE.md`) on: `PadHome`, `HomeBrandHeader`, `ModuleRow`, `HomeFeed`,
`TCFeedPost` / `TCFeedChip` / `TCIssueBox` (`TCRoofKit/Sources/TCRoofUI/Feed.swift`), `TCTabBar`, `PhoneTabs`,
`AppModule`; then `tests_for` on what you touch (`PhoneHomeFeedUITests`, `HomeNavbarUITests`).

## 1. `ฟีดโครงการ` replaces the module rows (`states/01`, `02`, `03`, `08`)

- **Reuse the iPhone feed.** `HomeFeed` (TCRoof/Views/Home/HomeFeed.swift) + `TCFeedPost` and the `ProjectFeed` /
  `FeedBuilder` data already exist for iPhone v3. Put the same feed in PadHome's right column; do not build a second feed.
  Add a `size: .pad` (or width-driven) variant only where the board's sizes differ.
- **Header row** (not scrolling): `ฟีดโครงการ` 20 bold navy · green pill `● อัปเดตล่าสุด 18:00` (12.5, `#1F6B43` on
  `#E8F5EE`) · right-aligned chips `ทั้งหมด 5` `กปภ. 4` `งานบ้าน 2` `ทีมของฉัน 3` (height 40, radius 20; selected navy
  fill + white text, count in a translucent 18 pt pill; others white with `#DDE4ED` border). Filter rules as the iPhone
  feed: `กปภ.` = PWA posts + project-wide; `งานบ้าน` = home posts + project-wide; `ทีมของฉัน` = the signed-in user's teams.
- **Post list** scrolls inside the column (gap 14). Post card (white, radius 18, border `#DDE4ED`, 4 pt left accent in the
  badge tone): avatar 40 · `who` 16 bold + tone badge · `where · when` 13 muted · `···` menu; body text 16;
  then one of: stat tiles (3 equal, radius 10), photo (radius 14, `1/4` counter top-right, chips bottom-left), or
  `TCIssueBox` (owner / due / `ยังค้าง` red ⇄ `แก้แล้ว ✓` green + `แก้แล้ว` / `เปิดอีกครั้ง` button);
  acknowledgement faces + `N คนรับทราบ`; two buttons 46 high: `รับทราบ` (toggles; on = `#E3EEF8`/primary) and
  `ดูสรุป ›` / `ดูงาน ›` … (`#EEF4FB`, primary). Footer `ดูโพสต์ก่อนหน้า`.
- Empty filter: reuse the iPhone feed's empty state.

## 2. Floating dock (`states/07-dock-crop.png`)

- Centred, 18 pt above the bottom, radius 28, padding 6, background white 96% + blur, border `#C9D3E0`.
  Buttons 84 × 58, radius 20, icon 24 + label 11.5 (selected: navy `#16325C` fill, white, label 800).
- Order: `หน้าหลัก` · `สำรวจ` (red badge = today's appointments) · `แผนงาน` · `ติดตั้ง` · `สแกน` · `กปภ.` · `เครื่องมือ` |
  1 pt divider | `ตั้งค่า` (opens the existing settings sheet — the action the avatar had).
- **Build it from `TCTabBar`** (the iPhone dock) with an iPad size; add it to `ComponentGallery`. Behaviour like
  `PhoneTabs`: one `NavigationStack` per tab, the dock on each tab's root screen only, hidden when a screen is pushed.
  If a per-tab stack conflicts with the current iPad navigation, keep `หน้าหลัก` as the only stack and make the
  module buttons push `module.destination` — and say which you chose in the report.
- Content keeps clear of the dock: bottom inset 100 pt (board `padding-bottom:100px`), with the page colour fading
  behind it like the iPhone (`PhoneTab.fade`).

## 3. Navbar (`states/06-navbar-crop.png`)

`HomeBrandHeader(size: .pad)`: remove the account avatar button. The capsule holds only the bell (52 pt) with its
unread badge. Brand + search field unchanged. Keep VoiceOver: settings is now reached from the dock's `ตั้งค่า`.

## 4. Small fixes

- Hero (`AppointmentHero`, pad): the job title is **one line** with tail truncation (was two lines).
- `งานสำรวจค้างอยู่` → `ดูทั้งหมด ›` opens the survey home (the `สำรวจ` tab), not the old survey list.

## Layout

Columns at ≥ 1000 pt: left 2 : right 3 (board `grid 2fr 3fr`, gap 20, side padding 32; ≈ 513 pt left at 1366 —
keeping the current 520 is fine). The narrow (< 1000 pt) stacked layout: feed below the left cards; dock unchanged.

## Check

- [ ] Right column is the feed (header row fixed, list scrolls); no module rows left on iPad
- [ ] Chips filter; `รับทราบ` toggles with count; issue `แก้แล้ว` ⇄ `เปิดอีกครั้ง`
- [ ] Dock: 8 buttons, `สำรวจ` badge, `ตั้งค่า` opens settings; hidden on pushed screens
- [ ] No avatar in the navbar; bell panel still opens
- [ ] iPhone unchanged (`PhoneTabs`, `PhoneHome`); `PhoneHomeFeedUITests`, `HomeNavbarUITests` pass (update the navbar
      test for the removed avatar)
- [ ] Build with your own `-derivedDataPath`, run on an iPad Pro 13" simulator (landscape), screenshots of states 01,
      02, 04, 05 in `docs/ui/tcroof-home-ipad-v2/screenshots/`, compared with `states/`; report differences

## Open questions (report, don't decide)

1. Should the module rows be kept anywhere on iPad (e.g. portrait), or is the dock enough?
2. Feed acknowledgements are still device-local (`FeedAcks`, see iPhone v3 open question 2).
