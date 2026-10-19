# Claude Code task: D1 sub-step 4/4 "ภาพถ่าย" (photos), iPad wide page

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-photo-ipad/CLAUDE_CODE_TASK.md`

## Base
This branch sits on `feat/tank-photo-details`. That branch adds:
- `Photo.note` / `Photo.tag` / `Photo.caption`
- `PhotoDetailSheet` (ภาพที่เลือก: map, note, opening tag, retake / delete)
- `TankPoints.tagOptions` / `tag(_:in:)`
- the `-surveyD1 photos|photodetails` flags

Build on top of those; don't redo them. If `feat/tank-photo-details` is merged into main first, nothing changes for you.

## Goal
D1 sub-step 4 (`TankPageWide`, `tab == 4`, `formStep`) is still a scroll of generic `PaperBox` + `FieldView` groups. Replace it on iPad (regular width, not `stacked`, not `phone`) with the designed page: a **photo gallery** on the left and an **inspector** for the selected photo on the right.

**Do only this.**
- The sub-step tab bar is a separate hand-off (`docs/ui/survey-d1-stepper-ipad`, branch `design/survey-d1-stepper-ipad`). Don't touch `tabBar`.
- iPhone and `stacked` keep `formStep` as it is.

## Files in this folder
| File | Shows |
|---|---|
| `iPadD1Photo.dc.html` | The board, 1366 × 1024. Read it as text. The markup inside `<sc-if value="{{is5}}">` is this page. In `renderVals()`, read the block `// ---- photo checklist` (`SHOT`, `tiles`, `rows`, `ringS`, `sumLine`, `cName` …). |
| `grf.css` | The board's shared styles (`g-pbtn`, `g-input`) |
| `preview.png` | The four states side by side |
| `states/01-default.png` | The first photo (ภาพมุมสูง) is selected and taken |
| `states/02-missing-required.png` | A required photo that hasn't been taken is selected: dashed red tile, camera / upload in the inspector, ถ่ายใหม่ / ลบภาพ disabled |
| `states/03-filter-missing.png` | Filter `ยังขาด` |
| `states/04-filter-done.png` | Filter `ถ่ายแล้ว` |
| `screenshots/` | Where your screenshots go |

Values in the board (dates, GPS, the 3/5 count) are examples. Never hardcode them.

## Layout (regular width, about 1240 pt content)
The page fills the height between the tab bar and the bottom bar. Two cards, 16 pt apart: the gallery takes the rest, the inspector is 430 pt.

**1. Gallery card** (`Theme.surface`, radius 14, padding 14 / 16)
- **Header row**
  - A progress ring, 52 pt (conic fill = required filled / required total), with "n/m" in the middle. It turns `Theme.success` when complete, else `Theme.primary`.
  - Title `ภาพที่ต้องถ่าย`.
  - Summary line: `ภาพบังคับยังขาด k ภาพ · ไม่บังคับ j ภาพ`, or `ภาพบังคับครบแล้ว · …`.
  - On the right, a 3-way segment with 38 pt segments: `ทั้งหมด n` / `ยังขาด n` / `ถ่ายแล้ว n`.
- **Tile grid**
  - 3 columns, 10 pt gaps.
  - Rows stretch to fill the card's height, at least 150 pt each. When there are more tiles, the grid scrolls.
  - Each tile is a button:
    - Photo area: the photo, aspect-fill. When there is none: a 2 % red tint for a required photo or `Theme.paper`-blue for an optional one, a camera icon, and `แตะเพื่อถ่าย`.
    - Pill, top-left: `✓ ถ่ายแล้ว` (white on success) / `บังคับ` (red tint) / `ไม่บังคับ` (grey).
    - White footer: name (14 bold) and what it shows (12, muted).
  - Border:
    - selected: 2 pt `Theme.primary` + a 3 pt soft halo
    - taken: thin
    - missing required: 1.5 pt dashed red
    - missing optional: dashed blue
- **Add bar** at the card's end: full width, 48 pt, dashed blue, `+ เพิ่มภาพสิ่งกีดขวาง  V1–V10 · บันได · ช่องลงถัง`.

**2. Inspector card** (430 pt)
- Title (17 bold) and the same status pill on the right.
- **Photo area**, which grows to the free height (at least 240 pt).
  - Taken: the photo, with its date · GPS chip bottom-left.
  - Missing: a dashed box with `ยังไม่มีภาพ` and two 48 pt buttons, `กล้อง` and `อัปโหลด`.
- **Row of two columns.**
  - Left: `วิธีถ่าย` with the tip text and the tile's description.
  - Right: a 128 pt mini plan `จุดถ่าย · GPS` with the photo's position around the tank. Hide it when the photo has no GPS.
- **หมายเหตุ** field, 44 pt.
- **Buttons.**
  - `ถ่ายใหม่` and `ลบภาพ` (red text) side by side. Both are disabled while there is no photo.
  - Then the full-width primary button `ภาพที่ยังขาดถัดไป ›`, which selects the next missing required photo. When none is missing it reads `✓ ครบทุกภาพบังคับ`.

