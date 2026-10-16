# Prompt for Claude Code · FIX-01

```
git fetch origin && git switch -c feat/pwa-plan-ipad-fix01-scurve origin/design/pwa-plan-ipad-fix01-scurve
```

```
Follow docs/ui/pwa-plan-ipad/FIX-01-scurve-height.md. Change ONLY this:

On iPad, the S-curve chart of the แผนงาน page's "แผน MP" card is 268 pt tall instead of 170 pt
(PWAPlanPhoneView+MP.swift curveCard, use a named constant). The chart must scale from its frame: line,
gridlines, labels (not stretched), today line. iPhone stays 120 pt. Nothing else changes.

Steps:
1. Read the fix file, then measure on states/fix/*.png.
2. Build with your own -derivedDataPath; run on an iPad Pro 13" simulator with
   -screen home -homeTab pwa -homeBoard YES -surveyHomeTab plan -pwaPlanDemo YES -pwaPlanToday 2026-10-12.
3. Save screenshots/F1-plan.png and F2-scurve-crop.png and compare them with states/fix/.
4. Commit on feat/pwa-plan-ipad-fix01-scurve and push it (no merge).
5. Report:
   - the difference
   - that the iPhone is unchanged
```
