# Vectors: แผนงาน PWA (iPhone)

24 × 24 glyphs are black: use them as **template** images. Prefer the SF Symbol where one is named.
The dock, stage-pill and popover glyphs are the same as `../pwa-solar-survey-iphone-v2/icons/` (already in the app).

| File | SF Symbol | Used for |
|---|---|---|
| `filter.svg` | asset `pwa-filter` (already added in v2) | Filter button: agenda row and `กำหนดส่ง` tab row |
| `search.svg` | `magnifyingglass` | Header search |
| `close.svg` | `xmark` | Remove-filter chip, close search |
| `tab-plan.svg` | `calendar` | Dock `แผนงาน` (selected) |
| `day-bars.svg` | — draw in SwiftUI | Calendar colour bars: a continuous `ติดตั้ง` run plus a short other-type bar |
| `gantt-row.svg` | — draw in SwiftUI | `รายสถานี` row: track, actual fill, plan tick, today line |

The S-curve has no asset: draw it with `Path` / Swift Charts (`LineMark`), see `CLAUDE_CODE_TASK.md` §4.
