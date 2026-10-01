# Prompt to paste into Claude Code (run from the TCRoof repo)

```
Follow docs/ui/photo-picker/CLAUDE_CODE_TASK.md.

Build one shared PhotoSlot / PhotoSourceButtons component (empty slot with "อัปโหลด" and "กล้อง", filled slot with done badge and 44 pt clear button) that matches preview-empty.png and preview-filled.png. Use it on A3, A4, B1 and B2 in place of their own photo pickers.

Use code-review-graph first to find every showPicker / showCamera / CameraPicker / photosPicker. Keep photo field ids, storage, Drive, PDF and Excel unchanged. Every control is at least 44 pt, and UI text stays Thai.

Verify with swift test and xcodebuild (your own -derivedDataPath), then check each page in the simulator. Finish with a list of the files you changed.
```
