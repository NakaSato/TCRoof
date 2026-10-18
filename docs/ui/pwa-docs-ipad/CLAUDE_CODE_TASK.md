# Claude Code task: iPad `เอกสาร` (PWA documents) page, regular width (board 18 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/pwa-docs-ipad/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · เอกสาร PWA (ตามสถานี · ต้องทำ · คลังกลาง)` (`iPadPwaDocs.dc.html`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** MP numbers, stations, counts, dates, names, %. Never hardcode it.

## What exists (the iPhone page is built)

- **iPhone page:** `docs/ui/pwa-docs-iphone-v2` is implemented as `TCRoof/Views/Job/StationDocs/PWADocsHomeView.swift` + `+Cards.swift`.
  - It has the three panes `st / todo / lib`, the summary and the station filter.
  - Its demo is `PWADocsDemo`. Its DEBUG flags are `-pwaDocsView`, `-pwaDocsFilter`, `-pwaDocsSearch` and `-pwaDocsDemo`.
- **Data:** everything comes from `TCRoofCore/PWADocs.swift` over `TCRoofCore/StationDocs.swift`:
  - `summary`, `rows`, `stepper` (the 4 steps `อ.1 · ขนานไฟ · พค.2 · ส่งมอบ`), `todo` groups by `Origin`, `library` rows, `nearestExpiry`
  - the พค.2 `pk2Checklist` (23 items)
  - `Status.choices(for:)`
