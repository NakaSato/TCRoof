# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/pwa-solar-survey-iphone-v2/CLAUDE_CODE_TASK.md.

Rebuild the PWA survey home on iPhone (SurveyHomeView compact branch only; iPad unchanged) to match
docs/ui/pwa-solar-survey-iphone-v2/preview.png and states/*.png at 390 × 844. Do it in this order:

1. Header: remove the gear, the ••• menu and the search row. One 44 pt search button grows leftwards into the
   field after a 0.1 s delay while the title fades out (states/02). Reduce Motion = cross-fade.
2. Stage pills ทั้งหมด · งานติดตั้ง · บำรุงรักษา + a 44 pt filter button (ทั้งหมด tab only) that opens the
   กรองและเรียง popover: 2×2 status tiles and the sort segments (states/03, 04). Drop the v1 filter pill row.
3. งานติดตั้ง overview (states/05–07) from an injected [InstallStationSummary] (TCRoofCore value type, set from
   SolarSurveyEntry; fall back to InstallInfo). บำรุงรักษา overview (states/08–09) on an empty-by-default
   MaintenanceStationSummary with a DEBUG seed.
4. Floating PWA dock (states/18): หน้าหลัก · โครงการ · แผนงาน · เอกสาร · ตั้งค่า, lists scroll under it behind a
   128 pt fade. Reuse/share the dock view from docs/ui/tcroof-home-iphone-v3 if it exists, else build it in TCRoofUI.
5. ตั้งค่า tab = a settings page (states/17) that also holds every old ••• action plus ตั้งค่าแอป.
   แผนงาน opens MPOverviewView for now; เอกสาร opens StationDocsScreen. The plan/docs boards are reference only.
6. Add the DEBUG launch arguments from the task to CLAUDE.md.

Read the *.dc.html boards as text for exact sizes and colours, but use Theme tokens in views (no hex, no Color.white,
no shadows). Keep hit areas ≥ 44 pt and the data rules in CLAUDE.md. Use code-review-graph first, then read the source.
Build with your own -derivedDataPath. Finish with simulator screenshots next to states/, the files changed, and
answers to the open questions.
```
