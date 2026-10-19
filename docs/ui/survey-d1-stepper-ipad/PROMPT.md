# Prompt for Claude Code

```
git fetch origin && git switch -c feat/survey-d1-stepper-ipad origin/design/survey-d1-stepper-ipad
```

```
Follow docs/ui/survey-d1-stepper-ipad/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoofKit/Sources/TCRoofUI/Survey/Pages/Tank/TankPageWide.swift with steps, tabBar, tabSegment, stepCircle
- the A2Icons asset d1-step-done

Do ONLY this:
- Restyle D1's sub-step tab bar on iPad (regular width) as the boards' stepper:
  - a white card
  - 26 pt circles (done / current / other)
  - title and status for each step
  - connector lines, green after a done step
  - the current step as a light-blue pill with a blue inset stroke
- Keep the 2 × 2 grid when narrow. Keep steps, tab switching, the sub-step pages and the iPhone step line unchanged.
- Do NOT build the photo page (another branch, design/survey-d1-photo-ipad, does that).

Change list:
1. TankPageWide.swift: tabBar (stepper in regular width), tabSegment, stepCircle (26 pt), and a new stepLine(after:). Keep them split into small views.
2. If Theme has no light-blue selection token, add one (light and dark) instead of a hex, and report it.

Steps:
1. Read the task, then the <nav aria-label="ขั้นย่อยของ D1"> markup and tabOn / tabOff / nOn / nOff / nDone / ln1–3 in any board. Look at states/*.png.
2. Use code-review-graph first (grep if it doesn't connect). Find every use of tabBar and the tabs' accessibility labels in the UI tests.
3. swift test, then xcodebuild with your own -derivedDataPath. Run TankUndoUITests.
4. Take the iPad screenshots 01–04 (-surveyD1 default, tab2, layout, and a tap on step 4) and save them in screenshots/. Compare them with states/.
5. Commit on feat/survey-d1-stepper-ipad and push (no merge).
6. Report: the differences, any token you added, and how narrow and stacked look.
```
