# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/survey-d1-obstacles-ipad && git checkout -b feat/survey-d1-obstacles-ipad

Follow docs/ui/survey-d1-obstacles-ipad/CLAUDE_CODE_TASK.md.

Scope: only the iPad page of D1 sub-step 2 (padObstacleStep in TankPageWide+Obstacles.swift) and the core it needs.
Work through the change list in order, Part A then Part B, and commit after Part A:

Part A, บนหลังคา:
A1 point card header with ตรวจแล้ว n/m and its progress bar
A2 three-way status ตรงแบบ | ย้ายตำแหน่ง | ไม่มีจริง (keep the hardware keys)
A3 distance rows − value + with the alignment pill
A4 ย้ายพร้อมกัน จุดเดียว | แถว | คอลัมน์, with ระยะห่างจุด for a group (TankPoints group / move / respace, with
   tests; one undo step each)
A5 ทำซ้ำแถว as an inline panel (แนวนอน | แนวตั้ง, count, spacing, สร้าง n จุด) in place of rowSheet on iPad
A6 the four action tiles
A7 the plan legend, drag hint and เลิกทำ beside the plan

Part B, เงาบัง:
B1 TankShade.Item (tree / building / tower, position, height, width) stored as a hidden shadeItems field, with the
   simulation per item, the legacy shade fields written back, and tests
B2 the shade card: แปลน | 3 มิติ, month and time steppers, play, the caption, the plan on the A2 picture with
   draggable items and shadows, a Canvas 3D view, the + เพิ่ม toolbar
B3 the right column: the sun-path diagram, per-item loss chips, the selected item's editor, the form's shade fields
   under a closed row

C: DEBUG -surveyD1 states, one CLAUDE.md sentence, TankShadeUITests

Leave alone, with no refactors or renames outside the list:
- the iPhone sub-step 2
- sub-steps 1, 3 and 4
- the header, step strip and bottom bar
- field ids, labels and Excel cells
- the PDF layout and the DXF
- firestore.rules
An old job must decode and simulate as before.

Start with the code-review-graph tools as CLAUDE.md says. Then read TankPageWide+Obstacles, TankPointsPlan,
TankPageWide+Undo, TankPoints, TankShade (and its tests), TankLayout+Energy, the tank's shade fields in Schema.swift
and where the PDF reads the shade, before writing code.

Rules:
- The board's script is a prototype: don't port its sun, shade or loss maths.
- The board's numbers are examples (assets/sample-data.json); never hard-code them.
- No invented defaults (keep-out distance, object sizes): ask through the open questions.
- The simulation runs off the main thread.
- Draw with Sketch / Canvas.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.
- Split each card and canvas into its own view.

When done:
- run swift test in TCRoofKit (tank golden files unchanged for old jobs)
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run TankShadeUITests, TankUndoUITests, TankKeyboardUITests and TankPhotosUITests on an iPad simulator
- save screenshots named like states/ to screenshots/
- tick the change list and answer the six open questions in your report

Commit and push feat/survey-d1-obstacles-ipad. Do not merge.
```
