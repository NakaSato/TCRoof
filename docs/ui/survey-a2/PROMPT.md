# Prompt to paste into Claude Code (run from the TCRoof repo)

```
Implement the A2 site-picture page design v2 on iPad.

Read docs/ui/survey-a2/CLAUDE_CODE_TASK_v2.md in full and follow it. Use these references in the same folder:
- preview.png, preview-layers.png, preview-locked.png, preview-fullscreen.png (1366×1024 landscape)
- iPadA2.dc.html (the design source; the <script> renderVals block holds the interaction logic)
- icons/ (A2Icons.xcassets, svg, png)

SitePageWide already implements v1 (docs/ui/survey-a2/CLAUDE_CODE_TASK.md). Treat this as a delta and keep everything v1 does.

Before editing, use the code-review-graph tools as CLAUDE.md says. Find every caller/reader of SitePageWide, layerBar, undo(), SiteShapes, SiteMarks.ops, MarkKind.paletteTitle/paletteDetail and cardBar, then read the source.

Scope:
1. Layout: picture card 860 wide, right column fills the rest, gap 24, one screen with no scroll.
2. New picture toolbar:
   - tool group: Select (new) / Panel area / Cable route / Measure
   - Undo + Redo (new redo stack, cleared on any new edit)
   - Lock toggle (orange when on)
   - right side: "ชั้น n/5" layers dropdown and a full-screen button
   Also: a 38 pt north button, and a navy hint banner bottom-left that replaces the old layer bar.
3. Layers dropdown with 5 rows (✓ on / ○ off), using the existing `layers` set.
4. Full-screen mode: dark #0E1A2B background, same tools and the same undo history, pinch-to-zoom, and the building-model panel on the right.
5. Building models (new):
   - Cards are built from the job's sections (D tank, C roofs, B1 buildings, B2 inverter room); don't hard-code them.
   - Drag a card onto the picture to place a footprint at real scale, using siteScale or the Google zoom. With no scale, show "ต้องตั้งสเกลก่อน" and offer the Measure tool; never guess a scale.
   - Select, move, rotate ±15° / 90°, lock per model or globally, and remove.
   - Store only position, rotation and lock in the new optional keys siteModels and siteModelsLocked. Read sizes live from the source sections.
   - In the PDF, draw placed models as vector outlines with name tags.
6. Copy changes in the right column:
   - "Zero Export"; "Weather" with "สถานีอากาศ"
   - "ติ๊กอัตโนมัติเมื่อวาง"
   - icon-only 44×44 LIST shortcuts with accessibility labels
   - "ไม่บังคับ · ใต้ภาพในรายงาน"
7. Bottom bar (cardBar, so every survey page gets it): a 24 pt filled status badge, green #2E9E5B ✓ when complete and orange #F08C00 ! when items are missing. Status text is #5B6B82 when complete, #D9453B when not.
8. Icons:
   - Replace TCRoofKit/Sources/SurveyUI/Resources/A2Icons.xcassets with docs/ui/survey-a2/icons/A2Icons.xcassets.
   - Use A2Icon(name:fallback:) with an SF Symbol fallback for every new icon.
   - ui/ icons are templates; ui-north and model-* keep their colours.
   - Draw model skins on the picture in code at real scale; never stretch the icon.

Rules:
- Do not change any existing field id, label, Excel cell or Excel layout.
- New keys are optional and hidden from the form (when: { _ in false }), so A2 completion is unchanged.
- Old job JSON must still decode (decodeIfPresent with defaults).
- iPad portrait and iPhone keep groupPage.
- Every control is at least 44 pt.
- All UI text stays Thai, exactly as in the design.
- Values in the previews are examples (TX 1 630 kVA, MDP-1 800AT, 312 panels, 38.8 m, building names and sizes, the note text). Never hard-code them.

Verify before finishing:
- In TCRoofKit: swift build and swift test.
- xcodebuild with your own -derivedDataPath, as CLAUDE.md says (the user keeps Xcode open).
- Add tests:
  - old JSON without siteModels decodes
  - a model's size follows its source section
  - redo restores an undone edit, and a new edit clears redo
- Run the simulator with -screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage site. Compare against all four previews and run this flow:
  1. Select a symbol and move it; undo, then redo.
  2. Hide the grid layer.
  3. Enter full screen.
  4. Drag D1 onto the picture, rotate it 15° and lock it; confirm it can no longer be dragged.
  5. Exit full screen.
  6. Export the PDF and check the model outline.
- Finish with a list of the files you changed and anything left open.
```
