# Claude Code task: A2 Site picture, design v2 (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-a2/CLAUDE_CODE_TASK_v2.md`

## Context
`SitePageWide` (A2) already implements the v1 design from `CLAUDE_CODE_TASK.md`:
- picture card with tools, north arrow, layer bar, scale and symbol popovers
- source picker, symbol palette, LIST and site note

This task is a **delta**. Bring the page in line with the v2 design and keep everything v1 already does.

| File | Shows |
|---|---|
| `preview.png` | default state, 1366 × 1024 landscape |
| `preview-layers.png` | layers menu open |
| `preview-locked.png` | "Lock" on, Select tool active |
| `preview-fullscreen.png` | full-screen mode with the building-model panel |
| `preview.html` | static render. The drone photo may not load, so trust the PNGs. |
| `iPadA2.dc.html` | design source: markup **and** interaction logic in the `<script>` block (`renderVals`) |

All UI text stays Thai, exactly as in the design. The English below is only for you.

Use code-review-graph first (see `CLAUDE.md`). Find every caller of:
- `SitePageWide`, `layerBar`, `undo()`
- `SiteShapes`, `SiteMarks.ops`
- `MarkKind.paletteTitle` / `paletteDetail`
- `cardBar`

Read the source before editing.

## Files likely involved
- `TCRoofKit/Sources/SurveyUI/SitePageWide.swift`
- `TCRoofKit/Sources/SurveyUI/SitePageWide+Stage.swift`: toolbar, layers, stage, editors
- `TCRoofKit/Sources/SurveyUI/A2Icon.swift`, `Resources/A2Icons.xcassets`
- `TCRoofKit/Sources/SurveyUI/JobEditor.swift`: `cardBar` bottom bar
- `TCRoofKit/Sources/TCRoofCore/SiteShapes.swift` and `SiteMarks.swift`, plus `Schema.swift` (new optional keys only)
- `TCRoofKit/Sources/PDFReport/ReportLayout+*.swift`: the A2 picture page

## Changes

### 1. Layout
- Content is 1318 wide.
- Left picture card is **860** wide; the right column fills the rest; gap 24.
- The right column itself is unchanged: source picker, palette, LIST, note.
- Everything still fits on one screen with no scrolling.

### 2. Picture toolbar (top of the picture, replaces the v1 toolbar)
The toolbar is one row of floating white groups:
- radius 10
- background `rgba(255,255,255,0.96)`
- shadow `0 1px 5px rgba(22,50,92,0.28)`
- 2 pt inner padding

Buttons are 36 pt tall inside the group, which keeps a 44 pt hit target with the group padding. Labels are 11.5 pt semibold and icons are 16 pt with a 1.9 stroke.

From left to right:

1. **Tool group**: segmented, exactly one item selected.
   - The selected item has a navy `#16325C` fill and white text.
   - Items: `เลือก` (Select, **new**), `พื้นที่แผง` (Panel area), `แนวสาย` (Cable route), `วัดระยะ` (Measure).
   - Select is the default for editing. Tapping a symbol, shape or building model selects it, and dragging moves it.
   - The other three items keep their v1 drawing behaviour.
2. **History group**: `ย้อนกลับ` undo and `ทำซ้ำ` redo, icon-only buttons 36 × 36.
   - **Redo is new.** Keep a redo stack next to the existing undo snapshots, and clear it on any new edit.
   - Disabled buttons show at 35% opacity.
3. **Lock group**: one toggle labelled `ล็อก`, or `ล็อกอยู่` when on. Use the `action-unlock` / `action-lock` icons.
   - When on: fill `#F08C00` with white text. All building models are locked (see §5).
   - Symbols and shapes are not affected.
4. **Right-aligned group**:
   - `ชั้น n/5` opens the layers menu (§3).
   - A full-screen button (`action-fullscreen`) enters full-screen mode (§4).

Other elements on the picture:
- **North arrow** sits under the toolbar at the top-left.
  - It is a 38 pt white circle (`ui-north`).
  - Tapping it rotates north in 90° steps and stores it in the existing `north` field, as v1 does.
- **Hint banner** at the bottom-left of the picture **replaces the v1 layer bar**.
  - Navy at 88% opacity, white 13 pt text, max width 420, no hit-testing.
  - It shows the bold tool name followed by the tool hint. Hint text, from `TL` in the script:
    | Tool | Hint |
    |---|---|
    | Select | `แตะสัญลักษณ์หรือโมเดลอาคารเพื่อแก้ไข ลากเพื่อย้าย` |
    | Panel area | `แตะมุมพื้นที่ทีละจุด แตะจุดแรกอีกครั้งเพื่อปิดรูป` |
    | Cable route | `แตะจุดเริ่มจากแผง ลากผ่านแนวที่เดินสาย จบที่ห้องอินเวอร์เตอร์` |
    | Measure | `แตะจุดเริ่มและจุดสิ้นสุด ระยะอ้างอิงจากสเกลภาพ` |
  - While a polyline is in progress, keep the v1 point count and "done" control.
