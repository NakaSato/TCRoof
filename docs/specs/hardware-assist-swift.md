# Hardware assist: using the iPad's hardware in the survey (iPad Swift dev spec)

**Status:** Mostly built (checked 2026-10-17): §1 `DeviceCaps` (Settings › เครื่องนี้), H1 Live Text and the nameplate parser (`LiveTextScanner`, `TCRoofCore/Hardware/NameplateParser`), H2 position, H3 roof angle and facing (`RoofSensor`, `Orientation`), H4 camera checks, wide rooms and stamp (`CheckedCamera`, `WideCamera`, `ImageQuality`, `PanoramaGuide`), H6 card / USB import (`CardImportSheet`, `CardImport`), H8 power (`PowerMonitor`, `PowerAdvice`). Files live in `TCRoofUI/Survey/Hardware/` and `TCRoofCore/Hardware/` (§5).
**Not built:** H5 Pencil tools; H6 external display; H7 laser meter and LiDAR / ARKit measuring (`FillSource` has `laser`, `lidar` and `arEstimate` cases, but nothing sets them).
**Platform:** TCRoof on **iPad** (SwiftUI, iPadOS 17+).
**Target device:** iPad Air (M-series), plus anything better.
**Rule:** every feature checks the hardware **at runtime** and falls back cleanly. The same build runs on iPad Air
Wi-Fi, iPad Air Cellular and iPad Pro, and does the best each device allows.
**No new dependencies:** Apple frameworks only.

**Already in the code:**
- `DataScannerViewController` (VisionKit) is used for barcodes in `TCRoof/Views/Scan/ScanViews.swift`.
- `LocationFetcher` (CoreLocation, one-shot) lives in `TCRoof/Utilities/LocationFetcher.swift`.
- `PencilKit` is used for signatures (`TCRoofUI/Survey/Photos/PhotoFields.swift`).
- `SurveyModel.addPhoto(_:to:maxSide:)` stores photos.

This spec builds on all of these.

---

## 1. What the hardware can do, and how the app finds out

| Capability | iPad Air (M1 / M2 / M3) | iPad Pro | Runtime check | Fallback |
|---|---|---|---|---|
| Neural Engine: on-device text recognition and image analysis | ✓ | ✓ | `DataScannerViewController.isSupported && isAvailable`; `VNRecognizeTextRequest.supportedRecognitionLanguages()` | type by hand |
| Rear camera | one 12 MP wide | wide + ultra-wide | `AVCaptureDevice.DiscoverySession([.builtInUltraWideCamera], …)` | guided multi-shot (§H4) |
| LiDAR | **no** | ✓ | `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` | ARKit planes (low accuracy label) or a Bluetooth laser meter |
| GPS | **Cellular models only**; Wi-Fi models get approximate location | same rule | the first fix's `horizontalAccuracy` (≤ 20 m counts as GPS) | external Bluetooth GNSS receiver (Core Location uses it automatically), or type / paste a Google Maps link |
| Compass (magnetometer) | ✓ | ✓ | `CLLocationManager.headingAvailable()`; `CLHeading.headingAccuracy` | pick the direction by hand |
| Motion (accelerometer / gyro) | ✓ | ✓ | `CMMotionManager.isDeviceMotionAvailable` | type the angle |
| Apple Pencil Pro: squeeze, barrel roll, Pencil haptics | Air **M2 and later** | M4 | `UIPencilInteraction` squeeze callback fires; `UITouch.rollAngle` non-zero | long-press menus; two-finger rotate |
| Pencil hover | depends on model | ✓ | `UIHoverGestureRecognizer` with Pencil events arriving | no preview; draw on touch |
| USB-C: storage, card readers, external display | ✓ (Stage Manager with an external display on M1+) | ✓ | `fileImporter`; `UIApplication.shared.openSessions` external display role | AirDrop / Files |
| Bluetooth LE | ✓ | ✓ | `CBCentralManager.state == .poweredOn` | type the value |
| Thermal state, battery, Low Power Mode | ✓ | ✓ | `ProcessInfo.thermalState`, `UIDevice.batteryLevel`, `isLowPowerModeEnabled` | — |

**Two facts shape the design:**
- **iPads have no haptic motor.** Only Apple Pencil Pro can give haptic feedback, so all confirmation is visual. The
  Pencil ticks only when a Pencil Pro is in use.
- **The compass is disturbed near steel and transformers.** Every heading reading shows its accuracy. Headings taken
  within about 2 m of a transformer or on a steel roof are marked "ตรวจทิศอีกครั้ง" (§H3).

