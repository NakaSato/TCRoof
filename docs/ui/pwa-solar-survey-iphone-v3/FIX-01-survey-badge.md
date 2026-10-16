# Fix 01: iPhone PWA home v3, survey card badge (14 ต.ค. 2569)

**Done 14 ต.ค. 2569.** `badge` is out of `JobCard`'s survey branch; `JobCard` has one layout, so the iPad got it too (`docs/ui/pwa-solar-survey-ipad-v3/FIX-01-ipad-rows-popover.md` §4).

Paste into Claude Code in the TCRoof repo:

```
Fix one difference between the built iPhone PWA home v3 and its board (docs/ui/pwa-solar-survey-iphone-v3).

Survey cards in the project list must show only the blue "สำรวจ" badge after the job number. Today they also show
the "ยังขาด n ช่อง" / "ครบ" / "ร่าง" capsule. Compare screenshots/01-projects.png (built) with states/01-projects.png (board).

Change ONLY this:
- In TCRoofKit/Sources/TCRoofUI/Survey/Home/JobCard.swift, the header HStack's survey branch (around line 47) shows
  `surveyBadge` followed by `badge`. Remove `badge` from that branch, so it shows `surveyBadge` alone.
- Do not touch the other branches:
  - `.locked` keeps `badge` + `lockBadge`
  - `.install` and `phaseBadge` are unchanged
- Keep the `badge` view itself if `.locked` or anything else still uses it.
- The missing count stays visible on the card through the orange caps and the group tags (e.g. "B ระบบไฟฟ้า ×5").
  Do not add it elsewhere.

Before editing:
- Check with code-review-graph (or grep) which layouts use this header branch.
- If the iPad's regular-width card shares it, ask before changing the iPad. The iPad is a separate hand-off
  (docs/ui/pwa-solar-survey-ipad-v3).

Check:
- Build with your own -derivedDataPath and run the iPhone simulator with -surveyHomeDemo cards.
- Replace docs/ui/pwa-solar-survey-iphone-v3/screenshots/01-projects.png and compare it with states/01-projects.png.
- PhoneSurveyUITests passes. Update any test that looks for "ยังขาด" on a survey card.
- Report what else, if anything, still differs from states/01.
```
