# Icons: iPhone home (`PhoneMenu.dc.html`)

These are vector exports of every icon on the board.
- Prefer the SF Symbol in the table. Use the SVG only where no symbol matches.
- Glyphs drawn on coloured tiles are exported white. Tint them in code.

| SVG | Where | SF Symbol |
|---|---|---|
| `module-survey.svg` | Module row: `สำรวจหน้างาน` | `list.clipboard.fill` (already in `AppModule.symbol`) |
| `module-plan.svg` | `แผนก่อสร้างและเอกสาร` | `calendar` |
| `module-scan.svg` | `สแกนอุปกรณ์` | `barcode.viewfinder` |
| `module-install.svg` | `บันทึกงานติดตั้งและใบตรวจรับงาน` | `folder.fill` |
| `module-pwa.svg` | `การประปาส่วนภูมิภาค` | `drop.fill` |
| `module-tools.svg` | `เครื่องมือและอุปกรณ์วัด` | `briefcase.fill` (new module, see task) |
| `bell.svg` | Header bell (44 pt circle) | `bell` |
| `chevron-left.svg` / `chevron-right.svg` | Appointment pager ‹ › | `chevron.left` / `chevron.right` |
| `navigate.svg` | Hero card: navigate | `location.north.fill` or `paperplane` |
| `phone.svg` | Hero card: call site contact | `phone` |
| `progress-ring-72.svg` | Hero progress ring (56 pt, stroke 5, `#8FD16A` on white 22 %) | draw with `Circle().trim` |
| `close.svg` | Full-screen notifications ✕ | `xmark` |
| `notif-survey.svg` | Notification type: survey appointment (tile `#1F6FB5`) | `calendar` |
| `notif-sync.svg` | Waiting to sync (tile `#F08C00`; after sync, green `#2E9E5B` with `checkmark`) | `icloud.and.arrow.up` |
| `notif-tool.svg` | Tool calibration due (tile `#B45309`) | `briefcase` |
| `notif-install.svg` | Install day / acceptance signed (tile `#2E9E5B`, or `#7A8BA3` when old) | `folder` |
| `notif-done.svg` | Done / saved (tile `#7A8BA3`) | `checkmark` |

The app icon and the header logo come from `../assets/tc-renewable-icon-1024.png`. It is the same image as `AppLogo` / `AppIcon` on branch `feat/new-app-icon`.

## Added for the iPad home (`iPadMenu.dc.html`)
| SVG | Where | Build with |
|---|---|---|
| `progress-ring-steps.svg` | `งานสำรวจค้างอยู่` row: steps done / 13 (44 pt, stroke 4, `#1F6FB5` on `#E3EEF8`; green `#2E9E5B` at 13/13) | `Circle().trim` + `Text` |
| *(no SVG)* timeline dot | live `#2E9E5B` · next `#1F6FB5` + 4 pt halo · later white + 2 pt `#AAB6C5` ring, 13 pt | `Circle()` |

All other icons on the iPad board are the same as the iPhone home above, just drawn larger (module tiles 56 pt with 28 pt glyphs, bell 24 pt).
