# Vector assets: iPhone home v3 (tab dock + project feed)

24 × 24, stroke 2.1, round caps, black: use them as **template** images (`.renderingMode(.template)`), so the tint follows the
selected / unselected colour. Use SF Symbols where the second column names one.

| File | SF Symbol | Used for |
|---|---|---|
| `tab-home.svg` | `house` | tab `หน้าหลัก` |
| `tab-homework.svg` | — (asset `tab-homework`) | tab `งานบ้าน`: a house with panels on the roof |
| `tab-pwa.svg` | — (asset `tab-pwa`) | tab `กปภ.`: a water drop |
| `tab-tools.svg` | — (asset `tab-tools`) | tab `เครื่องมือ`: a multimeter |
| `tab-settings.svg` | `gearshape` | tab `ตั้งค่า` |
| `ack-thumb.svg` | `hand.thumbsup` (`.fill` when on) | `รับทราบ` button |
| — | `ellipsis` | post `⋯` menu (44 × 44) |
| `example-photo-roof.svg` | — | **Example photo only** (layout): rooftop |
| `example-photo-inverter.svg` | — | **Example photo only** (layout): inverter room |

## Marks (board values → `Theme`)
| Part | Board value | Theme |
|---|---|---|
| Tab dock | white, 1 pt `#C9D3E0`, radius 28, 12 pt side inset, 22 pt above the bottom | `surface`, `borderOutdoor` |
| Selected tab | `#16325C` capsule, radius 22, white glyph and label | `navySolid`, `onPrimary` |
| Unselected tab | `#3E4C60` | `inkTab` |
| Dock badge | 17 pt, `#D9453B`, 2 pt white ring | `danger` |
| Fade above dock | 128 pt, `#F5F8FB` clear → 85 % (38 %) → solid (62 %) | `phonePage` |
| Post card | white, 1 pt `#DDE4ED`, radius 18, no shadow | `surface`, `borderSubtle` |
| Avatar | 40 pt circle, team colour, white initial | team colour |
| Badge | 10.5 pt bold capsule: blue / green / orange / red tints | `primarySoft` / success / warning / danger |
| Photo chips | 11 pt bold white on green / red / navy 72 % | success / danger / navy |
| Issue box | radius 12; open red tint, fixed green tint; 44 pt green button | danger / success tints |
| Filter chip | 40 pt capsule (44 pt hit area); on navy, off white + `#DDE4ED` | `navySolid`, `borderSubtle` |
