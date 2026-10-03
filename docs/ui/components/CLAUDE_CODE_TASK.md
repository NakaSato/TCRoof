# Task: build the TCRoof component library in SwiftUI

**Source board:** `คอมโพเนนต์ iPad · รวมทุกส่วนประกอบ UI (9 หมวด)` on the TCRoof Design canvas.

**Goal:** turn the board into one reusable SwiftUI component library.
- Every screen (iPad and iPhone) should build from these components instead of styling things inline.
- Existing screens keep their behaviour. Replace their ad-hoc styling with the components where the match is direct.

Text in the board is **example data**. Use it only in previews.

## Files in this folder

| Path | What |
|---|---|
| `preview.png` / `preview@2x.png` | Whole board, 1600 pt wide |
| `components.pdf` | Whole board as one vector page (zoom for exact sizes) |
| `sections/01-layout.png` … `09-number-pad.png` | One PNG @2x per section. Compare against these. |
| `preview.html` | Static render; open in a browser to inspect sizes and colours with dev tools |
| `iPadComponents.dc.html` | Source board (inline CSS = exact values; needs the canvas runtime to run, so read it as text) |
| `grf.css` | Wizard shell classes (`g-head`, `g-prog`, `g-caps`, `g-input`, `g-choice`, `g-bar`, `g-save`, `g-nav` …) |
| `tokens.css` | Design tokens, light + dark |
| `icons/*.svg` | Every icon on the board, exported at display size and colour. See `icons/README.md`. |
| `assets/tcroof-app-icon.svg` | App icon used in the iOS banner sample. Same image as `AppIcon` on `feat/new-app-icon`. |

## Where the code is today (read before changing)

- `TCRoof/Utilities/Theme.swift` holds:
  - colours: `navy`, `primary`, `primaryLight`, `teal`, `mint`, `danger`, `background`, `muted`, `inkMuted`, `borderSubtle`, `primarySoft`, `pending`, `pendingSoft` …
  - gradients
  - `cardStyle`
  - `OutlinedFieldStyle`
- `TCRoof/Components/Components.swift` holds:
  - `PageHeader`, `FloatingButton`, `StatusBadge`, `QueueFilterBar`, `JobCard`
  - `DotPill`, `GradientButtonLabel`, `FieldLabel`, `ChoiceButton`, `InfoRow`
- `TCRoof/Components/PhotoComponents.swift` holds `PhotoPickerSection`, `PhotoGrid`, `Thumbnail`, `PhotoViewer`, `SignaturePad`.
- `TCRoofKit/Sources/SurveyUI/` holds:
  - `Components.swift`: `CheckChip`, `PaperBox`, `ProgressRing`
  - `Fields.swift`: `FieldView`
  - `InputFields.swift`: `DateInput`, `GPSInput`
- The code-review-graph may be empty. If so, run `code-review-graph build` first, then use it to find every call site before you replace anything.

## 1 · Tokens (section 8 + `tokens.css`)

Make `Theme` match `tokens.css` and support **light and dark** (asset-catalog colours or `Color(light:dark:)`).

Tokens that are missing or differ today:

| Token | Light | Dark | Note |
|---|---|---|---|
| `okTick` | `#3B7420` | `#8FD16A` | Checkbox fill, "ครบ" chip text. `paperTickStrong` is `#4E7F2E` today; align it to `#3B7420`. |
| `pendingSoft` | `#FFF4E5` | `#2E2213` | Today `#FDF1E4` |
| `dangerText` | `#B42318` | `#FF8A7F` | New |
| `dangerSoft` | `#FDECEA` | `#3A1C1A` | New |
| `okSoft` | `#E2EFDA` | `#1E2A22` | Same value as `paperBand`. Background of the ok chip. |
| `onPrimary` | `#FFFFFF` | `#0B1A2E` | New |
| `sun` | `#FFC53D` | `#FFC53D` | New |

Type scale:
- header 30
- page title 24
- field label 17
- caption 13

Spacing:
- spacing 4 / 8 / 12 / 16 / 24
- radius 8 / 10 / 12 / 16
- touch target ≥ 44 pt

Font: Sarabun via `Font.sarabun` (already registered).

## 2 · Components to provide

