# Icons (24 × 24 viewBox, stroke 2, round caps, `currentColor`)

Prefer the SF Symbol. Use the SVG only when no symbol matches the board closely enough.
Several of these already exist as `A2Icon` assets (`ui-gps-locate`, `ui-phone`, `ui-calendar`, `ui-prev`, `ui-next`, `ui-check` in `docs/ui/survey-a1/icons`); reuse those.

| File | Where | Size / colour | SF Symbol |
|---|---|---|---|
| `gps-locate.svg` | 44 × 44 button right of `พิกัด Google Map` | 20 pt, `#1F6FB5` | `location.circle` / existing `ui-gps-locate` |
| `phone.svg` | trailing icon in the `เบอร์โทร` field (tap to call) | 16 pt, `#1F6FB5` | `phone` |
| `calendar.svg` | trailing icon in `วันที่สำรวจ` | 16 pt, `#1F6FB5` | `calendar` |
| `lock.svg` | trailing icon in the read-only `วิศวกรผู้สำรวจ` field | 15 pt, `#7A8BA3` | `lock` |
| `check.svg` | save button after saving (white on green circle, then green) | 14 / 18 pt | `checkmark` |
| `chevron-left.svg`, `chevron-right.svg` | bottom bar ‹ › | 18 pt, white | `chevron.left` / `chevron.right` |
| `map-placeholder-484x280.svg` | **Stand-in** for the map. Use the real `MapImage` / MapKit snapshot, not this drawing. | — | — |

The red pin, zoom chips, `+ −` buttons, hint and scale bar on the map are overlays drawn in SwiftUI.
