# Claude Code task: A2 → A3 auto-fill (site photo symbols fill the transformer / MDB page)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/a2-a3-autofill/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; English in brackets is only a gloss. Values in the previews (TX 1, 630 kVA, MDP-1, 800 AT, 500 kVA) are **example data**.

## Goal
On A2 (`ภาพสถานที่ติดตั้ง`, site photo) the surveyor places symbols on the aerial photo and types values into them:
- transformer name + kVA
- MDB name + AT
- PEA meter
- Zero Export MV / LV

A3 (`หม้อแปลง · MDB`) asks for the same facts again. Today data only flows **A3 → A2**: `SiteMarks.suggestedValue` pre-fills a new mark, and A3's `matchChip` only counts marks.

Make it **two-way**, with A2 able to fill A3:
1. Saving a mark on A2 fills the matching **empty** fields on A3 (and the B4 zero-export level).
2. Editing a linked field on A3 updates the label on the A2 photo.
3. A field that already has a different value is **never overwritten silently**. A3 shows it as a conflict and the surveyor picks `ใช้ค่า A2` (use A2's value) or `คงค่านี้` (keep this one).

## Before reading the source
Use code-review-graph first (per `CLAUDE.md`; run `code-review-graph build` if it is empty), then read the source:
- `SiteMarks`, `MapMark`, `MarkKind` (`TCRoofCore/SiteMarks.swift`)
- `ModuleMarks` (`TCRoofCore/ModuleMarks.swift`), `ZeroExport` (`TCRoofCore/ZeroExport.swift`)
- `Transformer`, `Board`, `setBoards`, `resolvedBoards` (`TCRoofCore/Models.swift`)
- `SitePageWide`, `SitePageWide+Stage` (`setMarks`, the mark editor, the `ดึงจาก A3` button, `suggestedValue`)
- `ElectricalPageWide`, `ElectricalPageWide+Cards` (`matchChip`, `meterCard`, `kvaField`, `mainBoardCard`, `mainName(i)`)
- `tests_for` on `SiteMarks`, `Transformer`, `ZeroExport`
- `BuildingPanels.link` / `ModuleMarks.place`: existing `static func …(_ job: inout Job, …)` cross-page writers to copy the style from

Facts from `origin/main` (c29547b) to check:
- Marks live in `job.values["siteMarks"]` as `FieldValue.marks([MapMark])`.
- `MapMark` has `kind`, `x`, `y`, `value` (kVA or AT), `label` ("TX 1", "MDP-1") and `module: UUID?` (only B3/B4/B5).
- A3 keeps `job.values["trafos"]` as `[Transformer]`.
  - The main board's **name** is the text key `tr{i}_feed`, not `Board.name`. Sub-boards use `Board.name`.
  - AT is written through `Transformer.setBoards`, so `mdb[]` stays mirrored for Excel, PDF and A2.
- PEA meter: `meterNo`, `meterKV`, `meterPhase`, … (A2 has no meter values, only its position).
- Zero export lives in the B4 backfeed module: `ZeroExport.levelKey = "level"` with `hv` = `กันย้อนที่แรงสูง` and `lv` = `กันย้อนที่แรงต่ำ`. The A2 `.zeroExport` mark links to that module through `MapMark.module`.

## Files in this folder
| File | Shows |
|---|---|
| `states/01-a2-tx-popover.png` / `.pdf` | A2: transformer popover. The old `ดึงจาก A3` (pull from A3) text is now a link chip `↔ A3 TX 1`. |
| `states/02-a2-zero-export-popover.png` / `.pdf` | A2: tapping the Zero Export symbol opens the `ZERO EXPORT MV` / `ZERO EXPORT LV` choice, chip `↔ B4` and the note `ส่งไป B4 กันย้อน: MV = กันย้อนที่แรงสูง · LV = กันย้อนที่แรงต่ำ` |
| `states/03-a3-badges.png` / `.pdf` | A3: fields filled from A2 carry a small blue `A2` badge (TX 1 size, MDP-1 name, main AT, PEA meter card) |
| `states/04-a3-autofill-panel.png` / `.pdf` = `preview.png` | A3: header button `ดึงจากภาพ A2 · 4 รายการ` opens the panel `ใส่ให้อัตโนมัติจากภาพ A2` (auto-filled from A2), every row `✓ ใส่แล้ว` (filled) |
| `states/05-a3-autofill-conflict.png` / `.pdf` | A3: conflict. The button reads `ดึงจากภาพ A2 · ต่างกัน 1`; the TX 1 row is orange with `ต่างกัน`, `หน้านี้ 500 · A2 630 kVA` and the buttons `ใช้ค่า A2` / `คงค่านี้` |
| `iPadA2.dc.html`, `iPadA3.dc.html`, `grf.css` | Board sources (inline CSS = exact values). Open A3's panel with state `{"a2o":true}`, conflict with `{"a2o":true,"a2d":true}`; A2's zero-export popover with `{"zeO":true}` |

The PDFs are vector; measure there.

## Mapping (A2 mark → target)
| A2 mark (`MarkKind`) | A2 data | Target | Rule |
|---|---|---|---|
| `.meter` | position only | A3 `meterCard` | No values to copy. Count it as linked and show the `A2` badge on the card title. Never touch `meterNo` etc. |
| `.trafo` | `value` = kVA, `label` = "TX n" | `trafos[i].kva` | Fill when empty. If there is no transformer `i`, append `Transformer(kva:)`, up to `Transformer.maxTransformers` / 5; past that, show the row as `เกิน 5 ลูก` (more than 5 units) and do not create one. The label is not stored on A3 (A3 names cards by index); keep it on the mark. |
| `.mdb` | `value` = AT, `label` = "MDP-1" | main board of the matching transformer: name → `tr{i}_feed`, AT → `boards[0].at` via `setBoards` | Fill each field only when empty. If the transformer has no boards, create the main board with `Board(name: "", isMain: true, at:)`. |
| `.zeroExport` | `value` = `MV` / `LV` (new, see below) | B4 module (`mark.module`): `level` = `ZeroExport.hv` / `.lv` | Fill when empty. If the mark has no module, show the row as `ยังไม่มีหน้า B4` (no B4 page yet) with no write. |
| `.inv`, `.weather`, `.office`, `.roofLabel`, `.meterSub`, … | | (none) | Listed in the panel footnote `ไม่ส่งมาหน้านี้: INV · Weather · Site Office · อาคาร` (not sent to this page) |

### Matching marks to A3 entries
Today matching is by **position**: the n-th trafo mark goes with `trafos[n]`, and the n-th mdb mark with the n-th non-empty `mdb` value.

Keep position as the fallback for old jobs, but make it stable:
- Add an optional `MapMark.link: String?` with backward-compatible decoding: `"tr:<Transformer.id>"`, or `"bd:<Board.id>"` for an MDB.
- The first sync stores the link. After that, deleting or reordering transformers on A3 must not move a mark's data to another transformer.
- Remember `Values.shiftTransformerAnswers(removed:)` renumbers the `tr{i}_*` keys. Resolve `link` → index at sync time, not when it is stored.

### Zero Export MV / LV on the mark
- Store the chosen text in `MapMark.value` for `.zeroExport` (`"MV"` / `"LV"`; empty = take it from the B4 level).
- Draw the third line of the symbol from it (`ZERO / EXPORT / MV`).
- Map `MV` ↔ `ZeroExport.hv` and `LV` ↔ `ZeroExport.lv`.

## Engine (TCRoofCore, pure and tested)
Add `TCRoofCore/SiteSync.swift`, in the same style as `BuildingPanels` / `ModuleMarks`:

```swift
public enum SiteSync {
    public enum Status: Equatable { case filled, same, conflict(a3: String, a2: String), skipped(String) }
    public struct Item: Identifiable, Equatable { public var id: UUID   // mark id
        public var kind: MarkKind; public var title: String  // "หม้อแปลง TX 1 · 630 kVA"
        public var target: String                            // "หม้อแปลง TX 1 · ชื่อ + ขนาด"
        public var status: Status }
    /// A2 → A3/B4: fill empty targets, store links, report conflicts. Never overwrites a non-empty differing value.
    @discardableResult public static func push(_ job: inout Job) -> [Item]
    /// A3/B4 → A2: after an edit on A3, copy linked values back onto the marks' value/label.
    public static func pull(_ job: inout Job)
    /// Conflict resolution from the A3 panel.
    public static func useA2(_ job: inout Job, mark: UUID)
    public static func keepA3(_ job: inout Job, mark: UUID)   // = copy the A3 value onto the mark
    /// Read-only list for the panel (same rows as push, no writes).
    public static func items(_ job: Job) -> [Item]
}
```

- Compare values after trimming, case-insensitively, ignoring units (`"630"` == `"630 kVA"`).
- `push` is idempotent: running it twice changes nothing the second time.
- Keep `SiteMarks.suggestedValue` (the A3 spec still requires A3 → A2 pre-fill when placing a new mark).

### When it runs
- A2 `SitePageWide.setMarks(_:)`, after writing `siteMarks`: `SiteSync.push(&job)`.
- A3, after `setTrafos`, `bText(… \.at …)` or the `tr{i}_feed` text changes: `SiteSync.pull(&job)`. Only linked marks change.
- B4: after the level changes, `pull`.
- Deleting a mark on A2 only clears the link. It never deletes A3 data.

## UI

### A2 (`SitePageWide+Stage`)
- Mark editor header for trafo / mdb: replace the plain `ดึงจาก A3` text with a small link chip `↔ A3 TX n` / `↔ A3 MDP-1` (states/01): blue text `#1F6FB5` on `#E3EEF8`, pill, 11.5 pt bold.
- Keep the existing pull-from-A3 action reachable: tap the chip to re-pull from A3, or keep it in the menu.
- Zero Export mark (states/02):
  - tapping it opens the editor with two 52 pt choice rows, `ZERO EXPORT MV` (sub `กันย้อนฝั่งแรงดันกลาง (22/33 kV)`, MV side) and `ZERO EXPORT LV` (sub `กันย้อนฝั่งแรงดันต่ำ (400/230 V)`, LV side)
  - a chip `↔ B4`, the note line, and `ลบ` (delete) / `เสร็จ` (done)
  - the selected symbol gets an orange halo
- Popovers place themselves on the side of the symbol with room (left → right → below → above), clamped inside the photo and below the toolbar, with a 14 pt arrow pointing at the symbol. Use `.popover` with `arrowEdge` or an overlay; match the board.

### A3 (`ElectricalPageWide`)
- Replace `matchChip` with the header button (states/03–05). Its title:
  - `ดึงจากภาพ A2 · N รายการ` (pulled from A2 · N items): N = rows with status filled/same
  - `ดึงจากภาพ A2 · ต่างกัน n` (differ n) in orange when there are conflicts
- Tapping it opens a popover, 440 pt wide, title `ใส่ให้อัตโนมัติจากภาพ A2`. One row per linked mark:
  - symbol pill (64 pt min), title, `→ target`, and a status on the right:
    - `✓ ใส่แล้ว` (filled), green `#2E9E5B`
    - `ต่างกัน` (differs), an orange pill
  - conflict rows: orange tint `#FFF8EF` with an orange border, a line `หน้านี้ <a3> · A2 <a2>` and two 36 pt+ buttons, `ใช้ค่า A2` (filled blue) and `คงค่านี้` (outline). Make the hit areas ≥ 44 pt.
  - `ยังไม่มีหน้า B4` / `เกิน 5 ลูก` rows use the grey skipped style
- Footnote text exactly as in the board, listing what is not sent.
- Badge `A2` (10.5 pt bold, `#1F6FB5` on `#E3EEF8`, 1 pt border) next to every field whose value came from, or matches, a linked mark: TX size, main board name, main AT, PEA meter card title.
- The existing count check ("ตรงกับภาพ A2 ✓" / "ไม่ตรงกับภาพ A2") folds into this button. Drop the separate chip.
- iPhone: the same panel as a sheet (`.presentationDetents([.medium, .large])`).

## Rules
- Thai text exactly as in the previews.
- Colours from `Theme` / `Home`; no new hex literals in views (add tokens if missing: `pendingSoft #FFF4E5` exists in the component task; use it for the conflict tint).
- Touch targets ≥ 44 pt.
- Never overwrite non-empty data without the user choosing.
- Don't change Excel / PDF layouts. They already read `trafos`, `tr{i}_feed` and `siteMarks`.
- Backward-compatible decoding for `MapMark.link` and the zero-export `value`.

## Tests (`TCRoofCoreTests/SiteSyncTests.swift`)
- trafo mark with kVA → empty A3 gets a transformer with that kVA; the link is stored; a second `push` changes nothing
- mdb mark → `tr0_feed` name and `boards[0].at`, and `mdb[0]` mirrors through `setBoards`
- non-empty differing kVA → status `.conflict(a3: "500", a2: "630")`, A3 unchanged; `useA2` writes 630; `keepA3` writes 500 onto the mark
- deleting transformer 0 on A3, then `push` → the TX 2 mark still points at the right transformer (link, not position)
- zero-export `MV` → B4 `level == ZeroExport.hv`; `LV` → `.lv`; a mark without a module → `.skipped`
- decoding an old `MapMark` JSON without `link` still works
- A3 edit → `pull` updates the linked mark's `value`

## Done when
- `xcodebuild` builds the app and TCRoofKit, and all tests pass, including the new `SiteSyncTests`.
- On an iPad Pro 13" simulator:
  - place TX + MDB + Zero Export on A2, then open A3: the fields are filled with `A2` badges and the panel matches states/04
  - change the kVA on A3 and go back to A2: the photo label shows the new kVA
  - an old job with different values shows the conflict as in states/05, and both buttons work
- Work on a new branch `feat/a2-a3-autofill`.
- Finish with a summary of files changed, model changes (`MapMark.link`, zero-export `value`), and any remaining differences from the boards.
