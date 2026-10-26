# Claude Code task: iPad install tracking `ความคืบหน้าเทียบแผน` card, milestones, weather and billing rows

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-progress-card` and type
> `Follow docs/ui/install-tracking-ipad-progress-card/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** It is the iPad overview's plan card (`progressCard`) only. Do not refactor, rename or
restyle anything outside the change list in §5. Do not touch:

- the KPI strip, the documents / site row (`siteRow`), the other tabs
- the S-curve (`InstallCurveChart`), except that its card keeps the same header
- the iPhone page (`InstallTrackingPage+PhoneProgress.swift`): reuse its milestone strip, don't change it
- Firestore rules and sync, beyond the one optional settings field of §5 item 3

**Example data.** The card's dates, stages, weather, milestones and billing steps are the board's examples
(`assets/sample-data.json`). Never hard-code them.

## 1. Context

- The iPad overview's `progressCard` (`TCRoof/Views/Install/Tracking/InstallTrackingPage+Progress.swift`) draws the
  header (title, span line, `forecastPill`, legend, `Gantt | S-Curve`), the day axis (`InstallAxis`), the stage rows and
  their sub-tasks (`InstallGantt`), and the S-curve.
- Three parts of the board's card are missing on iPad:
  1. **`เหตุการณ์สำคัญ`**: a row of milestone diamonds under the stages, and `◆ เหตุการณ์สำคัญ` in the legend. The
     comment in `ganttLegend` says there are no milestones to point at, but `InstallPlan.milestones` exists now and the
     iPhone draws them (`milestoneStrip`, `MilestoneDiamond`).
  2. **Weather on the day axis**: under each day an icon, and for today and later the chance of rain
     (`☀ 10%`, `☂ 70%`, red when high), with `พยากรณ์อากาศ · อัปเดต …` under `ขั้นตอน` on the left.
  3. **`งวดเบิกเงิน`**: a row under the milestones with the payment steps on their days (`งวด 1 · 40%` and its state:
     `วางบิลแล้ว`, `ทดสอบผ่าน`, `ส่งมอบ`).
- The iPhone says the weather row and `งวดเบิกเงิน` "have no source". This task gives them one (§4), on iPad only.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `InstallTrackingPage+Progress` (`progressCard`, `progressHeader`, `ganttLegend`, `ganttGrid`, `InstallAxis`,
  `InstallBars`, the axis header)
- `InstallTrackingPage+PhoneProgress` (`milestoneStrip`, `ganttFooter`), `MilestoneDiamond` (`+Plan.swift`)
- `InstallPageData` (`plan`, `InstallPlan.milestones`, how the gantt is built), `InstallPlan+Demo`
- `RoutineReport.Daily.weather`, `RoutineReport.weatherHours`, `RoutineReport.Settings`
- `tests_for` on them, plus `InstallTrackingUITests`

