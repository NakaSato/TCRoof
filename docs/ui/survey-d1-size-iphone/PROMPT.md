Follow docs/ui/survey-d1-size-iphone/CLAUDE_CODE_TASK.md

Make D1 ถังน้ำใส · sub-step 1/4 `ขนาดถัง` on iPhone (horizontalSizeClass == .compact) match docs/ui/survey-d1-size-iphone/states/01-screen.png and states/02-full-length.png (390 pt wide). Keep the iPad layout unchanged.

1. Header + step line `12/13 · ถังน้ำใส 1 · ยังขาด 2 ภาพ` + 13 bars, as on the other iPhone steps.
2. Sub-step tabs `ขนาดถัง · สิ่งกีดขวาง · จัดแผง · ภาพถ่าย`:
   - numbered 26 pt circles joined by a 3 pt line; current one blue with a halo
   - labels 12 pt
   - tap switches the existing sub-tab
3. Card 1 `แปลนหลังคาถัง`:
   - chip `วาดจากขนาดถัง`
   - plan 326 × 296 drawn in code with TankPlan: grid A–K × 1–11, spans `40.00`, north arrow rotated by the azimuth
   - full-screen button
   - caption `แปลนหลังคาถังน้ำใส 40 × 40 ม. · หน่วย ม.`
4. Card 2 `ข้อมูลถัง` (chip `✓ ครบ`):
   - size dropdown (existing presets + custom + change confirmation)
   - `ความสูงถัง` | `ส่วนพ้นดิน` steppers side by side (44 pt − / +)
   - `ตำแหน่งถัง` segmented `บนดิน / ฝังดิน / กึ่งฝัง`
   - `ผิวหลังคา` dropdown | `ดินกลบลึก` stepper
   - `ทิศของถัง`: value `12° เหนือ` + outline button `วัดด้วยเข็มทิศ` (TankCompass) + the caption line
5. Bottom bar `บันทึก` + ‹ › 72 × 53, with VoiceOver step names.

Reuse TankStepper, TankPlan, TankCompass and the existing Tank keys; layout changes only. Thai text exactly as in the previews; colours from Theme/Home; touch targets ≥ 44 pt. Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch feat/iphone-d1-size. Build, run TankTests, compare on an iPhone 16 simulator, and check that the iPad D1 is unchanged. Finish with a summary of files changed and the remaining differences.
