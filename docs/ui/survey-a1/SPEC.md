# A1 ข้อมูลโครงการ — Swift dev spec (iPad + iPhone)

**Status:** 2026-10-01, from the canvas page `iPadA1` (ขั้น 1/13). The canvas file is unchanged since the 30/9 export.
**Task:** [`CLAUDE_CODE_TASK.md`](CLAUDE_CODE_TASK.md)
**Design reference:** `preview.png`, `preview.html`, source `iPadA1.dc.html`. Its script holds the report-crop logic (`dragStart`).
**Icons:** `icons/` (§7)
**Code today:** `TCRoofKit/Sources/SurveyUI/InfoPageWide.swift`, `InfoPageWide+Sections.swift` (built from the 29/9 design)

## 1. Gaps between the code and the design

| # | Design (30/9) | Code today |
|---|---|---|
| 1 | location card **left** (~620 pt), document / project / coordinator / areas **right** | location card on the right (`rightWidth`), the other boxes on the left |
| 2 | **report crop frame** on the map, stored in `mapCrop`; PDF / Excel map uses only the crop | not built (no `mapCrop`) |
| 3 | install areas: **หลังคา** and **ถังน้ำใส** only, 2-column grid | still has **พื้นดิน** (`groundAreas`, `InfoPageWide.groundKey`) |
| 4 | engineer field has **no** `ผู้ใช้เครื่องนี้` tag | tag shown (`InfoPageWide.swift` ~line 124) |
| 5 | bottom bar `บันทึกอัตโนมัติ HH:mm` | `บันทึกอัตโนมัติแล้ว …` (`InfoPageWide+Sections.swift` ~line 268) |

Everything else in the design is already in the code and must keep working:
- the fields, the date picker, `tel:` on the phone number
- zoom levels, GPS current location with accuracy
- the office address copy button, the area steppers and their delete confirmation

## 2. Data

All existing ids keep their meaning (`Schema.info`):
`docNo`, `rev`, `date`, `engineer`, `projectName`, `capacity`, `internet`, `coordinator`, `phone`, `address`, `officeAddress`, `gps`.

| Key | Status | Meaning |
|---|---|---|
| `mapZoom` | exists (job extra key) | zoom level: พื้นที่ 500 ม. / สถานี 200 ม. / อาคาร 50 ม., plus + / − |
| `mapCrop` | **new**, job extra key, add to `WebBackup.extraJobKeys` | report crop as `"x,y,w,h"` in % of the map view; default `22,16,54,64` |
| `groundAreas` | **remove from the UI** | keep decoding it and keep it in `extraJobKeys`, so old backups round-trip; no longer shown or counted |

Install areas stay as they are: the counts of `.roof` sections (หน้า C) and `.tank` sections (หน้า D1), each with a − / + stepper. Lowering a count that would delete filled sections still asks first (existing confirmation).

## 3. Report crop (`mapCrop`)

The logic comes from `dragStart` in the design script.

- **Frame:**
  - 2 pt blue (`#1F6FB5`) border
  - everything outside dimmed with `rgba(22,50,92,0.32)`
  - four corner handles: 16 pt white squares, 2.5 pt blue border, 3 pt radius, inside 44 × 44 pt hit areas centred on the corners
- **Gestures:**
  - Drag inside the frame to **move** it, clamped to 0…100 − size.
  - Drag a corner to **resize** it. The corner's two edges move; the minimum size is 12 % of the map; the frame stays inside the map.
- **Label** (top-left inside the frame): `ภาพในรายงาน · {W} × {H} ม.`.
  - W and H come from the map's metres-across at the current zoom × the crop fraction.
  - The design's placeholder formula is `w × 2`, `h × 2 × 332/620` at the 200 m level.
  - In code, use `MapImage.metersAcross(zoom)` × `w/100` for W, and × the view aspect × `h/100` for H, rounded to whole metres.
- **Under the map:** the hint `ลากกรอบหรือมุมเพื่อเลือกพื้นที่ภาพในรายงาน PDF / Excel · แตะค้างที่หมุดเพื่อย้าย`, and the link `รีเซ็ตกรอบ` on the right (restores `22,16,54,64`).
- **Pin:** long-press it to move it, which updates `gps` (existing). The crop does not move with it.
- **Outputs:** PDF cover / A1 map and the Excel map image use `MapImage` at the saved zoom, cropped to `mapCrop`. Without `mapCrop`, the whole image is used (old jobs).

## 4. Layout (iPad landscape, content width 1240)

