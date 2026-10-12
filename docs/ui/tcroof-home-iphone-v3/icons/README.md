# Vector assets: iPhone home v3 (project feed)

Use SF Symbols in SwiftUI; the SVGs show the exact look on the board.

| File | SF Symbol | Used for |
|---|---|---|
| `ack-thumb.svg` | `hand.thumbsup` (`.fill` when on) | `รับทราบ` button |
| — | `ellipsis` | post `⋯` menu (44 × 44) |
| `example-photo-roof.svg` | — | **Example photo only** (layout): a post with a rooftop photo |
| `example-photo-inverter.svg` | — | **Example photo only** (layout): a post with an inverter-room photo |

## Marks (from the board, map to `Theme`)
| Part | Board value | Theme |
|---|---|---|
| Post card | white, 1 pt `#DDE4ED`, radius 18, no shadow | `surface`, `borderSubtle` |
| Avatar | 40 pt circle, team colour, white initial 16 pt heavy (13 pt for 2 letters) | team colour from settings |
| Badge | 10.5 pt bold capsule: blue `#E3EEF8/#1F6FB5`, green `#E8F5EE/#1F6B43`, orange `#FFF3E6/#9A4A06`, red `#FDECEA/#B42318` | `primarySoft`/`primary`, success, warning, danger tints |
| Photo chips | 11 pt bold white on green `#2E9E5B`, red `#D9453B`, or navy 72 % | success / danger / navy |
| Stat tile | radius 10, value 16 pt bold, label 10.5 pt | tints as badges |
| Issue box | radius 12; open `#FDECEA`, fixed `#E8F5EE`; button 44 pt green `#2E9E5B` | danger / success tints |
| Filter chip | 40 pt capsule; on `#16325C` white bold, off white + `#DDE4ED` | `navySolid`, `borderSubtle` |
