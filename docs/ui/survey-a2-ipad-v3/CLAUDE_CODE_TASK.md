# iPad A2 ภาพสถานที่ติดตั้ง · layout v3 (palette rail + full-screen bar)

Board: `iPadA2.dc.html` (open it in a browser next to `grf.css`). The board is interactive. To try a state in the browser:
- Tap a palette tile, then tap the photo.
- Tap a placed symbol.
- Tap `LIST ในภาพ`.
- Tap the photo to go full screen.
- Tap `อาคารในโครงการ` in full screen.

States (@2x of 1366 × 1024) are in `states/`:

| File | State |
|---|---|
| `00-before-main.png` | The layout on `main` today, for comparison |
| `01-layout.png` | The new three-column layout |
| `02-palette-armed.png` | A tile armed, and the banner on the photo |
| `03-symbol-placed-selected.png` | A placed symbol selected, with its `ลบ` |
| `04-list-open.png` | `LIST ในภาพ` open |
| `05-fullscreen.png` | Full screen, buildings panel closed |
| `06-fullscreen-buildings.png` | Full screen, buildings panel open |

Labels and example values are in `assets/sample-data.json`. They are examples; never hard-code them.

## 1. What changed on the board

1. **Normal layout, landscape iPad, three columns:**
   - A slim **symbol rail** on the left. It replaces the `สัญลักษณ์บนภาพ` card that sat in the right column.
   - The **picture** in the middle, the same size as today.
   - A narrower **side column** on the right.
2. **Side column:**
   - `ภาพมุมสูง`'s two sources sit one per row.
   - `LIST — รายการที่ระบุในภาพ` is titled `LIST ในภาพ`, and its open list is one column.
   - Each card's hint sits on its own line under the title.
3. **Full screen, iPad:**
   - A new top bar: `ออกจากเต็มจอ` pill on the left, title and hint centred, `อาคารในโครงการ · n/5` toggle on the right.
   - The picture fits the height under the bar.
   - The building panel is **closed by default**. It floats over the picture's right side when it is opened, or while a building card is armed.

What does **not** change:
- Placing, moving, editing and deleting symbols: `arm`, `SiteMarksEditor`, the edit popovers and `ลบ`.
- The drawing tools, undo / redo, layers, lock, zoom and pan.
- Building models (`SiteModels`) and the A3 / B4 sync (`SiteSync`).
- Every stored value, the PDF / Excel / DXF output, and completion.

The board's own tap-to-place and `ลบ` pill only show that the rail's tiles work. The app already has this behaviour. Keep the app's.

## 2. Scope

Only `SitePageWide` on iPad in regular width:
- `padBody`
- `rightColumn` and its sections
- the palette
- `padFull` / `fullHeader` / `fullPicture` / the model panel's placement

Out of scope. Do not touch:
- The iPhone page and the iPhone full screen (`SitePageWide+Phone.swift`, `phoneFull`). They stay as they are.
- The stacked (portrait) layout. It keeps today's order, except that the palette can show as the existing grid card there.
- Any behaviour of symbols, shapes, models or tools.
- Schema, storage, sync, and the PDF / Excel / DXF output.
- Other pages and the shared header and bottom bar.

## 3. Read first

Start with the code-review-graph tools, as CLAUDE.md says. Then read:

- `SitePageWide.swift`: `padBody`, `pictureWidth`, `rightColumn`, `heading`, `sourceSection`, `paletteSection`, `paletteButton`, `paletteTools`, `placed`, `listSection`, `noteSection`.
- `SitePageWide+Full.swift`: `padFull`, `fullHeader`, `fullPicture`, `modelPanel`, `panelOpen`.
- `SitePageWide+Toolbar.swift` and `SiteMarksEditor.swift`: the armed banner and the editors, which stay as they are.
- `docs/ui/survey-a2/CLAUDE_CODE_TASK_v2.md`, for the earlier full-screen spec.

## 4. Change list (in order)

1. **Symbol rail.** In `padBody`'s non-stacked branch, put a rail before `pictureCard`:
   - Width 104, full height. White card, radius 12, 1 pt `Theme.borderSubtle`, padding 8 / 6.
   - Head: `สัญลักษณ์` (14 bold, centred) and the hint `แตะ แล้วแตะบนภาพ` (10.5 muted) on two lines, with a hairline under them.
   - Then the `paletteTools` in one column (scrolls if needed), gap 5.
   - Each tile:
     - min height 58
     - `ToolIcon` 30 pt above the title (11.5 bold, centred, one line, scale down to 0.8)
     - no detail line
     - the placed dot (7 pt) in the top-right corner
     - armed: 2 pt `Theme.primary` border, `Theme.primarySoft` fill
   - Keep `paletteButton`'s accessibility label (title + detail) and its value (`วางแล้ว` / `ยังไม่วาง`). Tapping still calls `arm(t)`.

   Add a `rail: Bool` parameter to `paletteButton`, or a separate `railButton`. Don't fork the logic.