```swift
/// TCRoofUI/Survey/Hardware/DeviceCaps.swift: computed once at launch, refreshed on scene activation.
@Observable final class DeviceCaps {
    private(set) var liveText = false, compass = false, motion = false
    private(set) var lidar = false, ultraWide = false
    private(set) var gpsGrade: GPSGrade = .unknown            // after the first fix; kept in the app's defaults
}
```

- `DeviceCaps` sits in the SwiftUI environment. Every feature below reads it to show, hide or downgrade its button.
- **Settings › เครื่องนี้** lists what was detected, for example "ไม่มี LiDAR · GPS ประมาณการ (รุ่น Wi-Fi)". The team can then see why a button is missing.

---

## 2. Features

### H1. Read nameplates with the camera (Live Text)

**Fills these form fields:**

| Field | Value read |
|---|---|
| `meterNo` | meter number |
| `trafos[i].kva` | transformer rating |
| `breakerAT` (B1 panel) | main breaker AT |
| (SLD fields, when added: `_brand`, `_year`, `_z`, `_vector`, breaker `AF`/`kA`/brand) | nameplate details |

**How:**
- A **"อ่านจากป้าย"** button next to those fields opens `DataScannerViewController(recognizedDataTypes:
  [.text()])`. This is the same VisionKit view the barcode scanner uses, with `.text()` instead of `.barcode()`.
- Tapping a highlighted line takes it. The app also keeps the frame as the field's photo when the photo slot is
  empty, for example `tr0_plate` for the transformer nameplate.
- **Photos already taken:** `VNRecognizeTextRequest` (`.accurate`) runs on the existing nameplate photo in the
  background, and the app offers "พบ 630 kVA ในรูปป้าย ใช้ค่านี้?".

**Parsing** (`TCRoofCore/Hardware/NameplateParser.swift`, pure Swift, tested on Linux):

| Target | Pattern (case-insensitive, Thai/Arabic digits normalised with `NumberInput`) |
|---|---|
| kVA | `(\d{2,5})\s*k\s*V\s*A` |
| %Z / Uk | `(?:%\s*Z\|U\s*k\|IMPEDANCE)[^\d]{0,8}(\d{1,2}[.,]\d{1,2})` |
| Vector group | `\b(D\|Y)(y\|d\|yn\|zn)\s?(\d{1,2})\b` |
| Voltages | `(\d{2,3}(?:[.,]\d)?)\s*k?V\b` pairs → HV / LV |
| Year | `\b(19\|20)\d{2}\b`, or `\b25\d{2}\b` (B.E.), shown in B.E. as on the form |
| Breaker | `In\s*=?\s*(\d{2,4})\s*A` → AT; `(\d{2,4})\s*AF`; `Icu\s*=?\s*(\d{1,3})\s*kA` |
| Meter number | the longest digit run with `-`, 8–12 characters, next to "No." / "เลขที่" |

**Rules:**
- A parsed value is **proposed, never written silently.** The field shows the value with a "จากป้าย" chip, plus
  **ใช้ค่านี้ / ไม่ใช่**.
- The app records `fillSource = .nameplate` per field (§3), and the report can mark it.
- **Offline:** recognition runs on the Neural Engine. Thai text is used only if the device reports `th-TH` in
  `supportedRecognitionLanguages()`. Nameplates are mostly Latin script and digits either way.

### H2. Position

**`gps` field:**
- A **"ตำแหน่งปัจจุบัน"** button, using `LocationFetcher` (it stays in `TCRoof/Utilities`); the accuracy is graded
  by `GPSGrade` (`TCRoofCore/Hardware/Position.swift`).
- It waits up to 10 s for a fix with `horizontalAccuracy ≤ 20 m`, showing live accuracy ("± 8 ม.").
- It writes `"17.00621, 99.82354"`, the format `MapImage.coordinate(from:)` already parses.

**Low accuracy** (worse than 50 m, typical of a Wi-Fi iPad Air):
- The value is written with a warning: "ความแม่นยำ ± 120 ม. (เครื่องไม่มี GPS)".
- The field offers **วางลิงก์ Google Maps**, which is already supported.
- Settings suggests an external Bluetooth GNSS receiver. Core Location uses it with no app code.

**Also:** the photo stamp (§H4) and the drone import (§H6) use the same service.

### H3. Roof angle and facing direction (motion + compass)

**Form fields:**

