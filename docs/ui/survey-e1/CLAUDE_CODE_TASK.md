# Claude Code task: E1 Summary and sign-off, wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-e1/CLAUDE_CODE_TASK.md`

## Goal
E1 (`JobEditor.Page.final`, "สรุปผลและลงนาม", the last page of the PDF) is still drawn by `groupPage(Schema.final, …)` in `JobEditor+Detail.swift`. Give it a designed wide page on iPad landscape that matches the previews. Everything fits on one screen, with no scrolling.

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of:
- `Schema.final`, `Options.verdict`
- the field ids `verdict`, `remarks`, `surveyorSign`, `reviewer`, `customerName`, `customerSign`
- `finalCompletion`, `missingGroups`, `missingSignatures`
- `PendingExport` / the export flow
- `SignatureField`, `SignaturePad` (`PhotoFields.swift`)
- `PhotoFolders` (signatures)
- the PDF last page and its Excel cells

Read the source before editing.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` / `preview.html` | default: `ติดตั้งได้ (มีเงื่อนไข)`, 2 suggestions added, surveyor signed, coordinator not signed |
| `states/01-verdict-installable.png` | `ติดตั้งได้`: green; the remarks aside `ไม่บังคับ` |
| `states/02-verdict-not-recommended.png` | `ไม่แนะนำให้ติดตั้ง`: red; the aside `ระบุเหตุผล` |
| `states/03-suggestions-all-added.png` | all 4 suggestions added; the box grows; `✓ ใส่ข้อเสนอแนะครบแล้ว · แก้ข้อความในช่องได้` |
| `states/04-remarks-empty.png` | empty remarks with the placeholder; all suggestions offered |
| `states/05-signature-pad-surveyor.png` | full-screen signature pad for the surveyor |
| `states/06-signature-pad-coordinator.png` | the same pad for the coordinator |
| `states/07-both-signed.png` | both signatures done |
| `states/08-surveyor-cleared.png` | after `เซ็นใหม่`: the box is empty, `แตะเพื่อเซ็นชื่อ`, and the chip shows `รอลงนาม` |
| `states/09-page-complete.png` | the page is complete; the bar shows `หน้านี้ครบแล้ว · ยังขาดอีก 2 หน้า (A2, D1)` |
| `iPadE1.dc.html` | design source: markup and logic (`renderVals`) |
| `icons/` | see Icons below |

## Data mapping (ids, choices and labels unchanged)
| UI | Field | Notes |
|---|---|---|
| `ผลการประเมินความเหมาะสมในการติดตั้ง *` | `verdict` | The exact `Options.verdict` strings. |
| `ความเห็น / เงื่อนไข / สิ่งที่ต้องแก้ไขก่อนติดตั้ง` | `remarks` (textarea, optional) | Editable text. Suggestions append numbered lines. |
| `วิศวกรผู้สำรวจ *` signature | `surveyorSign` (`.signature`) | The name under the line comes from `engineer` (A1). |
| `ผู้ประสานงาน / เจ้าของสถานที่ *` signature | `customerSign` (`.signature`) | — |
| name under the coordinator line | `customerName` | Editable inline (dashed underline). |
| `ผู้ตรวจสอบ` | `reviewer` (optional text) | — |

- **No schema change, no new stored fields.** Suggestions that have already been added are detected from the `remarks` text (see below), not stored separately.
- Completion stays exactly `Schema.final.completion`.

**Owner rule shown in the design (do not enforce as completion):** for `ติดตั้งได้ (มีเงื่อนไข)` the aside says `ระบุเงื่อนไขให้ครบ`, and for `ไม่แนะนำให้ติดตั้ง` it says `ระบุเหตุผล`. Both are bold in the verdict colour. For `ติดตั้งได้` it says `ไม่บังคับ` in muted grey. If the verdict is 2 or 3 and `remarks` is empty, also list `ความเห็น / เงื่อนไข` in the bottom-bar status as a warning. It does not block completion or export unless the owner decides otherwise; mention this in your summary.

## Layout (landscape, content width 1240, centred)
- Header: `E1 สรุปผลและลงนาม`, sub-title `แบบสำรวจ NO.<docNo> · <project code> · หน้าสุดท้ายของรายงาน PDF`.
- The 13-step progress strip `13/13 สรุปผลการสำรวจและลงนาม`.
- A two-column grid, `1fr : 2fr`, gap 28.

### Left column
1. **Verdict.** The label (16 pt bold, red `*`) above three full-width option buttons, each at least 48 pt tall, radius 10, with a 12 pt dot on the left and 15 pt bold text.
   - Selected: 2 pt border and a tint in the verdict colour; the dot is filled.
     - `ติดตั้งได้`: `#2E7D32`, tint 12%
     - `ติดตั้งได้ (มีเงื่อนไข)`: `#B26A00` text and border, tint `rgba(240,140,0,0.13)`
     - `ไม่แนะนำให้ติดตั้ง`: `#D9453B`, tint 12%
   - Not selected: 1 pt border `rgba(22,50,92,0.45)`, white, with a ring dot.
