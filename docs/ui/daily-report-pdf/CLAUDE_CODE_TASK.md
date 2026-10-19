# Task: the daily report PDF in the customer's DAILY REPORT format

Today, `RoutineReportPages.daily` (`TCRoofKit/Sources/PDFReport/RoutineReportPages.swift`, MARK R2) draws the daily report as one flowing A4 page set with our own headings. The customer (กปภ. / กฟภ.) uses a fixed form: **DAILY REPORT · รายงานการทำงานประจำวัน**. It has three pages, plus continuation pages for extra photos. Redraw R2 in that form.

Everything that prints a daily report gets the new pages:
- the daily report screen's PDF
- `PDF รวม` on the install tracking page
- `-routineDemo pdf` (`Documents/daily.pdf`)

R1, R3 and R4 stay as they are.

## Files in this folder
| File | What it is |
|---|---|
| `RptDaily1.dc.html` | Filled report, page 1: header, weather, manpower, tools, materials |
| `RptDaily2.dc.html` | Filled report, page 2: key plan, progress of work, problems |
| `RptDaily3.dc.html` | Filled report, page 3: four photos and the two signatures |
| `RptDailyForm1–3.dc.html` | The same three pages blank, for printing and filling by hand |
| `RptDailyForm4.dc.html` | Continuation page: photos 5–10, six per page |
| `assets/daily-pdf/` | Logos (`logo-tc.png`, `logo-pea.png`), the example key plan and the example photos (3 days × 4) |
| `assets/iec/pwa-logo.jpg` | The PWA logo |
| `fonts/THSarabun.ttf` | The font of the page number |
| `states/` | @2x renders, listed below |
| `preview.png` | All pages side by side |
| `screenshots/` | Where your screenshots go |

**Reading the boards.** Read them as text. The markup is the layout. `renderVals()` holds the example data, and the `day` prop picks one of three example days. The `live` prop is how the iPad daily screen (`docs/ui/daily-report-ipad/iPadDaily.dc.html`) fills the pages, and its fields are the data mapping below. Values in the boards are examples: never hardcode them.

**States**
- `01`–`03`: day 1, pages 1–3
- `04`: day 2, page 1 (rain 14:00–17:00)
- `05`: day 2, page 2 (three progress lines)
- `06`–`09`: the blank form, pages 1–4

## Page geometry
- The board page is 816 × 1056 px at 96 dpi, which is US Letter (612 × 792 pt).
- Margin: 40 px (30 pt).
- Frame: 736 × 976 px, 1.5 px black.
- Page number: centred under the frame, "n / N", TH Sarabun 18.23 px.

Convert px to pt with × 0.75. Our other reports are A4 (`ReportLayout.pageW/H`). See open question 1. Until it's answered, build Letter, keep the size in one constant, and check that A4 would fit.

Fonts and colours:
- Latin text: Arial (Helvetica in the PDF).
- Thai text: Sarabun.
- Lines: black.
- Weather cells: `F` is #B7DEE8 and `R` is #FF0000.

Everything is vector (`DrawOp`), as in the rest of `PDFReport`. Photos and logos are images.

## Common header (every page)
1. **Logo band, 76 px.**
   - TC Renewable logo on the left, 40 px high.
   - Centre: "DAILY REPORT" (14 px bold) over "รายงานการทำงานประจำวัน" (15 px bold).
   - Right: PWA logo (40 px) and PEA logo (36 px).
   - Add the three logos to `PDFReport` resources.
2. **Info table.** Four columns: 92 / flex / 72 / 232 px.
   - Row 1 (60 px): CONTRACT / PROJECT, then the contract text, ending with "กำลังการผลิตติดตั้ง {kWp, 2 decimals} กิโลวัตต์". Then DATE / วันที่, then the date "1-Jul-2025" (12 px bold, `d-MMM-yyyy`, English, Gregorian) with "Working Time: 08.00 AM - 18.00 PM" below it.
   - Row 2 (42 px): FROM / จาก → `settings.contractor`; TO / ถึง → `settings.employer`.
   - Row 3 (28 px, spans all columns): "ชื่อโครงการ : {station line}".

## Data mapping (`RoutineReport.Daily`, `Settings`, `DailyEntry`)

