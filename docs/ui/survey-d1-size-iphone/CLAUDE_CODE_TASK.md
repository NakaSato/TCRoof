# Claude Code task: D1 ถังน้ำใส · 1/4 ขนาดถัง on iPhone

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-size-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Values in the previews (40 × 40 ม., 4.50 ม., 12°, the date) are **example data**.

## Goal
`TankPageWide` (+ `TankPageWide+Size.swift`, sub-tab "ขนาดถัง") was designed for iPad. On iPhone the survey pages now show in one column (commit "Use the designed survey pages on iPhone in one column"), but that column is not the phone design.

Make the D1 size sub-step on compact width (`horizontalSizeClass == .compact`) match `PhoneD1.dc.html` (390 × 844). Keep the iPad layout unchanged.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`):
- `TankPageWide`, `infoCard`, `TankStepper`, `TankPlan`, `Tank` (TCRoofCore), `TankCompass`, `PageStepBar` / `InfoPageBar`
- `tests_for` on `Tank` / `TankPlan` (`TankTests`)

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-screen.png` | First screen at 390 × 844 (@3x) |
| `states/02-full-length.png` / `.pdf` | The whole sub-step scrolled out, as one tall image. The PDF is **vector**; measure there. |
| `states/01-screen.pdf` | Vector first screen |
| `preview.html` + `grf.css` | Static render; inspect sizes and colours in a browser |
| `PhoneD1.dc.html` | Board source (inline CSS = exact values) |
| `svg/` + `svg/README.md` | Plan drawing and icons as SVG, with SF Symbol mapping |

## Layout, top to bottom (page `#F5F8FB`, margins 16, card gap 12)

### 1. Header and step line
- Same as the other iPhone steps: gradient header, title `D1 ถังน้ำใส 1`, sub `แบบสำรวจ NO.224 · GRF2567-23407`.
- Step line: `12/13` · `ถังน้ำใส 1` · orange chip `ยังขาด 2 ภาพ`, then 13 bars (6 pt).
- Reuse the shared iPhone header if it exists.

### 2. Sub-step tabs (D1 has 4 sub-steps)
- Row of 4: `ขนาดถัง` · `สิ่งกีดขวาง` · `จัดแผง` · `ภาพถ่าย`.
- Each item:
  - circle 26 pt with the number: current = `#1F6FB5` fill, white, 4 pt halo `rgba(31,111,181,.18)`; others = white with a grey border
  - label 12 pt below; current label is blue and bold
  - a 3 pt connector line `#DDE4ED` between circles
- Hit area ≥ 48 pt high. Tapping a tab switches the existing sub-tab state (`tab`).

### 3. Card 1 · `แปลนหลังคาถัง`
- Header: number tile `1`, title, chip `วาดจากขนาดถัง` (info style).
- **Plan**:
  - 326 × 296 inside a 1 pt `#DDE4ED` frame, radius 12
  - drawn from the tank size with `TankPlan`: outline navy 2 pt; dashed grid columns `1…11` / rows `A…K`; span dimensions `40.00` bottom and right; north arrow top-right, rotated by `ทิศของถัง`
  - full-screen button bottom-right: 36 pt white tile, 44 pt target
- Caption 12 pt: `แปลนหลังคาถังน้ำใส 40 × 40 ม. · หน่วย ม.`
- Reference: `svg/tank-plan-40x40.svg`. Draw it in code, not as an image.

### 4. Card 2 · `ข้อมูลถัง` (chip `✓ ครบ` / `ขาด n ช่อง`)
Labels are 14 pt semibold, with a red `*` when required. Controls are 44 high, radius 10.

- **`ขนาดถัง *`** (aside `เลือกจากรายการ`): dropdown showing `40 × 40 ม. · กปภ. มาตรฐาน`. Reuse the existing preset list, `+ กำหนดขนาดเอง`, and the change confirmation (`ตำแหน่งสิ่งกีดขวางเดิมอาจอยู่นอกแปลน`).
- **`ความสูงถัง *`** and **`ส่วนพ้นดิน`** side by side, each a stepper `− value ม. +`:
  - −/+ buttons 44 × 44
  - value field shows 2 decimals
  - step 0.1, using the existing `TankStepper` ranges
- **`ตำแหน่งถัง *`**: segmented `บนดิน` / `ฝังดิน` / `กึ่งฝัง`.
- **`ผิวหลังคา *`** (dropdown `คอนกรีต` …) and **`ดินกลบลึก`** (stepper, step 0.05) side by side.
- **`ทิศของถัง`** (aside `ผนังบน (แนว A) หันไปทิศ`):
  - value field `12°` + `เหนือ` (tap to type)
  - outline button `วัดด้วยเข็มทิศ` with the compass icon, which opens `TankCompass` (the iPad text `วัดด้วย iPad` becomes `วัดด้วยเข็มทิศ` on iPhone)
  - caption 12 pt grey: `วัดด้วยเข็มทิศ iPhone · ±3° · <date time> · แปลนหมุนตามค่านี้`

### 5. Bottom bar
- `บันทึก` (stretch) · `‹` `›` 72 × 53, icon only.
- VoiceOver: `ก่อนหน้า C1 หลังคา 2`, `ถัดไป D1 2/4 สิ่งกีดขวาง`.
- If `docs/ui/components/iphone-bottom-bar` has been implemented, use that bar.

## Rules
- Thai text exactly as in the previews.
- Colours from `Theme` / `Home`; no new hex literals in views.
- Touch targets ≥ 44 pt.
- Don't change `Tank` / `TankPlan` maths or saved keys. This is a layout task on compact width.
- The page scrolls vertically on iPhone (`states/02` is the full length). Keep the bottom bar fixed.

## Done when
- `xcodebuild` builds the app and TCRoofKit, and `TankTests` pass.
- On an iPhone 16 simulator, D1 · ขนาดถัง matches `states/01` (first screen) and `states/02` (scrolled).
- The other D1 sub-steps still work.
- The iPad D1 is unchanged (check an iPad Pro 13" screenshot).
- Summary of files changed and the remaining differences from the board.
