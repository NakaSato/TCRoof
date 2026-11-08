# iPad install tracking · KPI strip: every cell opens its detail

Component: the KPI strip at the top of the install tracking page's `ภาพรวม` tab:

`ความคืบหน้า | กำหนดการ | คาดส่งมอบ | SPI | ต้องดำเนินการ`

The board is `boards/iPadInstall.dc.html`; open it in a browser.

The states in `states/` are at 2x:

- `01`: the strip.
- `00`: the strip with the Gantt card under it.
- `02`: after tapping `ความคืบหน้า`, which switches the progress card to S-Curve.
- `03`: after tapping `ต้องดำเนินการ`, which opens its sheet.

`preview.png` is the whole page at 1x. The values are examples (`-installDemo YES`); never hard-code them.

## 1. Goal

The strip is already built: `kpiStrip(_:)` and `cells(_:)` in `TCRoof/Views/Install/Tracking/InstallTrackingPage+HeaderAndKPI.swift`. Its cells, values, colours, notes and widths match the board. One difference is left: on the board **every cell is a button**, while in the app only `ต้องดำเนินการ` reacts to a tap. On the board:

| Cell | Tap |
|---|---|
| `ความคืบหน้า` | progress card → `S-Curve` (`view = .curve`) |
| `กำหนดการ` | progress card → `S-Curve` |
| `คาดส่งมอบ` | progress card → `Gantt` (`view = .gantt`) |
| `SPI` | a popover explaining SPI with this station's numbers (decision 2, §6) |
| `ต้องดำเนินการ` | `ต้องดำเนินการ` sheet (`sheet = .actions`), as today |

The progress card sits right under the strip, so nothing needs scrolling.

## 2. Scope

Do only the change list in §4. Out of scope; do not touch these:

- The cells' values, notes, colours, widths and order, and the note separator. The app's `|` stays; the board's `·` is not a change to copy.
- `progressCard`, the Gantt, the S-curve and the key plan view.
- The `ต้องดำเนินการ` sheet.
- The iPhone overview (`InstallTrackingPage+PhoneOverview.swift`), which also calls `cells(_:)`. Its behaviour and look stay the same.
- `InstallPageData` and every number's source.

## 3. Read first

- `InstallTrackingPage+HeaderAndKPI.swift`: `Cell`, `cells(_:)`, `kpiStrip(_:)`.
- `InstallTrackingPage.swift`: `@State var view`, `sheet`, and where `kpiStrip` and `progressCard` are placed.
- `InstallTrackingPage+Progress.swift`: `enum ProgressView { gantt, curve, keyplan }`, and how the card's own `Gantt | S-Curve | Key Plan` switch sets `view`.
- `InstallTrackingPage+PhoneOverview.swift`: the other caller of `cells(_:)`.
- `TCRoofUITests/InstallTrackingUITests.swift`: the existing tap on the `ต้องดำเนินการ` cell.

## 4. Change list (in order)

1. **Cell target.**
   - Give `Cell` an optional `opens: ProgressView?`. Set it to `.curve` for `ความคืบหน้า` and `กำหนดการ`, and to `.gantt` for `คาดส่งมอบ`.
   - Give `Cell` a flag `explainsSPI` for the `SPI` cell (item 6).
   - Keep `opensActions` as it is.
   - The iPhone overview ignores `opens`.
2. **Buttons.**
   - In `kpiStrip`, a cell with `opens` or `opensActions` becomes a `Button` over its whole cell; the cell is 52 pt high.
   - `opens` sets `view`, animated as the card's own switch does. `opensActions` sets `sheet = .actions`.
   - A cell with neither, and not `SPI`, stays a plain view: `ต้องดำเนินการ` reading `ไม่มี` does nothing, as today.
   - Use a plain button style with a pressed state: `Theme.background` behind the cell while it is pressed. No other visual change.
   - Remove the `onTapGesture`.
3. **Accessibility.**
   - Each button reads `<label> <value> | แตะเพื่อดูรายละเอียด` as one element with the button trait.
   - Give each an identifier `kpi.<label>` for the UI test.
   - The plain cell keeps its combined reading.
4. **UI test.** Extend `InstallTrackingUITests`, iPad, `-installDemo YES`:
   - tapping `ความคืบหน้า` selects the progress card's `S-Curve`;
   - tapping `คาดส่งมอบ` selects `Gantt`;
   - the existing `ต้องดำเนินการ` tap still opens its sheet.
5. **CLAUDE.md.** Add one sentence to the `InstallTrackingUITests` line: the strip's cells switch the progress card, and `SPI` explains itself.
6. **SPI popover** (decision 2). Tapping `SPI` opens a popover anchored to the cell, about 320 pt wide. It shows:
   - the title `SPI (Schedule Performance Index)`;
   - the line `ความคืบหน้าจริง ÷ ตามแผน = <actual>% ÷ <planned>% = <spi>`, from `InstallTracking.actual`, `.planned` and `.spi`;
   - the rule the cell already uses: `≥ 0.95 ปกติ` (success ink) and `< 0.95 ต่ำกว่าแผน` (danger text), with the current band marked;
   - one line: `1.00 = ตรงแผน · ต่ำกว่า 1 = ช้ากว่าแผน`.
   It has no other actions; tapping outside closes it. Its accessibility identifier is `kpi.SPI.popover`.
7. **Mark the cell that is showing** (decision 1).
   - A cell whose `opens` equals the progress card's current `view` is marked: a 2 pt `Theme.primary` bar along its bottom edge and the `.isSelected` trait.
   - When S-Curve is on, both `ความคืบหน้า` and `กำหนดการ` are marked; when Gantt is on, `คาดส่งมอบ` is. With Key Plan on, none are.
   - The mark follows `view` whichever way it changed: the strip, the card's own switch, or `-installView`.
   - `SPI` and `ต้องดำเนินการ` are never marked.
8. **UI test additions.**
   - After tapping `ความคืบหน้า`, it has the selected trait and `คาดส่งมอบ` doesn't.
   - Tapping `SPI` shows `kpi.SPI.popover` and leaves the card's view unchanged.

## 5. Check list

- [ ] The strip looks exactly as before at rest; compare with `states/01`.
- [ ] Each cell's hit area is the full cell (≥ 44 pt).
- [ ] The iPhone overview is unchanged.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath`, and `InstallTrackingUITests` passes on an iPad simulator.
- [ ] Screenshots like `states/02` and `03` are saved to `screenshots/`. Use `-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES`, then the taps.

## 6. Decisions (answered 8 Nov 2569)

1. **Mark the cell that is showing:** yes. See §4 item 7.
2. **SPI opens an explanation instead of the S-Curve:** yes. See §4 item 6.
