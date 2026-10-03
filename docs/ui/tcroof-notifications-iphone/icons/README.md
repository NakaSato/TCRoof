# Icons: iPhone notifications (`PhoneNotif.dc.html`)

These icons are vector exports from the board. Use the SF Symbol in the table for notification actions (`UNNotificationActionIcon(systemImageName:)`).

## Quick actions (long-press menu)
| SVG | Action | SF Symbol |
|---|---|---|
| `action-navigate.svg` | `นำทาง` | `mappin.and.ellipse` |
| `action-open-survey.svg` | `เปิดแบบสำรวจ` | `list.clipboard` |
| `action-remind-later.svg` | `เตือนอีก 10 นาที` / `ขอขยายเวลา 1 วัน` / `เตือนอีก 7 วัน` | `clock` |
| `action-camera.svg` | `รับเครื่อง · ถ่ายภาพตอนยืม` | `camera` |
| `action-list.svg` | `ดูคิว` / `ดูรายการ` | `list.bullet` |
| `action-close.svg` | `สละคิว` | `xmark` |
| `action-return.svg` | `คืนอุปกรณ์` | `arrow.uturn.backward` |
| `action-phone.svg` | `โทรหาผู้รอคิว` | `phone` |
| `action-tool-register.svg` | `เปิดทะเบียนเครื่อง` | `briefcase` |
| `action-sync-now.svg` | `ซิงก์ตอนนี้` | `arrow.triangle.2.circlepath` |
| `action-drive.svg` | `เปิดใน Drive` | `cloud` |
| `action-share.svg` | `แชร์ลิงก์` | `square.and.arrow.up` |

## Type colours (category text after `TCROOF ·`)
`type-*.svg` are 20 pt type badges with the type colour. The board shows only the coloured category word; the badge on the icon was removed by design. Use these colours for the category text and the in-app panel tiles.

| SVG | Type | Category text | Colour |
|---|---|---|---|
| `type-survey.svg` | Survey appointment | `สำรวจ` | `#1F6FB5` |
| `type-queue.svg` | Tool queue reached | `เครื่องมือ` | `#2E9E5B` |
| `type-late.svg` | Tool overdue | `ด่วน` | `#D9453B` |
| `type-cal.svg` | Calibration due | `สอบเทียบ` | `#F08C00` |
| `type-sync.svg` | Waiting to sync | `ซิงก์` | `#F08C00` |
| `type-done.svg` | Saved to Drive | `ส่งออก` | `#7A8BA3` |

The notification icon itself is the app icon (`../assets/tc-renewable-icon-1024.png`); iOS draws it, so the app needs nothing extra.
