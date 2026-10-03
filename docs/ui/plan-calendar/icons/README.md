# Vector assets — PlanCalendarView

All icons are 24×24, stroke 1.75, round caps/joins, `#16325C` (recolor with `currentColor` / `.foregroundStyle`). In SwiftUI prefer the SF Symbol in the second column; the SVG is the exact look on the board.

| File | SF Symbol | Used for |
|---|---|---|
| `icons/chevron-left.svg` | `chevron.left` | back button; previous month |
| `icons/chevron-right.svg` | `chevron.right` | next month |
| `icons/list-bullet.svg` | `list.bullet` | header link ดูรายการแผนก่อสร้าง |
| `icons/clipboard-survey.svg` | `list.bullet.clipboard` | survey row in the day panel |
| `icons/info-circle.svg` | `info.circle` | empty note ไม่มีงานติดตั้งในวันนี้ |
| `icons/bolt.svg` | `bolt` | kW in install row |
| `icons/mappin.svg` | `mappin.and.ellipse` | province in install row |
| `icons/person.svg` | `person` | customer in install row |

## Marks (not icons)
| File | What |
|---|---|
| `survey-marker.svg` | dashed pill `นัดสำรวจ n` at the bottom of a day cell (white, 1px dashed `#77889E`, radius pill, 12 pt bold) |
| `survey-dot-legend.svg` | legend mark for นัดสำรวจ under the grid |
| `team-dot-TCR0x.svg` | 8 pt team dots (filters, team pill) — colours = `Team.color` |
| `install-bar-TCR0x.svg` | install bar look: team colour at 18 % opacity, radius 4 (square edge where the job continues into the next/previous week), bold team + customer, regular grey `n วัน · kW` |
