Follow docs/ui/survey-b4/CLAUDE_CODE_TASK.md

Build a designed wide page for B4 ระบบกันย้อน (ModuleType.backfeed), named BackfeedPageWide, the same way as InverterPageWide (B2) and FtsPageWide (B5). Match docs/ui/survey-b4/preview.png and states/*.png at 1366 × 1024, on one screen:
- Left: (1) LV / HV option cards writing values["level"], with the เสา chips (เสาเดิม / เสาใหม่) for HV only. (2) A 2×2 photo grid, minimum 4 photos, with labels that change by level; add the new fields photoRating and photoAccess. (3) The detail text.
- Right: an SLD crop from the real SingleLineLayout around the B4 parts (LV or HV), the A2 image cropped at the กันย้อน site mark, and the list "อุปกรณ์ที่ต้องติดตั้ง" built from A3/B2 data.
- Bottom bar: the missing-photo status, then save, previous (B3) and next (B5).

Old jobs must still decode. Update Progress, the PDF photos (Excel only if there are free slots) and the tests listed in the task. Vector assets are in docs/ui/survey-b4/icons (README lists SF Symbols and which files are only reference crops). Thai UI text exactly as in the previews. Use code-review-graph first, then read the source. Finish with a summary of the files changed, the new fields and the test results.
