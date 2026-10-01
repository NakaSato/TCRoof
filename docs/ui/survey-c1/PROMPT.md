# Prompt to paste into Claude Code (run from the TCRoof repo)

```
Follow docs/ui/survey-c1/CLAUDE_CODE_TASK.md.

Build the C1 roof "แปลน + โครงสร้าง" wide page for iPad landscape. It must fit on one screen with no scrolling, and match preview.png and all 17 images in states/. iPadC1.dc.html is the executable spec: plan geometry, section A-A geometry, PV packing, member lists and defaults are all in its renderVals().

Left:
- Interactive roof plan: grid and dimension chains from spansX/spansY; span chips open a popover (± 0.5, quick values, split, delete, next, EQ, all 4.00); + adds a span; ridge line from ridgeDir; frame lines by frameType; purlins; posts with an "แก้เสา" toggle mode; slope arrows; section mark A-A; skylights that toggle วางทับได้ / ห้ามวางทับ (stored in obst).
- "จัดแผง" mode: PV packing preview using the default module from the equipment catalogue, with keep-out zones drawn by drag (stored in obst) and a portrait/landscape toggle. It shows the count and kWp only; do not overwrite panelsBefore.
- Below the plan: a true-scale section A-A for the 5 frame types (ปกติ / Pratt / Warren / ขื่อรัด / จันทันถัก+T2) with dimensions, callouts ①–⑦ and a bays-per-side stepper (trussBays).

Right:
- Roof info: roofShape and roofMaterial dropdowns mapped onto the existing options (others go to "อื่นๆ" + text), panelsBefore, ridge นอน/ตั้ง (write sheetDir back), ไม้/เหล็ก → roofStructure, frame type.
- Member sizes 1–7 stored in comp1…comp7 as "size @spacing", with display names per frame type, thumbnails and profile glyphs from icons/, and a picker popover.
- 6-angle photo checklist mapped to aerialPhoto, generalPhotos and structPhotos, using the shared PhotoSlot.
- The shared bottom bar with the ✓ / ! badge and the missing-angles status. This is a warning only; Progress is unchanged.

Use code-review-graph first to find every reader of spansX/spansY, sheetDir, obst, plan/planPhoto/diag, comp1–7, roofShape/roofMaterial/roofStructure and the roof photos (Sketch, SiteModels, Progress, PDF, Excel, MemberPicker).

Rules:
- Keep all existing ids, labels, choice strings and Excel cells. New fields are optional and hidden; completion is unchanged.
- Old JSON must decode, and free-text values must survive.
- iPad portrait and iPhone keep groupPage. The page must never overflow the free width.
- Every control is at least 44 pt (enlarge hit areas for the small plan chips). UI text stays Thai.
- Numbers in the previews are examples.
- Build the plan and section with DrawOp so the PDF reuses them.

Verify:
- swift test plus new tests: old JSON decodes; span round-trip to the comma string; ridgeDir ↔ sheetDir; the comp mapping; PV count = 84 for the default 19×16 Pratt portrait roof; completion unchanged.
- xcodebuild with your own -derivedDataPath.
- Add -surveyPage roof and compare it with every state image in the simulator.

Finish with a summary of the files changed, the comp display-name mapping, the roofShape/roofMaterial mapping, the sheetDir convention you confirmed, and anything left open.
```