| Page · section | Rows | Source |
|---|---|---|
| Header contract text | – | `settings.contractName` (fall back to the board's sentence) + `station.capacityKWp` |
| Header date / working time | – | `daily.date`; `workStart` / `workEnd` |
| 1 · WEATHER REPORT | 15 hour cells, 06:00–20:00 | `daily.weather` (`RoutineReport.weatherHours` is 6…20, which matches). `.fine` → F, `.rain` → R, nil → blank. See open question 3 for `.cloudy`. |
| 1 · MANPOWER REPORT | 17 rows + Total Man-Day | `daily.crew`: Item, Description, Qty. The total is `crewTotal`. |
| 1 · TOOL & MACHINERY REPORT | 17 rows + Total | `daily.tools`: Item, Description, Used. The total is the sum. |
| 1 · MATERIAL ON SITE | 8 rows | `daily.materials`: Item, Description, LOCAL/LINE, Qty, Unit, Remark |
| 2 · KEY PLAN | picture 480 × 333 px, centred | the A2 site picture (`KeyPlan`, as now). Keep marking today's locations if `keyPlan.points` exist. Leave the box empty when there is no picture. |
| 2 · PROGRESS OF WORK | 6 rows | `daily.progress`: Item, Description (`description`, else the MP task's title), LOCAL/LINE, Qty 1, Unit "งาน", Today % = `RoutineReport.todayDelta`, Accumulated % = `percent`, Remark blank. A stopped day writes `stopReason` in row 1. |
| 2 · PROBLEMS, OBSTRUCTIONS AND SOLUTIONS | 5 rows | `daily.problems` (non-empty): Item, Description, Solutions, Status (`closed` → "แก้แล้ว", else "กำลังแก้") |
| 3 · photos | 2 × 2 grid, caption "รูปที่ n {caption}" | `DailyEntry.photos[0..<4]`, aspect-fill in a 5 px inset frame |
| 3 · signatures (144 px band) | – | Left: "Please be informed accordingly / จึงเรียนมาเพื่อทราบ", `settings.siteEngineer`, "Site Engineer", with the date from `engineerSignedAt`. Right: "Acknowledge / รับทราบ", `settings.inspector`, "Inspector", with the date from `inspectorAckAt`. An unsigned date stays "......../......../........". |
| 4+ · SITE PHOTOS (CONTINUED) | 2 × 3 grid per page | photos 5, 6, …. Add pages only while photos remain, so N = 3 + ceil((photos − 4) / 6). |

Rows that overflow a fixed table (more than 17 crew lines, more than 8 materials, more than 6 progress lines, more than 5 problems) continue on an extra page with the same header and section title. Never shrink the text.

## Change list
1. **`RoutineReportPages.dailyForm(_:all:keyPlan:)`.** Draws the pages above. Point `daily(...)` at it (or replace it), so every caller gets the new form. Keep the old flowing layout only if something else still needs it.
2. **Header and table helpers.** Build the fixed-grid tables: bilingual header cells, fixed row heights, 1 / 1.5 px rules. Don't build them with the flowing `Flow.table`. Split them into small functions (see the Debug SIGSEGV note in CLAUDE.md for long expressions).
3. **Blank form.** `RoutineReportPages.dailyBlankForm()` draws pages 1–4 of `RptDailyForm*`:
   - dotted fill-in lines for kWp, date, working time and the station
   - numbered empty rows (15 crew, 15 tools, 7 materials, 7 progress, 5 problems)
   - "พื้นที่วางผังตำแหน่งงาน (Key Plan)"
   - photo slots 1–10

   Offer it from the daily report list's menu as `พิมพ์แบบฟอร์มเปล่า` (share sheet).
4. **DEBUG.**
   - `-routineDemo pdf` writes the new pages to `Documents/daily.pdf`.
   - Add `-routineDemo blank`, which writes `Documents/daily-blank.pdf`.
   - Update both lines in CLAUDE.md.
5. **Tests (`PDFReportTests`).**
   - A day with 4 photos gives 3 pages, and with 9 photos gives 4.
   - 20 crew lines give an extra page 1.
   - The weather row puts F/R in the right hour cells.
   - The header's date reads `d-MMM-yyyy` in English.
   - A signed report prints the sign dates.
   - The blank form has 4 pages.

## Check list
- [ ] `swift test` (PDFReport and the routine report tests)
- [ ] xcodebuild with your own `-derivedDataPath`
- [ ] `-screen daily -routineDemo pdf` and `-routineDemo blank`: render the PDFs to PNG and save them in `screenshots/` as `01`–`09`, matching `states/`. Compare them side by side and list the differences.
- [ ] `PDF รวม` on the install page shows the new pages, one report after another, each numbered "n / N" within its own report.

## Open questions (report them)
1. Letter (as the board) or A4 (our other PDFs and the Excel template's print setup)?
2. "Working Time: 08.00 AM - 18.00 PM" mixes 24 h with AM/PM. Should we copy it as on the customer's form, or write "08.00 - 18.00 น."?
3. The form's legend has only F and R. How should `.cloudy` (C) print: as F, or as a third grey cell with a legend entry?
4. ชื่อโครงการ: the board reads "สถานีผลิตน้ำโชคชัย การประปาส่วนภูมิภาคสาขาโชคชัย". Which job fields make that line (station name + branch)?
5. Should page 3 carry the signature images, or only names and dates as on the board?
