# iPad A3 หม้อแปลง · MDB · v3 (picker menus, CB editor, LV-only meter)

Board: `iPadA3.dc.html`. Open it in a browser next to `grf.css`. It is interactive:
- tap TX 1's size, a nameplate field, the MDP's AT / AF / Icu / ยี่ห้อ
- tap a CB ลูกย่อย row
- tap `0.4` under the meter

States (@2x of 1366 × 1024) are in `states/`:

| File | State |
|---|---|
| `00-before-main.png` | The `docs/ui/a2-a3-autofill` board: what `main` builds today |
| `01-default.png` | The new board: TX 1 at 630 kVA, read from its nameplate photo |
| `02-size-menu.png` | TX 1's size menu open |
| `03-size-400.png` | 400 kVA picked: standard values filled, `In แรงต่ำ` hint |
| `04-field-menu.png` | A nameplate field's menu open (Vector group) |
| `05-mdb-at-menu.png` | MDP-1 main breaker's AT menu open |
| `06-cb-editor.png` | CB ลูกย่อย 3's editor open |
| `07-lv-no-transformer.png` | Meter at 0.4 kV: no transformer, MDBs fed from the meter |

The labels, lists and standard values are in `assets/sample-data.json`. They are board examples. The lists and the standard values must be confirmed with the team (§6). Never hard-code a job's example answers.

## 1. What changed on the board (compared with `00-before-main`)

1. **Header of the flow card.**
   - The `ดึงจากภาพ A2 · 4 รายการ ▾` button is now a compact `A2 ใส่จากภาพ A2` button. It opens the same panel.
   - The subtitle `กรอกทุกอย่างในผังนี้ ·` is gone; only the flow line stays.
2. **TX size.** `kVA` is a menu of the standard sizes, which the app already has (`kvaSizes`). Picking a size:
   - fills the empty nameplate fields with the size's standard values (V, vector group, %Z);
   - shows a hint `In แรงต่ำ ≈ n A` under the row, from kVA × 1000 / (√3 × 400).
   Values read from the nameplate photo (630 kVA in the example) stay as they are.
3. **Nameplate fields as menus.**
   - V, Vector group, %Z, ยี่ห้อ and ปีผลิต each open a short menu.
   - Each menu has an `อื่น ๆ` / free-text way out, so any plate can still be typed.
4. **MDP main breaker.**
   - AT, AF and Icu are menus with a `+ เพิ่ม` custom value.
   - AF offers `อัตโนมัติ`: the smallest AF ≥ AT, shown until the person sets one.
   - `ยี่ห้อ / รุ่น` is split into a ยี่ห้อ menu and a รุ่น text field.
5. **CB ลูกย่อย rows.**
   - Each row is tappable and opens an editor `CB ลูกย่อย n` with AT / AF (อัตโนมัติ) / Icu / ยี่ห้อ menus, `+ เพิ่ม`, สภาพ `ดี | พอใช้ | ชำรุด` and `เสร็จ`.
   - A row missing Icu or brand reads red (the app already marks `?kA` and `ยี่ห้อ ?`).
   - A hint under the list: `แตะแถวเพื่อแก้ AT/AF/Icu/ยี่ห้อ/สภาพ`.
6. **Meter at 0.4 kV: no transformer.**
   - When `meterKV` is `0.4`, the page title is `A3 มิเตอร์แรงต่ำ · MDB` and the flow line reads `มิเตอร์แรงต่ำ 0.4 kV → ตู้ MDB · ไม่มีหม้อแปลง`.
   - The transformer column is hidden. A chip `0.4 kV ไม่มีหม้อแปลง` sits on the meter, and the MDBs hang off the meter, with `+ เพิ่ม MDB`.
   - The meter shows a size menu: `15(45) A`, `30(100) A`, `50(150) A`, `CT` (CT shows the CT ratio, e.g. `400/5 A`).
7. **Bottom bar.**
   - The missing-photo line follows what's actually missing (the LV mode lists no TX).
   - The saved state reads `บันทึกร่างแล้ว`.

What does **not** change:
- The diagram's geometry, folding, zoom, the photo tiles, nameplate scan / OCR (`NameplateParser`, `platePhotoSuggestion`).
- `SiteSync` and the A2 panel's content.
- The SLD page, the iPhone A3 (`ElectricalPageWide+Phone.swift`).
- Every schema id, label and Excel cell; the PDF and DXF.

