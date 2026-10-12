# Claude Code task: iPhone tab bar, `ติดตั้ง` tab becomes `เครื่องมือ` (measuring tools)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-tools-tab-iphone/CLAUDE_CODE_TASK.md`

Thai strings in `backticks` are literal UI labels. Data in the preview is **example data**.

## Context
The iPhone home (`docs/ui/tcroof-home-iphone-v2`) is built. Its docked tab bar is in
`TCRoof/Views/Home/PhoneTabs.swift` (`PhoneTab`, `items`). The owner changed the board
`iPhone · หน้าหลัก TCRoof (เมนู 6 หัวข้อ)` on 12 ต.ค. 2569. **Only the differences below apply.**

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `COMPONENT.md` | Tab bar spec: items, metrics, `Theme` tokens, states (check `TCTabBar` against it) |
| `preview.png` | Home with the new tab bar, 390 × 844 |
| `states/01-tabbar-crop.png` | Tab bar close-up (@2x) |
| `states/02-tools-row-crop.png` | The renamed module row (@2x) |
| `states/01-selected-home.png` … `05-selected-settings.png` | Each tab selected, 390 wide (@2x) |
| `PhoneMenu.dc.html` + `grf.css` | Design source (read as text; styles are inline) |
| `icons/tab-*.svg` | All five board glyphs, 24 × 24; only `tab-tools.svg` is new (the others stay SF Symbols) |
| `assets/tab-tools.imageset/` | Ready-to-copy asset (template, vector, same format as `tab-install`) |

## Changes

### 1. Tab bar: 4th tab
- **Before:** `ติดตั้ง`, asset `tab-install`, opens the install module.
- **After:** label `เครื่องมือ`, accessibility label `เครื่องมือวัด`, glyph `icons/tab-tools.svg`
  (copy `assets/tab-tools.imageset` into `TCRoof/Assets.xcassets`; template rendering, 22 × 22 like `tab-install`).
- Keep `tab-install.imageset` only if something else still uses it (grep); otherwise delete it.
- It opens the **tools** module (`AppModule.tools`, today the "coming soon" screen in `PhoneHome.swift`).
  Replace `PhoneTab.install` with `PhoneTab.tools` (keep `stacks` order: home, survey, plan, tools).
- `-homeTab install` (DEBUG) becomes `-homeTab tools`; update `CLAUDE.md` where it lists `-homeTab survey|plan|install`.
- The install module stays reachable from the home list row `บันทึกงานติดตั้งและใบตรวจรับงาน` (unchanged).
- Check `TCRoofUITests/HomeNavbarUITests.swift` / `PhoneSurveyUITests.swift` for taps on `ติดตั้ง` and update them.

### 2. Home list row: tools module title
- `AppModule.tools.title`: `เครื่องมือและอุปกรณ์วัด` → **`เครื่องมือวัด`**
- Subtitle unchanged: `โดรน กล้องถ่ายภาพความร้อน แคลมป์มิเตอร์`.
- `ComponentGallery` (`GalleryCards.swift`, `GalleryLayout.swift`) shows the old labels; update them to match.

### Not in this task
- The iPad home and its navbar are unchanged.
- The tools screen itself (instrument list, calibration dates, who has what) is not designed yet.

## Check list
- [ ] Tab bar order and labels: `หน้าหลัก` · `สำรวจ` · `แผนงาน` · `เครื่องมือ` · `ตั้งค่า`
- [ ] Hit area of every tab ≥ 44 pt; badge on `สำรวจ` unchanged
- [ ] `-screen home -homeTab tools` opens with the tools tab selected; matches `states/04-selected-tools.png`
- [ ] Old job JSON / SwiftData stores open (no model change expected)
- [ ] xcodebuild with your own `-derivedDataPath`; screenshot on an iPhone simulator vs `preview.png`

## Open questions
1. Should the tools tab badge something (e.g. instruments due for calibration)? Not on the board yet.