**Left column (~620 pt), card `ที่ตั้ง`:**
1. **Map (~350 pt):**
   - zoom segment top-left: พื้นที่ 500 ม. / สถานี 200 ม. / อาคาร 50 ม.; the selected level is mint
   - + / − top-right (44 pt)
   - scale bar
   - pin
   - crop frame (§3)
   - hint and `รีเซ็ตกรอบ`
2. **`พิกัดดาวเทียม Google Map *`:**
   - `สำคัญ` tag, the coordinate field
   - `ตำแหน่งปัจจุบัน` button (`ui-gps-locate`)
   - line `ความแม่นยำ ±{m} ม. · บันทึกเมื่อ HH:mm`
3. **`ที่อยู่สถานี / สถานที่ติดตั้ง *`**
4. **`ที่อยู่สำนักงาน / สาขา`** (aside `ไม่บังคับ`): placeholder `เหมือนที่อยู่สถานี`, button `คัดลอก`

**Right column (gap 28):**
1. **`เอกสาร`:** `เลขที่ *`, `REV.`, `วันที่สำรวจ *` (Buddhist-era date, `ui-calendar` opens the picker), `วิศวกรผู้สำรวจ *` (default `settings.engineer`, no tag). Ratio 1 : 0.7 : 1.2 : 1.6.
2. **`โครงการ`:** `ชื่อโครงการ / สถานี *`, then `ขนาดที่ต้องการติดตั้ง *` (unit `kWp`) and `สัญญาณอินเตอร์เน็ต *` (มี / ไม่มี).
3. **`ผู้ประสานงาน`:** `ชื่อผู้ประสานงาน *`, `เบอร์โทร *` (`ui-phone`, tap = `tel:`).
4. **`พื้นที่ติดตั้ง *`** (aside `กำหนดหน้า C / D ในแบบสำรวจ · รวม {n} ขั้น`):
   - two tiles in a grid
   - each tile: checkbox (`a1-checkbox-on` / `-off`), title, sub-line (`หน้า C · หลัง` / `หน้า D1 · ถัง`), − count + stepper

**Bottom bar:**
- `ui-check` + `บันทึกอัตโนมัติ HH:mm` + `ครบ {k}/{n} ช่องในหน้านี้`
- `บันทึกร่างตอนนี้`
- disabled `‹ หัวข้อแรก`
- `ถัดไป 2/13 A2 ภาพสถานที่ติดตั้ง ›`

**Portrait / iPhone:** one column. Order: location, document, project, coordinator, areas.

## 5. Report and export

- **PDF:** the cover / A1 map uses the crop. Everything else is unchanged (`ReportLayout+Cover.swift`).
- **Excel:** the map image uses the crop. Cells are unchanged (`ExcelExporter` ~lines 111 and 220).

## 6. Tests

| Test | Expect |
|---|---|
| crop move | dragging past an edge clamps x to 0…(100 − w) |
| crop resize | the NW corner keeps SE fixed; w, h ≥ 12; stays inside |
| crop label | at the 200 m level, w 54 → about 108 m wide (design sample `108 × 69 ม.`) |
| reset | `รีเซ็ตกรอบ` → `22,16,54,64` |
| export | a PDF / Excel map with `mapCrop` has the cropped aspect; without it, the full image |
| ground removed | job with `groundAreas = 2` opens, the tile is not shown, the value survives a web backup round-trip, A1 completion unchanged |
| layout | location card on the left in landscape |

## 7. Icons (`icons/`)

`icons/icons.png` shows them all. Formats: `svg/`, `png/` @1x/@2x/@3x, and `A1Icons.xcassets` (PDF vector; `ui-*` are template images).

| File | Use |
|---|---|
| `a1-map-pin` | map pin with its accuracy halo |
| `a1-report-crop` | report crop frame with corner handles (draw the real frame as a view; use this in hints / help) |
| `a1-checkbox-on`, `a1-checkbox-off` | install area tiles |
| `ui-gps-locate` | `ตำแหน่งปัจจุบัน` |
| `ui-calendar` | date field |
| `ui-phone` | phone field |
| `ui-check` | autosave |
| `ui-prev`, `ui-next` | bottom navigation |
| `ui-plus`, `ui-minus` | zoom and area steppers |

Copy `A1Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/` next to the other catalogs. Use it in place of the SF Symbols the page uses now where the design differs.

## 8. Open questions

1. Should the crop keep a fixed aspect ratio that matches the report frame (PDF map box / Excel range), so the image is never letterboxed?
2. Should the crop be stored per zoom level, or once? (One value is specified here.)
