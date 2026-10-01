# Prompt to paste into Claude Code (run from the TCRoof repo)

```
Follow docs/ui/survey-b5/CLAUDE_CODE_TASK.md.

Build the B5 "ปุ่ม Emergency" wide page for iPad landscape, matching preview.png, preview-missing.png and preview-height.png:
- Left card: the photoEmg photo, using the shared PhotoSlot from docs/ui/photo-picker. Below it: place text (new optional emgPlace), derived "สั่งตัด", and a button-height stepper bound to the existing emgMountCm (shown in m, ✓ for 1.10–1.50, ⚠ outside), so A4's flood check uses the same value.
- Right column: the A2 site picture with a tappable FTS-switch pin, stored as a new hidden MarkKind.emergency in A2's siteMarks; and a read-only SLD crop of the FTS / emergency part, with a link to the SLD page.
- The shared bottom bar with the green ✓ / orange ! badge.

Owner's decision: do not record the FTS cabinet location. Keep photoFTS (id, Excel, PDF) but make it optional and hidden. B5 completion then needs only photoEmg; update Progress, and call this out in your summary.

Use code-review-graph first to find every reader of ModuleType.fts, photoFTS/photoEmg, emgMountCm, MarkKind/siteMarks and SingleLineLayout's emergency button.

Keep all other ids, labels, Excel and completion unchanged. Old JSON must decode. iPad portrait and iPhone keep groupPage. The page must never overflow the free width. Every control is at least 44 pt, and UI text stays Thai.

Verify with swift test plus new tests (pin creates or moves one .emergency mark; the stepper writes emgMountCm and A4 shows it; completion needs only photoEmg; old JSON decodes), and with xcodebuild using your own -derivedDataPath. Add -surveyPage fts and check it in the simulator against the previews. Finish with a list of the files you changed.
```
