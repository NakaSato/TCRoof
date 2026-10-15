# Task: iPhone · เอกสาร PWA v2 (ตามสถานี · ต้องทำ · คลังกลาง)

Board: `PhonePwaDocsV2.dc.html` (390 × 844). States: `states/*.png` (@3x). Preview: `preview.png`. No image assets.

Branch: this hand-off lives on `design/pwa-docs-iphone-v2` (cut from `feat/ipad-home-v3` 3aa7fdb).
Work on your own branch `feat/pwa-docs-iphone-v2` cut from it, and push it. Do not merge.

## What exists today

- `TCRoofCore/StationDocs.swift`: `Kind` (origin `internalDoc / signoff / external`, scope `org / contractor / project / branch / site`,
  packages, `expires`), `Status` (`missing → requested → draft → signed → submitted → approved`, `notNeeded`), `DocState`, `Library`,
  package `Progress`, `expiry(_:_:on:warnDays:)`. `StationDocs+Drafts.swift`: the papers the app drafts.
- `TCRoof/Views/Job/StationDocs/`: `StationDocsScreen` (one station's papers), `StationDocsStore` (the library, `library.json`),
  `StationDocsCard`, `ERCFlowViews`, `OutageLetterSheet`.
- iPhone main dock (`PhoneTabs`): `หน้าหลัก · งานบ้าน · กปภ. · เอกสาร | ตั้งค่า`; `เอกสาร` is `HomeLibraryView` (residential library).
- PWA dock (`PWAPhoneTabs`): its `เอกสาร` tab opens `StationDocsScreen` of the FIRST installing station only.

## Scope: only this

Build ONE new iPhone page, `PWADocsHomeView`: every PWA station's papers at once, in three views. iPhone (compact width) only.

Hosting (report what you did):
1. `PWAPhoneTabs` `.docs` root → `PWADocsHomeView` (replaces the single-station `StationDocsScreen` there; that screen is now pushed from a row).
2. The board shows it under the MAIN dock's `เอกสาร` (selected). Do that too, and keep `HomeLibraryView` reachable as a row
   `เอกสารงานบ้าน` in the settings sheet (the same pattern as `เครื่องมือวัด`). If you think that breaks the home flow, do (1) only and report.

Out of scope: iPad, `StationDocsScreen` internals, the ERC flow, drafting sheets, `StationDocs` rules, stored model fields (add only optional ones).

## Change list

1. **Header** (blue gradient, as the PWA home): title `เอกสาร PWA`, a 44 pt round search button and the bell with its unread badge.
   - Search: the field grows to the left over 0.36 s (after 0.1 s), the title fades out; placeholder `ค้นหาเลขที่ ชื่อโครงการ…`, ✕ closes (state 06).
     It filters by MP number, station name and paper name in all three views. Reuse the PWA home's search animation if it exists.
   - The bell opens the existing notifications screen.
2. **View switch** (pill segmented control, 3 equal segments, 38 pt): `ตามสถานี n` (stations), `ต้องทำ n` (count in red = open items for us), `คลังกลาง n` (library papers).
3. **Summary card** (all views):
   - `อนุมัติแล้ว` + big `approved / total ฉบับ` and a green `%` pill.
   - One stacked bar by status: อนุมัติแล้ว green, ยื่นแล้ว purple, รอลงนาม orange, ร่าง blue, ยังไม่มี grey (proportional; `requested` counts with ยื่นแล้ว's purple? — see open questions).
   - Three counts with coloured dots: `ทีมเราทำ` (blue, open internal papers), `รอ กปภ. ลงนาม` (orange, sign-off papers drafted not signed),
     `รอหน่วยงานนอก` (purple, external papers requested / submitted). Tapping one opens `ต้องทำ`.
   - Totals: over every PWA station's applicable papers (`notNeeded` and conditions excluded) + library papers counted once.
4. **Expiry banner** (orange, clock icon): the nearest expiring library paper, e.g. `ใบ กว. วิศวกรไฟฟ้า หมดอายุอีก 49 วัน ›`; tap opens that paper.
   Hidden when nothing expires soon. Use `StationDocs.expiry`; the board shows 49 days while the default warning is 30 days (open question).
5. **ตามสถานี** (states 01–03):
   - Filter pills `ต้องทำ n · รอผู้อื่น n · ทั้งหมด n`. ต้องทำ = next item is ours or late; รอผู้อื่น = waiting for กปภ. or an outside office.
   - Station cards sorted late → ours → waiting กปภ. → waiting outside → ready: name (bold), `MP n · x kWp · ผู้รับเหมา X`, a status tag top right
     (`ครบกำหนด` / `ทีมเรา` red-ish or blue, `รอ กปภ.` orange, `รอเทศบาล` / `รอ กฟภ.` purple, `พร้อมยื่น` green).
   - **Package stepper**, 4 steps `อ.1 · ขนานไฟ · พค.2 · ส่งมอบ` with `ready/total` under each: done = green ✓ 22 pt, current (first unfinished) = blue 26 pt with a soft ring,
     later = grey outline, not required = dashed `–` and `ไม่ต้องยื่น` (พค.2 only when the inverters are ≥ 200 kVA). Connecting lines green up to the current step.
     Map: อ.1 = `.building`, ขนานไฟ = `.gridConnection`, พค.2 = `.pk2`, ส่งมอบ = `.handover` (`.commissioning` is not on the board, see open questions).
   - A soft row `ถัดไป <first open paper of the current package>  ส่งมอบ dd/MM ›` (handover date from the MP plan). The card opens `StationDocsScreen` for that station.
   - The list scrolls under the dock (bottom inset for the dock). No "show 6" cap: the board's `อีก n สถานี` line is only the board's cut.
6. **ต้องทำ** (state 04): three grouped cards by origin:
   - `ทีมเราจัดทำ` (blue dot) `n รายการ · แอปสร้างได้ m` (m = kinds with `StationDocs.draft(for:)`),
   - `เราร่าง → กปภ. ลงนาม` (orange), `ขอจากหน่วยงานนอก · ติดตามอย่างเดียว` (purple).
   - Rows: a status ring (colour by status), paper name, `MP n station · who / package · <status>` (status word coloured), due on the right (red when late: `เลย n วัน`, `วันนี้`).
     Sorted by due date. Tap opens the station's paper in `StationDocsScreen`.
7. **คลังกลาง** (state 05): the note `อัปโหลดครั้งเดียว ใช้ได้ทุกสถานี · แอปเช็กวันหมดอายุให้`, then one card of rows for library papers (scope org / contractor / project):
   a scope badge (`กปภ.` blue, `บริษัท` purple, `โครงการ` green), name, sub line (scope · use / expiry date), a right pill:
   `ล่าสุด` green, `ตรวจ` orange (needs checking), `n วัน` red (expires soon), `หมดอายุ` red. Tap opens the library paper (upload / replace).
8. **DEBUG**: `-pwaDocsView st|todo|lib`, `-pwaDocsFilter todo|wait|all`, `-pwaDocsSearch YES`, and `-pwaDocsDemo YES` showing the board's example
   (12 stations, nothing saved). One line in CLAUDE.md's simulator list.

## Rules

- Counts and statuses come from `StationDocs` (packages, `papers(in:_:)`, `state(_:station:library:)`, `Progress`); add helpers to `TCRoofCore`
  for the summary, the next paper per station and the to-do grouping, with tests. No numbers from the board in code.
- Station list = `jobs.pwaStations`; installing ones first.
- Colours from `Theme` (navy `#16325C`, primary `#1F6FB5`, ok `#2E9E5B`, warning `#F08C00`, purple `#6B4FBB`, danger `#B42318`, lines `#DDE4ED`);
  add a token for the purple if missing. No hex in views, no `Color.white`; buttons via `TCButtonStyle`; hit areas ≥ 44 pt.
- Split views into computed properties (CLAUDE.md type-check rule).

## Tests (`swift test`)

- summary totals: `notNeeded` excluded, library papers counted once, ≥ 200 kVA adds พค.2
- stepper state per package (done / current / later / skip)
- station filter buckets and sort order
- to-do grouping by origin, late flag
- library pill: latest / soon (n days) / expired

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes.
- [ ] iPhone 17 Pro screenshots of states 01, 04, 05, 06 in `screenshots/` (with `-pwaDocsDemo YES`), compared with `states/`.
- [ ] The PWA dock's เอกสาร and the main dock's เอกสาร both open this page; `StationDocsScreen` opens from a card.
- [ ] iPad unchanged.

## States

| File | What |
|---|---|
| 01-stations-todo | ตามสถานี, filter ต้องทำ |
| 02-stations-waiting | filter รอผู้อื่น |
| 03-stations-all | filter ทั้งหมด |
| 04-todo | ต้องทำ, three groups |
| 05-library | คลังกลาง |
| 06-search | search open |

## Open questions (report)

1. Main dock `เอกสาร`: PWA papers (board) vs the residential library today. Where should `HomeLibraryView` live?
2. Stacked bar: where do `requested` and `signed` go (board has 5 colours: approved, submitted, waiting signature, draft, missing)?
3. `.commissioning` papers: hidden from the stepper, or folded into ส่งมอบ?
4. Expiry banner window: 30 days (code) or 60 (the board shows 49)?
5. `ตรวจ` on a library paper (two versions disagree): is there a field for it, or a new optional `needsReview` flag?
