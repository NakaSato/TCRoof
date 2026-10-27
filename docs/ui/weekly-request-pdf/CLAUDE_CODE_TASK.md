# Task: the weekly request PDF (R1) in the customer's WORK REQUEST form

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/weekly-request-pdf`, then paste `PROMPT.md`, or type
> `Follow docs/ui/weekly-request-pdf/CLAUDE_CODE_TASK.md`

Today, `RoutineReportPages.request` (`TCRoofKit/Sources/PDFReport/RoutineReportPages.swift`, MARK R1) draws the weekly request as a flowing A4 page set with our own headings ("1. กำลังคน" …). The customer (กปภ. / กฟภ.) uses a fixed one-page form: **WORK REQUEST CIVIL-ELECTRICAL · คำขอปฏิบัติงานรายสัปดาห์ (Weekly Request)**. Redraw R1 in that form, the way `docs/ui/daily-report-pdf` redrew R2 (`RoutineReportPages+DailyForm.swift`), and add the blank form.

Everything that prints a weekly request gets the new page: `RoutineReportFiles.request` (the request screen's PDF, `RequestPDFSheet`'s preview and `ดูตัวอย่างคำขอ`, the file kept on the job and sent to Drive, the iPhone summaries' share). R2, R3 and R4 stay as they are.

## Files in this folder

| File | What it is |
|---|---|
| `RptWeekly32.dc.html` | The filled request, week 32 (example data) |
| `RptWeeklyForm.dc.html` | The same form blank, for printing and filling by hand |
| `assets/weekly-pdf/logo-tc.png`, `logo-pea.png`, `assets/iec/pwa-logo.jpg` | The three logos (the same files as `PDFReport`'s `FormImage.tcLogo` / `peaLogo` / `pwaLogo`) |
| `fonts/THSarabun.ttf` | The page number's font |
| `states/01-report.png`, `states/02-blank.png` | @2x renders of the two boards |
| `preview.png` | Both side by side |
| `screenshots/` | Where your renders go |

**Reading the boards.** Read them as text: the markup is the layout (px at 96 dpi), `renderVals()` holds the example data. The filled board's `live` prop is how the iPad request screen fills it (`L.man`, `L.tools`, `L.work`, `L.risk`, `L.wk`, `L.eng`, `L.insp`); that is the data mapping below. **Values in the boards are examples** (สถานีผลิตน้ำโชคชัย, 171.00 kW, 04–10 August 2025, week 32, the names): never hard-code them; `assets/sample-data.json` lists them.

## Page geometry (same as the daily form)

- The board page is 816 × 1056 px (US Letter at 96 dpi). Draw it in board px and scale once onto `dailyFormPage` (A4), exactly as `finishForm` does: the frame at 40 px margin, 736 × 976, 1.5 px black; the page number `n / N` centred under the frame in TH Sarabun 18.23 px.
- Header: the logo band (76 px) and the info table (92 / flex / 72 / 232 px columns; rows 60, 42, 28) are **the daily form's `formHeader`** except the two title lines. Reuse it: give `FormHeader` (or `formHeader`) the titles, `DAILY REPORT` / `รายงานการทำงานประจำวัน` by default, `WORK REQUEST CIVIL-ELECTRICAL` (13 px bold Helvetica, letter-spaced 0.04 em) / `คำขอปฏิบัติงานรายสัปดาห์ (Weekly Request)` (15 px bold) for R1. The daily form's output must stay byte-for-byte the same.
- Body (between the header and the signatures, 12 px padding, blocks spread top to bottom like `spaced`):
  1. two tables side by side (16 px gap): `MANPOWER PLAN แผนกำลังคน` and `TOOL & MACHINERY PLAN แผนเครื่องมือและเครื่องจักร`; columns 52 / flex / 58; header row 36 px (`Item ลำดับที่`, `Description รายการ`, `Qty. จำนวน` / `Used ใช้งาน`); 8 rows of 20 px; a 22 px total row `Total Man-Day` / `Total Tool & Machinery`
  2. `WORK PLAN แผนงานประจำสัปดาห์`: columns 52 / flex / 170 / 56 / 56 / 96 (`Item`, `Description`, `LOCAL/LINE ตำแหน่ง`, `Qty. จำนวน`, `Unit หน่วย`, `Remark หมายเหตุ`); 7 rows of 20 px (taller when a description wraps, as the board's `padding: 2px 8px; line-height: 15px`)
  3. `RISK ASSESSMENT ประเมินความเสี่ยง`: columns 52 / flex / 130 / 250 (`Item`, `Description`, `Risk Level ระดับความเสี่ยง`, `Prevention แนวทางการป้องกันความเสี่ยง`); 4 rows of 20 px, one line each, clipped
  - Section titles 10 px bold underlined, Thai part in Sarabun 11 px; table outer border 1.5 px, inner 1 px; header row's bottom 1.5 px.
- Signatures (136 px band, 1.5 px top border, two halves): `For Approve / เพื่อขออนุมัติ` … `Site Engineer` and `Approve / อนุมัติ` … `Inspector`, a 200 × 42 px signing space over a line, `( name )`, `Date : …`. Reuse the daily form's `signature(_:name:date:drawn:role:x:w:top:)`.

## The blank form (`RptWeeklyForm`)

Same page, with what the board shows: the header's dotted lines (`FormHeader` with nil fields, as `dailyBlankForm`), section titles in English only (`MANPOWER PLAN`, `TOOL & MACHINERY PLAN`, `WORK PLAN`, `ประเมินความเสี่ยง`), numbered empty rows: 11 / 11 / 10 / 4, the `LOCAL/LINE` and risk headers as on the board, empty names. Add `RoutineReportPages.requestBlankForm(settings:measure:)` beside `dailyBlankForm`.

## Data mapping (R1 → form)

| Form | From |
|---|---|
| CONTRACT / PROJECT, kW | `contractText(settings)`, the station's capacity, as the daily form |
| DATE | the request's Monday–Saturday in English, `04–10 August 2025` (`formDate` style, Gregorian, Bangkok), then `(สัปดาห์ที่ n)` with the page's week number (`WeeklyRequestScreen.weekNumber`); move the number into a `RoutineReport` / page helper if PDFReport can't see it |
| Working Time | `workingTime(…)` from the request's own `workStart` / `workEnd`, else the station's |
| FROM / TO / ชื่อโครงการ | as the daily form |
| MANPOWER rows | `r.crew` with a count > 0: role name, count |
| Total Man-Day | the board sums the counts (7). See open question 1 |
| TOOL rows / total | `r.tools` with a count > 0: name, count; total = sum |
| WORK PLAN rows | `r.work`: description, location, qty (`num`, blank when 0), unit; Remark empty |
| RISK rows | `r.risks` with a description: description, `level.title`, prevention |
| Site Engineer | `settings.siteEngineer`, `engineerSignedAt` (`signDate`), the drawn signature (`signature: Photo?`) |
| Inspector | `approvedBy`, else `settings.inspector`; `approvedAt` |

**More rows than the form holds** (8 crew, 8 tools, 7 work, 4 risks): continue on a second page with the same frame and header, the same four sections carrying the rows that didn't fit (numbering continues), and the signatures on the last page only; the page number reads `n / N`. Never shrink the text to fit.

## Scope: only this

- **In scope:** `RoutineReportPages.request` and a new `RoutineReportPages+RequestForm.swift` (or similar); the small shared changes in `+DailyForm.swift` (header titles); `requestBlankForm`; a DEBUG output; tests.
- **Do not touch:** R2 / R3 / R4 output (the daily form must render byte-for-byte as before), `RoutineReport.WeeklyRequest` and its stored fields, the request screens' UI, `RequestPDFSheet`'s UI, `firestore.rules`.
- The per-day columns of today's R1 (`PlanLine.days`, `crewOff`) have no place on the customer's form; they stay in the app and leave the PDF (open question 2).

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `TCRoofKit/Sources/PDFReport/RoutineReportPages.swift` (MARK R1 `request`, `stationLine`, `projectFacts`)
- `TCRoofKit/Sources/PDFReport/RoutineReportPages+DailyForm.swift` (all of it: `FormImage`, `finishForm`, `formHeader`, `table`, `headerCell`, `cell`, `signature`, the helpers, `dailyBlankForm`)
- `TCRoofKit/Sources/TCRoofCore/RoutineReport+Request.swift` (`WeeklyRequest`: `crew`, `tools`, `work`, `risks`, `workStart` / `workEnd`, `engineerSignedAt`, `approvedBy` / `approvedAt`)
- `TCRoof/Views/Job/RoutineReports/RoutineReportSupport.swift` (`RoutineReportFiles.request`, `dailyBlank`, `-routineDemo pdf`)
- the daily form's tests (`grep -rn dailyForm TCRoofKit/Tests`)

## Change list

1. **Shared header.** Make the form header's two title lines a parameter, defaulting to the daily form's. Prove the daily form is unchanged (its existing tests, or a before/after ops comparison).
2. **`requestForm(_:signature:)`.** The filled page as above, from `RoutineReport.WeeklyRequest` and the station; `request(_:signature:)` returns it.
3. **Continuation pages** for rows beyond the form's.
4. **`requestBlankForm(settings:measure:)`**, and `RoutineReportFiles.requestBlank(job)` beside `dailyBlank` (no UI button: open question 3).
5. **DEBUG.** `-screen request -routineDemo pdf` writes next week's request to `Documents/request.pdf` and `-routineDemo blank` also writes `Documents/request-blank.pdf` (beside the daily ones).
6. **Tests** in `TCRoofKit/Tests` (they run on macOS; PDFReport isn't in the Linux set): one page for a request within the form's rows, two for 9 work lines with the signatures on page 2 only; the header's title strings; the Total rows' sums; the blank form's 11 / 11 / 10 / 4 numbered rows; the daily form's ops unchanged.

## Checks when done

- `swift test` in `TCRoofKit` (the new tests and every existing PDFReport test).
- The app builds with `xcodebuild … -derivedDataPath <your scratch>` (in the background).
- Render `request.pdf` and `request-blank.pdf` on a simulator (DEBUG flags above), save PNGs of each page to `screenshots/` (`01-report.png`, `02-blank.png`, and `03-report-p2.png` for an overflow) and compare them with `states/` side by side: frame, header, column widths, row counts, signatures.
- `RequestPDFSheet` still previews page 1.

## Open questions (answer in your report)

1. `Total Man-Day`: the board sums the people (7). Man-days would be people × working days (`r.manDays(days:)`, 42 on the board's week). Which does the customer want?
2. The days per line (`PlanLine.days`) and the crew's days off: drop them from the PDF (the form has no place), or write them in `Remark` (e.g. `จ อ พ`)?
3. Where should `พิมพ์แบบฟอร์มเปล่า` for the request live in the UI (the daily list has one)?
4. The form's date range: Monday–Saturday (working days) or Monday–Sunday, as the screen's header (`4 – 10 ส.ค.`)?
