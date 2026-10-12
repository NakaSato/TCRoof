# Vector assets: PWA Solar Project home, iPhone v2

24 × 24, stroke 2.1, round caps, black: use them as **template** images (`.renderingMode(.template)`) so the tint follows
the state. Use the SF Symbol where one is named.

| File | SF Symbol | Used for |
|---|---|---|
| `search.svg` | `magnifyingglass` | Header search button |
| `close.svg` | `xmark` | Close the search field |
| `filter.svg` | — (asset `pwa-filter`; `line.3.horizontal.decrease` is close) | Filter button beside the stage pills |
| `tab-home.svg` | `house` | Dock `หน้าหลัก` |
| `tab-project.svg` | — (asset `tab-project`; `list.clipboard` is close) | Dock `โครงการ` |
| `tab-plan.svg` | `calendar` | Dock `แผนงาน` |
| `tab-docs.svg` | — (asset `tab-docs`; `doc.badge.checkmark` is close) | Dock `เอกสาร` |
| `tab-settings.svg` | `gearshape` | Dock `ตั้งค่า` |
| `daily-report.svg` | `doc.text` | Daily report strip (install overview) |
| `ring-64-install.svg` | — (draw with `Circle().trim`) | Install summary ring with plan tick |
| `ring-64-maintenance.svg` | — (draw with `Circle().trim`) | Maintenance summary ring |
| `plan-bar.svg` | — (draw in SwiftUI) | Station row bar with plan tick |
| `toggle-on.svg` | — (`Toggle`, tint success) | Settings toggles |

Asset names are global across catalogs: check for clashes before adding `tab-project` / `tab-docs` / `pwa-filter`.

## Marks (board values → `Theme`)
| Part | Board value | Theme |
|---|---|---|
| Header | `#1F6FB5` gradient (`.g-head`), bottom radius 15 | existing header |
| Search button | white 18 % fill, white 40 % border, radius 12; open: white 97 % | — |
| Stage pill on / off | `#16325C` white bold / white + `#DDE4ED` | `navySolid` / `surface`, `borderSubtle` |
| Filter button open / filtered | `#E3EEF8` + `#1F6FB5` / `#16325C` + `#F08C00` dot | `primarySoft`, `primary` / `navySolid`, warning |
| Popover | white, 1 pt `#C9D3E0`, radius 18, no shadow | `surface`, `borderOutdoor` |
| Dock | white, 1 pt `#C9D3E0`, radius 28, 12 pt side inset, 22 pt above bottom | `surface`, `borderOutdoor` |
| Dock selected / unselected | `#16325C` capsule radius 22 / `#3E4C60` | `navySolid`, `onPrimary` / `inkTab` |
| Dock badge | 17 pt `#D9453B` (docs: `#F08C00`), 2 pt white ring | `danger` / warning |
| Fade above dock | 128 pt `#F5F8FB` clear → 85 % (38 %) → solid (62 %) | `phonePage` |
| Behind / on plan / ahead | `#D9453B` / `#1F6FB5` / `#2E9E5B` tints | `danger` / `primary` / success |
