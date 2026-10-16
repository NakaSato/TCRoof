# Prompt for Claude Code

Check out the design branch, create your own feature branch from it, then open Claude Code in the repo and paste:

```
git fetch origin && git switch -c feat/pwa-docs-iphone-v2 origin/design/pwa-docs-iphone-v2
```

```
Follow docs/ui/pwa-docs-iphone-v2/CLAUDE_CODE_TASK.md.

FIRST check that TCRoofKit/Sources/TCRoofCore/StationDocs.swift and TCRoof/Views/Job/StationDocs/ exist. If not, STOP and report.

Build ONLY a new iPhone page PWADocsHomeView ("เอกสาร PWA"): every PWA station's papers in three views.
Host it as the PWA dock's เอกสาร root (today: StationDocsScreen of the first station) and under the main dock's เอกสาร
as the board shows; keep HomeLibraryView reachable from the settings sheet. Report the hosting.

1. Header: เอกสาร PWA, search button that grows into a field (title fades), the bell with its badge.
2. View switch: ตามสถานี n · ต้องทำ n (red) · คลังกลาง n.
3. Summary card: approved / total + %, one stacked bar by status, three counts (ทีมเราทำ, รอ กปภ. ลงนาม, รอหน่วยงานนอก) that open ต้องทำ.
4. Orange expiry banner for the nearest expiring library paper (hidden when none).
5. ตามสถานี:
   - Filter ต้องทำ / รอผู้อื่น / ทั้งหมด.
   - Station cards with a status tag and a 4-step package stepper (อ.1, ขนานไฟ, พค.2 only ≥ 200 kVA, ส่งมอบ: done / current / later / skip).
   - A "ถัดไป … ส่งมอบ dd/MM" row. A card opens StationDocsScreen.
6. ต้องทำ: three groups by origin with status rings, station + who, coloured status, due (red when late).
7. คลังกลาง: library papers with a scope badge (กปภ. / บริษัท / โครงการ) and a pill (ล่าสุด / ตรวจ / n วัน / หมดอายุ).
8. DEBUG flags -pwaDocsView, -pwaDocsFilter, -pwaDocsSearch, -pwaDocsDemo (one line in CLAUDE.md).

Rules:
- All numbers from StationDocs (packages, states, Progress, expiry); new helpers in TCRoofCore with tests.
- Don't change StationDocs rules, StationDocsScreen, the ERC flow or stored fields (only optional additions).
- iPhone only; iPad unchanged. Theme tokens, no hex in views, TCButtonStyle, 44 pt hit areas.

Steps:
1. Read the task, then PhonePwaDocsV2.dc.html as text, and measure on states/*.png (@3x).
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test in TCRoofKit with the new tests in the task.
4. Run on an iPhone simulator with -pwaDocsDemo YES. Save screenshots 01, 04, 05 and 06 in
   docs/ui/pwa-docs-iphone-v2/screenshots/ and compare them with states/.
5. Commit on feat/pwa-docs-iphone-v2 and push it (no merge to main).
6. Report:
   - the differences
   - the hosting choice
   - what was missing as a data source
   - the open questions
```
