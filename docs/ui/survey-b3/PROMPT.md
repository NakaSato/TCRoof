# Prompt to paste into Claude Code (run from the TCRoof repo)

```
Follow docs/ui/survey-b3/CLAUDE_CODE_TASK.md.

Build the B3 "ระบบน้ำล้างแผง" wide page for iPad landscape, matching preview.png, preview-new.png and preview-missing.png. It has four numbered cards:
1. the A2 site picture with a tappable water-point pin, stored as A2's siteMarks .water mark (no new coordinate field)
2. the two water-mode choice cards bound to waterMode
3. photoArea and photoWide tiles using the shared PhotoSlot from docs/ui/photo-picker
4. the detail text
Use the shared bottom bar with the green ✓ / orange ! badge.

Use code-review-graph first to find every reader of the water module, waterMode, photoArea/photoWide, MarkKind.water and siteMarks.

Keep field ids, choice strings, Excel and completion unchanged. Old JSON must decode. iPad portrait and iPhone keep groupPage. The page must never overflow the free width. Every control is at least 44 pt, and UI text stays Thai.

Verify with swift test plus new tests (pin creates or moves one .water mark; old JSON decodes) and xcodebuild with your own -derivedDataPath. Add -surveyPage water and check it in the simulator against the previews. Finish with a list of the files you changed.
```