## 2. Scope

Only the iPad `ElectricalPageWide`:
- `ElectricalPageWide.swift`: `cardHeader`, the bottom line;
- `ElectricalPageWide+Cards.swift`: `meterCard`, `kvaField`, `openTransformer`, `mainBoardCard`, `breakerList` / `breakerRow`, the breaker editor at the end of the file;
- `ElectricalPageWide+A2.swift`: only the button's label.

Out of scope. Do not touch:
- The iPhone page.
- `SingleLinePage*`, the SLD and its DXF.
- `Schema` ids and labels, `ExcelExporter`, `ReportLayout`.
- `SiteSync`'s rules.
- Other pages.

## 3. Read first

Start with the code-review-graph tools, as CLAUDE.md says (`get_impact_radius_tool` on `Transformer`, `Board`, `Breaker` and `meterKV`). Then read:
- `ElectricalPageWide.swift`: the layout constants, `card`, `cardHeader`, `diagram`, `connectors`, `add`, `edit`, `editBoards`, `breakerBinding`, `gaps`.
- `ElectricalPageWide+Cards.swift`: in full.
- `ElectricalPageWide+A2.swift`: `A2SyncCache`, the panel button.
- `TCRoofCore/Models.swift`: `Transformer`, `Board`, `Breaker` and their `init(from:)`.
- `TCRoofCore/SiteSync.swift`: around `ยังไม่มีหม้อแปลงใน A3`.
- Every reader of `trafos` and `meterKV`: the SLD (`SingleLine`), `Progress`, the PDF, Excel, `Flood`, B1 / B2 / B4.
- `docs/ui/survey-a3/` and `docs/ui/a2-a3-autofill/` for the earlier specs.

## 4. Change list (in order)

1. **Header.**
   - `cardHeader`: drop the `กรอกทุกอย่างในผังนี้ ·` text.
   - Make the A2 button compact: `A2Badge` + `ใส่จากภาพ A2`, min 44 high, opening the same panel.
   - Keep its accessibility label naming the count (`ดึงจากภาพ A2 · n รายการ`).
2. **Standard values on a size pick.**
   - Add `TransformerStandard` in TCRoofCore (pure, tested): for a kVA it returns the board's standard voltage, vector group and %Z (§6 Q1), and `lvCurrent(kva:)` = kVA × 1000 / (√3 × 400), rounded.
   - In `kvaField`'s menu, after setting `kva`, fill only the **empty** `voltage`, `vectorGroup` and `impedance`, and mark their source as the standard so the field shows it as suggested, not measured. Use the existing `Values` source mechanism if it fits; otherwise no badge.
   - Never overwrite a value typed by the person or read from the plate.
   - Show the `In แรงต่ำ ≈ n A` hint under the size row.
3. **Nameplate menus.**
   - Make a small reusable `A3MenuField` (label, value, options, `อื่น ๆ` → text entry, required flag), built from `A3Input`'s look. Don't fork `A3Input`.
   - Use it for V, Vector group, %Z, ยี่ห้อ and ปีผลิต in `openTransformer`. The bindings stay `plateText` / `tText`, so plate sources and `forgetSource` keep working.
   - The option lists live in one place (`ElectricalPageWide.Options` or TCRoofCore), not inline in views.
4. **Main breaker.**
   - In `mainBoardCard`, AT / AF / Icu use `A3MenuField` with `+ เพิ่ม`.
   - AF shows `อัตโนมัติ (n)` while `af` is empty. n = the smallest AF ≥ AT. Store nothing until the person picks; keep `af` empty in that case and decide with the team whether export should use the derived value (§6 Q3).
   - Split `ยี่ห้อ / รุ่น`: a ยี่ห้อ menu writes `Board.brand`. รุ่น needs a new optional `Board.model` (`decodeIfPresent`, default `""`).
   - Everything that printed `brand` before must print `brand + " " + model` when model is set: find every reader of `Board.brand` (PDF, Excel, SLD) first. This keeps one cell, so Excel addresses don't change.