- Scale bar (bottom-right), symbol popovers and the row under the picture are unchanged.

### 3. Layers menu (replaces the v1 layer bar)
- A dropdown under `ชั้น n/5`:
  - 180 wide, white, radius 12
  - shadow `0 6px 20px rgba(22,50,92,0.3)`
  - rows 36 tall
- Rows: `แผง`, `แนวสายไฟ`, `สัญลักษณ์`, `ระยะ`, `กริด 5 ม.`.
  - An on row shows `✓` with a `#E3EEF8` fill.
  - An off row shows `○` with grey struck-through text.
- `n` is the number of visible layers. This uses the existing `layers` set; only the control changes.
- Building models (§5) follow the `สัญลักษณ์` layer.

### 4. Full-screen mode (new)
- A full-screen cover with a dark background `#0E1A2B`.
- Header row:
  - title `ภาพสถานที่ติดตั้ง`
  - hint `เต็มจอ · ใช้เครื่องมือวาด / วางสัญลักษณ์ได้เหมือนเดิม · หนีบ 2 นิ้วเพื่อซูม`
  - white button `ออกจากเต็มจอ` with the `action-fullscreenExit` icon, at least 44 pt tall
- The picture with its full toolbar fills the left. Pinch-to-zoom and pan are available.
- All tools work the same as in the card, and edits are the same edits (shared state and undo).
- The **building-model panel** sits on the right: white, 290 wide, radius 14 (§5).

### 5. Building models (new)
Every building or area recorded in the survey can be dropped onto the picture as a footprint drawn **to the picture's scale**.

**Panel header**
- Title `อาคารในโครงการ`, with `วางแล้ว n/N` on the right.
- Intro text: `โมเดลจากขั้นที่บันทึกแล้ว ขนาดจริงตามสเกลภาพ · ลากการ์ดไปวางบนภาพ แล้วลากโมเดลบนภาพเพื่อย้าย`.

**Card list**: one card per survey area. Build it from the job's sections; don't hard-code it.
| Source | Card | Size from | Skin icon |
|---|---|---|---|
| D sections (water tank) | `D1 หลังคาถังน้ำใส 1` | tank size from the D page | `model-tank` |
| C sections (roof) | `C1 หลังคาอาคาร 1` … | roof width × length from C | `model-roof` |
| B1 buildings | `B1 อาคารตู้ไฟฟ้า MDB` | building size if recorded | `model-building` |
| B2 inverter room | `B2 ห้องอินเวอร์เตอร์` | room L × W (`sizeLWH`) | `model-building` |

Card details:
- At least 56 tall. Layout: 40 × 34 chip, then name, then the subtitle `ขั้น x/13 · W × L ม. · …`.
- Status pill:
  - `วางแล้ว`: green, `#1E7B45` on 14% green
  - `ลากไปวาง`: blue, `#1F6FB5` on 12% blue
- Border:
  - unplaced: dashed in the type colour
  - placed: 1 pt hairline
  - selected: 2 pt `#F08C00` on 8% orange
- Type colours: PV areas `#1F6FB5`, electrical `#178A7D`.
- Interaction:
  - Dragging a card onto the picture places the model. A ghost at real scale follows the finger, outlined in orange with a name tag.
  - Tapping a card selects it.

**On the picture**
- The model is a rectangle `w × h` metres converted with the picture scale, centred on its point and rotated by `r`. Opacity is 0.85, or 0.95 when selected.
- Skin, matching `skin()` in the script:
  - tank: panel rows
  - roof: two panel fields with a ridge line
  - building: teal diagonal hatch
- Border: 2 pt in the type colour, or 3 pt `#F08C00` when selected. A name tag sits above the top-left corner and starts with `🔒 ` when the model is locked.
- Dragging moves the model unless it is locked. Each drag is one undo step.

**Selected-model footer** (bottom of the panel)
- Name and size, plus the line `หมุน r° · ลากโมเดลบนภาพเพื่อย้าย` (or the locked text).
- `ล็อกตำแหน่งตามที่วาง` / `ปลดล็อกตำแหน่ง` toggles a per-model lock (orange when locked). It is disabled while the global Lock is on.
- `↺ 15°`, `↻ 15°`, `90°` rotate the model. These are disabled while it is locked.
- `เอาโมเดลออกจากภาพ` (red outline) removes the model. Disabled while locked.
- All buttons are at least 44 pt.