2. **Remarks.** The label plus the aside described above. A multi-line `TextEditor` (14.5 pt, 21 pt line height):
   - 150 pt tall, growing to about 236 pt when it holds more than 2 lines
   - placeholder `พิมพ์ความเห็น หรือแตะข้อเสนอแนะด้านล่าง`
3. **Suggestions** `ข้อเสนอแนะอัตโนมัติจาก AI · บนเครื่อง`, with the purple sparkle `e1-ai-sparkle` (`#5B4BC4`):
   - Each suggestion is a dashed purple row (1 pt `rgba(106,90,224,0.55)` on `#FBFAFF`, radius 10, at least 48 pt tall) showing its text, then its source page code in bold purple (`A3`, `D1`…), then `+ เพิ่ม` on the right.
   - Tapping a row appends `<n>. <text>` as a new line to `remarks`, numbered after the existing numbered lines, and removes the row.
   - `เพิ่มทั้งหมด` (top-right, at least 44 pt tall) appears when 2 or more rows remain.
   - When all rows are added: `✓ ใส่ข้อเสนอแนะครบแล้ว · แก้ข้อความในช่องได้` in green `#1E7B45`.
   - A suggestion counts as added when its text is already in `remarks`, after trimming the number prefix. So editing or deleting a line brings the row back. No extra storage.
   - Hide the whole block when there are no suggestions for the job.
4. **Missing on other pages** card (`ยังขาดในหน้าอื่น`, aside `ส่งออกได้ แต่จะยังไม่ครบ`):
   - One row per `missingGroups` entry except `.final`: the page code in bold (30 pt column), the missing items joined with ` · ` (one line, truncated), and a `ไปที่หน้า ›` button (at least 44 pt) that navigates to `group.target`.
   - Show at most 4 rows, then `และอีก n หน้า`.
   - Hide the card when nothing is missing elsewhere.

### Suggestions engine (on device)
Add `RemarkSuggestions.make(job:) -> [RemarkSuggestion]` in `TCRoofCore`, where `RemarkSuggestion` holds `text`, `source` (page code) and `target`.
- It is **rule-based and deterministic**, so it can be tested. Every number comes from the job; if the data isn't there, the rule doesn't fire.
- The four rules in the design (the texts are examples):
  - **Shade on a tank or roof (D/C pages):** shade = `มี` with `shadeFrom` set → `ตัดแต่ง<shadeFrom>ด้าน<shadeDir> <section title> ก่อนติดตั้ง`, plus the shading % when the layout has computed one.
  - **Flood (A4):** a reported flood or a GISTDA estimate → `ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ <Schema.recommendedEquipHeight> ซม.` plus `(<where> เคยน้ำท่วม <level> ซม.)` when known.
  - **Electrical data missing (A3):** a breaker IC or transformer %Z is empty → `ขอค่า IC ของ <breaker> และ %Z ของ <TX> ก่อนออกแบบ`.
  - **Anti-reverse (B1/B4):** daytime load < PV kW → `ต้องมีระบบกันย้อน (โหลดกลางวัน <x> kW < PV <y> kW)`. Use whatever B1/B4 already compute; don't invent a formula. If nothing computes it yet, leave the rule out and list it as open.
- The "AI" label stays as designed. Optionally, when Apple's on-device `FoundationModels` is available, it may smooth the Thai wording of a rule's text. It must keep every number and name. Wrap this in `#if canImport(FoundationModels)` with an availability check, and fall back to the rule text. This is optional; skip it if it complicates the build.

### Right column: `ลงนาม` (aside `เซ็นด้วย Apple Pencil หรือนิ้ว`)
Two equal signature cards fill the height, then a reviewer row.

**Signature card:** white, radius 14, a hairline border and a soft shadow.
- **Header row** (at least 52 pt): the title (16 pt bold, red `*`), then a status chip:
  - `✓ ลงนามแล้ว`: green `#1E7B45` on 14% green
  - `รอลงนาม`: `#C0392B` on 12% red
  - On the right, `เซ็นใหม่` (`e1-resign`, at least 44 pt) when signed. It clears the field and keeps the photo file for the undo window, as the current delete does.