| Field | Section |
|---|---|
| `roofAngle` "12. มุมเอียงของหลังคา" | C3 |
| `facing` "หันหน้าแผงที่จะติดตั้ง" | C3 |
| `facing` "หลังคาหันไปทางทิศ" | C2 |
| (later: `eaveHeight` / `ridgeHeight` checks in C1 via the derived pitch) | C1 |

**Angle:**
1. Tap **"วัดด้วยเครื่อง"**. A sheet says "วาง iPad ให้ขอบยาวขนานแนวลาดหลังคา".
2. `CMMotionManager.deviceMotion.gravity` runs at 50 Hz. The plane tilt is `atan2(√(gx² + gy²), |gz|)`, with the
   downhill direction projected on the screen.
3. The reading counts as **stable** when the 1 s standard deviation is under 0.3°. The app then shows "14.8°" and
   **ใช้ค่านี้**.
4. On corrugated sheet the guide says "วางขวางลอน".

**Direction:**
- Hold the iPad with the back camera facing down-slope, the same way the panels will face.
- `CLLocationManager.startUpdatingHeading()` gives `trueHeading` (magnetic declination handled by Core Location).
- The heading is mapped to the form's choices: เหนือ / ใต้ / ตะวันออก / ตะวันตก / ตะวันตกเฉียงใต้ /
  ตะวันออกเฉียงเหนือ, or อื่นๆ with the degrees.
- If `headingAccuracy > 15°`, or the magnetic field is disturbed, the app shows **"ตรวจทิศอีกครั้ง (ใกล้โลหะ)"**
  and offers the site picture's north as a cross-check.

**Stored:** the value, plus `fillSource = .sensor`.

### H4. Camera: quality check, stamp, wide rooms

1. **Quality check right after each shot** (before the photo is kept):

   | Check | Test | Warning |
   |---|---|---|
   | blur | Laplacian variance of the 512 px luminance (Accelerate `vImage`) below a threshold, tuned on team photos | "ภาพไม่ชัด ถ่ายใหม่?" |
   | too dark | mean luminance < 0.18 | "มืดเกินไป ถ่ายใหม่โดยเปิดแฟลช?": the retake uses the flash (there is no torch) |
   | tilted | `deviceMotion.gravity` roll > 12° at capture, for fields marked "ตรง" (nameplates, panels) | "ภาพเอียง" |

   Each warning has **เก็บไว้** / **ถ่ายใหม่**. It never blocks.

2. **Stamp:** new optional fields on `Photo`: `lat`, `lon`, `accuracy`, `heading`, `pitch`, `device`.
   - They are written at capture from §H2 and §H3 when available, and copied into the JPEG EXIF / GPS dictionary
     (ImageIO), so Drive and other apps see them too.
   - The report can print "17.0062, 99.8235 · หันทิศ 195° · 29/9/2569 10:42" under the photo (setting: on or off).
   - Old photos decode unchanged.

3. **Wide rooms without an ultra-wide lens** (iPad Air):
   - For "มุมกว้าง" fields (`photoWide`, `tr*_wide`, `underRoofPhoto`), the camera offers **ถ่ายต่อกัน 3 ภาพ**.
   - It shows an overlay guide with 30 % overlap (left → centre → right) and uses the gyroscope to say when to take
     the next shot.
   - The three are joined side by side into one picture (`WideCamera`), so the field, the report and Excel take it as
     before.
   - On devices with an ultra-wide camera, the camera opens at 0.5× instead, and no multi-shot is offered.
   - Stitching into one panorama (`VNHomographicImageRegistrationRequest`) is phase 2.

4. **Camera:** `CheckedCamera` wraps the existing `CameraPicker` and checks the photo after it is taken; only
   `WideCamera` has its own capture session. Photos are stored at `maxSide` 1600 (as before). The quality check runs
   off the main thread.

### H5. Apple Pencil (Pro)

- **Squeeze (Pencil Pro, iPad Air M2+):** `UIPencilInteraction` squeeze shows a small palette at the Pencil tip:
  - ถ่ายรูปช่องนี้
  - เขียนทับรูป (markup on the current photo, PencilKit)
  - ข้อความสำเร็จรูป (phrase list for remarks / condition notes)
  - ย้อนกลับ

  Squeezing again, or lifting, closes it.
- **Barrel roll:**
  - While dragging a site symbol, rolling rotates it. `MapMark` gets an optional `rotation`, shown in the editor and
    the report.
  - In the tank / roof editors, rolling turns the north arrow in 90° steps.
