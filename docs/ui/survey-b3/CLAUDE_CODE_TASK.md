# Claude Code task: B3 Panel washing water system, wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-b3/CLAUDE_CODE_TASK.md`

## Goal
B3 (`ModuleType.water`, "ระบบน้ำล้างแผง") is still drawn by the generic `groupPage` form. Give it a designed wide page on iPad landscape, like the A2/B1/B2 wide pages, matching the previews.

| File | Shows |
|---|---|
| `preview.png` | default: "ร่วมกับระบบน้ำเดิม" selected, both photos taken |
| `preview-new.png` | "ติดตั้งระบบน้ำใหม่" selected, pin moved |
| `preview-missing.png` | one photo missing: orange badge and red status in the bottom bar |
| `preview.html` | static render |
| `iPadB3.dc.html` | design source: markup and logic (`renderVals`) |

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of the water module:
- `ModuleType.water`, `Schema.modules[.water]`
- `photoArea` / `photoWide` / `waterMode` / `detail` on water modules
- `stationSlots[.water]`
- `MarkKind.water` and `siteMarks`
- the PDF page `ภาพตำแหน่งระบบน้ำล้างแผง`
- the Excel slots

Read the source before editing.

## Existing data (do not change ids)
`Schema.modules[.water]` fields:
- `photoArea`: ภาพถ่ายพื้นที่ติดตั้ง (required)
- `photoWide`: ภาพถ่ายมุมกว้าง (required)
- `waterMode`: choice `ติดตั้งระบบน้ำใหม่` / `ติดตั้งร่วมกับระบบน้ำเดิม`
- `detail`: optional

Note that the design's card label "ร่วมกับระบบน้ำเดิม" maps to the stored value `ติดตั้งร่วมกับระบบน้ำเดิม`. Keep the stored strings exactly.

## Layout (landscape, content width 1318)
- Grid: left column flexible, right column 500, gap 20.
- Cards: white, radius 16, 1 pt border `rgba(22,50,92,0.16)`, shadow `0 2 6 rgba(22,50,92,0.06)`, padding 14/16.
- Each card header has a numbered chip: 28 × 28, radius 8, fill `#E3EEF8`, text `#1F6FB5`, 14 pt heavy.
- Everything fits on one screen with no scrolling.

### Card 1: water point on the A2 picture (left, full height)
- **Header**:
  - `1 ตำแหน่งจุดจ่ายน้ำ *`
  - grey tag `ภาพจากหน้า A2 · แตะบนภาพเพื่อย้ายจุด`
  - right-aligned outline button `เปิด A2 →`, at least 44 pt, which opens the A2 page
- **Picture**:
  - The **A2 site picture itself** (`siteMap`), with A2's symbols and drawings drawn on top as they are on A2.
  - Read-only for everything except the water point. Do not copy the image.
  - Aspect 704:560 in the prototype, but follow the real photo's aspect. Radius 12.
- **Water point pin**:
  - 44 pt hit target with a 30 pt white circle, a 4 pt `#1F6FB5` ring and a 10 pt blue dot (`icons/b3-water-pin.svg`).
  - Label pill under it: white 12.5 pt bold on `#1F6FB5`.
    - mode "new": `ถังพัก / ปั๊มใหม่`
    - mode "existing": `จุดต่อแยก`
  - Tap anywhere on the picture to move the pin; a drag also works.
  - **Store the pin as A2's `siteMarks` entry of kind `MarkKind.water`**, one per water module, so A2, B3, the PDF and B4/B5 all show the same point.
    - If there is none, tapping creates it.
    - Do not add a separate coordinate field.
    - `.water` stays hidden from A2's palette, as before.
- **Legend chip** at the top-left of the picture:
  - mode "new": `จุดวางถังพัก / ปั๊มใหม่`
  - mode "existing": `จุดต่อแยกจากท่อประปาเดิม`
- **Summary strip** under the picture: three grey tiles (`#F5F8FC`, radius 10).
  - `หลังคาที่ต้องล้าง`: the roof / tank names from the C and D sections
  - `จำนวนแผง (จาก D1)`: total panels · kWp from the C/D layout data
  - `แสดงผลใน`: `ภาพ A2 · รายงาน`
  - Compute the values from the job. The `416 แผง · 237.1 kWp` in the previews is an example.

