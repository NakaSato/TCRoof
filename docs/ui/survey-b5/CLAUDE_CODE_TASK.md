# Claude Code task: B5 Emergency button, wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-b5/CLAUDE_CODE_TASK.md`

## Goal
B5 (`ModuleType.fts`, "ตู้ FTS และปุ่มฉุกเฉิน") is still drawn by the generic `groupPage`. Give it a designed wide page on iPad landscape that matches the previews:

| File | Shows |
|---|---|
| `preview.png` | default: photo taken, height 1.40 m OK, pin placed |
| `preview-missing.png` | photo missing: orange badge in the bottom bar, `ยังขาดภาพบังคับ 1 ภาพ` |
| `preview-height.png` | height 1.65 m outside the recommended range (⚠ in red), pin moved |
| `preview.html` | static render |
| `iPadB5.dc.html` | design source: markup and logic (`renderVals`) |

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of:
- `ModuleType.fts`, `photoFTS` / `photoEmg`
- `emgMountCm` (`FloodCheck.emergencyCm`, the A4 height check)
- `Progress` (`case .fts`), `stationSlots[.fts]`
- `SingleLineLayout` (emergency button, `hit(… .module(.fts))`)
- `siteMarks` / `MarkKind`
- the PDF page `ภาพตำแหน่งติดตั้งตู้ FTS และปุ่ม Emergency`
- the Excel slots

Read the source before editing.

## Product decision in this design (owner's request)
The owner asked that the FTS cabinet location **not** be recorded ("ไม่ต้องระบุตำแหน่งตู้ FTS"). The page only records the **Emergency (FTS switch) button**.

- Keep the field id `photoFTS`, its label, Excel cell and PDF slot, but make it `optional: true` and hidden from the wide page. An existing photo still prints.
- This changes B5 completion from 2 required photos to 1 (`photoEmg`). That is intended.
- Update `Progress` for `.fts` so a missing FTS photo no longer counts as a gap.
- Call this change out clearly in your summary.

## Layout (landscape, content width 1318)
Two columns: left 520, right flexible, gap 20. Cards are white, radius 16, with a hairline border and a soft shadow, the same as B3/B4.

### Left card: `1 ภาพพื้นที่ติดตั้งปุ่ม Emergency *`
- Sub-title: `จุดที่เข้าถึงได้ทันที`.
- Large photo slot bound to `photoEmg`, filling the card height:
  - Filled: the photo, with the done badge (`photo-done`, top-left), a clear button (`photo-clear`, top-right, 44 pt hit area), and a caption pill `วงจุดติดตั้งปุ่ม · ระบุความสูง`. Tap to view full screen.
  - Empty: dashed red border on `#F7F9FC`. **Use the shared `PhotoSlot` from `docs/ui/photo-picker/`** (Upload + Camera). The prototype shows a single "ถ่ายภาพ" button; the shared slot replaces it.
- Info rows under the photo (label on the left in `Home.muted`, bold value on the right):
  - `ตำแหน่ง`: a short text, e.g. `ผนังข้างประตู Site Office`. New optional field `emgPlace` (text). Tap to edit inline.
  - `สั่งตัด`: derived, not stored: `ตู้ FTS + อินเวอร์เตอร์ทุกเครื่อง`, or the inverter count from B2.
  - `ความสูงปุ่ม`: a stepper with − / + buttons (at least 44 pt) in 0.05 m steps, range 0.80–1.80 m. **Bound to the existing `emgMountCm`**, stored in cm and shown in metres with 2 decimals, so A4's flood check uses the same value.
    - Default: `FloodCheck.defaultEmergencyCm`.
    - 1.10–1.50 m shows `✓` in navy; outside that shows `⚠` in `#C0392B`.
    - Note: `emgMountCm` is currently `when: flooded` on A4. Make sure B5 can always read and write it. A4 shows it only when flooded, which is its own visibility rule, not the storage.

### Right column, card A: `ตำแหน่งบนภาพ A2` with the hint `แตะบนภาพเพื่อวางตำแหน่งปุ่ม FTS switch`
- The **A2 site picture itself** (`siteMap`), with A2's symbols and drawings, read-only except for this pin.
- Legend chip at the top-right: red dot + `ปุ่ม FTS switch (Emergency)`.
- Pin (`icons/b5-fts-pin.svg`):
  - 44 pt hit area with an orange halo `#F08C00`, a white circle, a red `#D9453B` ring and a red dot.
  - Label pill `FTS switch`: white 12.5 pt bold on `#D9453B`.
  - Tap anywhere on the picture to place or move it; a drag also works.
- **Store the pin as an A2 `siteMarks` entry of a new kind `MarkKind.emergency`**, one per B5 module:
  - Hidden from A2's palette, like `.water`.
  - Drawn on A2, in the PDF, and here.
  - Add its symbol to `SiteMarks.symbol` and the PDF ops, using the colours above.
  - No separate coordinate field.
- Cable or route lines are **not** drawn (owner's request).

### Right column, card B: `ใน SLD`
- Sub-title: `FTS ตัดวงจร DC · ปุ่ม Emergency สั่งตัด`. Right-aligned link `ดู SLD ทั้งหมด →` opens the SLD page.
- Shows a read-only crop of the existing SLD around the FTS / emergency button: inverters (B2), the FTS DC cut, PV arrays and the emergency button with its dashed control lines.
- Render it with `SingleLineLayout` ops cropped to that region; don't redraw it by hand. The labels come from the job (inverter count and kW, kWp).

### Bottom bar
Use the shared `cardBar` / `InfoPageBar`:
- 24 pt badge: green `✓` when complete, orange `!` otherwise.
- Status line:
  - `ยังขาดภาพบังคับ 1 ภาพ` when the photo is missing
  - otherwise `ความสูงปุ่มแนะนำ 1.10–1.50 ม.` when the height is out of range (a warning only; it doesn't block completion)
  - otherwise `ครบช่องบังคับแล้ว · ตำแหน่งแสดงบนภาพ A2 และ SLD`
- Previous: `B4 ระบบกันย้อน`. Next: `C1 หลังคา`.

## Rules
- Do not change field ids, labels, Excel cells or the Excel layout. The only completion change is the agreed `photoFTS` → optional.
- Old job JSON must decode. B5 modules without an `.emergency` mark show no pin until one is tapped. Jobs with a `photoFTS` keep it.
- iPad portrait and iPhone keep `groupPage`. Route to the wide page the same way B1/B2 do. Never push wider than the free space (see the A4 overflow fix).
- Every control is at least 44 pt. UI text stays Thai, exactly as in the design.
- The place text, height, inverter count, kWp and times in the previews are examples; never hard-code them.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass. Add tests:
   - tapping creates or moves exactly one `.emergency` mark
   - the B5 stepper writes `emgMountCm`, and the A4 `FloodCheck` row shows the same height
   - B5 completion needs only `photoEmg`
   - old JSON (with `photoFTS`, without `emgPlace` / the `.emergency` mark) decodes
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add `-surveyPage fts`, open it in the simulator at 1366 × 1024 and compare with the three previews. Flow:
   1. Remove and add the photo.
   2. Step the height to 1.65 m (⚠) and back.
   3. Move the pin, then open A2 and check the same point is there.
   4. Open the SLD from the link.
   5. Export the PDF.
4. Summarise the files changed, the `photoFTS` completion change, and anything left open.