## Data mapping (keep the schema)
Tiles come from the existing fields of the D1 `ภาพถ่าย` group (`Schema.swift`, `.tank`). **Don't add, rename or re-require fields.** "Required" comes from the `FieldSpec` (`optional`), so `Tank.photoCompletion`, `Progress`, the PDF and Excel stay as they are.

| Tile (board) | Field | Notes |
|---|---|---|
| ภาพมุมสูง · โดรน หรือ Google Maps | `aerialPhoto` | required |
| ผนังถัง · ใช้วางแนวรางสายไฟ | `sidePhotos` (max 4) | required. The tile shows the first photo with a small "n/4" badge. The inspector shows a strip of the 4 slots, in the order เหนือ ใต้ ตะวันออก ตะวันตก (as the current group title says). |
| หลังคาถัง · ภาพรวม | `roofPhotos[0]` | optional today |
| ผิวหลังคาใกล้ | `roofPhotos[1]` | optional today |
| แนวเดินสายไฟ · จากถังถึงห้อง Inverter | `cablePhoto` | optional today |
| สิ่งบังแดด | `shadePhoto` | optional |
| + เพิ่มภาพสิ่งกีดขวาง | `obstPhotos` (max 5) | required. Each obstacle photo becomes a tile after the six, named after its point (V9 …) when the photo is linked to one, else `สิ่งกีดขวาง n`. The add bar appends one and hides at 5. The first photo still goes in the report's big frame. |

- The `วิธีถ่าย` tips are the board's `SHOT[i][4]` strings. Keep them in one table next to the tiles.
- Taking or uploading a photo, retaking and deleting all use the existing photo pipeline that `FieldView` uses for `.photo` / `.photos` (`SurveyModel` photos, `PhotoAsset`, Drive upload). Don't write a second one.
- **หมายเหตุ:** `Photo.note`, edited inline in the inspector, the same way `PhotoDetailSheet` saves it.
- **Obstacle tag:** obstacle tiles are named after `Photo.tag` (V9, H1, บันได, V1–V10) when set. The inspector offers the tag the way the sheet does (`PhotoDetailsContext`, `TankPoints.tagOptions`).
- **Reuse, don't duplicate:** move the map, note and tag parts of `PhotoDetailSheet` into small shared views, and use them both in the sheet (iPhone, stacked) and in the inspector (iPad).
- **Shot point:** the same source as `PhotoDetailSheet`'s map: the photo's own location. Hide it when the photo has none.

## Change list
1. **`TankPageWide+Photos.swift` (new):** `padPhotoStep` with `photoGallery`, `photoTile(_:)`, `photoInspector`, `photoRing` and `addObstacleBar`, all as separate computed properties or functions (the Debug SIGSEGV note in CLAUDE.md). Add a small model with tile id, field id, slot index, name, subtitle, tip and required, built from the schema.
2. **`TankPageWide.swift`:** in the body's `switch tab`, regular width uses `padPhotoStep` for tab 4. `formStep` stays for iPhone and `stacked`. Selection and filter state are `@State` (`photoSel`, `photoFilter`).
3. **DEBUG:** `-surveyD1 photo|photomiss|photofilter|photodone` (with `-surveyPage tank`) opens tab 4 in states 01–04, with generated placeholder photos on the taken tiles (as `-surveyB4` does). Add it to the `-surveyD1` line in CLAUDE.md.
4. **Tests:**
   - A unit test that the tile list maps every field of the `ภาพถ่าย` group exactly once (side and roof slots counted).
   - A unit test that required tiles match `Tank.photoCompletion`.
   - A UI test on iPad: tap a missing tile, the camera stub fills it, and the ring count goes up.

## Rules
- Theme tokens only, no hex. `TCButtonStyle` for buttons, 44 pt hit areas, `Font.sarabun`.
- Photos stay bitmaps. The mini plan is a vector `Sketch` / `Canvas`.
- Old job JSON must decode unchanged. No schema change.

## Check list
- [ ] `swift test`
- [ ] xcodebuild with your own `-derivedDataPath`
- [ ] iPad simulator, `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage tank -surveyD1 photo` (and the other three states). Save the screenshots as `screenshots/01–04` and compare them with `states/`.
- [ ] iPhone and the stacked layout still show the old form
- [ ] The PDF and Excel of a job with D1 photos are unchanged

## Open questions (report them)
1. The board marks 5 photos required (aerial, wall, roof overview, roof surface, cable route). Only aerial, side and obstacle photos are required in the schema today. Should roof and cable become required? That would change `Progress` and old jobs' completion.
2. The board has one wall photo "from a corner, showing 2 sides", while the schema keeps 4 side photos. Keep 4 slots, or ask for 2 corner shots?