2. **Columns.**
   - `HStack(spacing: 12)` of rail 104 | `pictureCard` | side column.
   - `pictureCard` keeps today's width (860 / 1294 of the content width in the board's proportions). In the board, the rail and side column share the rest: the side column is ≈ 330 at 1366.
   - Check `pictureWidth` still gives the board's 860 at 1366 once the rail is in. Adjust only the formula, not the picture's aspect handling.
3. **Side column.** `rightColumn` on iPad is `sourceSection`, `listSection`, `noteSection`. The palette moves to the rail; it stays in the column only when `stacked` / iPhone.
   - `heading` on iPad: the title, then the hint **under** it (12 muted, its own line).
   - `sourceSection`: one option per row, each min 48.
   - `listSection`: title `LIST ในภาพ` with the existing count chip, list in one column on iPad.
   - `noteSection`: takes the remaining height.

   Text: the only label that changes is `LIST — รายการที่ระบุในภาพ` → `LIST ในภาพ`, on iPad. iPhone keeps its labels.
4. **Full-screen bar** (`fullHeader`, iPad only): 64 high, `Theme.mediaBackdrop`, three parts:
   - **Left:** `ออกจากเต็มจอ` as a pill (min 44), `onMedia` 12 % fill, 28 % border. It has a white 34 pt circle holding `action-fullscreenExit` in navy, then the label. It sets `fullScreen = false`.
   - **Centre:** `A2 ภาพสถานที่ติดตั้ง` (17 bold) and, under it, `แตะจุดบนภาพเพื่อแทรกอาคาร · ลากเพื่อย้าย` (12.5, `onMedia` 70 %).
   - **Right:** a pill toggle `อาคารในโครงการ · n/N` (n = placed models, N = models), with a building glyph. It is filled `Theme.primary` when the panel is open, and outlined when closed. It toggles `panelOpen`.
5. **Full-screen picture and panel** (`padFull`, iPad only):
   - The picture keeps its aspect and fits the height under the bar with 16 pt top and bottom, centred horizontally, radius 8.
   - The model panel is an overlay on the right: width 290, top 76, bottom 16, right 16, shadow.
   - It shows when `panelOpen` is true **or** a building card is armed (keep it open while dragging a card).
   - On iPad, `panelOpen` starts `false` when entering full screen. The iPhone keeps its own `panelOpen` default.

   `-surveyA2 fullscreen` (a model selected) should open with the panel open, so the existing debug state still shows the panel.
6. **Debug and test.**
   - Add `-surveyA2 rail|armed|listopen|fullpanel` so `states/02`, `04` and `06` can be reproduced.
   - Extend an existing iPad A2 UI test, or add `PadA2LayoutUITests`:
     - the rail arms a tool
     - full screen opens with the panel closed
     - the toggle opens it
     - `ออกจากเต็มจอ` returns
   - Add the flags and the test to CLAUDE.md in the style of the other entries.

## 5. Rules

- Colours from `Theme` (`primary`, `primarySoft`, `borderSubtle`, `mediaBackdrop`, `onMedia`, `success`, `progressZero`). No hex literals in views.
- `TCButtonStyle` / plain buttons as the file already does.
- Hit areas ≥ 44 pt.
- Each card or bar as its own computed property; long expressions crash Debug builds.
- iPhone A2 and iPhone full screen must look the same before and after. Take one screenshot of each.
- `swift test` in `TCRoofKit`. Build the app with xcodebuild, with your own `-derivedDataPath`, in the background. Save simulator screenshots, named like `states/`, to `screenshots/`.

## 6. Open questions (answer in the report)

1. The board's rail tile has no detail line, for example `มิเตอร์ กฟภ.`. Is the title alone clear enough? The default is to keep the detail in the accessibility label only.
2. In portrait (stacked), should the rail also be used, or the old grid card? The default is the grid card.
3. Full screen opens with the building panel closed. Should it reopen as it was last left, per job? The default is closed every time.
