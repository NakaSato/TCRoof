Read CLAUDE.md, then follow docs/ui/survey-e1/CLAUDE_CODE_TASK.md.

Build the iPad landscape wide page for E1 "สรุปผลและลงนาม" (JobEditor.Page.final), replacing groupPage(Schema.final) on iPad landscape. It must fit on one screen.

Match preview.png and states/01–09. Use iPadE1.dc.html as the design source.

Key points:
- Use code-review-graph first, then read the source.
- No schema change. Bind to the existing verdict, remarks, surveyorSign, customerName, customerSign and reviewer; the surveyor name comes from engineer (A1). Completion is unchanged.
- Left column:
  - three verdict buttons in their colours
  - the remarks TextEditor, with the aside depending on the verdict
  - the "ข้อเสนอแนะอัตโนมัติจาก AI · บนเครื่อง" rows from a new deterministic RemarkSuggestions in TCRoofCore (shade, flood height, missing IC/%Z, anti-reverse; numbers only from job data). Tapping appends a numbered line to remarks. Added detection comes from the remarks text.
  - the "ยังขาดในหน้าอื่น" card from missingGroups, with "ไปที่หน้า ›" navigation
- Right column: two signature cards (status chip, เซ็นใหม่, dotted canvas with a baseline, name, and Buddhist-calendar date from the photo's takenAt), an inline-editable customerName, and the reviewer row.
- Upgrade the shared SignaturePad to a full-screen iPad pad (ยกเลิก / ล้าง / บันทึก) and keep the same PNG export.
- The bottom bar status text follows the design; the primary button "สรุปผล · ส่งออก" runs the existing export flow.
- Do not change field ids, labels, PDF, Excel or completion. Old JSON must decode. Controls ≥ 44 pt. UI text in Thai exactly as designed. Names, dates and suggestion texts in the previews are examples.
- Add -surveyPage final. Run swift build and swift test with the new tests, and the CLAUDE.md xcodebuild with your own -derivedDataPath. Compare in the simulator at 1366 × 1024.
- Finish with a summary: the files changed, the rules implemented or left out, and anything left open.
