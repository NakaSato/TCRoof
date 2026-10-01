# B1 ตู้ไฟฟ้าอาคาร — Swift dev spec (iPad + iPhone)

**Status:** Draft for development, 2026-10-01, from the canvas page `iPadB1` (ขั้น 5/13)
**Task:** [`CLAUDE_CODE_TASK.md`](CLAUDE_CODE_TASK.md)
**Design reference:** `preview.png` (1366 × 1024), `preview.html`, source `iPadB1.dc.html` (static markup, no logic)
**Icons:** `icons/` (§7)
**Targets:** `TCRoofKit` (TCRoofCore / SurveyUI / PDFReport)
**New dependencies:** none

## 1. What the page does

A job has one B1 section per building panel (`.panel` modules: โรงสูบน้ำ, อาคารสำนักงาน, โรงกรอง …). Today each section is its own `groupPage`. The new B1 page shows **all B1 sections on one page**: a master list on the left, the selected building in the middle and right. For each building the surveyor:

1. photographs the panel wide, and **marks the PV connection point** on the photo;
2. photographs the main breaker (AT / model readable);
3. **links the panel to its breaker in the A3 diagram** (`ตู้นี้ในผัง A3`), so AT and the SLD load come from one place;
4. enters the load (kW) and the time it was read;
5. sees at once whether total daytime load is below the PV size, which means zero export (B4) is needed.

## 2. Data (module `.panel`)

Existing fields keep their ids and meaning:

| Field | Now | B1 page |
|---|---|---|
| `name` (module name) | building name | card title and page heading |
| `photoWide` | required photo | `ภาพมุมกว้างของตู้ไฟฟ้า *` |
| `photoBreaker` | required photo | `ภาพเบรกเกอร์เมนของตู้ *` |
| `breakerAT` | number AT | still written: copied from the linked A3 breaker's AT; editable only when no A3 link exists |
| `loadKW` | number kW | `ปริมาณการใช้ไฟ *` |
| `loadTime` | text (`10 น.`) | chips `ตอนนี้` / `10:00` / `12:00` / `14:00`; `ตอนนี้` stores the current time `HH:mm` |
| `detail` | textarea | `รายละเอียดเพิ่มเติม` |

New optional fields (B1 completion counts as before):

| Field | Kind | Meaning |
|---|---|---|
| `a3Breaker` | text: `"{trafoIndex}/{boardId}/{breakerId}"` | the A3 breaker that feeds this panel; picker `ตู้นี้ในผัง A3` lists `{board name} · CB{n} {AT} AT` for every outgoing breaker of every A3 board |
| `pvPoint` | shape (`SiteShape` rect, points 0–1 on `photoWide`) | the marked connection point, drawn dashed teal |
| `spareSlots` | number | `ช่องว่าง {n} ช่อง`, shown in the marker label (`จุดเชื่อมต่อ PV · ช่องว่าง 2 ช่อง`) |

**Link both ways:** setting `a3Breaker` also writes the A3 `Breaker.target` to `ตู้ไฟฟ้า {name} (B{n})`, which the SLD already reads. That removes the fuzzy name matching in `SingleLine.loadText(for:)`. `SingleLine` should prefer `a3Breaker` and fall back to the text match for old jobs.

## 3. Rules (`TCRoofCore/BuildingPanels.swift`)

- **Card status pill:**
  - `ครบ` (green) when both photos and `loadKW` are present
  - else `{n}/2 ภาพ` (red) while a photo is missing
  - else `ยังไม่กรอกโหลด` (red)
- **Card sub-line:** `CB{n} · {AT} AT · โหลด {kW} kW`, or `… · ยังไม่กรอกโหลด`. `CB{n}` and AT come from the A3 link, else from `breakerAT`.
- **Daytime load note** (orange card under the load):
  - `โหลดกลางวันรวม {Σ loadKW} kW (ยังขาด{names without load}) · PV {kW} kW → ต้องมีระบบกันย้อน (B4)`
  - Σ over all B1 sections.
  - PV kW = Σ B2 `invSizes` when present, else A1 `capacity`.
  - The arrow text is `ต้องมีระบบกันย้อน (B4)` when Σ load < PV kW. Otherwise it is `โหลดมากกว่า PV · กันย้อนยังแนะนำตามเงื่อนไข กฟภ.` (open question 2).
  - Shown only when at least one load is entered.
- **Bottom status:** `ยังขาด: ภาพเบรกเกอร์ {names} · {name} ทั้ง 2 ภาพ` lists missing required items across every B1 section, grouped by building. The icon is `ui-alert` (red) when anything is missing, else `ui-check` (green), with `ครบทุกอาคาร`.
- **Delete (`ลบอาคาร`):** asks for confirmation. It removes the module and clears any A3 `Breaker.target` that pointed to it.

## 4. UI (`SurveyUI/PanelsPageWide.swift`)

iPad landscape, three columns in the 1240 pt content width: 240 · flexible · 380, gap 24.

