# Before submitting: photo check, REV comparison, lock after signing (iPad, Swift dev spec)

**Status:** Built 2026-10-10 (PR #6): photo check (§2, without the leaving-site reminder of §2.4), REV comparison
(§3) and lock after signing (§4), with the core tests and iPad UI tests of §6. Changes from this spec:
- The slot types are `ReviewSlot` / `ReviewSlotGroup` (`TCRoofCore/Review/ReviewSlots.swift`), because SurveyUI already
  has a `PhotoSlot` view.
- Issued REVs reach other iPads as one immutable Firestore document each (`pwaSurveyRevisions`, rule deployed
  2026-10-10) instead of only through Drive. A device without the signed PDF rebuilds it from the REV's snapshot.
- Per-field "แก้จาก REV" captions (§3.3) are replaced by "แก้ n" markers on the sidebar rows, because the designed
  pages have no per-field anchors; "ไปที่ช่องในฟอร์ม" opens the page without scrolling to the field.
- `FormHash.of` returns nil while a photo isn't on the device: locking waits for it, and the integrity check skips.

**Lock removed 2026-10-16** (branch `feat/survey-to-install-no-lock`): feature 7 (§4) is gone. Signing both no
longer locks the form or issues a REV, nothing is read-only, and the PDF has no check-code footer. `Job.lock`,
`pendingReason` and the lock / integrity banners and sheets were deleted; an old `job.json` with `lock` still
decodes and drops it. REVs, their snapshots, PDFs, the รายการแก้ไข page, the change markers and their sync stay.
**Issuing without the lock (same day):** once both have signed and the answers aren't the last issued REV, E1 shows
`ออก REV nn`. The first issue keeps the cover's number and needs no reason; after that the issue takes the next number
(`RevisionRule.next`) and needs a reason, written to the cover's REV field at issue time. The snapshot, its
`FormHash` check code and the PDF are kept as before; the form stays editable. §4.1–§4.4 are kept below as history.

**Drive `REV` folder (2026-10-16):** each issued REV's `REVnn.pdf` and `REVnn.json` go to a `REV` folder in the job's
Drive folder, named `REVnn แบบสำรวจ NO.<doc> <project>.pdf/.json`, once each (`DriveLink.revisionFiles`), with any Drive
save and with the background upload, which `ออก REV` starts. Not `DriveSync.Kind.revisions`: the files ride along like
the photos rather than being a kind to tick.

Not built: the Excel รายการแก้ไข sheet, REVs in `WebBackup`,
and the leaving-site reminder (§2.4, open question 5).
**Platform:** TCRoof on **iPad** (SwiftUI, iPadOS 17+). The same code runs on iPhone in compact layout.
**Modules:** `TCRoofCore` (model, diff, hash; testable with `swift test`), `SurveyUI` (pages), `PDFReport` (page and
footer), `DriveSync` (upload).
**No new dependencies.** Hashing uses CryptoKit, which the app already imports in `GoogleAuth.swift`. `TCRoofCore`
wraps it in `#if canImport(CryptoKit)`, with a small pure-Swift SHA-256 for Linux test runs.

Three features work together:

| # | Feature | In one line |
|---|---|---|
| 5 | **ตรวจรูปทั้งหมด** (photo check) | every photo slot of the job on one page, grouped A–E; missing required photos are red frames; tap to take the photo there |
| 6 | **เทียบ REV** (REV comparison) | each issued REV is kept as an immutable snapshot; the app lists what changed from which value to which; the PDF gets a "รายการแก้ไข" page |
| 7 | **ล็อกหลังลงนาม** (lock after signing) | when both the engineer and the coordinator have signed, the form locks; editing opens the next REV, so every signature matches the data it was given for |

---

## 1. Current code this builds on

| Existing | Where | Used for |
|---|---|---|
| `Job { values, modules, updated, drive, … }`, synthesized `Codable` | `TCRoofCore/Models.swift` | new fields are **optional** so old `job.json` files decode unchanged |
| `FieldKind.photo`, `.photos(max:)`, `.signature` (a signature is stored as `.photo`, PNG) | `Schema.swift`, `PhotoFields.swift` (`SignatureField`, `SignaturePad`) | slots (§2); the lock trigger (§4) |
| `FieldSpec.isRequired(_:)`, `isFilled(_:)`, `displayText(_:)` | `Schema.swift`, `Progress.swift` | red frames (§2), diff text (§3) |
| `Job.photoFolders`, `transformerAngles`, `transformerGaps` | `PhotoFolders.swift`, `Schema.swift`, `Progress.swift` | the same section order and names as the Drive photo folders |
| `Job.sectionsByCategory` (A/B/C/D/E numbering "C1.2") | `Progress.swift` | page grouping |
| `rev` field "REV." (default "00"), printed in the cover box | `Schema.info`, `ReportLayout.cover()` | REV number (§3) |
| `JobStore.save`, `addPhoto`, `purgeUnusedPhotos`, `duplicate` | `JobStore.swift` | snapshots on disk; purge must keep snapshot photos (§3.4) |
| `SurveyModel.update(_:)` (debounced save) | `SurveyModel.swift` | the lock is enforced here too (§4.3) |
| `JobEditor.Page`, sidebar rows, `checked { }` before export | `JobEditor.swift` | two new pages, extended export check (§2.4) |

---

## 2. Feature 5: ตรวจรูปทั้งหมด (photo check)

### 2.1 Slots (`TCRoofCore/Review/PhotoSlots.swift`)

```swift
public enum SlotScope: Hashable, Sendable { case cover, module(UUID) }
public struct PhotoSlot: Identifiable, Hashable, Sendable {
    public var id: String { "\(scope)|\(fieldID)|\(index.map(String.init) ?? "-")" }
    public let scope: SlotScope
    public let fieldID: String          // "tr0_plate", "structPhotos", "surveyorSign" …
    public let label: String            // field label; "TR1 ภาพป้ายพิกัด (Nameplate)", "ภาพโครงสร้าง 2"
    public let kind: Kind               // .photo, .photosItem, .photosAdd, .signature
    public let index: Int?              // position inside a .photos field
    public let photo: Photo?
    public let required: Bool           // FieldSpec.isRequired(values) and, for .photos, "at least one"
    public enum Kind: Sendable { case photo, photosItem, photosAdd, signature }
}
public struct PhotoSlotGroup: Identifiable, Sendable {
    public let id: String               // "A1", "A3", "B1.2", "C1", "E1"
    public let title: String            // "A3 มิเตอร์ หม้อแปลง และตู้ MDB"
    public let slots: [PhotoSlot]
    public var missingRequired: Int { slots.filter { $0.required && $0.photo == nil && $0.kind != .photosAdd }.count }
}
public extension Job {
    var photoSlots: [PhotoSlotGroup] { … }   // A1, A2, A3, A4, sectionsByCategory…, E1, in the same order as photoFolders
    var missingRequiredPhotos: Int { photoSlots.reduce(0) { $0 + $1.missingRequired } }
}
```

**Rules:**
- **Visible fields only:** only fields where `isVisible(values)` is true. For example, TR2's photos appear only
  when `transformerPresent(values, 1)`, and the flood photo only when the site has flooded.
- **`.photo` fields:** one slot each. Red when `isRequired` and empty.
- **`.photos(max:)` fields:** one slot per existing photo, plus a **"เพิ่ม"** slot while `count < max`. When the field
  is required and empty, the first "เพิ่ม" slot is the red one.
- **`.signature` fields:** shown in group E1 as slots (red when missing). A signature can only be made in its own
  field, never from the camera (§2.3).
- **`siteMap`:** shows its symbols overlaid, the same picture as `markedSiteMap`.
- **Leftover photos:** photos that no field claims (the "อื่นๆ" folder) are listed last, read-only.

### 2.2 Page layout (iPad)

- **Where:** a new `JobEditor.Page.photos` in the sidebar under E: **"ตรวจรูปทั้งหมด"**, showing the count
  "ขาด n" in red, or ✓.
- **Top bar:**
  - progress "รูปบังคับ 46/52"
  - filter segments: **ทั้งหมด · ขาด · มีแล้ว**
  - size slider: 3–6 columns
- **Body:**
  - `ScrollView` + `LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)])`
  - one pinned section header per group: "A3 มิเตอร์ หม้อแปลง และตู้ MDB · 10/12"
  - headers stay pinned (`pinnedViews: .sectionHeaders`)
- **Cells:**

  | State | Look |
  |---|---|
  | has photo | thumbnail (aspect-fill, 4:3), label under it (2 lines) |
  | missing, required | **red dashed frame**, camera symbol, label, "แตะเพื่อถ่าย" |
  | missing, optional | grey dashed frame, same content; hidden by the **ขาด** filter only when the filter's option "เฉพาะที่บังคับ" is on |
  | signature missing | red frame, pen symbol, "ไปลงนาม" |

- **Thumbnails:** loaded with `model.image(_:in:)` downscaled to 300 px and cached per photo id (`NSCache`). This
  keeps a grid of 100+ photos smooth.
- **Split View / Stage Manager:** the adaptive grid reflows. It must work from 320 pt width upward.

### 2.3 Actions

| Tap | Result |
|---|---|
| missing photo cell | opens `CameraPicker` **directly** (the library picker only when no camera). The result is written into **that field** of **that scope**: `.photo` → set; `.photos` → append |
| filled cell | full-screen viewer (`PhotoViewer`) with **ถ่ายใหม่** (replaces in place), **เลือกจากคลังภาพ**, **ลบ**, **ไปที่ช่องในฟอร์ม** |
| **ไปที่ช่องในฟอร์ม** | `page = .info/.site/.electrical/.flood/.module(id)/.final`, then scrolls to the field (`ScrollViewReader`, `.id(field.id)`) and flashes it |
| signature cell | goes to E1 and scrolls to the signature field |
| long-press | context menu with the same actions |

**Writing a photo:** one helper in `SurveyUI`:

```swift
func setPhoto(_ p: Photo, slot: PhotoSlot, in job: inout Job)   // cover → job.values; module → job.modules[i].values; .photos → append / replace at index
```

After writing, `model.update(job)` saves as today.

**When locked (§4):** the page is read-only. Tapping a missing cell shows "ฟอร์มล็อกแล้ว · เปิด REV ใหม่เพื่อเพิ่มรูป".

### 2.4 "ดูครบก่อนออกจากสถานี"

- **Exports:** `checked { }` in `JobEditor` today warns about `transformerGaps`. It now also counts
  `missingRequiredPhotos`. The sheet lists the missing slots by group, with a button **ไปตรวจรูป** (opens the page
  filtered to **ขาด**) next to **ส่งออกต่อ**.
- **Signing:** the E1 signature fields show the same warning before the first signature: "ยังขาดรูปบังคับ n รูป".
  Signing is still allowed.
- **Optional, off by default (Settings › เตือนก่อนออกจากสถานี):**
  - The app monitors a `CLCircularRegion` of 300 m around the job's `gps` while the job has missing required photos.
  - On exit it posts a local notification: "ยังขาดรูป n รูป ที่ <projectName>".
  - It needs location permission "Always", which is asked for only when the user turns the setting on. Wi-Fi-only
    iPads use approximate location, and the setting says so.

---

## 3. Feature 6: เทียบ REV (REV comparison)

### 3.1 Model (`TCRoofCore/Review/Revision.swift`)

```swift
/// The answers exactly as issued: what the PDF was made from and what was signed.
public struct FormSnapshot: Codable, Hashable, Sendable {
    public var values: Values
    public var modules: [SurveyModule]
}
public struct Revision: Codable, Hashable, Identifiable, Sendable {
    public var id: String { rev }
    public var rev: String                 // "00", "01", …
    public var issuedAt: Date
    public var issuedBy: String            // engineer name at the time
    public var reason: String              // "" for REV 00; required from REV 01
    public var hash: String                // FormHash of the snapshot (§4.2), hex
    public var pdfFile: String?            // "revisions/REV00.pdf" (the PDF as signed)
}
// new stored properties on `struct Job` (Models.swift), optional so old job.json decodes unchanged
public var revisions: [Revision]?
public var lock: FormLock?                 // §4
public var pendingReason: String?          // reason typed when REV nn+1 was opened (§4.4)
```

**On disk** (next to `job.json`):

```
Jobs/<uuid>/job.json
Jobs/<uuid>/photos/…                      (all photos, current and old)
Jobs/<uuid>/revisions/REV00.json          FormSnapshot, written once, never rewritten
Jobs/<uuid>/revisions/REV00.pdf           the report exported at lock time
```

`JobStore` gets:
- `saveRevision(_ snapshot: FormSnapshot, rev: String, job: UUID)`: throws if the file exists
- `loadRevision(rev:job:) -> FormSnapshot?`
- `revisionPDF(rev:job:) -> URL`

### 3.2 Diff (`TCRoofCore/Review/FormDiff.swift`, pure Swift)

```swift
public struct FieldChange: Hashable, Identifiable, Sendable {
    public enum Kind: Sendable { case changed, added, removed }
    public let id: String                   // scope|field|sub
    public let group: String                // "A3 มิเตอร์ หม้อแปลง และตู้ MDB", "B1.2 ตู้ไฟฟ้า · โรงกรอง"
    public let field: String                // field label (+ " · TR2", " · สิ่งกีดขวาง 3")
    public let kind: Kind
    public let old: String, new: String     // FieldSpec.displayText, or "แนบภาพแล้ว"/"—"
    public let oldPhoto: Photo?, newPhoto: Photo?
}
public enum FormDiff {
    public static func changes(from a: FormSnapshot, to b: FormSnapshot) -> [FieldChange]
}
```

**Walk order:** the cover groups (`Schema.info/site/electrical/flood`), then modules, then `Schema.final`. This is
the same order as the report.

**Rules:**

| Item | Change rule |
|---|---|
| Modules | matched by `SurveyModule.id`. Only in b → one "เพิ่มหัวข้อ <title>" row. Only in a → one "ลบหัวข้อ" row. Renamed → a row for the name |
| Text / number / choice / multi | compare `displayText`; a trimmed-whitespace-only difference is not a change |
| `.photo` | compared by `Photo.id`. Different ids → "เปลี่ยนภาพ", with both thumbnails. Added/removed likewise |
| `.photos` | set difference by id → "เพิ่มภาพ n", "ลบภาพ n", with thumbnails |
| `.signature` | **not listed.** Signatures always change between REVs (§4.4) |
| `.obstacles` | matched by `Obstacle.id`; per-row changes of label, x, y, w, h |
| `.transformers` | matched by `Transformer.id`; kVA and each MDB slot |
| `.marks` | matched by `MapMark.id`: added / removed / rating changed / moved more than 2 % of the picture |
| Invisible fields | a field visible in neither REV is ignored. A field that became hidden → "ไม่ใช้แล้ว" |
| System fields | `rev` and `date` are left out of the list. They head the page instead |

### 3.3 Screens

- **Where:** a new `JobEditor.Page.revisions`, sidebar row **"REV และรายการแก้ไข"** under E, shown once
  `revisions` is not empty.
- **Page contents:**
  - **History list:** REV, date, by, reason, 🔒 hash short code (first 8 hex, grouped "A1B2-C3D4"), and **เปิด PDF**
    (the stored `REVnn.pdf`).
  - **Compare picker:** two menus, **จาก REV** and **ถึง** (another REV, or "ฉบับปัจจุบัน (ยังไม่ออก)").
  - **Change list:** grouped by section (same headers as the report). Each row shows field, old → new (old struck
    through in red, new in green). Photo rows show both thumbnails; tapping opens them side by side.
  - Filter: **ทั้งหมด · ข้อความ · รูป**.
- **In the form while editing a new REV:**
  - Fields changed since the last issued REV show a small orange dot and a "แก้จาก REV 00: <old>" caption under the
    field.
  - The caption is computed with `FormDiff.changes(from: lastSnapshot, to: current)` for the visible page only.

### 3.4 Keeping old photos

- **Purging:** `purgeUnusedPhotos(of:)` must keep every photo referenced by **any** snapshot in `revisions/`. Otherwise
  replacing a photo in REV 01 would delete the REV 00 photo and break its diff and its PDF. It becomes:

  ```swift
  let used = Set(job.allPhotos.map(\.fileName)) ∪ Set(snapshots(of: job).flatMap(\.allPhotos).map(\.fileName))
  ```

- **Duplicating:** `JobStore.duplicate` copies only the current answers. The copy gets no revisions and no lock,
  keeps `rev` at "00", and has its signatures cleared.

### 3.5 Report: "รายการแก้ไข" page (`PDFReport`)

- **When:** only when the current REV is higher than "00". The page goes after the cover.
- **Contents:**
  - **Revision table:** REV · วันที่ · ผู้แก้ไข · เหตุผล · รหัสตรวจสอบ, one row per issued REV plus the current one.
  - **Changes from the previous REV:** section · รายการ · เดิม → ใหม่. Photo changes print as two 60 pt thumbnails.
  - Long lists continue on the next page with the table header repeated. The existing `Unit` pagination handles
    this.
- **Every page footer** gets "REV nn · รหัสตรวจสอบ XXXX-XXXX" once the job is locked (§4.2).
- **Excel (NO.224):** an optional sheet "รายการแก้ไข" with the same rows.

---

## 4. Feature 7: ล็อกหลังลงนาม (lock after signing)

> **Removed 2026-10-16.** Kept as history; see the status at the top.

### 4.1 States

```
แก้ไขได้ (REV nn, draft) ──(both signatures present, confirm)──▶ ล็อก (REV nn issued)
      ▲                                                              │
      └────────────(เปิดแก้ไขเป็น REV nn+1, reason required)────────┘
```

```swift
public struct FormLock: Codable, Hashable, Sendable {
    public var rev: String
    public var lockedAt: Date
    public var hash: String         // FormHash of the snapshot at lock time
}
public extension Job {
    var isLocked: Bool { lock != nil }
    var bothSigned: Bool { values.photo("surveyorSign") != nil && values.photo("customerSign") != nil }
}
```

- **Lock trigger:** saving the **second** of `surveyorSign` / `customerSign`, in either order, opens the sheet
  **ลงนามครบแล้ว · ล็อกฟอร์ม REV nn**.
- **What the sheet shows:**
  - the job's `missingItems` count and `missingRequiredPhotos`, as warnings that don't block
  - for REV 01 and later, the number of changes since the previous REV
  - **ล็อกและออก REV nn** / **ยังไม่ล็อก**
- **ยังไม่ล็อก:** keeps the form editable. A banner then stays at the top of E1: "ลงนามครบแต่ยังไม่ล็อก".
  **Editing any other field** while both signatures exist asks "การแก้ไขนี้จะล้างลายเซ็นทั้งสอง" and clears them
  on confirm. A signature therefore can never sit on data it was not given for, even without locking.

### 4.2 Issuing and the hash

On **ล็อกและออก REV nn**, `SurveyModel.issue(job:)` runs these steps:
1. `snapshot = FormSnapshot(values, modules)`.
2. `hash = FormHash.of(snapshot, photos: store)`: SHA-256 over:
   - the snapshot encoded with `JobStore.encoder` (`sortedKeys`)
   - followed by the SHA-256 of every referenced photo file, in `Photo.id` order, **including the two signature
     PNGs**

   The short code is the first 8 hex digits, "A1B2-C3D4".
3. `store.saveRevision(snapshot, rev: nn, job:)`.
4. Export the report PDF (the existing `exportPDF` path) and copy it to `revisions/REVnn.pdf`. The PDF footer already
   carries the code.
5. `job.revisions.append(Revision(rev: nn, issuedAt: now, issuedBy: engineer, reason: pendingReason, hash:,
   pdfFile:))` and `job.lock = FormLock(rev: nn, lockedAt: now, hash:)`, then save.
6. If the job is linked to Drive, upload `REVnn.pdf` and `REVnn.json` to the job folder's `REV/` subfolder with the
   next save (`DriveSync.Kind.revisions`).

**Integrity check on open:**
- When a locked job opens, the app recomputes the hash of the current answers.
- If it differs from `lock.hash` (for example after a manual edit of `job.json`, or a restore from `WebBackup` of
  other content), the editor shows a red banner: **"ข้อมูลไม่ตรงกับที่ลงนามใน REV nn"**. It offers **เทียบกับ REV
  nn** (opens §3.3) and **เปิด REV ใหม่**.
- The locked state is never cleared silently.

### 4.3 What locked means in the app

| Area | Locked behaviour |
|---|---|
| All field views (`FieldView`, `PhotoField`, `PhotosField`, `SignatureField`, obstacle / transformer / marks editors, plan, member pickers) | read-only: `.disabled(job.isLocked)` on the detail column. Photo menus hidden, viewer allowed |
| Sidebar | **เพิ่มหัวข้อสำรวจ**, duplicate, delete and swipe actions hidden |
| Photo check page (§2) | read-only |
| Top of every page | banner 🔒 **"REV nn ลงนามแล้ว · ล็อก"** with the hash code and **แก้ไข (เปิด REV nn+1)** |
| Export PDF / Excel, Drive save, share, presentation mode | allowed: they read only |
| Duplicate job | allowed; the copy is unlocked (§3.4) |
| `SurveyModel.update(_:)` | **defence in depth:** if the stored job is locked and the new `values`/`modules` differ, the update is rejected and logged. The lock cannot be bypassed by a stray binding |

### 4.4 Opening the next REV

**แก้ไข (เปิด REV nn+1)** opens a sheet:
- **เหตุผลที่แก้ไข:** required text, for example "สถานีแจ้งขนาดหม้อแปลงใหม่".
- **อัปเดตวันที่เป็นวันนี้:** a toggle, on by default.

On confirm:
1. `rev` = next ("00" → "01"; two digits; a non-numeric rev gets "-1" appended).
2. `surveyorSign` and `customerSign` are cleared, because the new content must be signed again. `reviewer` and
   `customerName` stay.
3. `lock = nil`. The reason is kept as `pendingReason` (in the job) for the next `Revision`.
4. The form is editable, with the change markers from §3.3 against REV nn.

**REV nn stays exactly as issued:** its `REVnn.json`, `REVnn.pdf` and photos are untouched.

### 4.5 Old jobs

| Job | Behaviour |
|---|---|
| No `lock` and no `revisions` | behaves as today |
| Both signatures present | E1 shows "ลงนามครบแต่ยังไม่ล็อก" with **ล็อกตอนนี้**. It never locks by itself |

---

## 5. Files

| File | Contents |
|---|---|
| `TCRoofCore/Review/PhotoSlots.swift` | §2.1 |
| `TCRoofCore/Review/Revision.swift` | `FormSnapshot`, `Revision`, `FormLock`, `Job` extensions, next-REV rule |
| `TCRoofCore/Review/FormDiff.swift` | §3.2 |
| `TCRoofCore/Review/FormHash.swift` | SHA-256 (CryptoKit, with a pure-Swift fallback for Linux tests), canonical encoding, short code |
| `TCRoofCore/JobStore.swift` | `saveRevision`, `loadRevision`, `revisionPDF`, purge rule (§3.4), duplicate rule |
| `SurveyUI/SurveyModel.swift` | `issue(job:)`, `openNextRevision(job:reason:updateDate:)`, lock guard in `update(_:)`, integrity check |
| `SurveyUI/Review/PhotoReviewPage.swift` | §2.2–2.3 (grid, filters, camera into slot, go-to-field) |
| `SurveyUI/Review/RevisionsPage.swift` | §3.3 |
| `SurveyUI/Review/LockViews.swift` | banner, **ลงนามครบแล้ว** sheet, **เปิด REV ใหม่** sheet, clear-signatures confirm |
| `SurveyUI/JobEditor.swift` | `Page.photos`, `Page.revisions`, sidebar rows, `.disabled(job.isLocked)`, change markers, `checked { }` extension |
| `SurveyUI/Fields.swift` | `.id(field.id)` anchors for scroll-to-field; "แก้จาก REV" caption |
| `PDFReport/ReportLayout.swift` | "รายการแก้ไข" unit, footer code |
| `ExcelExport/ExcelExporter.swift` | optional "รายการแก้ไข" sheet |
| `DriveSync` | `Kind.revisions` upload to `<job>/REV/` |
| `TCRoofCore/WebBackup.swift` | back up `lock`, `revisions` and the snapshot files |

## 6. Tests (`swift test`, no simulator)

- **PhotoSlots:**
  - the `station` template job has the expected slot count per group
  - TR2 photos appear only when TR2 is present
  - a required empty `.photos` field gives exactly one red slot
  - signatures are in E1
  - photos are placed in the right module by scope
- **FormDiff:**
  - a text edit, a choice "อื่นๆ" edit, a replaced photo, two added photos, an obstacle moved, a transformer kVA
    changed, a module added / removed / renamed: each gives the expected rows
  - signatures, `rev` and `date` are not listed
  - identical snapshots give no rows
- **FormHash:**
  - stable across encode/decode round trips and dictionary order
  - changes when any value, any photo byte or a signature changes
  - the pure-Swift SHA-256 matches CryptoKit on the NIST vectors
- **Revisions:**
  - `saveRevision` refuses to overwrite
  - `purgeUnusedPhotos` keeps REV 00 photos after a replacement in REV 01
  - `duplicate` drops lock, revisions and signatures
  - the next-REV rule: "00" → "01", "09" → "10", "A" → "A-1"
- **Lock:**
  - `update(_:)` rejects a changed value on a locked job
  - opening the next REV clears both signatures and keeps the reviewer
  - the integrity check flags a hand-edited `job.json`
- **Old data:** a `job.json` from before this change decodes, is unlocked, and has no revisions.

**UI tests (XCUITest, iPad simulator):**
1. Missing photo → tap → camera stub → the slot fills and the count drops.
2. Sign both → lock sheet → locked banner; fields are disabled.
3. Open REV 01 → edit a value → the change marker shows.
4. Sign both → REV 01 issued; the "รายการแก้ไข" page lists the change.

## 7. Done when

- [ ] A surveyor can see every missing required photo of a job on one page, and fill each with one tap, on an iPad
      in landscape and in Split View.
- [ ] No export, lock or share happens without the missing-photo count being shown first.
- [ ] After signing by both, no field can change without opening a new REV, and the new REV has no signatures.
- [ ] Every issued REV can be reopened as its own PDF and compared with any other REV.
- [ ] Old jobs open and export exactly as before.

## 8. Open questions

1. **Lock trigger:** lock automatically after both signatures (with the sheet), or only when the engineer taps
   **ล็อก**?
2. **Reviewer:** should the reviewer (`reviewer`) also sign before locking? The form has the name only, no signature
   field.
3. **REV format:** always two digits ("00", "01"), or does กปภ. use another pattern?
4. **Date on a new REV:** update to today by default (current plan), or keep the survey date and add a "วันที่แก้ไข"?
5. **Leaving-site reminder:** is location permission "Always" acceptable for the team's iPads, or keep only the
   reminders at export and signing?
