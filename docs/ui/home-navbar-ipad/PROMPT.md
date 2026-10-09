Follow docs/ui/home-navbar-ipad/CLAUDE_CODE_TASK.md

Update the top bar of the iPad home screen to the board in docs/ui/home-navbar-ipad (`boards/iPadMenu.dc.html`, 1366 × 1024). Bar only: wire the existing notifications popover and settings sheet, and don't redesign them. Don't change the iPhone home bar.

1. **Bar.** White, padding 18 / 32 / 16 (91 high), bottom corners 22, 1 pt bottom border, soft shadow, gap 16.
2. **Brand.**
   - Icon 56 × 56, radius 14 (`assets/tc-renewable-icon.png`).
   - `TC` heavy navy + `Roof` bold blue, 27 pt rounded.
   - Under it, a teal 14 × 2 bar + `INTERNAL`, 10.5 pt, tracking 2.4.
3. **Search.** After a flexible spacer: max 600 wide, 52 high, radius 14, light fill and border, magnifier + `ค้นหาเลขที่ ชื่อโครงการ สถานี…`. Tap opens the existing search.
4. **Capsule.** 56 high, radius 28, light fill, holding:
   - **bell**, 52 circle: red unread badge, hidden at 0; when open, light blue fill + 2 pt blue ring
   - **account**, 52 hit area: 42 navy circle with the initials `WC`

   Each button toggles its panel and closes the other.

**Open questions (use the defaults):**
- Search becomes a tappable field that presents the existing search.
- Initials come from the user's name, falling back to the username.

**Rules.**
- Thai text exactly as shown; all values are example data (`assets/sample-data.json`).
- No hex in views; add named `Theme` tokens if needed.
- Targets ≥ 44 pt.
- Layout only.
- Use code-review-graph first, then read the source.
- Branch `feat/ipad-home-navbar`.

**Verify.**
- Build and run `swift test`.
- Compare an iPad Pro 13" simulator in landscape with `states/01`–`04` (measure in `states/01-full-page.pdf`).
- Check portrait and that iPhone is unchanged.
- Finish with a summary of the files changed, your open-question choices and any remaining differences.