- **Body:** a dotted-grid background (`#FCFDFE`, dots every 18 pt), a baseline at 30% from the bottom (inset 56 pt), and a `✕` mark at the left of the baseline.
  - Signed: the signature PNG, about 380 × 124, centred on the baseline.
  - Unsigned: `e1-sign-pen` plus `แตะเพื่อเซ็นชื่อ`; grey for the surveyor, red `#D9453B` for the coordinator when it is the missing one. Use red whenever a required signature is missing.
  - Under the baseline: `( <name> )` in 15 pt semibold, then `<role> · <d/M/พ.ศ.>`. The date is the signature photo's `takenAt` in the Buddhist calendar, e.g. `29/9/2569`; use today, grey, when unsigned.
  - Surveyor name = `engineer`. Coordinator name = `customerName`, edited inline with a dashed blue underline (at least 220 × 36 pt; tapping it doesn't open the pad).
  - If the photo exists in the job but not on this device: `ลายเซ็นอยู่บนเครื่องอื่น`, as now.
- Tapping the body opens the signature pad.

**Reviewer row** (at least 52 pt): `ผู้ตรวจสอบ` bold, the aside `ไม่บังคับ · ลงนามบนกระดาษ`, and on the right a 220 pt text field (`#F3F6FA`, radius 10) bound to `reviewer`.

### Signature pad (`states/05`, `06`)
Upgrade the shared `SignaturePad` and keep its API, so `groupPage` / iPhone also benefit.
- On iPad, present it as a `fullScreenCover` with a dimmed backdrop, the sheet inset 32 pt, radius 20.
- Top bar (buttons at least 48 pt): `ยกเลิก` (outline) | centre title `ลายเซ็น` + sub `<role> · <name>` | `ล้าง` (outline) | `บันทึก` (filled `#1F6FB5`).
- The `PKCanvasView` fills the rest, on `#FCFDFE` with radius 14. The baseline sits at 26% from the bottom, inset 80 pt, with a `×` at its left. Hint under it: `เซ็นชื่อเหนือเส้นด้วย Apple Pencil หรือนิ้ว`.
- Keep the PNG export exactly as now: light trait, bounds inset −12, scale 2, max side 900, `png: true`.

### Bottom bar (shared `cardBar`)
- Badge: green `✓` (`e1-status-ok`) when the whole job is complete, orange `!` (`e1-status-warn`) otherwise.
- Line 1: `บันทึกอัตโนมัติ HH:mm`.
- Line 2, in red unless everything is complete:
  - when this page has gaps: `ยังขาดในหน้านี้: <items joined by ", "> · และอีก n หน้า`, using `ผลการประเมิน`, `ลายเซ็นวิศวกรผู้สำรวจ`, `ลายเซ็นผู้ประสานงาน`
  - when only other pages have gaps: `หน้านี้ครบแล้ว · ยังขาดอีก n หน้า (<codes>)`
  - when nothing is missing: `ครบทุกหน้าแล้ว · พร้อมส่งออก`, in green
- Buttons:
  - `บันทึกร่างตอนนี้`
  - previous: sub-line `ก่อนหน้า 12/13`, then the real previous module title
  - primary: sub-line `ขั้นสุดท้าย`, then `สรุปผล · ส่งออก ›`. It runs the existing export flow (`pendingExport` with the gaps sheet), not a new one.

## Icons (`icons/`)
Add them to `Resources/A2Icons.xcassets` as PDF vectors and use them through `A2Icon(name:fallback:)`:

| Name | Fallback | Use |
|---|---|---|
| `e1-ai-sparkle` | `sparkle` | suggestions header (keeps its colour) |
| `e1-sign-pen` | `pencil.tip` | empty signature box (template image) |
| `e1-resign` | `arrow.counterclockwise` | `เซ็นใหม่` (template image) |
| `e1-chevron-left` / `e1-chevron-right` | `chevron.left` / `chevron.right` | bar buttons; reuse existing ones if present |
| `e1-status-ok` / `e1-status-warn` | `checkmark.circle.fill` / `exclamationmark.circle.fill` | bar badge; reuse `d1-status-*` if already added |

## Rules
- Do not change field ids, choice strings, labels, Excel cells, the PDF layout or completion.
- Old job JSON must decode. Jobs with free-text `remarks` keep their text untouched; suggestions only append.
- iPad portrait and iPhone keep `groupPage`, which gets the improved pad too. Route `.final` to the wide page the same way the other wide pages do, with the same free-width handling (`min(detailSize.width, 1240 + 48) − 48`, stacked below 1100 pt), so it never overflows.
- Every control is at least 44 pt. UI text stays Thai, exactly as in the design.
- The names (สมชาย ใจดี, สมหญิง รักษ์น้ำ, วิชัย ตรวจดี), dates, times, suggestion texts with their numbers, and the A2/D1 missing items in the previews are examples; never hard-code them.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass. Add tests for `RemarkSuggestions`:
   - each rule fires only with its data, and its numbers come from the job
   - added detection works on numbered lines, survives edits, and a deleted line returns the row
   - appending numbers after the existing lines
   - `Schema.final` completion is unchanged
   - old JSON decodes
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Add `-surveyPage final`, open it in the simulator at 1366 × 1024 and compare with `preview.png` and `states/01–09`. Flow:
   1. Switch all three verdicts.
   2. Add one suggestion, then `เพิ่มทั้งหมด`; delete a line and check the row returns.
   3. Sign both boxes, then `เซ็นใหม่`.
   4. Edit the coordinator name.
   5. Tap `ไปที่หน้า ›` on a missing row.
   6. Run `สรุปผล · ส่งออก` and check the PDF last page shows the verdict, remarks and both signatures.
4. Summarise the files changed, the suggestion rules implemented (and any left out because the data isn't computed yet), the verdict/remarks warning, and anything left open.