Then open `iPadInstall.dc.html` as text: the card is the `<section …height:{{ganttH}}px…>` in the `{{isOv}}` section;
`WX` (weather), `M` (milestones) and `BL` (billing) are its data in `renderVals()`.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadInstall.dc.html`, `grf.css` | The board (the whole install page; this task is its `ความคืบหน้าเทียบแผน` card) |
| `preview.png` = `states/01-gantt-default.png` | The card: weather under the days, stages 4–5 open, milestones and billing rows. @2x |
| `states/02-gantt-collapsed.png` | Every stage closed |
| `states/03-scurve.png` | `S-Curve` (unchanged; same header) |
| `states/04-gantt-rows-scrolled.png` | The stage rows scrolled inside the card; axis, milestones and billing stay put |
| `states/00-page-context.png` | The whole page, for where the card sits |
| `assets/sample-data.json` | The board's example values |
| `screenshots/` | Put your simulator screenshots here, named like `states/` |

## 4. The three rows

### 4.1 `เหตุการณ์สำคัญ`

- Under the stage rows (outside their scroll), a row 44–52 pt high: the label `เหตุการณ์สำคัญ` in the name column, then a
  diamond on each milestone's day with its title under it; filled navy once passed, outlined before.
- Source: `InstallPlan.milestones`, as the iPhone. Reuse `MilestoneDiamond` and the iPhone's layout of the strip; if you
  factor the strip into a shared view, the iPhone must look the same.
- Add `◆ เหตุการณ์สำคัญ` to `ganttLegend` when there is at least one milestone, and fix its comment.

### 4.2 Weather under the days

- Under each day label in the axis header, one line: an icon and, for today and later days, the chance of rain.
- **Past days and today:** from that day's daily report weather (`Daily.weather`, the 06:00–20:00 slots): `☂` (with
  `ฝน` for a past day) when any slot is rain, `⛅` when most are cloud, `☀` otherwise; nothing when there is no report.
- **Future days:** a forecast. The app has no forecast source today. Add a small optional input,
  `InstallPlan.forecast: [Date: DayForecast]` (icon kind and rain %), filled by nothing in this task except the DEBUG
  demo (`-installDemo YES`, the board's values), and say in your report what source you'd suggest (§7 Q1). A day with no
  forecast shows nothing.
- Rain ≥ 60 % in `Theme.dangerText` with an up arrow, as the board; else `Theme.primary`.
- Under `ขั้นตอน`, a second line `พยากรณ์อากาศ · อัปเดต <time>` only when a forecast is present.
- Use SF Symbols (`sun.max`, `cloud.sun`, `cloud.rain`), not emoji.

### 4.3 `งวดเบิกเงิน`

- Under the milestones, a row 32–36 pt: the label `งวดเบิกเงิน` in the name column, then each step centred on its day:
  a small round `฿` badge, `งวด n · p%`, and its state in its tone (billed: `Theme.primary`, paid: `Theme.successInk`,
  pending: `Theme.inkMuted`).
- Source: a new optional list on the station's routine settings, `RoutineReport.Settings.billing: [BillingStep]`
  (`title`, `percent`, `date`, `state` `pending | billed | paid`, `note`), decoded with `decodeIfPresent` (empty by
  default). The row is hidden when the list is empty. Editing the list is not part of this task (§7 Q2); the DEBUG demo
  fills the board's three steps.
- The board labels the row `งวดเบิกเงิน (ตัวอย่าง)` because its values are examples; the app shows `งวดเบิกเงิน`.

### 4.4 Heights

The stage rows keep scrolling inside the card; the axis header (now with the weather line) and the two new rows are
fixed. The card's total height doesn't change (`fittedHeight`); the rows area gets what is left.

## 5. Change list

Do these in order, and nothing else.

1. **Milestones row + legend** (§4.1), sharing the iPhone's strip where possible.
2. **Weather line** in the axis header (§4.2): a pure helper that turns a `Daily`'s slots into a day icon
   (`RoutineReport.dayWeather(_:)` in TCRoofCore, with tests: all fine, mostly cloud, one rain slot, no report), the
   optional `InstallPlan.forecast`, and the header line.
3. **Billing row** (§4.3): `RoutineReport.BillingStep` and `Settings.billing` in TCRoofCore with an old-JSON decode test,
   `InstallPlan.billing` filled from it, and the row.
4. **DEBUG demo:** `-installDemo YES` fills the forecast and the billing steps with `sample-data.json`'s values (in
   memory, nothing saved), so the card matches the board.
5. **UI test:** in `InstallTrackingUITests`, check that `เหตุการณ์สำคัญ` and `งวดเบิกเงิน` exist on `-installDemo YES`
   and that a stage row still opens and closes.

## 6. Rules and check list

- Colours from `Theme`, no hex literals or `Color.white`; text sizes from the card's existing fonts.
- Hit areas ≥ 44 pt for anything tappable (nothing new here is tappable unless you make a milestone open its paper; don't).
- Old job JSON decodes unchanged (`Settings` without `billing`).
- [ ] `swift test` in `TCRoofKit` passes, with the new tests.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath` (in the background).
- [ ] Simulator screenshots at 1366 × 1024 (`-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES`,
      and with `-installView curve`) cropped to the card and saved to `screenshots/` named like `states/`, compared side
      by side.
- [ ] `InstallTrackingUITests` passes; the iPhone's `PhoneInstallTrackingUITests` still passes.
- [ ] Every item of §5 ticked in your report.

## 7. Open questions (answer in your report; do not block on them)

1. **Forecast source.** Which service should fill `InstallPlan.forecast` (WeatherKit, TMD, Open-Meteo), how often, and
   should it sync or stay on the device?
2. **Billing steps.** Where should a manager enter them: `ตั้งค่าโครงการ` on the install page, or the MP plan's
   settings? Should `ทดสอบผ่าน` / `ส่งมอบ` come from the IEC test and the hand-over automatically?
3. **More milestones.** The board shows `ยื่นขนานไฟ` and `RFI-01…03`; the app's milestones are the start, the
   pre-commissioning test and the hand-over. Should papers from `StationDocs` (grid submission, RFIs) add milestones?
