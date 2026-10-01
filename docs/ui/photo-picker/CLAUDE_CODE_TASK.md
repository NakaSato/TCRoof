# Claude Code task: one shared photo slot (Upload / Camera) for every survey page

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/photo-picker/CLAUDE_CODE_TASK.md`

## Goal
The empty-photo UI from the B1 design is shown in `preview-empty.png` and `preview-filled.png`; `preview-page-B1.png` shows it in context. B1 (`PanelsPageWide+Photos.swift`) already matches it.

Other pages build the same control in their own way:

| Page | File | What differs |
|---|---|---|
| A3 | `ElectricalPageWide+Cards.swift` | `tileButton("photo.on.rectangle", "คลังภาพ")`, label "คลังภาพ" instead of "อัปโหลด", small tiles |
| A4 | `FloodPageWide.swift` `photoButton(_:_:_:)` | SF Symbol `Label`, 96×60, no shared style |
| B2 | `InverterPageWide.swift` | `.buttonStyle(.bordered)` Labels |
| B1 | `PanelsPageWide+Photos.swift` | the reference: `emptyPhoto`, `photoButton`, `doneBadge`, `clearButton` |

Make **one** shared component that matches the design and use it everywhere. Before editing, use code-review-graph as `CLAUDE.md` says to find every photo picker / camera entry point: `showPicker`, `showCamera`, `CameraPicker`, `photosPicker`. Then read the source.

## Design spec

**Empty slot** (`preview-empty.png`)
- Container: white, radius 12.
- Border, dashed 1.5 pt, dash `[6, 4]`:
  - required and missing: `Home.danger` (#D9453B)
  - optional: `Home.borderControl`
- Centre, top to bottom with a 12–14 pt gap:
  - hint text: 15 pt, `Home.muted` (#5B6B82), e.g. `ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลขชัด`
  - a row of two buttons with a 10 pt gap
- Buttons: 150 × 46 pt, white, radius 10, 1 pt border `Home.navy` at 45% opacity.
  - Icon 18–20 pt in `Home.primary` (#1F6FB5), then the label 15–16 pt bold `Home.navy`.
  - `อัปโหลด`: icon `ui-upload-photo`, fallback SF Symbol `photo`. Opens the PhotosPicker.
  - `กล้อง`: icon `ui-camera`, fallback `camera`. Opens `CameraPicker`. Show it only when `UIImagePickerController.isSourceTypeAvailable(.camera)`.
- In tight spaces (slot shorter than 120 pt or narrower than 330 pt), use icon-only buttons of at least 44 × 44 pt with accessibility labels `อัปโหลด` / `กล้อง`. Pick the layout with `ViewThatFits`, not a hard-coded width.

**Filled slot** (`preview-filled.png`)
- The photo scaled to fit on `#E8EEF5`, radius 12, hairline border.
- Top-left: done badge `photo-done`, 28 pt green circle with a check, not hit-testable.
- Top-right: clear button `photo-clear`, 28 pt visual inside a 44 × 44 hit area, accessibility label `ลบภาพ`.
- Tap the photo to open it full screen (the existing viewer).
- If the photo exists in the job but not on this device, show `ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด` with `icloud.and.arrow.down`, as B1 does.

## Implementation
1. Add `TCRoofKit/Sources/SurveyUI/PhotoSlot.swift`, wrapped in `#if canImport(UIKit)`:
   ```swift
   struct PhotoSlot: View {
       let photo: Photo?
       let jobID: String
       var hint: String
       var required: Bool = false
       var onPick: (UIImage) -> Void      // receives the picked / captured image
       var onClear: () -> Void
       var onOpen: (Photo) -> Void
   }
   struct PhotoSourceButtons: View {      // the two buttons alone, for rows like A4's photo strip
       var compact: Bool = false
       var onUpload: () -> Void
       var onCamera: () -> Void
   }
   ```
   `PhotoSlot` owns its PhotosPicker and fullScreenCover camera state, so pages stop duplicating `showPicker` / `showCamera` / `pickPhoto`. Image saving stays in the page through `model.addPhoto`, called from `onPick`.
2. Move `photoButton`, `doneBadge` and `clearButton` out of `PanelsPageWide+Photos.swift` into the shared file. B1 then uses `PhotoSlot`.
3. Replace the variants:
   - A3 tiles (keep their size; use the compact buttons)
   - the A4 photo strip (`PhotoSourceButtons`, 60 pt tall)
   - B2 photos
   - any other empty-photo UI the graph finds
4. Icons: add `ui-upload-photo`, `ui-camera`, `photo-done` and `photo-clear` from `docs/ui/photo-picker/icons/` to `Resources/A2Icons.xcassets`, as PDF vectors. `ui-*` are template images; `photo-*` keep their colours. If `ui-upload-photo` / `ui-camera` or `b1-photo-done` / `b1-photo-clear` already exist, reuse them and don't duplicate. Keep the `A2Icon(name:fallback:)` SF Symbol fallbacks.

## Rules
- Do not change photo field ids, how photos are stored, Drive upload, PDF or Excel.
- Every hit target is at least 44 pt.
- UI text stays Thai, exactly as in the design.
- The hint texts in the previews are examples; each page passes its own.
- iPhone (compact) uses the same component.

## Check before finishing
1. `swift build` and `swift test` in `TCRoofKit` pass.
2. The xcodebuild command from `CLAUDE.md` passes, using your own `-derivedDataPath`.
3. Run the simulator on the A3, A4, B1 and B2 pages (`-surveyPage electrical|flood|panels|inverter`). On each page:
   1. Check the empty slot against `preview-empty.png`.
   2. Upload a photo and check the filled slot against `preview-filled.png`.
   3. Clear the photo.
   4. Confirm the camera button is hidden on the simulator.
4. Summarise the files changed and list any page left on its own picker, with the reason.
