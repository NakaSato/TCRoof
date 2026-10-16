# IEC 62446 Word photo appendix (Swift spec, draft)

**Status:** Built with approach B (`ExcelExport/IECWord.swift`, tests `IECWordTests`; `ส่งออก Word ภาพถ่าย` on the IEC overview) and the draft answers of §7: a missing photo keeps its frame with `ไม่มีรูป`, captions are labels only, the thermal images are a part 7, photos are shrunk to 1600 px at JPEG 0.7 (`ImageUtil.compressed`), and the font is TH Sarabun New 16 pt. The header's title line is the app's wording until the original is available; with the customer's .docx, approach A replaces it.
**Platform:** `TCRoofKit` package: the writer beside the Excel one in `ExcelExport` (`IECWord.swift`, reusing
`ZipArchive`), testable with `swift test` on macOS; the app passes the photos' bytes in.
**Source:** the customer's `2_Form_IV TEST_Before-After_PWA.docx` (A4 portrait, 37 pages, 123 photos for
แพรกหนามแดง), described in `docs/forms/iec62446-pwa/README.md` §2. **The file itself is not in the repo** (17 MB).
**Related:** `docs/specs/iec62446-excel-export-swift.md` (the Excel half, filled in place), the iPad screens under
`TCRoof/Views/Install/IEC/` (photos are taken on `กรอกทีละสตริง` and `รูปถ่าย`).

**One idea:** the Word file is the photo evidence for the Excel sheet: every string's meter photos before and after
the connection and its IR screen, labelled `INV{i}ST{seq}` in the order of the used strings, then the irradiance
photo. The app already keeps every one of these photos; the export only lays them out.

---

## 1. What the original contains (from the README)

Every page has the same header: project name, station / branch line, the table's title and the PWA + PEA logos.

| # | Part | Layout | Per page |
|---|---|---|---|
| 1 | Cover **(ก่อนการเชื่อมต่อระบบ)** in red | — | — |
| 2 | Voltage testing and Current testing `INV{i}ST{n}` (before) | 1-column table, each cell 2 photos: voltage meter at the box + clamp on the cable | 3 strings |
| 3 | Cover **(หลังการเชื่อมต่อระบบ)** | — | — |
| 4 | Voltage testing and Current testing `INV{i}ST{n}` (after) | as 2 | 3 strings |
| 5 | Insulation Resistance testing `INV{i} ST{n}` | 2-column table, 1 photo per cell (IR tester screen) | 6 strings |
| 6 | Irradiance (W/m²) | 1 photo (weather station screen) | 1 |

Photos per station = strings × (2 before + 2 after + 1 IR) + 1 → แพรกหนามแดง, 24 strings = 121.

## 2. Data (already in the app)

| Word part | Source |
|---|---|
| Header station line | `IECReport.stationLine` (the Excel's C3) |
| Labels | `IECReport.Inverter.strings` → `(slot, seq, value)`; `IECReport.label(inverter:seq:)` = `INV1ST3` |
| Photos 2 / 4 | `Slot.photo(.voltageBefore / .currentBefore / .voltageAfter / .currentAfter)` |
| Photos 5 | `Slot.photo(.insulation)` |
| Photo 6 | `IECReport.irradiancePhoto` |
| (thermal, open question 4) | `IECReport.thermalPhotos` |

Photo ids resolve to `PhotoAsset`s on `Job.iecPhotos`; the app reads their JPEG bytes and passes
`[String: Data]` (id → JPEG) to the writer, so the package stays free of SwiftData.

## 3. Writing approach (open question 1 decides)

**A. Fill the original in place** (as the Excel export does). Ship the customer's `.docx` emptied of its photos as
`Resources/iec62446_word_template.docx`; the writer keeps the header, covers and styles byte for byte and repeats
the table rows of parts 2, 4 and 5 for each string, swapping each picture's `r:embed` to a new `media/` part. Needs
the original file.

**B. Build the document** from this spec: a minimal WordprocessingML package (`document.xml`, `styles.xml`,
`header1.xml`, `settings.xml`, rels, content types, `media/`), A4 portrait, margins 2 cm, Sarabun 14 pt (or the
font of open question 6). The logos are the Excel template's own `xl/media` images, so both files carry the same
ones. Close to the original's look but not identical.

Either way:
- One table row per string, `cantSplit` so a row never breaks across pages; page breaks every 3 (parts 2 / 4) or
  6 (part 5) strings, as in the original.
- Pictures inline (`wp:inline`), scaled to the cell keeping their aspect ratio.
- A missing photo leaves its frame with the label and `ไม่มีรูป` (open question 2), so the gap is visible.
- Photos are re-encoded once: long edge 1600 px, JPEG quality 0.75 (≈ 200 KB, ≈ 25 MB for 121 photos; open
  question 5). The app does this off the main thread before calling the writer.

## 4. Delivery

- `ส่งออก Word ภาพถ่าย` on the IEC overview, beside `ส่งออก Excel IEC 62446` (screen 1 of
  `docs/ui/iec62446-test` already shows both buttons).
- Name `IEC62446 ภาพถ่าย {station} {yyyy-MM-dd}.docx`; a sample gets `ตัวอย่าง ` before the station, as the Excel.
- Saved to the job's documents in folder `IEC 62446` (so it goes to Drive), then opened in the share sheet.
- The same station-line check as the Excel: a line naming another station asks first.

## 5. Tests (`Tests/ExcelExportTests/IECWordTests.swift`)

1. **Package:** every relationship target exists, every part has a content type, every `r:embed` points at a
   `media/` part, XML well-formed.
2. **Order and labels:** the sample's 24 strings give labels `INV1ST1 … INV1ST16, INV2ST1 … INV2ST8` in each part,
   with 3 / 3 / 6 strings per page.
3. **Count:** pictures = strings × 5 + 1 when every photo is there; a missing photo gives its `ไม่มีรูป` frame.
4. **Manual:** open in Word for Mac and Windows and in Pages: no repair prompt, header on every page, print preview.

## 6. Not in this spec

Editing the Word in the app, a PDF of the appendix (the share sheet's print can make one), thermal-image analysis.

## 7. Open questions

1. **Original file.** Can the customer's `2_Form_IV TEST_Before-After_PWA.docx` be added to the repo (photos
   removed is enough)? With it, approach A matches the PWA's file exactly; without it, approach B.
2. **Missing photo.** Keep the empty frame with `ไม่มีรูป`, or leave the string out of that part?
3. **Captions.** Label only (`INV1ST3`, as the original), or label + reading (`INV1ST3 · Voc 752 V · 0 A`)?
4. **Thermal photos.** The Excel's row 27 says `เอกสารแนบ`. Add a part 7 with `thermalPhotos`, or are they a
   separate file?
5. **Photo size.** 1600 px / 0.75 (≈ 25 MB per station), or smaller for e-mail (1200 px / 0.7 ≈ 12 MB)?
6. **Font.** The original's body font (Sarabun / TH SarabunPSK / Angsana New)? Only matters for approach B.
