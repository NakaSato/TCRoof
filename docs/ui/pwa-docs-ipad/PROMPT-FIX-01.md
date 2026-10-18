# Prompt for Claude Code (FIX-01)

```
git fetch origin && git switch -c feat/pwa-docs-ipad-fix01 origin/design/pwa-docs-ipad-fix01
```

```
Follow docs/ui/pwa-docs-ipad/FIX-01-top-row.md.

FIRST check that TCRoof/Views/Job/StationDocs/Pad/PWADocsPadView.swift has topRow(_:) with "syncChip" after
the switch. If it doesn't, STOP and report.

Change ONLY the iPad เอกสาร page's top row:
1. Remove syncChip from topRow; the row is the view switch alone, left-aligned. Delete syncChip and anything
   only it uses (lastSync if nothing else reads it).
2. Keep isOffline: the upload sheet's offline note and -pwaDocsOffline YES still use it.
3. CLAUDE.md: "-pwaDocsOffline YES (the offline chip and note)" becomes "(the upload sheet's offline note)".

Do not touch the summary, lists, sheets, search, the locked state, the iPhone page or CloudSync.

Steps:
1. Read the FIX file and look at fix01-top-row.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run PadPWADocsUITests and HomeNavbarUITests.
4. iPad Pro 13" simulator, run with -screen home -homeTab docs -homeBoard YES -pwaDocsDemo YES.
   Save screenshots/01-stations.png again, and 11-offline-upload.png with the offline and upload flags.
   Compare them with states/.
5. Commit on feat/pwa-docs-ipad-fix01 and push it (no merge).
6. Report:
   - before / after
   - the open question
```
