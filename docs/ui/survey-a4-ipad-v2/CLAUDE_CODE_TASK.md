# iPad A4 น้ำท่วม · v2 (cards, water level input, min-level equation, new section drawing)

Board: `iPadA4.dc.html`. Open it in a browser next to `grf.css`. It is interactive:
- `ไม่เคย | เคย | ไม่ทราบ`
- the water level's −/+, typed value and slider
- the freeboard's −/+
- frequency, cause and hit chips
- `ดึงข้อมูลจาก GISTDA` under `ไม่ทราบ`

States (@2x of 1366 × 1024) are in `states/`:

| File | State |
|---|---|
| `00-before-main.png` | The `docs/ui/survey-a4` board: what `main` builds today |
| `01-flooded.png` | เคย: 80 ซม., freeboard 50 → 130 ซม. |
| `02-rounded.png` | 75 ซม. + 30 → 105, rounded up to 110 (`ปัดขึ้นจาก 105`) |
| `03-never.png` | ไม่เคย |
| `04-unknown-empty.png` | ไม่ทราบ, no GISTDA data yet |
| `05-unknown-gistda.png` | ไม่ทราบ, GISTDA fetched |

Labels and example values are in `assets/sample-data.json`. They are examples; never hard-code them.

## 1. What changed on the board (compared with `00-before-main`)

1. **The right column is three cards** (white, radius 14, 1 pt border), and scrolls as today; `หมายเหตุ` follows below them.
   - **`ประวัติน้ำท่วม`**, with the aside `มีผลกับระดับติดตั้ง B2 · B4 · B5`. It holds:
     - the answer `ไม่เคย | เคย | ไม่ทราบ`;
     - the water level, year and days;
     - `วัดความสูงจาก` and `ที่มาข้อมูล`;
     - the new `ระดับติดตั้งต่ำสุด` row.
   - **`ความถี่ · สาเหตุ`**: frequency on one row of three, and cause on one row of five, with short labels.
   - **`จุดที่ได้รับผลกระทบ`**: five checkbox chips in one row, with short labels, and an aside `n จุด · แสดงบนภาพ A2`.
   - The cards only show while `เคย`. `ไม่เคย` shows a note; `ไม่ทราบ` shows the GISTDA card, as today.
2. **Water level input.**
   - `ระดับน้ำสูงสุด` moves first in its row (then ปีล่าสุด, ท่วมขัง; widths 1.3 : 1 : 1).
   - It is a stepper: 44 pt −/+ buttons on a soft fill, step **5** cm. The number between them can be typed.
   - Under it, a slider from 0 to 200 cm (step 5) with ticks at 0 / 50 / 100 / 150 / 200 ซม.
3. **`ระดับติดตั้งต่ำสุด`.** This is a new row that reads as an equation: `[น้ำสูงสุด 80 ซม.] + [เผื่อเหนือน้ำ − 50 ซม. +] = [ติดตั้งต่ำสุด 130 ซม. · +1.30 ม.]`.
   - The freeboard becomes an answer: step 10, 0–150, default 50. Today it is the constant `FloodCheck.freeboardCm`.
   - The result tile is mint. When the sum was rounded up, its second line adds `· ปัดขึ้นจาก n`.
   - The row's aside reads `วัดจาก{ref} · ใช้ตรวจ B2 · B4 · B5`.
4. **Section drawing** (left).
   - A metre ruler on the left (0 to 2.0) and a legend: `ระยะเผื่อ` (a hatched band between the water and the minimum level) and `น้ำท่วม`.
   - Level tags on the right as pills:
     - `ติดตั้งต่ำสุด +1.30` (teal)
     - `น้ำสูงสุด 2554 +0.80` (blue, with a ⇕ grip that shows the line can be dragged)
     - `พื้นห้อง INV +0.30` (outlined)
     - `ดินเดิม ±0.00` (navy)
   - The B2 room holds INV, SMDB and an E-stop drawn at their heights. Each carries a ✓ / ✗ badge from the check.
   - Dimensions: `เผื่อ 50` and the INV mount `100`.
   - The caption is `ระดับเป็นเมตร · มิติเป็น ซม.`.
   - The `ลากเส้นน้ำเพื่อปรับระดับ` label is replaced by the grip on the water tag. Dragging still works.
