# FIX-01 · iPad แผนงาน PWA: taller S-curve

The iPad plan page (`docs/ui/pwa-plan-ipad`, built in 3f8e324) is unchanged except for one thing on the board: the S-curve chart in `แผน MP` is taller.

Branch: `design/pwa-plan-ipad-fix01-scurve` (from `feat/ipad-home-v3`). Implement on `feat/pwa-plan-ipad-fix01-scurve` cut from it, push, don't merge.

## Board diff (`iPadPwaPlan.dc.html`, the only change)

| | Before (built) | Now |
|---|---|---|
| chart height | 170 pt | **268 pt** |
| SVG viewBox | `0 0 540 120` | `0 0 540 188` |
| plot area | y 2 … 104 (`Y = 104 − p`) | y 2 … 168 (`Y = 168 − 1.6·p`) |
| today line | y2 = 104 | y2 = 168 |
| month labels | y = 116 | y = 182 |

So the plot itself is 1.6× taller; the x mapping, the % gridlines (0 / 25 / 50 / 75 / 100), the month labels, the today line and the legend are the same.

Card height grows by ~98 pt. The two cards under it (`รายสถานี` | `กำหนดส่ง`) move down; the right column already scrolls with 130 pt bottom padding, so nothing else changes.

## Change list

1. `TCRoof/Views/Survey/PWAPlan/PWAPlanPhoneView+MP.swift`, `curveCard`: `.frame(height: pad ? 170 : 120)` → `.frame(height: pad ? 268 : 120)`.
   Use a named constant (e.g. `curveHeight`) instead of the literal.
2. Check `PWAPlanCurveChart` draws from its frame (`GeometryReader`), not from a fixed 170, so the line, the gridline labels and the today line scale with it and the label text does NOT stretch (labels 11 pt on iPad).
3. iPhone stays 120 pt. Nothing else on the page changes.

## Check

- Build with your own `-derivedDataPath`.
- iPad Pro 13" landscape: `-screen home -homeTab pwa -homeBoard YES -surveyHomeTab plan -pwaPlanDemo YES -pwaPlanToday 2026-10-12`.
- Save `screenshots/F1-plan.png` and `screenshots/F2-scurve-crop.png`; compare with `states/fix/F1-plan.png` and `states/fix/F2-scurve-crop.png`.
- `-pwaPlanScrollEnd YES` still reaches the end of the right column.
- iPhone `แผนงาน` page unchanged (120 pt chart).