**Scale requirement**
- Models need metres-per-pixel, from `siteScale` or the Google zoom level.
- If there is no scale, the cards show `ต้องตั้งสเกลก่อน` and switching to the Measure tool is offered. Do not guess a scale.

**Data** (new optional keys only, no existing id changes)
- `siteModels`: `[ { id: "D1", x: 0…1, y: 0…1, rotation: Double, locked: Bool } ]`
  - Position is a fraction of the picture, like `MapMark`.
  - Size is **not** stored; it is always read live from the source section, so later edits there resize the model.
- `siteModelsLocked: Bool`: the global Lock.
- Both keys are hidden from the form (`when: { _ in false }`) and are optional, so A2 completion is unchanged.
- Old job JSON must still decode: use `decodeIfPresent` with defaults.

**PDF**
- On the A2 picture, draw placed models as vector outlines with the skin pattern simplified to an outline plus a light fill, and draw the name tag.
- Respect the `สัญลักษณ์` layer setting only on screen; the PDF always draws them.
- Excel is unchanged.

### 6. Copy changes (right column)
- Palette: `ZERO EXPORT MV` detail becomes `Zero Export`; `Weather St.` becomes title `Weather`, detail `สถานีอากาศ`.
- LIST heading trailing text becomes `ติ๊กอัตโนมัติเมื่อวาง`.
- LIST shortcuts become **icon-only** 44 × 44 buttons, `action-place` and `action-camera`, with accessibility labels `วางบนภาพ` / `ถ่ายรูป`. `⌄ เลือก` for land type keeps its text.
- Note trailing text becomes `ไม่บังคับ · ใต้ภาพในรายงาน`.

### 7. Bottom bar status badge (all survey pages, via `cardBar`)
Replace the plain check / alert glyph left of `บันทึกอัตโนมัติ HH:mm` with a 24 pt filled circle:
- complete: `#2E9E5B` with a white `✓`
- missing items: `#F08C00` with a white `!` (bold, 14 pt)

The status line below it is `#5B6B82` when complete and `#D9453B` when items are missing. A2 keeps its orange chips for missing LIST items. Because `cardBar` is shared, every page gets the badge.

## Icons (updated 1/10/2569)
The whole `icons/` folder is regenerated. It is a superset of v1 and adds `A2Icons.xcassets` (PDF vector), `svg/`, `png/` @1x/2x/3x and `icons.png`.

Replace `TCRoofKit/Sources/SurveyUI/Resources/A2Icons.xcassets` with the new one.

**Redrawn in v2** (same names, new paths that match the design):
- `tool-panelArea`
- `tool-cableRoute`
- `tool-measure`

**New `ui/` icons**: 24 pt templates with a 1.9 stroke, tinted like the button text:
| File | Use |
|---|---|
| `tool-select` | Select tool |
| `action-undo` / `action-redo` | History group |
| `action-lock` / `action-unlock` | Lock toggle (on / off) |
| `action-layers` | `ชั้น n/5` |
| `action-fullscreen` / `action-fullscreenExit` | Enter / leave full screen |
| `action-chevronDown` | `เลือก` dropdowns |

**New colour icons**: 34 pt, original colours, not templates:
| File | Use |
|---|---|
| `ui-north` | North button |
| `model-tank` / `model-roof` / `model-building` | Building-model card chips. On the picture, draw the skins in code at real scale; don't stretch the icon. |

Keep using `A2Icon(name:fallback:)`; every new icon needs an SF Symbol fallback.

## Rules
- Do not change existing field ids, labels, Excel cells or the Excel layout.
- A2 completion counts exactly as before.
- iPad portrait and iPhone keep the generic `groupPage`.
- Every button and field is at least 44 pt.
- Values in the previews are **examples**; never hard-code them:
  - TX 1 630 kVA, MDP-1 800AT, 312 panels, 38.8 m
  - building names and sizes, the note text, 10:15

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass.
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add tests:
   - Old job JSON without `siteModels` / `siteModelsLocked` decodes.
   - A model's size follows its source section.
   - Redo restores an undone edit, and a new edit clears redo.
4. Run the simulator with `-surveyWideA1 YES -surveyPage site` and compare at 1366 × 1024 against all four previews. Flow:
   1. Select a symbol and move it.
   2. Undo, then redo.
   3. Open layers and hide `กริด`.
   4. Enter full screen.
   5. Drag D1 onto the picture, rotate it 15°, lock it, and try to drag it (it must not move).
   6. Exit full screen.
   7. Export the PDF and check the model outline on the A2 page.
5. Summarise the files changed and anything left open.