5. **Bottom bar status.**
   - A round icon: a green ✓ when everything passes, an orange ! when a device fails.
   - The status line: `ครบช่องบังคับแล้ว · อุปกรณ์ใหม่ผ่านเกณฑ์ ≥ n ซม. · …`, or `อุปกรณ์ต่ำกว่าเกณฑ์ n รายการ` (danger colour).
   - The `บันทึกอัตโนมัติ hh:mm` line goes.

What does **not** change:
- The check table `ตรวจความสูงอุปกรณ์` and its rules (`FloodCheck.Status`).
- The evidence photos block.
- The GISTDA card, its fetch and estimate (`FloodGistda`, `FloodLookup`, `FloodCache`).
- `equipHeight`.
- Every stored id, label and option value. Short labels are display only.
- The PDF / Excel output, unless §6 Q1 says otherwise.

## 2. Scope

Only `FloodPageWide` (iPad, regular width and the stacked layout), plus:
- `FloodCheck` in `TCRoofCore/Flood.swift`, for the freeboard answer;
- `FloodSection`, for the screen drawing.

Out of scope. Do not touch:
- The iPhone A4, if it has its own layout. Check first whether it shares `FloodPageWide`. If it does, keep its look unchanged where the board doesn't say otherwise, and screenshot it.
- Other pages; the shared header, step bar and bottom bar (only A4's status text and icon).
- Schema ids and option strings; Excel cells.

## 3. Read first

Start with the code-review-graph tools, as CLAUDE.md says (`get_impact_radius_tool` on `FloodCheck.minCm`, `FloodCheck.freeboardCm`, `FloodSection.sketch`). Then read:
- `FloodPageWide.swift`, in full: `body`, `leftColumn`, `sectionDrawing` (the drag), `checkTable`, `rightColumn`, `floodedForm`, `numberBox`, `choiceRow`, `hitBox`, `neverNote`, `gistdaCard`.
- `TCRoofCore/Flood.swift` (`FloodCheck`), `FloodSection.swift`, `FloodGistda`.
- `Schema.swift`: the `flood` group (around line 241) and the readers of `minCm` (`equipHeight`, line ~270).
- `ReportLayout+Electrical.swift`: the PDF uses `FloodSection` too.
- Every reader of `FloodCheck.minCm`: B2, B4, B5, the report summary.
- `docs/ui/survey-a4/CLAUDE_CODE_TASK.md`, for the earlier spec.

## 4. Change list (in order)

1. **Freeboard as an answer.**
   - Add an optional hidden field `floodFreeboard` (`N`, ซม., `when: { _ in false }`) to `Schema.flood`, so completion is unchanged.
   - Add `FloodCheck.freeboardCm(_ v: Values) -> Double`: the answer when set, else 50 (keep the static default and rename it, e.g. `defaultFreeboardCm`).
   - `minCm` and `FloodSection`'s `ระยะเผื่อ` label use it.
   - Old jobs, with no answer, compute exactly as before.
   - Unit tests:
     - no answer gives today's result;
     - 75 + 30 rounds to 110;
     - 0 freeboard;
     - `ไม่เคย` gives the freeboard alone.
2. **Right column cards.**
   - Wrap `floodedForm` and the answer row into the three cards of §1.1. Each card is its own computed property: `historyCard`, `frequencyCauseCard`, `hitsCard`.
   - The title and aside go on one line (17 bold / 13 muted).
   - The cards use `Theme.surface` and `Theme.borderSubtle`, radius 14, padding 16, spacing 12.
3. **Short labels.**
   - Add display-only short labels for `Schema.floodSources` and `Schema.floodHits`: a dictionary next to them, or a `short` parameter to `choiceRow` / `hitBox`.
   - Tapping still writes the full option string, so stored values, the PDF and A2 don't change.
   - Cause: one row of five, 44 high, `minimumScaleFactor`. Hits: five chips in a row on iPad (checkbox + label, 48 high, filled `Theme.primarySoft` when on). Keep 2 or 3 per row when `narrow`.
4. **Water level stepper.**
   - Replace `numberBox("ระดับน้ำสูงสุด", …)` with a `levelStepper`:
     - 44 pt −/+ with `Theme.primarySoft` fill, step 5, clamped 5…200;
     - a `TextField` in the middle (number pad) writing `floodDepth`;
     - a `Slider(0…200, step: 5)` under it, with the tick labels.
   - Accessibility: `accessibilityAdjustableAction` steps by 5.
   - Order the row as level, year, days (1.3 : 1 : 1).
5. **`ระดับติดตั้งต่ำสุด` equation row** (`minLevelRow`, flooded only). Three tiles joined by `+` and `=`:
   - the level (read only, `Theme.surfaceMuted`);
   - the freeboard stepper (44 pt −/+, step 10, 0…150, writes `floodFreeboard`);
   - the result (`Theme.mint` with `Theme.teal` border): `minCm` ซม. big; `+m.mm ม.` and, when rounded, `· ปัดขึ้นจาก n` small.
   `neverNote` reads the freeboard from the same function.
6. **Section drawing.**
   - Restyle the **screen** drawing as §1.4. Add a style parameter to `FloodSection.sketch` (`.screen` / `.report`) so the PDF keeps today's drawing until §6 Q1 is answered.
   - Keep the drag on the water line: the grip on the tag is the visual cue, so remove the floating `ลากเส้นน้ำเพื่อปรับระดับ` label. It moves in 5 cm steps now, to match the stepper.
   - Keep `fetchOverlay` and the GISTDA banner.
   - All drawing stays vector (`Sketch`); colours from the existing tokens used by `FloodSection`.
7. **Bottom status.** A4's footer shows the round ✓ / ! icon and the status text of §1.5, built from `FloodCheck`'s results. If the footer is shared, add a status slot rather than forking the bar.
8. **Debug and tests.**
   - Add `-surveyA4 flooded|rounded|never|unknown|gistda` (with `-surveyPage flood`). They write the states' example values into the opened job:
     - `rounded` sets 75 and freeboard 30;
     - `gistda` uses `FloodGistda.estimate`.
   - A UI test `PadA4FloodUITests` (iPad):
     - type a level, check the result tile;
     - + on the freeboard moves the result by 10;
     - `ไม่เคย` hides the cards.
   - Add the flags and the test to CLAUDE.md in the style of the other entries.

## 5. Rules

- Data rules from CLAUDE.md:
  - Existing ids, labels and option values don't change.
  - The new field is optional and hidden.
  - Find every reader of `minCm` before changing it.
- Colours from `Theme`, no hex literals; `TCButtonStyle` / plain buttons as the file already does.
- Hit areas ≥ 44 pt.
- Each card, row and tile is its own computed property. Long expressions crash Debug builds.
- Run `swift test` in `TCRoofKit`. Build the app with xcodebuild, with your own `-derivedDataPath`, in the background.
- Save simulator screenshots named like `states/` to `screenshots/`.

## 6. Open questions (answer in the report, ask the team before merging)

1. **PDF drawing.** Should the report's section drawing follow the new screen drawing (ruler, pills, E-stop, badges)? The default is no, behind a style parameter.
2. **Freeboard.** Is 50 cm the team's default, and should 0–150 in steps of 10 be the range? Should a manager be able to set the default per project?
3. **Water level step.** 5 cm on the stepper, the slider and the drag; and 200 cm as the slider's top (today the drag allows 300). Is that right?
4. **Short labels.** Are the short cause and hit labels in `sample-data.json` acceptable on screen, with the full text kept in the PDF?