Put them in `TCRoof/Components/` (split into files by section), or in `TCRoofKit/Sources/SurveyUI` when the survey module needs them.

**Each component needs:**
- an `#Preview` for every state shown on the board
- iPad and iPhone sizes where the board gives both (see the size table in section 2)
- Dynamic Type
- VoiceOver labels (icon-only buttons need `accessibilityLabel`)

### Section 1 · Layout (`sections/01-layout.png`)

**Survey header** (`g-head` + `g-prog` + `g-caps`)
- Gradient `#1F6FB5→#2E8FDB`, bottom radius 15.
- Text: title 20, sub 15, and the line `5/13 · step name`.
- 13 progress capsules:
  - iPad: height 8, colours mint = done, gradient = current, grey = todo
  - iPhone: height 6, colours green = done, blue = current
  - iPhone also puts the status chip on the step line.

**PWA header**
- Title 30, search field in the header, bottom radius 15.

**White nav bar (`pc-nav`)**
- Back button, title, breadcrumb, plus a trailing secondary action.

**Bottom bar (`g-bar`)**
- Height 53.
- iPad: status button (left, see section 2), `บันทึกร่าง`, `‹ ก่อนหน้า`, `ถัดไป ›`.
- iPhone: `บันทึก` stretches; `‹` and `›` are 72 × 53 and icon only.

**Page scaffolds**
- 2-column, 3-pane and 3-column card grid on iPad.
- 1 column on iPhone: margin 16, card radius 16, gap 12, vertical scroll.

### Section 2 · Buttons (`sections/02-buttons.png`)

**Styles**

| Style | Look |
|---|---|
| primary | solid `#1F6FB5` |
| primary gradient | gradient `#1F6FB5→#2E8FDB` |
| teal gradient | survey module; gradient `#27A99A→#4DB6E0` |
| secondary | white, navy outline |
| destructive | outline, danger text |
| disabled | |
| text | blue, target 44 |
| dashed add | `+ เพิ่ม…` |
| solid danger | only inside confirm dialogs |

**Other button types**
- FAB circle and FAB capsule.
- 44 pt icon button with an optional badge (bell, gear, ✕).

**States**
- pressed: darker, scale 0.98
- disabled: always shows the reason next to the button
- working: spinner, can't be tapped again until done

**Sizes**

| Kind | iPad | iPhone |
|---|---|---|
| Primary in page | 52 · r12 · 16 pt · hugs content | 48 · r10 · 15 pt · full width |
| Bottom bar · บันทึก | 53 · width 170 · 16 pt | 53 · stretches · 16 pt |
| Bottom bar · ก่อนหน้า / ถัดไป | 53 · width 210–250 · step number + name | 53 × 72 · icon only · name in VoiceOver |
| Button in card | 44 · r10 · 14 pt | 44 · r10 · 14 pt · shorter text |
| Icon button | 44 × 44 · r8 | 44 × 44 · no border (in header) |
| FAB | 68 · 24 from edge | 60 · right 20 · bottom 12 |

**Status button (bottom bar)**
- Green when all required fields are done; orange `ยังขาด n รายการ` otherwise.
- Tapping it scrolls to the first missing item.
- The "previous" button always sits next to "next".

### Section 3 · Inputs (`sections/03-inputs.png`)

**Text and value fields**
- Text field; number + unit; calculated / auto value (mint background, filled by the system).
- Focus state: 2 pt blue border.
- Required-but-empty field: red border, pink background, and it counts in `ยังขาด n ช่อง`.
- Read-only: lock icon; the value comes from another step, so edit it there.
- Default vs nameplate value: grey text = default (type over it); tag `ตั้งต้น` / `ป้าย`.

**Pickers**
- Dropdown, closed and open: one open at a time, closes after picking, ✓ marks the current value.
- Date, time, stepper ±.
- Range from–to.
- Switch: for yes/no values that need nothing more.

**Search**
- Search field, and search + type picker.
- Clear button ✕: shown only when there is a value; 44 pt target.

**Choices**
- Single-select chips.
- Pass / fail chips: "ไม่ผ่าน" turns danger at 25%.
- Segmented control; capsule tabs.
- Multi-select chips.

