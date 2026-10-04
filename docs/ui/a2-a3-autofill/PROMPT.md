Follow docs/ui/a2-a3-autofill/CLAUDE_CODE_TASK.md

Make survey step A2 (`ภาพสถานที่ติดตั้ง`, site photo) auto-fill step A3 (`หม้อแปลง · MDB`) and the B4 zero-export level, two-way. Match docs/ui/a2-a3-autofill/states/01–05.

1. Add a pure engine `SiteSync` in TCRoofCore with `push` / `pull` / `useA2` / `keepA3` / `items`. Mapping:
   - trafo mark kVA → `trafos[i].kva`, appending a transformer when missing (max 5)
   - mdb mark name → `tr{i}_feed`; AT → `boards[0].at` through `setBoards`
   - zero-export mark `MV`/`LV` (stored in `MapMark.value`) → B4 `level` `ZeroExport.hv`/`.lv`
   - PEA meter mark → link only
2. Fill empty targets only. A different non-empty value becomes a conflict and is never overwritten silently. `push` is idempotent.
3. Add optional `MapMark.link` (`"tr:<id>"` / `"bd:<id>"`) with backward-compatible decoding. Position matching stays as the fallback for old jobs.
4. Run `push` after A2 `setMarks`, and `pull` after A3 / B4 edits. Deleting a mark only unlinks; it never deletes A3 data. Keep `SiteMarks.suggestedValue`.
5. A2 UI:
   - the mark editor shows the chip `↔ A3 TX n` instead of `ดึงจาก A3` (pull from A3)
   - the Zero Export editor offers `ZERO EXPORT MV` / `ZERO EXPORT LV` with chip `↔ B4` and the note line
   - popovers auto-place left → right → below → above with an arrow
6. A3 UI:
   - replace `matchChip` with the header button `ดึงจากภาพ A2 · N รายการ` (pulled from A2 · N items), or `· ต่างกัน n` (differ n) in orange
   - the button opens a 440 pt panel `ใส่ให้อัตโนมัติจากภาพ A2` (auto-filled from A2) with rows `✓ ใส่แล้ว` (filled) / `ต่างกัน` (differs) + `ใช้ค่า A2` (use A2's value) / `คงค่านี้` (keep this one)
   - `A2` badges on the filled fields
   - a sheet on iPhone
7. Tests: add `SiteSyncTests` for fill, idempotence, conflict + resolve, link survives a transformer delete, zero-export MV/LV, old JSON decoding, and pull.

Keep all Thai UI labels exactly as written (English in brackets is only a gloss). Colours come from Theme/Home, touch targets are ≥ 44 pt, and Excel/PDF layouts stay unchanged. Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source. Work on a new branch `feat/a2-a3-autofill`. Build, run the tests, and try it on an iPad Pro 13" simulator: place symbols on A2 → see A3 filled, then edit on A3 → see the A2 label change. Finish with a summary of files changed, the model changes, and any differences from the boards.