- **Hover** (where available): previews a symbol before it is dropped, and shows the running length while drawing
  cable routes and paths.
- **Pencil haptics** (Pencil Pro): a tick when a route snaps to a symbol, or a slot snaps to a bay.
- **Without Pencil Pro:** a long-press menu gives the same palette, and two-finger rotation rotates symbols.

### H6. USB-C: drone and camera cards, external display

**Card / USB import:**
- **นำเข้ารูปจากการ์ด / USB** uses `.fileImporter(allowedContentTypes: [.image, .jpeg, .heic], allowsMultiple:
  true)`, which works with a USB-C SD card reader or a drone's USB connection.
- For each image, ImageIO reads the EXIF date, GPS, altitude and camera model. Then:
  - The **picture with the highest altitude** is offered as the `siteMap` picture ("ภาพมุมสูงจากโดรน").
  - Pictures near a **symbol's position** are offered for that symbol's section. This works when the site picture is
    a map with a known scale (`MapImage` centre + zoom). For example, a photo taken within 15 m of the transformer
    symbol is proposed for the transformer's photos.
  - Everything else goes to a tray, and the surveyor drags items onto slots of the photo-check page
    (`ตรวจรูปทั้งหมด`).
- Imports are copied, never moved. The originals stay on the card.

**External display (USB-C / AirPlay, Stage Manager on M1+):**
- In the office: form on the iPad, **report preview** on the monitor, re-rendered whenever the form changes.

### H7. Measuring distances

| Tool | Where it fills | Notes |
|---|---|---|
| **Bluetooth laser meter** (preferred) | any number field in metres or cm: spans, heights, gate width, `measA`…`measI2`, purlin spacing | CoreBluetooth; one adapter per supported brand's BLE measurement characteristic. Tap a field, press the meter's button, and the value goes in. The field shows "จากเลเซอร์" |
| **LiDAR** (iPad Pro) | heights and widths in the logistics editor, tank / roof spans | `ARWorldTrackingConfiguration` + `sceneReconstruction`; tap two points; ± 1–2 cm class |
| **ARKit planes** (iPad Air) | same | plane detection only; the result carries "ความแม่นยำต่ำ ตรวจด้วยตลับเมตร" and `fillSource = .arEstimate` |

The laser meter makes the iPad Air measure as well as a Pro for the survey's needs. It is the recommended accessory.

### H8. Power, heat, storage (a full day outdoors)

The app watches `ProcessInfo.thermalState`, battery level and Low Power Mode, and adapts:

| Condition | App behaviour |
|---|---|
| `.serious` / `.critical` thermal | pause map snapshot fetches and PDF previews; camera stays available; banner "iPad ร้อน พักในที่ร่ม" |
| battery < 20 % or Low Power Mode | Drive upload waits for charging or Wi-Fi; thumbnails only in the photo check page; the screen dims sooner on the editor's idle pages |
| free storage < 2 GB (`volumeAvailableCapacityForImportantUsage`) | warning, with **ย้ายงานที่ส่งแล้วขึ้น Drive** |

The top bar shows a small battery/heat indicator only when one of these applies.

---

## 3. Data model changes (all optional → old jobs decode unchanged)

```swift
public enum FillSource: String, Codable, Sendable { case typed, nameplate, sensor, laser, lidar, arEstimate, gps, drone }
// Values gets a parallel map, so FieldValue stays unchanged:
public struct Values: Codable, Hashable, Sendable {
    public var storage: [String: FieldValue] = [:]
    public var sources: [String: FillSource]? = nil      // field id → how the value was obtained
}
// Photo (Models.swift): optional capture metadata
public var lat: Double?, lon: Double?, accuracy: Double?, heading: Double?, pitch: Double?, device: String?
// MapMark (SiteMarks.swift): optional rotation in degrees
public var rotation: Double?
```

- **Where `fillSource` shows:**
  - a small chip on the field
  - the REV diff, for example "แก้เอง จากค่าที่อ่านจากป้าย"
  - optionally, a footnote in the report
- **Typing** over a proposed value resets the source to `.typed`.

## 4. Permissions (Info.plist)

| Key | Status | Text |
|---|---|---|
| `NSCameraUsageDescription` | done | "…ถ่ายรูปหน้างาน และอ่านตัวเลขจากป้ายอุปกรณ์" |
| `NSLocationWhenInUseUsageDescription` | exists | keep |
| `NSMotionUsageDescription` | done | "ใช้วัดมุมเอียงหลังคาและตรวจภาพเอียง" |
| `NSBluetoothAlwaysUsageDescription` | **not yet** (for H7) | "ใช้รับค่าจากเครื่องวัดระยะเลเซอร์" |

