Read CLAUDE.md, then follow docs/ui/survey-d1-size/CLAUDE_CODE_TASK.md.

Build the iPad landscape wide page for D1 (ModuleType.tank): the page shell, the 4-tab sub-step bar, and sub-step 1 "ขนาดถัง" only. Tabs 2–4 keep the existing generic groups for now.

Match preview.png and states/01–10. Use iPadD1.dc.html (tab 1 and the compass modal) as the design source.

Key points:
- Use code-review-graph first, then read the source. Reuse RoofPageWide (shell, width handling, span editor) and Sketch.plan(tank: true) for the plan, so the PDF gets the same drawing.
- The size presets write expanded spansX/spansY strings ("4,4,…"); parseSpans has no "n@d" syntax.
- Existing ids stay: tankHeight, tankPos, surface, soilDepth, spansX/Y, tankType.
- New optional, hidden fields:
  - tankExposed (ส่วนพ้นดิน: = the height for บนดิน, 0 for ฝังดิน, editable for กึ่งฝัง)
  - tankAzimuth, tankAzimuthAt, tankAzimuthSrc
- The design omits tankType, which is still required. Add a compact ชนิดถัง menu under ขนาดถัง and flag it for the owner.
- "วัดด้วย iPad" opens a full-screen camera + CLLocationManager heading modal. It locks after 2 s stable and saves az = (wall − 90 + 360) % 360. Use manual entry on the simulator. The N arrow rotates by −az.
- Do not change field ids, labels, Excel cells or completion. Old JSON must decode. Controls ≥ 44 pt. UI text in Thai exactly as designed. The values in the previews are examples.
- Add -surveyPage tank. Run swift build and swift test with the new tests, and the CLAUDE.md xcodebuild with your own -derivedDataPath. Compare in the simulator at 1366 × 1024.
- Finish with a summary: the files changed, the new fields, the ชนิดถัง addition, and anything left open.