**Checkbox (system spec)**
- 22 × 22, radius 3.
- On: fill `#3B7420` with a white ✓.
- Off: white with a `rgba(0,0,0,.75)` 1 pt border.
- Row min-height 44.

**Other inputs**
- Radio card.
- Long text, and long text with a counter (`22/200`).
- Signature box.
- Photo / location buttons.
- Number input that opens the number pad (section 9).

**Field label**
- 17 semibold navy, red `*` when required.
- Optional fields get a grey `ไม่บังคับ` tag after the name.

### Section 4 · Status (`sections/04-status.png`)

**Status chip**
- Height 24, 12.5 pt bold, capsule, optional 7 pt dot.
- Colour pairs:

| Use | Background | Text |
|---|---|---|
| ok | `#E2EFDA` | `#2E7D32` / `#3B7420` |
| active | `#E3EEF8` | `#1F6FB5` |
| overdue | `#FDECEA` | `#B42318` |
| pending | `#FFF4E5` | `#B45309` |

**Other status elements**
- Example-data / team chip.
- Dot + text line.
- Progress ring with % or days.
- Segmented progress bar.
- `ทำต่อ` resume strip.
- Warning banner, result summary box, missing-items line.
- Toast (dark, 2 lines, auto-dismiss).

### Section 5 · Cards (`sections/05-cards.png`)

- Home menu card with illustration.
- PWA job card:
  - number, gap chip, name, place, ring %, segmented bar
  - `ทำต่อ` strip, section counts, date, sync mark
- Survey job card with appointment time and the teal CTA.
- Horizontal list row (tool, with overdue state).
- Number tiles used as filters.
- Side filter list with counts.

### Section 6 · Media (`sections/06-media.png`)

- Photo slot, empty (upload + camera).
- Photo slot with photo, overlay label, ✓ and ✕.
- Map with layer chips and zoom buttons.
- Compass.
- Shadow animation play / pause.
- Fullscreen button.
- Small segmented control (`แปลน` / `3 มิติ`).

### Section 7 · Overlays (`sections/07-overlays.png`)

- Centre dialog.
- Alert (icon, title, body, 2–3 actions).
- Right-hand detail panel (iPad).
- iOS notification banner with quick actions. Use `UNNotificationCategory` actions in the real app.
- In-app notification panel: unread dot + tint, `อ่านทั้งหมด`.

### Section 9 · Number pad (`sections/09-number-pad.png`)

`NumberPadPopover` replaces the system keyboard for numeric fields.

- **Opening:** tap a number field and a popover opens under it, with an arrow pointing at the field. The field being edited gets a 2 pt blue border.
- **Header:** field name and accepted range. Display is 30 pt, right-aligned, with the unit.
- **Stepper:** − / + step by the value type's step (0.1 m, 1 A, 5 kW).
- **Keys:**
  - 3 × 4 grid, each key ≥ 52 pt
  - decimal point, hidden for integers
  - ⌫ deletes one character; `ล้าง` clears all
- **Out of range:** red display, a message naming the limit, and `ตกลง` is disabled.
- **Confirm / cancel:** `ตกลง` saves and closes. `ยกเลิก` or tapping outside restores the old value.
- **Uses:** distance (m), current (A), load (kW), height (cm), counts.
- **API:** `value: Binding<Double?>`, `range`, `step`, `unit`, `allowsDecimal`.

## 3 · Rules

- Thai UI text exactly as on the board.
- Map every colour to `Theme`; no hex literals in views.
- Touch targets ≥ 44 pt everywhere.
- Don't change the data layer or `TCRoofKit` export logic.
- Keep the iPad layouts that are already built. Only swap in components where the look matches the board.
- Prefer SF Symbols (see `icons/README.md`). Add an SVG to the asset catalog only where no symbol matches (compass, module illustration).
- Add a `ComponentGallery` debug screen (DEBUG builds only, reachable from Settings) that shows every component in all states, laid out like the board. It is the visual test.

## 4 · Done when

- `xcodebuild` builds the app and TCRoofKit.
- Existing tests pass.
- `ComponentGallery` on an iPad Pro 13" simulator (landscape 1366 × 1024) and an iPhone 16 simulator matches `sections/*.png` section by section.
- Take screenshots and list what still differs.
- Summary of files added or changed, and which old views now use the new components.