Each permission is asked for only the first time its feature is used, never at launch.

## 5. Files

| File | Contents |
|---|---|
| `TCRoofUI/Survey/Hardware/DeviceCaps.swift` | §1 detection, environment object, Settings › เครื่องนี้ |
| `TCRoofUI/Survey/Hardware/LiveTextScanner.swift` | VisionKit text scanner sheet, photo OCR task (§H1) |
| `TCRoofUI/Survey/Hardware/RoofSensor.swift` | §H3 angle and facing |
| `TCRoofUI/Survey/Hardware/CheckedCamera.swift` | `CameraPicker` plus the quality check after each shot (§H4) |
| `TCRoofUI/Survey/Hardware/WideCamera.swift` | its own capture session: 0.5× or the three-shot guide, joined into one picture |
| `TCRoofUI/Survey/Hardware/CaptureContext.swift`, `CameraRoll.swift` | the stamp's capture context, camera helpers |
| `TCRoofUI/Survey/Hardware/CardImportSheet.swift` | `fileImporter`, placement proposals (§H6) |
| `TCRoofUI/Survey/Hardware/PowerMonitor.swift` | §H8 |
| `TCRoofCore/Hardware/NameplateParser.swift` | §H1 patterns (pure Swift) |
| `TCRoofCore/Hardware/Orientation.swift` | tilt from gravity, heading → form choice (pure Swift) |
| `TCRoofCore/Hardware/ImageQuality.swift` | blur / brightness metrics on a luminance buffer |
| `TCRoofCore/Hardware/PanoramaGuide.swift` | the three-shot guide's angles |
| `TCRoofCore/Hardware/CardImport.swift` | EXIF reading and placement rules |
| `TCRoofCore/Hardware/Position.swift` | `GPSGrade` |
| `TCRoofCore/Hardware/PowerAdvice.swift` | §H8 rules |
| `PencilTools`, `LaserMeter`, `ARMeasure` | **not built** (H5, H7) |

The photo slots (`Photos/PhotoSlot.swift`) use `CheckedCamera` (around the existing `CameraPicker`) for fields that
need the checks. The library
picker stays.

## 6. Tests

**Unit (`swift test`, Linux-compatible):**
- `NameplateParser` on 30 recognised-text samples from real nameplates (transformers, MCCB/ACB, meters). The samples
  are collected by the team and stored as text fixtures.
- `Orientation`:
  - gravity (0, −0.259, −0.966) gives 15.0°
  - heading 195° gives "ใต้"
  - heading 225° gives "ตะวันตกเฉียงใต้"
- `ImageQuality`: a synthetic sharp vs blurred pattern, and dark vs normal.
- EXIF → picture fraction: a photo 15 m east of the map centre at zoom 19 gives the expected fraction.
- Old `job.json` decodes: no `sources`, `rotation` or photo metadata.

**On device (manual, checklist in the PR):**
- iPad Air Wi-Fi:
  - location shows "ประมาณการ"
  - no LiDAR, so ARKit shows the low-accuracy label
  - multi-shot is offered for wide photos
- iPad Air M2+ with Pencil Pro: squeeze palette and roll rotation work.
- Laser meter: 10 readings match the meter's display.
- Inclinometer: within ±0.5° of a digital level on a test roof sheet.

## 7. Done when

- [ ] Every button in §H1–H8 is visible only when the device can do it, and Settings › เครื่องนี้ explains the rest.
- [ ] A 630 kVA transformer nameplate and an MCCB label fill their fields after one tap on a proposed value, offline.
- [ ] No sensor or OCR value is written without the surveyor confirming it, and each keeps its source.
- [ ] The app works a full survey day on an iPad Air, with uploads deferred on low battery and no crash on thermal
      warnings.

## 8. Open questions

1. **Exact models:** which iPad Air the team uses (M1 / M2 / M3, Wi-Fi or Cellular), and whether anyone has Pencil
   Pro.
2. **Laser meter:** which brand and model the team has or will buy, so the first Bluetooth adapter matches it.
3. **External GPS:** buy Bluetooth GNSS receivers for Wi-Fi iPads, or switch to Cellular models?
4. **Photo stamp:** print coordinates and time under photos in the report by default, or only on request?
5. **Nameplate fields:** besides kVA, meter number and main breaker AT, which nameplate values should the form keep?
   This ties in with the SLD's transformer and breaker fields.
