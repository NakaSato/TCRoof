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
| `SPI` | progress card → `S-Curve` |
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
   - Give `Cell` an optional `opens: ProgressView?`. Set it to `.curve` for `ความคืบหน้า`, `กำหนดการ` and `SPI`, and to `.gantt` for `คาดส่งมอบ`.
   - Keep `opensActions` as it is.
   - The iPhone overview ignores `opens`.
2. **Buttons.**
   - In `kpiStrip`, a cell with `opens` or `opensActions` becomes a `Button` over its whole cell; the cell is 52 pt high.
   - `opens` sets `view`, animated as the card's own switch does. `opensActions` sets `sheet = .actions`.
   - A cell with neither stays a plain view: `ต้องดำเนินการ` reading `ไม่มี` does nothing, as today.
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
5. **CLAUDE.md.** Add one sentence to the `InstallTrackingUITests` line: the strip's cells switch the progress card.

## 5. Check list

- [ ] The strip looks exactly as before at rest; compare with `states/01`.
- [ ] Each cell's hit area is the full cell (≥ 44 pt).
- [ ] The iPhone overview is unchanged.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath`, and `InstallTrackingUITests` passes on an iPad simulator.
- [ ] Screenshots like `states/02` and `03` are saved to `screenshots/`. Use `-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES`, then the taps.

## 6. Open questions (answer in your report; don't build these)

1. Should the cell whose view is showing be marked, for example with an underline on `ความคืบหน้า` while S-Curve is on? The board shows no mark.
2. Should `SPI` open a short explanation of SPI (EV / PV) instead of the S-Curve?