**Left, `อาคาร`:**
- One card per B1 section: name, status pill, sub-line.
- The selected card has a 2 pt blue border on a light blue fill.
- `+ เพิ่มอาคาร` (dashed, 44 pt) adds a `.panel` module named `อาคาร {n}` and selects it.
- The header progress line reads `ตู้ไฟฟ้าอาคาร · {n} อาคาร`.

**Middle, the selected building:**
- Heading = name (tap to rename), `ลบอาคาร` (red outline) on the right.
- **`ภาพมุมกว้างของตู้ไฟฟ้า *`** (aside `ใช้พิจารณาจุดเชื่อมต่อระบบโซลาร์`), a 330 pt photo:
  - `b1-photo-done` badge top-left when present, `b1-photo-clear` top-right
  - hint chip `แตะภาพเพื่อวงจุดเชื่อมต่อ`
  - drag a rectangle to set `pvPoint`, drawn as `b1-connection-point` with a teal label above it
- **`ภาพเบรกเกอร์เมนของตู้ *`** (aside `เห็นป้าย AT / รุ่น ชัด`):
  - empty state: red dashed 250 pt box with `ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลขชัด` and the buttons `อัปโหลด` (`ui-upload-photo`) and `กล้อง` (`ui-camera`)
  - filled: the photo with the same badges
  - Optional later: read the AT from the photo with Live Text (see spec branch `spec/hardware-assist`).

**Right:**
- `ตู้นี้ในผัง A3`: picker on a mint background showing `MDP-1 · CB1 400 AT ▾`; `ยังไม่ได้เลือก` when empty. It lists the A3 outgoing breakers with the boards they belong to. A breaker already linked to another building shows that building's name.
- `ปริมาณการใช้ไฟ *`: number field with the unit `kW`; four time chips (44 pt).
- The daytime load note (§3).
- `รายละเอียดเพิ่มเติม`: textarea filling the remaining height.

**Bottom bar:** status (§3), `บันทึกร่างตอนนี้`, `‹ ก่อนหน้า 4/13 A4 น้ำท่วม`, `ถัดไป 6/13 B2 พื้นที่อินเวอร์เตอร์ ›`.

**Portrait / iPhone:** the master list becomes a horizontal chip row above the building. Columns stack. The existing per-section `groupPage` remains available from the sidebar.

## 5. Report and export

- **PDF:** the B1 unit per building, as now (`ReportLayout` ~line 544). Also draw `pvPoint` on the wide photo (teal dashed rectangle and label), and print `ตู้ใน A3: {board} · CB{n} {AT} AT`.
- **Excel:** unchanged cells (`ExcelExporter` ~lines 126–127). `breakerAT` is still written.
- **SLD:**
  - Load blocks read the linked building first.
  - When the building has no link, the SLD still falls back to its current name matching.
  - `โหลด ? (B1)` disappears once `loadKW` is filled on a linked building.

## 6. Tests

| Test | Expect |
|---|---|
| status pill | photos 1/2 → `1/2 ภาพ`; both photos, no load → `ยังไม่กรอกโหลด`; all → `ครบ` |
| A3 link | setting `a3Breaker` writes `breakerAT` from the A3 breaker and `Breaker.target`; deleting the building clears the target |
| daytime note | 85 + 22 kW with one building missing, PV 120 → `โหลดกลางวันรวม 107 kW (ยังขาดโรงกรอง) · PV 120 kW → ต้องมีระบบกันย้อน (B4)` |
| `ตอนนี้` chip | stores `HH:mm` of now |
| SLD | a linked building's `loadKW` shows on its SLD load block; an unlinked old job still matches by name |
| old jobs | B1 sections with only `breakerAT` / `loadKW` / `loadTime` open and count as before |

## 7. Icons (`icons/`)

`icons/icons.png` shows them all. Formats: `svg/`, `png/` @1x/@2x/@3x, and `B1Icons.xcassets` (PDF vector; `ui-*` are template images).

| File | Use |
|---|---|
| `b1-connection-point` | dashed teal PV connection marker on the wide photo (draw it as a shape; the icon is for legends / hints) |
| `b1-photo-done` | green check badge on a photo that is present |
| `b1-photo-clear` | dark round clear button on a photo |
| `b1-status-missing` | red alert in the bottom bar / list |
| `ui-check`, `ui-close`, `ui-upload-photo`, `ui-camera`, `ui-alert`, `ui-prev`, `ui-next`, `ui-add` | page controls |

Copy `B1Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/` next to the other catalogs, and use `Image(name, bundle: .module)`.

## 8. Open questions

1. Load time chips: are 10:00 / 12:00 / 14:00 the times the team reads load, or should any time be allowed?
2. Should zero export be flagged only when Σ daytime load < PV, or always (กฟภ. rules)?
3. `spareSlots`: record it here or on the A3 board (it describes the board)?
4. A building fed from a sub-board, not straight from the MDB: should the picker include sub-board breakers? (The design shows the MDP-1 breakers.)
