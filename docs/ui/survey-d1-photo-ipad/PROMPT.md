# Prompt for Claude Code

```
git fetch origin && git switch -c feat/survey-d1-photo-ipad origin/design/survey-d1-photo-ipad
```

```
Follow docs/ui/survey-d1-photo-ipad/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoofKit/Sources/TCRoofUI/Survey/Pages/Tank/TankPageWide.swift with formStep and the tab switch
- Schema.swift .tank group "ภาพถ่าย" with aerialPhoto, sidePhotos, roofPhotos, shadePhoto, cablePhoto, obstPhotos
- Tank.photoCompletion in TCRoofCore/Tank.swift

Do ONLY this:
- Build D1 sub-step 4 "ภาพถ่าย" on iPad (regular width, not stacked) as the board's gallery + inspector:
  - the progress ring and the filter segment
  - the 3-column tiles that fill the height
  - the add-obstacle bar
  - the inspector: photo, วิธีถ่าย, GPS mini plan, note, retake / delete, next missing
- Keep formStep for iPhone and stacked.
- Do NOT touch the sub-step tab bar (another branch, design/survey-d1-stepper-ipad, changes it).
- No schema change. "Required" comes from the FieldSpec. Reuse the existing photo pipeline.

Change list:
1. TankPageWide+Photos.swift (new): padPhotoStep, split into small computed properties, and the tile model built from the schema.
2. TankPageWide.swift: tab 4 → padPhotoStep in regular width.
3. DEBUG -surveyD1 photo|photomiss|photofilter|photodone. Update CLAUDE.md.
4. Tests: the tile ↔ field mapping, required == Tank.photoCompletion, and an iPad UI test with the camera stub.

Steps:
1. Read the task, then the board as text (the <sc-if value="{{is5}}"> markup, and the "photo checklist" block in renderVals). Look at states/*.png.
2. Use code-review-graph first (grep if it doesn't connect). Find every reader of the ภาพถ่าย fields (PDF, Excel, Progress).
3. swift test, then xcodebuild with your own -derivedDataPath.
4. Take the iPad screenshots 01–04 and save them in screenshots/. Compare them with states/.
5. Commit on feat/survey-d1-photo-ipad and push (no merge).
6. Report: the differences, anything with no data source that you hid, and the open questions.
```
