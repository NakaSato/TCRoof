# Prompt for Claude Code (FIX-01)

```
git fetch origin && git switch -c feat/tcroof-home-ipad-v3-fix01 origin/design/tcroof-home-ipad-v3-fix01
```

```
Follow docs/ui/tcroof-home-ipad-v3/FIX-01-time-and-feed-edge.md.

FIRST check that both of these exist. If either is missing, STOP and report.
- TCRoof/Views/Home/PadHome.swift, with TimelineItem.list and its install loop.
- TCRoofKit/Sources/TCRoofUI/Feed.swift, with the iPad "tone.accent.frame(width: 4)" overlay.

Change ONLY these two things on the iPad home:
1. In วันนี้, an install day whose installStart has no time of day (00:00) reads "ทั้งวัน", sorts first and says
   "กำลังทำ". Reuse the plan rows' "ทั้งวัน" path in the same file. A real start time stays as it is.
   Check the iPhone hero and the PWA plan for the same 00:00; fix them only if they show it, and report.
2. Remove the iPad feed post's 4 pt coloured left edge. Keep the board's 16 pt content inset, so the summary
   wraps as on the board. The iPhone card is unchanged.

Do not touch:
- the hero
- the default open row
- the dock, search, งานสำรวจค้างอยู่, or the feed's data and filters

Steps:
1. Read the FIX file and the two crops (fix01-*.png).
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run PhoneHomeFeedUITests and HomeNavbarUITests.
4. On an iPad Pro 13" simulator, run with -screen home -homeDemo YES -homeFeed demo -homeBoard YES.
   Save screenshots/fix01-01-home.png and compare it with states/01-home.png.
5. Commit on feat/tcroof-home-ipad-v3-fix01 and push it (no merge).
6. Report:
   - before / after
   - whether the iPhone or the plan had 00:00
   - the open question
```
