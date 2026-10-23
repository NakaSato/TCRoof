# Prompt for Claude Code

```
git fetch origin && git switch -c feat/daily-report-ipad-v2 origin/design/daily-report-ipad-v2
```

```
Follow docs/ui/daily-report-ipad-v2/CLAUDE_CODE_TASK.md. Do ONLY its change list. v1 (docs/ui/daily-report-ipad) is
already built. Everything not listed stays as it is.

FIRST check that these exist:
- TCRoof/Views/Job/RoutineReports/DailyOnePage.swift
- TCRoof/Views/Job/RoutineReports/DailyOnePage+Plan.swift
- TCRoof/Views/Job/RoutineReports/DailyOnePage+Work.swift
- TCRoofKit/Sources/TCRoofUI/SaveButton.swift
If not, STOP and report.

Change ONLY DailyOnePage on iPad regular width (≥ 1000 pt):
1. Remove the work card's header (งานวันนี้, its count line, "+ งานจากแผน MP" and its menu) and v1's "+" tab button.
   MP tasks are added only by the key plan's ghost "+" pins.
2. The left card is one vertical scroll: the key plan (inset 10/12, radius 12, ~560 pt), then the task list.
   The selected task's detail is pinned at the card's bottom.
3. Key plan overlay:
   - top left: the "KEY PLAN" navy badge + "หน้า 2"
   - top right: compact 28 pt buttons (44 pt hit):
     - "อัปโหลดผัง" opens a 4-option menu: camera with document correction, photo library, PDF file (page + crop),
       use the survey's A2 picture
     - ⛶ full screen
4. Task list v3: group the lines by location (Thai numeric order) under "location · n งาน · +x% วันนี้" headers.
   Each row:
   - pin
   - title (TAP = select the line + take a photo for it)
   - "MP code · ก่อนวันนี้ n%"
   - progress control: − (−5%) · 10-segment bar (tap = set the accumulated %; segments before today are grey and
     disabled) · + (+5%) · accumulated % with "+x% วันนี้" or orange "ยังไม่กรอก" · เสร็จ toggle
   - camera with a count badge (orange dashed when there is no photo)
   This replaces v1's tab strip and the +10/+20/+30/+50 picks.
5. Pinned detail of the selected line:
   - pin, name, "location · before% → after% · เร็วกว่า/ช้ากว่า x%"
   - numbered photo thumbnails (tap retakes) and an empty "ถ่าย" slot
   - "n รูป · ใช้ในรายงาน"
   - + วัสดุ, + ปัญหา, เอาออก
   - material / problem rows inside the footer
   Remove v1's status pill, tools text, MP weight line and station bar FROM THE SCREEN ONLY. The data and the PDF keep
   them.
6. Bottom bar "บันทึกร่างตอนนี้": use TCSaveButton.pad (idle → saving spinner → saved green flash → clean outline with
   "ล่าสุด HH:mm น.").
7. Team card: remove the header's right-aligned "n คน · เครื่องมือ n รายการ".
8. DEBUG: add upload|saving|saved|clean|material to -routineDailyState. Update the CLAUDE.md line.

Rules:
- Uploaded key plan:
  - an optional PhotoAsset on the job, synced by PhotoSync
  - it wins over the A2 siteMap, and "use A2" clears it
  - the PDF key plan uses it too
  - old data must decode
- A problem row links to its line through a new optional Problem.lineKey (decodeIfPresent).
- Segment → today mapping in TCRoofCore (RoutineReport), with tests. Caps today ∈ [0, 100 − before].
- Theme tokens, TCButtonStyle, 44 pt hit areas, no hex in views. Don't ship the board's images.

Steps:
1. Read the task. Read iPadDaily.dc.html as text (the template, then the renderVals script). Measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath, in the background. Run swift test with the new tests.
4. Run on an iPad Pro 13" simulator with -screen daily -routineDaily onepage -routineKeyPlan YES.
   Save screenshots 01, 02, 03, 06 and 11 in docs/ui/daily-report-ipad-v2/screenshots/ and compare them with states/.
   Check that -routineDemo pdf is unchanged and that the iPhone daily report is unchanged.
5. Commit on feat/daily-report-ipad-v2 and push it. Do not merge.
6. Report:
   - the differences from the board
   - what DWG does
   - the open questions
```
