# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-request-map && git checkout -b feat/install-tracking-ipad-request-map

Follow docs/ui/install-tracking-ipad-request-map/CLAUDE_CODE_TASK.md.

Scope: the iPad install tracking page's คำขอรายสัปดาห์ tab shows the existing one-page key-plan request
(WeeklyRequestOnePage) under the page's header and tab bar, in place of the R1 form, on widths ≥ 1000 pt.
Work through change list items 1–5 in order, and nothing else:
1. WeeklyRequestOnePage gets embedded: no own header, no page background, 24 pt margins
2. host it through WeeklyRequestScreen(embedded: true) so save / sign / PDF / send stay in one place
3. padBody's .request branch: the embedded one-page at ≥ 1000 pt, requestTab() below
4. hide the dock on this tab so the request's bottom bar sits at the bottom (or above the dock; report which)
5. DEBUG (-installTab request with -installDemo YES) and a test in InstallTrackingUITests

Do not change:
- the one-page request's content, states or logic
- WeeklyRequestStore, the sign / PDF sheets, RoutineReport.WeeklyRequest
- the R1 form (keep it for compact width)
- the iPhone, the other tabs
- stored model fields
- firestore.rules
No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read InstallTrackingPage.swift (padBody, Debug),
InstallTrackingPage+Request.swift, WeeklyRequestScreen.swift (onePage, prepare, weekChoices),
WeeklyRequestOnePage.swift (body, header, bottomBar) and PadTabs.swift (padDock) before writing code.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.

When done:
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run InstallTrackingUITests and WeeklyRequestOnePageUITests on an iPad simulator
- save simulator screenshots named like states/ to screenshots/
- tick the change list and answer the open questions in your report

Commit and push feat/install-tracking-ipad-request-map. Do not merge.
```
