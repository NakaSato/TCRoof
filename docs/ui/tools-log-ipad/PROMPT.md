# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/tools-log-ipad && git checkout -b feat/tools-log-ipad

Follow docs/ui/tools-log-ipad/CLAUDE_CODE_TASK.md.

Scope: build only the iPad screen บันทึกเครื่องมือและรถ (ToolLogPadScreen) as drawn in iPadToolsHub.dc.html. It has:
- on the left, the ledger card: the kind tabs, the out-now table, the log table with its range, action, person/job
  and search filters, ส่งออก CSV and โหลดเพิ่ม;
- on the right, the เครื่องมือวัด card (KPIs and chase list) and the บันทึกการใช้รถ card (vehicle rows and two actions).
Push it from the iPad เครื่องมือ tab (ToolsView, regular width) through one row that replaces the ToolLogCard /
VehicleCard HStack there.

Work through the change list in §5 in order, and nothing else:
- no refactors, renames or restyles outside it;
- no change to how the iPhone ToolsView, ToolLogCard or VehicleCard look or behave;
- no change to ToolLogFormSheet's fields, ToolLog.Event / Vehicle storage, CloudSync or firestore.rules;
- no new stored fields;
- no QR scanning, vehicle history or tools-tab landing page.
Leave out what §2 lists as having no stored source (the หลักฐาน column and the จองแล้ว state).

Start with the code-review-graph tools as CLAUDE.md says. Then, before writing code, read:
ToolsView, ToolLogViews (ToolLogCard, VehicleCard), ToolLogForm, ToolLogModels (ToolLogDemo), TCRoofCore/ToolLog.swift
and Instruments.swift. Reuse their data, wording, forms and the existing remind().

The board's values are examples (assets/sample-data.json); never hard-code them. Use colours from Theme, buttons with
TCButtonStyle, hit areas ≥ 44 pt, and split each card into its own computed property.

When done:
- run swift test in TCRoofKit (new ToolLogTests cases for driven, filter and csv);
- run the xcodebuild app build with your own -derivedDataPath (in the background);
- run ToolLogPadUITests on an iPad simulator;
- save simulator screenshots named like states/ to screenshots/;
- tick the change list;
- answer §7's open questions in your report.
Commit on feat/tools-log-ipad and push it.
```
