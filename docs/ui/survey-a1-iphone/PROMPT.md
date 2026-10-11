Follow docs/ui/survey-a1-iphone/CLAUDE_CODE_TASK.md

Give survey step A1 ข้อมูลโครงการ its iPhone design from docs/ui/survey-a1-iphone (board `PhoneA1.dc.html`, 390 × 844).

Scope: compact width only. Add `InfoPageWide+Phone.swift` with a `phoneBody`, like `TankPageWide+Phone.swift` does for D1. The iPad `InfoPageWide` (two columns in landscape, one in portrait) must not change.

1. **Header and step line.**
   - Shared iPhone step header: `A1 ข้อมูลโครงการ`, sub `แบบสำรวจ NO.224 · GRF2567-23407`.
   - `PageStepBar(compact: true)`: `1/13 ข้อมูลโครงการ`, chip `ครบ 11/11 ช่อง` (green) or `ขาด n ช่อง` (orange), and 13 bars of 6 pt.
2. **Full-bleed white bands** instead of cards:
   - 1 pt `#DDE4ED` borders, padding 12 / 16 / 14, gap 12.
   - Each band header: a big blue two-digit number (`01`, 24 pt / 800), a 1 × 18 divider, a 16 pt bold title and a `✓ n/m` chip.
3. **New order:**
   - `01 โครงการ`: name; `ขนาดติดตั้ง` (kWp) | `อินเทอร์เน็ต` segmented `มี` / `ไม่มี`.
   - `02 ที่ตั้ง`:
     - `SiteMapPreview`, 170 pt high, with overlays: zoom chips `พื้นที่ 500 ม.` · `สถานี 200 ม.` · `อาคาร 50 ม.` (selected chip mint), `+` / `−`, the hint `ลากหมุดเพื่อปรับ · ระดับซูมนี้ใช้ในรายงาน`, a scale bar and the pin
     - `พิกัด Google Map` with a 44 pt GPS button
     - station address
     - `officeAddress` (`ไม่บังคับ`) with a `คัดลอก` button that copies `address`
   - `03 ผู้ประสานงาน`: name | phone, with a tap-to-call icon.
   - `04 เอกสาร`: `เลขที่` | `REV.` (72 pt column); `วันที่สำรวจ` (calendar) | `วิศวกรผู้สำรวจ` (read-only, grey, lock, aside `จากการตั้งค่า`).
   - `05`: keep the existing areas box last.
4. **Fields:**
   - labels 14 pt semibold with a red `*`
   - inputs 44 pt high, r10, 1 pt navy 35% stroke
   - pre-filled fields keep the mint fill
   - reuse `inputBox`, `FieldLabel` and `RatioRow`
5. **Bottom bar:**
   - `บันทึก` is a fixed 104 pt outlined button with states idle → spinner → green `✓ บันทึกแล้ว` → green outline. Editing resets it to idle.
   - `‹` `›` fill the rest; `‹` is disabled on A1.
   - Apply the 104 pt save button in the shared `BottomBar`, so every phone step gets it.

**Rules.**
- Thai text exactly as in the previews; every value shown is example data (`assets/sample-data.json`).
- No hex literals in views.
- Touch targets ≥ 44 pt.
- Layout only: keep the `Schema.info` ids, Excel / PDF output and completion counts.
- Use code-review-graph first, then read the source.
- Branch `feat/iphone-a1`.

**Verify.**
- Build, then compare an iPhone 16 simulator against `states/01-screen.png` and `states/02-full-length.png` (measure in the PDFs) and against the save states `04`–`06`.
- Check that iPad A1 is unchanged.