- **Existing screens:**
  - `StationDocsScreen`: one station's papers by package, plus the พค.2 check list.
  - `StationDocSheet`: edits one paper (status, expiry, note, file import, the app's drafts).
  - `OutageLetterSheet`: the outage letter draft.
  - `ERCFlowViews`: `ลำดับ กกพ.`.
- **iPad dock today:** `PadTabs` `.docs` (`เอกสาร`) shows `HomeLibraryView`, the residential library.
  - On iPhone the dock's `เอกสาร` is already `PWADocsHomeView`, and the residential library is the settings sheet's `เอกสารงานบ้าน` row (`PhoneSettings.swift`).

**This task builds the iPad (regular width) layout of the same page** and adds the drill-downs and sheets the board shows. The iPhone page stays as it is.

## Scope

- **In scope:**
  - iPad regular width: the `เอกสาร` page and its sheets
  - the `PadTabs` `.docs` route
  - additive `PWADocs` helpers with tests
- **Do not touch:**
  - the iPhone layout of `PWADocsHomeView`
  - `StationDocsScreen`'s layout
  - `OutageLetterSheet`, `ERCFlowViews`
  - stored `StationDocs` fields (except the one optional field in §6)
  - the residential library itself
- **Data rule:** show only what has a source.
  - If an element has no model (see "No source"), hide it and list it in the report.
  - `-pwaDocsDemo YES` may show the board's example, for screenshots only.
- **Board-only control:** the dashed chip `ตัวอย่าง: … ▾` at the top right only switches the board's previews (team / contractor / offline). **Do not build it.**

**Before editing:**
- Use code-review-graph (per `CLAUDE.md`), else grep.
- Read `PWADocsHomeView*.swift`, `PWADocs.swift`, `StationDocs.swift` (`Kind`, `Status`, `DocState`, `Library`, `pk2Checklist`), `StationDocsScreen.swift` (`StationDocSheet`), `PadTabs.swift` and `PhoneSettings.swift`.

## Files in this folder

| File | Shows |
|---|---|
| `states/01-stations.png` | `ตามสถานี`, station list + selected station panel (= `preview.png`) |
| `states/02-package-pk2.png` | Right panel drilled into a package: พค.2 with its 23-item check list and the `ลำดับ กกพ.` link |
| `states/03-doc-sheet.png` | Document sheet: status steps, file preview, facts, history, actions (a sign-off paper waiting for signature, reminded once) |
| `states/04-upload-id-card.png` | Upload sheet on an ID-card slot: slot chips, shared-file note, source cards, the 3 masking checks |
| `states/05-todo.png` | `ต้องทำ`: three columns by origin, every open paper due-first |
| `states/06-library.png` | `คลังกลาง`: expiry timeline, groups `ระดับ กปภ.` / `ผู้รับจ้าง` / `โครงการ` / `สาขา กปภ.`, `ใช้ใน N สถานี` |
| `states/07-library-sheet.png` | Library paper sheet: zone choice (two conflicting orders), versions, stations using it |
| `states/08-search.png` | Search results grouped `สถานี` / `เอกสาร` / `คลังกลาง` |
| `states/09-filter-empty.png` | Contractor filter with no match: empty state + `ดูทุกสถานี` |
| `states/10-contractor-locked.png` | A contractor (external role) opens `เอกสาร`: the page is locked (§1) |
| `states/11-offline-upload.png` | Offline: header chip + the upload sheet's queue note |
| `iPadPwaDocs.dc.html` + `grf.css` | Design source. Read it as text: `renderVals()` holds every size, colour and rule. The v2 part starts at the comment `v2: one document model` |
| `screenshots/` | Empty: put your simulator screenshots here |

The board uses Sarabun (the app's `Font.sarabun`); its font `url(/_blob/…)` lines only work on the design canvas.

## Change list

### 1. Route

- `PadTabs` `.docs` shows the new iPad page (`PWADocsHomeView` in regular width, or a sibling `PWADocsPadView`, whichever reads cleaner).
- Move `HomeLibraryView` on iPad to a row `เอกสารงานบ้าน` in the iPad settings, the same as the iPhone settings sheet.
- **Contractors have no access** (decided 18 ต.ค.). Keep the permission gate: without `.stationDocsDrafts` (the external role) the page is only the locked state, as on iPhone (`states/10`):
  - centred icon, `เอกสารสำหรับทีมภายใน`
  - `เอกสาร PWA ร่างและยื่นโดยทีมภายใน · ผู้รับเหมาไม่มีสิทธิ์เข้าถึงหน้านี้`
  - `งานที่ต้องส่งจากหน้างาน เช่น รายงานประจำวันและผลทดสอบ IEC ทำได้ในหน้างานของแต่ละสถานี`
  - No summary, list, search results or sheets are built for them, and no paper data is loaded.

### 2. Frame (`states/01`)

**Header:** the home's large blue header: title `เอกสาร`, the growing search, and the bell (`PWABell`).

**Under the header:**
- **View switch:** `ตามสถานี n` · `ต้องทำ n` · `คลังกลาง n`, 520 pt wide.
  - `ต้องทำ` counts only papers **late or due today** (red). Today it counts every paper that is ours.
- **Right of the switch:**
  - the project line
  - a sync chip:
    - `ซิงก์ล่าสุด HH:mm` with a green dot, from `CloudSync`
    - `ออฟไลน์ · แสดงข้อมูลในเครื่อง` in amber when sync is offline (`states/11`)

**Summary row:**
- **Summary card:**
  - an approved ring and `n% อนุมัติแล้ว a / t ฉบับ`
  - one stacked bar by status, with a legend: `อนุมัติแล้ว · ยื่นแล้ว · รอลงนาม · ขอแล้ว · ร่าง · ยังไม่มี` (from `PWADocs.summary` bands)
- **Three tiles,** 190 pt each, one per origin: `ทีมเราทำ`, `รอ กปภ. ลงนาม`, `รอหน่วยงานนอก`.
  - Each shows its open count; a tap opens `ต้องทำ`.

**Bottom:** content ends 116 pt above the page bottom, clear of the dock. Lists scroll inside their cards.

### 3. `ตามสถานี` (`states/01`, `02`, `09`)

**Left card**

- **Header row:** title, plus the existing station filter `ต้องทำ · รอผู้อื่น · ทั้งหมด`, with counts.
- **New toolbar row:**
  - contractor chips `ทุกผู้รับเหมา` / `ผู้รับเหมา A…`, from the stations' `contractor` values, in that order
  - a sort button, `เรียง: วันส่งมอบ` ↔ `เรียง: ขาดมากสุด`; "missing" = open papers of the station
- **Columns:** `สถานี` 200 pt · `ถัดไป` · `ชุดเอกสาร` 300 pt.
- **Row:**
  - **Station cell:** `MP n name` (one line), then `ส่งมอบ d/M · ผู้รับเหมา X · ขาด n` (one line; `ขาด n` in amber).
  - **`ถัดไป` cell:** the tag pill, then the next paper.
    - **No `ทีมเรา` tag:** when the row's tag is `ทีมเรา` (state `.ours`), show no pill, only the text.
    - Other tags stay: `ครบกำหนด`, `รอ กปภ.`, `รอเทศบาล`, `พร้อมยื่น`.
    - Do this in the iPad view only; `PWADocs.row` keeps its tag, which the iPhone still shows.
  - **Stepper:** as on iPhone.
- **Selected row:** tint plus a 3 pt left bar.
- **Empty state** (`states/09`):
  - ✓ tile, `ไม่มีสถานีที่<filter> ของผู้รับเหมา X`, `เอกสารของสถานีกลุ่มนี้ไม่มีอะไรค้าง`
  - a `ดูทุกสถานี` button that resets both filters

**Right panel (440 pt): selected station**

- **Head:** `MP n name`, full name, `kWp · ผู้รับเหมา · ส่งมอบ`, and `เปิดสถานี ›`, which pushes `StationDocsScreen`.
- **Next box:**
  - The heading is `ถัดไป · <tag>`, or just `ถัดไป` when the tag is `ทีมเรา`.
  - Tinted by state.
- **Package cards:** one per step.
  - Content: title, `a/b ฉบับ` or `ครบ n/n`, a progress bar, the package's note, and a `›`.
  - The พค.2 card under 200 kVA is dashed: `ไม่ต้องยื่น`, not tappable.
  - **A tap drills in** (`states/02`): the panel shows `‹ ทุกชุดเอกสาร`, the package title, `a/b`, a bar, a note line, then one row per paper.
- **Paper rows:**
  - status ring, or ✓ (approved), or a purple dot (submitted), or dashed `–` (not needed)
  - the paper name
  - origin and who (`kind.signBy` / `obtainFrom`), plus `· ต้องปิดข้อมูลบนบัตร` for ID papers
  - a teal `⇄ <other packages>` line when the kind is in more than one package (`kind.packages`)
  - a status pill
- **พค.2 drill-down:**
  - list the 23 `pk2Checklist` items, numbered, in that order
  - items whose condition the station doesn't meet read `ไม่เข้าเงื่อนไข`, greyed, and count as done
  - add a purple row `ลำดับ กกพ. · ยื่น พค.1 → ตรวจสถานที่ → พค.2 ›` that opens `ERCFlowViews` (`ลำดับ กกพ.`) for that station
- **`ความเคลื่อนไหว`:** the station's two most recently updated papers (`DocState.updatedAt`), with relative time.
- **Sticky bottom bar:**
  - `รวมชุดเอกสาร PDF` (primary): merge the station's approved files with PDFKit and open the share sheet.
  - `อัปโหลด`: opens §5, scoped to the drilled package if any.

### 4. Document sheet (`states/03`)

- **Size:** 920 × 760 sheet. Use it from every paper tap: drill-down rows, `ต้องทำ` cards and search.
  - Build it as a regular-width presentation of the existing `StationDocSheet` data, or a new `PWADocSheetPad` that edits the same `DocState`.
- **Head:** paper name, `MP n name · <package>`, the origin pill, and ✕.
- **Status steps:** from `Status.choices(for: origin)` without `.notNeeded`.
  - Done steps are green ✓, the current one is blue with a ring, later ones are grey.
  - Labels: `ยังไม่มี · ร่าง · รอลงนาม · ยื่นแล้ว · อนุมัติ`.
  - External papers: `ยังไม่มี · ขอแล้ว · ได้รับแล้ว`.
  - Map `.requested` on a sign-off paper to `รอลงนาม`.
- **Left column (380 pt), file preview:**
  - first page of the file (QuickLook thumbnail) and `ฉบับล่าสุด · PDF · n หน้า`
  - when there is no file: a dashed `ยังไม่มีไฟล์` box
- **Right column, facts:**
  - `ผู้รับผิดชอบ`
  - `ครบกำหนด` (`PWADocs.due`; `เลย n วัน` in red)
  - `เลขที่หนังสือ`: only if the note holds one; otherwise hide the line
  - `ใช้ร่วมกัน`
  - `ผู้รับเหมา`
- **ID papers** (`grantor_docs`, `grantee_docs`): a red note `🔒 ก่อนแนบ ปิดศาสนา กรุ๊ปเลือด และวันเกิดบนบัตรทุกใบ · แอปไม่เก็บเลขบัตรเป็นข้อความ`.
- **`ประวัติ`:** only what has a source (`updatedAt`, reminders from §6). See "No source".
- **Footer actions by status,** last one primary:

  | Status | Actions |
  |---|---|
  | `missing` | `สร้างร่างจากข้อมูลหน้างาน` if `StationDocs.draft(for:)` exists (opens the existing draft flow) · `แนบจากคลังกลาง` for shared scope · `ส่งคำขอเอกสาร` (→ `.requested`) for external · `อัปโหลดไฟล์` (§5) |
  | `draft` | `แก้ร่าง` (draft flow) · `ส่งให้ <signBy> ลงนาม` (→ `.requested`) for sign-off, else `ยื่นแล้ว` (→ `.submitted`) |
  | `requested` | `ทวง` / `ทวง (ครั้งที่ n)` (§6) · `อัปโหลดฉบับลงนาม` or `ได้รับแล้ว · อัปโหลด` (§5) |
  | `signed` / `submitted` | `บันทึกผลอนุมัติ` (→ `.approved`) |
  | `approved` | `ดาวน์โหลด` (share sheet) · `เปลี่ยนไฟล์` (§5) |

### 5. Upload sheet (`states/04`, `11`)

- **Size:** 640 pt wide.
- **Title:** `อัปโหลดเอกสาร · MP n name`, with the package (or `ทุกชุดของสถานีนี้`) under it.
- **`1 · ใส่ในช่องไหน`:**
  - chips of the station's open papers (the drilled package only, when there is one)
  - up to 12, then `อีก n ช่อง`
  - preselected when opened from a paper
- **Shared note:** the teal `⇄ ไฟล์นี้จะเข้า <packages> ด้วย · อัปโหลดครั้งเดียว` when the kind is in several packages. It is the same `DocState`, so one upload covers them.
- **`2 · จากไหน`:** three cards.
  - `ถ่ายรูปเอกสาร`: `VNDocumentCameraViewController`, multi-page → one PDF
  - `เลือกไฟล์`: the existing file importer
  - `จาก Google Drive`: only if a Drive picker exists; otherwise hide it and report
- **`3 · ยืนยันว่าปิดข้อมูลบนบัตรทุกใบแล้ว`:** ID papers only. Three checks: `ปิดศาสนา`, `ปิดกรุ๊ปเลือด`, `ปิดวันเกิด`.
  - `อัปโหลด` stays disabled until all three are ticked.
  - Store nothing from the card as text.
- **Footer:**
  - a hint line: `เลือกช่องเอกสาร` / `เลือกที่มาของไฟล์` / `ยืนยันการปิดข้อมูลบนบัตรให้ครบ 3 ข้อ` / `พร้อมอัปโหลด`
  - `ยกเลิก`, and `อัปโหลด`
- **On upload:** attach the file the way `StationDocSheet.attach` does.
  - New status: sign-off `requested` → `submitted` (signed copy), otherwise sign-off → `draft`; internal → `submitted`; external → `approved`.
- **Offline:** an amber note `ออฟไลน์ · ไฟล์จะเข้าคิวและส่งเมื่อออนไลน์`. Files are local first, so nothing else changes.

### 6. Reminders (`ทวง`), the only new stored field

- Add `reminders: [Date]` to `StationDocs.DocState`:
  - optional
  - `decodeIfPresent` with default `[]`
  - not encoded when empty, if that is easy
- `ทวง` appends now, then opens the share sheet with a short Thai message: paper, station, `ครบกำหนด d/M`.
  - The app sends nothing by itself.
- **Where it shows:**
  - the count: `ทวงแล้ว n ครั้ง` on `ต้องทำ` cards, `ทวง (ครั้งที่ n+1)` on the button
  - the history lines: `ทวงครั้งที่ n · <date>`
- Add a `StationDocsTests` case: old JSON decodes, and a round trip keeps the reminders.

### 7. `ต้องทำ` (`states/05`)

- **Layout:** three equal columns: `ทีมเราจัดทำ` (internal; also the library papers that are missing) · `เราร่าง → กปภ. ลงนาม` · `ขอจากหน่วยงานนอก`.
  - Each column has a 3 pt top accent: `#1F6FB5` / `#F08C00` / `#6B4FBB` via Theme tokens.
- **Column head:** dot, title, a red `เลย n` pill (late or due today; hidden at 0), and `n รายการ`.
- **Sub-bar:** `แอปสร้างได้ n · เรียงตามกำหนด` / `ทวงได้จากแอป · …` / `ติดตามอย่างเดียว · …`.
- **Cards:** every open paper (`PWADocs.todo`), sorted by due date ascending. The whole column scrolls.
  - **Card content:**
    - ring by status, and the paper name
    - `MP n name · <step title>` plus `· ทวงแล้ว n ครั้ง`
    - a green `แอปสร้างได้` pill when draftable and missing
    - status pill, due (`เลย n วัน` red, `วันนี้` amber, else `d/M`)
    - an action button: `สร้างร่าง` / `แก้ร่าง` / `ทวง` / `ขอเอกสาร` / `อัปโหลด` / `แนบจากคลัง`
  - Card and button both open §4.
  - Name พค.2 papers by check-list number where they map to one: `พค.2 ข้อ n · …`.
- **Empty column:** `ไม่มีรายการค้าง`.

### 8. `คลังกลาง` (`states/06`, `07`)

- **Expiry timeline card:** `หมดอายุใน 12 เดือน`, with `แอปเตือนก่อน 60 วัน · ใช้แทนในทุกสถานีเมื่ออัปโหลดฉบับใหม่`.
  - A 12-month track; its first 60 days are tinted red.
  - Markers for each library paper with `expiresAt` within a year, coloured red under 60 days, amber under 180, green otherwise.
  - Each marker's label is `name · n วัน`, and a tap opens the paper.
  - Hide the card when no paper expires.
- **Groups by `Scope`** (`.org` · `.contractor` · `.project` · `.branch`): `ระดับ กปภ.` / `ผู้รับจ้าง` / `โครงการ` / `สาขา กปภ.`, each with its sub-line. Three cards per row.
  - **Card:** scope badge, name, sub-line (`scope.title`, expiry), a blue `ใช้ใน n สถานี` line, and a status pill.
  - n = PWA stations whose needed papers include that kind.
- **Library sheet** (600 pt):
  - **Head:** badge, name, sub-line, pill, ✕.
  - **`ใช้ใน n สถานี`:** chips of the first six stations, then `และอีก n สถานี`.
  - **Footer:** `ดาวน์โหลด`, and `อัปโหลดฉบับใหม่` (replaces the library file).
  - **`ฉบับ`** (versions) and the **zone choice** (`ฉบับเขต 1–5 / 6–10`) have no model: hide them (open questions 3–4).

### 9. Search (`states/08`)

- **Trigger:** the header search grows as on the PWA home.
- **Panel** (560 pt, under the header, right-aligned):
  - **Empty text:** `ค้นได้ทั้งสถานี ชื่อเอกสาร และเลขที่หนังสือ`, plus four suggestion chips. Recent searches are fine instead.
  - **With text:** `n ผลลัพธ์`, then rows tagged `สถานี` / `เอกสาร` / `คลังกลาง`: name, then context (`MP · package · status`).
    - A station row selects it in `ตามสถานี`; a paper row opens §4; a library row opens §8's sheet.
  - **No match:** `ไม่พบ "<q>" · ลองเลข MP หรือชื่อสถานี`.
- **Matching:** reuse `PWADocs.matches`; add the paper note so a letter number can be found.

### 10. DEBUG flags (iPad, with `-screen home -homeTab docs -homeBoard YES -pwaDocsDemo YES`)

- **Reuse:** `-pwaDocsView st|todo|lib`, `-pwaDocsFilter`, `-pwaDocsSearch YES`.
- **Add:**
  - `-pwaDocsStation <mp>`: selects a station
  - `-pwaDocsPackage building|grid_connection|pk2|handover`: drills in
  - `-pwaDocsPaper <kind id>`: opens §4 for the selected station
  - `-pwaDocsUpload YES`: opens §5
  - `-pwaDocsContractor <name>`
  - `-pwaDocsSort miss`
  - `-pwaDocsLibPaper <kind id>`: opens §8's sheet
  - `-pwaDocsQuery <text>`: search open with text
- Add one line for them in `CLAUDE.md`'s simulator list.

## No source (hide and report, unless you find one)

- History lines other than `updatedAt` and reminders (who uploaded, who sent the request).
- A library paper's earlier versions, and the zone choice between two conflicting orders.
- `จาก Google Drive` as an upload source, if there is no picker.
- A letter number (`เลขที่หนังสือ`) as its own field. Don't add one; read it from the note only if the team writes it there.

## Check

- [ ] `swift test` (new `StationDocs` reminders test; any new `PWADocs` helpers tested: late count, station missing count, `usedIn` count).
- [ ] Build with your own `-derivedDataPath`.
- [ ] Add `PadPWADocsUITests` (iPad), covering:
  - [ ] Opening the `เอกสาร` tab.
  - [ ] A contractor chip narrows the list, and the empty state's `ดูทุกสถานี` resets it.
  - [ ] A package card drills in, and `‹ ทุกชุดเอกสาร` goes back.
  - [ ] A paper opens §4, and `ทวง` raises the count.
  - [ ] Upload on an ID paper stays disabled until the three checks are ticked.
  - [ ] Search opens a paper.
- [ ] With `-role external`, the `เอกสาร` tab shows only the locked state (add it to `PadPWADocsUITests`, or to `RoleUITests`).
- [ ] Run it, plus `HomeNavbarUITests` (the dock's `เอกสาร` route changed).
- [ ] iPad Pro 13" simulator, `-screen home -homeTab docs -homeBoard YES -pwaDocsDemo YES` plus the flags:
  - Save `screenshots/01`–`11` with the same names as `states/`.
  - Compare them with the states.
- [ ] Regression: iPhone `-screen home -homeTab docs -pwaDocsDemo YES` looks as before (`docs/ui/pwa-docs-iphone-v2/states`).

## Open questions (report)

1. Is moving the residential library to iPad settings (`เอกสารงานบ้าน`) OK, now that the iPad dock's `เอกสาร` is the PWA page as on iPhone?
2. Should library papers keep earlier versions (a version list on `Library`)?
3. The two conflicting `คำสั่ง กปภ.` (POA orders): keep one kind per zone, or one kind with a zone choice?
4. Is a letter number worth its own optional field on `DocState`?