### Card 2: water system type (right)
- Header: `2 รูปแบบระบบน้ำ *`.
- Two choice cards, at least 96 pt tall, radius 14:
  - selected: fill `#E8F7F3`, 2 pt border `#27A99A`, 3 pt halo at 14%, and a 24 pt `#27A99A` check circle at the top-right
  - unselected: white, 1 pt border `#C9D3DF`
  - a small tag on top: `ใหม่` / `ต่อแยก`, teal fill when selected, grey otherwise
  - title 17 pt bold, sub-text 13 pt
- Choices:
  - `ติดตั้งระบบน้ำใหม่`, sub-text `วางท่อและจุดจ่ายน้ำใหม่ทั้งหมด`
  - `ร่วมกับระบบน้ำเดิม`, sub-text `ต่อแยกจากท่อที่มีอยู่`
- Info row under the cards: `#F5F8FC` with a blue `i` (`icons/ui-info.svg`) and a hint that depends on the mode:
  - new: `ถ่ายภาพจุดวางถัง/ปั๊ม · ระบุแหล่งน้ำในรายละเอียด`
  - existing: `ถ่ายภาพจุดที่ต่อแยกจากท่อเดิมให้เห็นขนาดท่อ · ระบุขนาดท่อและวาล์วในรายละเอียด`

### Card 3: photos
- Header: `3 ภาพประกอบ *`, with a counter on the right:
  - `2/2 ภาพ ✓` in green `#2E9E5B` when complete
  - `n/2 ภาพ · ขาดอีก k ภาพ` in red `#D9453B` bold when not
- Two tiles side by side, 196 pt tall, radius 12:
  - `ภาพพื้นที่ติดตั้ง *` → `photoArea`. Its caption depends on the mode: `จุดวางถังพักน้ำ / ปั๊มใหม่` / `จุดต่อแยกจากท่อเดิม`.
  - `ภาพมุมกว้าง *` → `photoWide`. Caption `<roof name> · จุดที่ต้องล้าง`.
- Filled tile: the photo, a caption pill at the bottom-left, and a clear button at the top-right (28 pt visual, 44 pt hit area).
- Empty tile: 2 pt dashed `#9FB3CB` on `#F5F8FC`. **Use the shared `PhotoSlot` from `docs/ui/photo-picker/CLAUDE_CODE_TASK.md`**, with Upload + Camera. If `PhotoSlot` doesn't exist yet, build that task first, or build it here the same way.

### Card 4: additional details
- Header: `4 รายละเอียดเพิ่มเติม`.
- Multi-line text field bound to `detail`; it fills the remaining height.
- Placeholder by mode, both marked as examples:
  - `ตัวอย่าง: วางถังพักน้ำ 1,000 ลิตร ข้างอาคาร · ใช้น้ำจากบ่อพักน้ำใส`
  - `ตัวอย่าง: ต่อแยกจากท่อ PVC 1 นิ้ว ข้างห้องปั๊ม มีวาล์วเดิม · แรงดันพอขึ้นหลังคา`

### Bottom bar
Use the shared `cardBar` / `InfoPageBar`:
- Status badge: 24 pt filled circle, green `✓` when complete, orange `!` when not.
- Status line:
  - complete: `ครบช่องบังคับแล้ว · จุดจ่ายน้ำแสดงบนภาพ A2 และรายงาน`
  - missing: `ยังขาดภาพประกอบอีก k ภาพ`, in red
- Previous: `B2 พื้นที่อินเวอร์เตอร์`. Next: `B4 ระบบกันย้อน`.

## Rules
- Do not change field ids, choice strings, labels, Excel cells or the Excel layout. B3 completion counts exactly as before.
- Old job JSON must decode. A water module without a `.water` mark simply shows no pin until one is tapped.
- iPad portrait and iPhone keep `groupPage`. Route to the wide page the same way B1/B2 do (`infoColumns`, `detailSize`). Make sure the page never pushes wider than the free space; see the overflow fix for A4.
- Every control is at least 44 pt. UI text stays Thai, exactly as in the design.
- The roof name, panel totals, times and texts in the previews are examples; never hard-code them.
- PDF: the existing water page should draw the A2 picture crop with the water pin, if it doesn't already.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass. Add tests:
   - tapping the picture creates or moves exactly one `.water` mark for this module
   - old JSON decodes
   - completion is unchanged
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add a debug page id, e.g. `-surveyPage water`, open it in the simulator at 1366 × 1024, and compare with the three previews. Flow:
   1. Switch the mode.
   2. Move the pin, then open A2 and check the same point is there.
   3. Remove a photo, check the badge turns orange, then add it back.
   4. Export the PDF.
4. Summarise the files changed and anything left open.
