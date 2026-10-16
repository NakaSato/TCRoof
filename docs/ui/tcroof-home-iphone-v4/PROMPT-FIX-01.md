# Prompt for Claude Code (FIX-01)

```
git fetch origin && git switch -c feat/tcroof-home-iphone-v4-fix01 origin/design/tcroof-home-iphone-v4-fix01
```

```
Follow docs/ui/tcroof-home-iphone-v4/FIX-01-hero-date.md.

FIRST check that TCRoof/Views/Home/HomeParts.swift formats the hero date with ThaiFormat.weekdayShort
(the line "ThaiFormat.weekdayShort.string(from: current?.date ...)"). If it doesn't, STOP and report.

Change ONLY the hero card's date label (iPhone and iPad):
1. Use the short Thai weekday ("EEEEEE d MMM", e.g. "พฤ. 1 ต.ค."). Move NewJobFormat.weekdayDayMonth into
   ThaiFormat as weekdayTiny and use it in both places. Keep weekdayShort as it is.
2. Draw the date and " · n/m" as two Texts. The counter has a higher layoutPriority and never truncates.
3. Keep a full VoiceOver label: "<full weekday> d MMMM · รายการที่ n จาก m".

Do not touch the rest of the hero, the feed, the dock or other screens.

Steps:
1. Read the FIX file and look at fix01-hero-date.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run PhoneHomeFeedUITests.
4. iPhone 16 simulator:
   a. Run with -screen home -homeDemo YES -homeNoAppointments YES -homeHeroPlan demo, then with
      -screen home -homeDemo YES.
   b. Save screenshots/fix01-02-no-survey-plan-1.png and fix01-01-home.png.
   c. Check an iPhone SE width too.
5. Commit on feat/tcroof-home-iphone-v4-fix01 and push it (no merge).
6. Report:
   - before / after
   - the weekday form chosen
   - the open question
```