5. **CB ลูกย่อย editor.**
   - Make each `breakerRow` a button that opens the existing breaker editor (the struct at the end of `+Cards`, via `breakerBinding`), restyled as the board's popover anchored to the row: title `CB ลูกย่อย n`, AT / AF (อัตโนมัติ) / Icu / ยี่ห้อ as `A3MenuField`, สภาพ segments writing `Breaker.condition`, `เสร็จ`.
   - Keep its other fields (poles, target, cable…) as they are, below.
   - Add the hint line under the list.
6. **LV-only meter.**
   - When `meterKV == "0.4"`: title and flow line as §1.6, transformer column hidden, MDBs drawn from the meter.
   - **Data:** don't invent a new structure until you have read every `trafos` reader. Proposed default: keep the boards under `trafos[0]`, and add an optional `Transformer.lvSupply: Bool` (`decodeIfPresent`, default `false`) meaning "no transformer; these boards are fed at 0.4 kV from the meter". Then:
     - `Progress`, the PDF, Excel, the SLD and `SiteSync` skip the transformer fields and photos for it, but keep its boards;
     - `gaps` drops the TX photo gaps;
     - switching from 0.4 back to 22 / 33 asks before turning it into a transformer.
   - If that touches more than the readers listed in §3, stop after the UI and report the readers instead (§6 Q4).
   - The meter size menu: `15(45) A | 30(100) A | 50(150) A | CT`. It writes the existing `meterCT` text field: the size, or the CT ratio for CT. No new id.
7. **Bottom bar.**
   - The missing-photo line from `gaps` (it already lists them).
   - `บันทึกร่างแล้ว` as the saved label, if the shared bar takes a per-page label. Otherwise leave it and say so.
8. **Debug and tests.**
   - Add `-surveyA3 size|field|mdbat|cb|lv` (with `-surveyPage electrical`) to open states 02, 04, 05, 06 and 07.
   - `-surveyA3 lv` sets `meterKV` to `0.4` on the opened job.
   - Unit tests:
     - `TransformerStandard`: every size, the 630 / 800 %Z edge, `lvCurrent`;
     - `Board.model` and `Transformer.lvSupply` decode from old JSON;
     - the AF auto pick.
   - A UI test `PadA3PickersUITests` (iPad):
     - pick 400 kVA: the empty V fills, a typed one stays;
     - open a CB row, set Icu, `เสร็จ`: the row no longer reads `?kA`;
     - set the meter to 0.4: the TX column is gone.
   - Add the flags and the test to CLAUDE.md in the style of the other entries.

## 5. Rules

- Data rules from CLAUDE.md:
  - Existing ids, labels and Excel cells don't change.
  - New fields are optional with `decodeIfPresent` defaults.
  - Find every reader before editing.
- Colours from `Theme`, no hex literals; `TCButtonStyle` / plain buttons as the file already does.
- Hit areas ≥ 44 pt. Menus are system `Menu`s unless the board's look needs a popover.
- Each card, menu field and popover is its own computed property or view. Long expressions crash Debug builds.
- The iPhone A3 must look the same; take one screenshot.
- Run `swift test` in `TCRoofKit`. Build the app with xcodebuild, with your own `-derivedDataPath`, in the background.
- Save simulator screenshots named like `states/` to `screenshots/`.

## 6. Open questions (answer in the report, ask the team before merging)

1. **Standard values per size.** The board fills 22k/230-400, Dyn11, %Z 4 up to 630 kVA and 6 above. Are these the team's standard (PEA 22 kV)? What about PEA 33 kV areas, where V should follow `meterKV`? The default is to follow `meterKV` for V and the board for the rest.
2. **Option lists.** Are the brand lists (transformer and breaker), the V list, and the AT / AF / Icu lists in `assets/sample-data.json` right? Should they be team-editable (a `config/` document) rather than in code? The default is in code.
3. **AF อัตโนมัติ.** Should export (Excel / PDF / SLD) print the derived AF when `af` is empty, or leave it blank? The default is blank, with the UI showing the derived value as a suggestion.
4. **LV-only storage.** Is `Transformer.lvSupply` acceptable, or should LV boards live outside `trafos`? And what should Excel's transformer cells hold for an LV-only job: blank, or `ไม่มีหม้อแปลง`?
5. **Meter size.** Is writing it into `meterCT` enough, or should it get its own optional field?
