# iPad A1 ข้อมูลโครงการ · parity check against the board (v2)

Board: `iPadA1.dc.html` (open it in a browser next to `grf.css`). The states in `states/` are @2x of 1366 × 1024:

- `01-landscape.png`: the whole page.
- `02-crop-moved.png`: the report frame moved and resized.
- `03` to `05`: the bottom bar's save button while saving, just saved, and saved idle.

`preview.png` is state 01 at 1 ×. Example values are in `assets/sample-data.json`. They are examples; never hard-code them.

## 1. Why this exists

The board `iPad · ขั้น 1/13 A1 ข้อมูลโครงการ` is the same design that `docs/ui/survey-a1-ipad` described. That task is built on `main`:

- `InfoPageWide.padBody` / `padBar`
- `RatioRow` rows 0.8 : 0.6 : 1.35 : 1.25, 1 : 1 and 1.4 : 1
- the merged `โครงการ | ผู้ประสานงาน` card
- the generalised `SaveButton` with `-surveySave`
- `MapCrop`, `รีเซ็ตกรอบ`
- GPS accuracy through `GPSGrade.note`
- the area tiles

This branch is **not** a redesign. It is a pixel-parity pass:

1. Render the page in the simulator.
2. Compare it with `states/`.
3. Fix only the differences you can measure.

If the page already matches, the result is a report and no code change.

## 2. Scope

**In scope:**

- iPad A1 regular width only:
  - `InfoPageWide.padBody`, its sections in `InfoPageWide+Sections.swift`
  - `InfoPageBar.padBar`

**Out of scope. Do not touch:**

- iPhone A1 (`InfoPageWide+Phone.swift`, `phoneBody`)
- `SaveButton`'s behaviour
- `Schema.info` ids, labels and storage
- `mapZoom` / `mapCrop`
- Excel / PDF output
- A1 completion counts
- Other pages and the header bar (`SurveyHeader`, shared by every page)

**Text differences that are intentional. Keep them:**

| Board | App | Reason |
|---|---|---|
| `·` separators, e.g. `หน้า C · หลัง` | `|` | The repo switched every separator in commit c6f9c8b5 |
| `ความแม่นยำ ±5 ม. · บันทึกเมื่อ 09:41` | `GPSGrade.note` | Live wording from the GPS grade |
| `500 / 200 / 50 ม.` zoom chips | The app's zoom presets from settings | |
| `ที่อยู่สำนักงาน / สาขา` | Left out of the iPad layout | Open question 1 of the earlier task, already decided |

## 3. Read first

Start with the code-review-graph tools, as CLAUDE.md says. Then read:

- `InfoPageWide.swift`
- `InfoPageWide+Sections.swift`
- `A1Card`, `RatioRow`, `inputBox`, `areaTile`
- `InfoPageBar.padBar`
- `SaveButton` in `BottomBar.swift`
- `JobEditor+Debug.renderInfo` (`-surveyA1Render YES`)
- `docs/ui/survey-a1-ipad/CLAUDE_CODE_TASK.md`, the original spec. Its measurements still apply.

## 4. Change list (in order)

1. **Render.** On an iPad Pro 13" simulator, take screenshots of these states and save them to `screenshots/` with the same names as `states/`:
   - `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES` (landscape layout): the page (01)
   - the report frame after a drag (02)
   - `-surveySave saving|saved|clean` (03–05)

   Also write `-surveyA1Render YES`'s offscreen 1366 render (`Documents/a1-1366x….png`).
2. **Compare.** Compare each screenshot with `states/` at the same scale. Make a table in your report: element, board value, app value, difference.

   Measure at least these:
   - Column split: location card 720 pt, gap 20.
   - Card padding 16 / 18 and radius 12.
   - Card title size: the board is 18 semibold.
   - Label size: the board is 17 / 22 semibold with a red `*`.
   - Input height 50, radius 12.
   - The map's minimum height, and that it fills its card.
   - The hint row under the map, with `รีเซ็ตกรอบ` on the right.
   - The GPS row: the locate button at least 50 high.
   - Area tiles: 60 high, fill and border, 22 pt checkbox, − / + with 44 pt targets.
   - Bottom bar: badge and status line, save button 170 × 56, nav buttons 210 and 250.
3. **Fix** only rows of that table with a visible difference (≥ 2 pt, or a different colour, weight or wrapping). Use `Theme` / `Home` tokens and the existing components. No new hex literals, and hit areas stay ≥ 44 pt.
4. **Re-take** the screenshots after the fixes, and put the before/after pairs in the report.

## 5. Rules

- Thai text exactly as on the board, except the intentional differences in §2.
- Run `swift test` in `TCRoofKit`, including `MapCropTests`.
- Build the app with xcodebuild, with your own `-derivedDataPath`, in the background.
- iPhone A1 must look the same before and after. Take one iPhone screenshot to show it.
- Commit on `feat/survey-a1-ipad-v2` and push it.

## 6. Open questions (answer in the report)

1. If the board and the original spec disagree on a measurement, which did you follow? The default is the board.
2. Is anything on the board not reachable in the app? Examples: the zoom chip labels, or the accuracy line's wording.
