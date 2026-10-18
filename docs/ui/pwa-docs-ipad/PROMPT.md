# Prompt for Claude Code

```
git fetch origin && git switch -c feat/pwa-docs-ipad origin/design/pwa-docs-ipad
```

```
Follow docs/ui/pwa-docs-ipad/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoof/Views/Job/StationDocs/PWADocsHomeView.swift (+Cards)
- TCRoofKit/Sources/TCRoofCore/PWADocs.swift, with stepper, rows, todo, library and summary
- TCRoofKit/Sources/TCRoofCore/StationDocs.swift, with DocState, pk2Checklist and Status.choices(for:)
- PadTabs .docs routing to HomeLibraryView

Build ONLY the iPad (regular width) เอกสาร page and its sheets (the task's change list):
1. Routing:
   - PadTabs .docs → the PWA docs page.
   - HomeLibraryView moves to an iPad settings row "เอกสารงานบ้าน".
   - Keep the .stationDocsDrafts gate: contractors see only the locked state (states/10).
2. Frame:
   - Header with search and bell.
   - Switch: ต้องทำ counts late or due-today only.
   - Sync chip (offline state).
   - Summary card with the stacked status bar, and three origin tiles.
3. ตามสถานี:
   - Contractor chips and the sort toggle; one-line rows with "ขาด n".
   - NO "ทีมเรา" tag pill: in the iPad view only, show no pill when the tag is ทีมเรา, and the
     next box heading reads just "ถัดไป".
   - Empty state.
   - Right panel:
     - package cards drill into paper rows; พค.2 shows the 23 check-list items and the ลำดับ กกพ. link
     - ความเคลื่อนไหว
     - sticky PDF / อัปโหลด bar
4. Document sheet (920×760):
   - status steps, file preview, facts, ID-card warning, history
   - actions by status
5. Upload sheet:
   - slot chips and the shared-file note
   - sources: document camera / file importer (Drive only if a picker exists)
   - three masking checks gate ID papers
   - offline note
6. One new optional stored field, DocState.reminders: [Date] (decodeIfPresent), for ทวง, with a test.
7. ต้องทำ: three due-sorted columns with เลย n pills and an action per card.
8. คลังกลาง:
   - expiry timeline; groups by scope, including สาขา; "ใช้ใน n สถานี"
   - library sheet without versions or the zone choice
9. Search panel grouped สถานี / เอกสาร / คลังกลาง.
10. DEBUG flags (task §10), plus one line in CLAUDE.md.

Rules:
- Only data with a source. Hide history beyond updatedAt/reminders, library versions, the zone choice,
  Drive (if no picker) and a letter-number field, and report them.
- Do NOT build the board's dashed "ตัวอย่าง: … ▾" chip (board-only).
- Contractors (external role) have NO access: the เอกสาร tab is only the locked state of states/10.
- Theme tokens only, TCButtonStyle, 44 pt hit areas.
- Split big views into computed properties (CLAUDE.md, the Debug SIGSEGV).
- Don't touch the iPhone layout, StationDocsScreen's layout, OutageLetterSheet or ERCFlowViews.

Steps:
1. Read the task, then iPadPwaDocs.dc.html as text: renderVals(), the part after "v2: one document model".
   Look at states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test, the new PadPWADocsUITests and HomeNavbarUITests.
4. iPad Pro 13" simulator, run with -screen home -homeTab docs -homeBoard YES -pwaDocsDemo YES and the new flags.
   Save screenshots 01–11 (10 with -role external) in docs/ui/pwa-docs-ipad/screenshots/ and compare them with states/.
   Check that the iPhone page is unchanged.
5. Commit on feat/pwa-docs-ipad and push it (no merge).
6. Report:
   - the differences
   - what had no data source and was hidden
   - the open questions
```
