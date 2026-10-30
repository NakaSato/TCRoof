# TCRoofKit — แบบสำรวจเพื่อออกแบบ (เบื้องต้น) NO.224

Swift package สำหรับ iPad (iOS 17+) ที่ใช้ใน TCRoof

## Toolchain

Requires Swift 6.2 or later (Xcode 26 or later on macOS). `.swift-version` selects
Swift 6.2 for toolchain managers. The package keeps Swift 5 language mode and its
existing iOS 17 / macOS 14 deployment targets; the app keeps iOS 18.

The pure Swift SHA-256 implementation uses `Span`, `InlineArray`, and a noncopyable
working state on supported runtimes (iOS/macOS 26 or newer, and Linux with Swift 6.2).
Older Apple runtimes use the existing implementation. Apple builds continue using
CryptoKit for `FormHash.sha256`.

Class collections exposed by SwiftData and SwiftUI remain `Array`: `ContiguousArray`
would require conversions and only makes the references contiguous, not the objects.
Use it for private class collections when profiling demonstrates a benefit.

| Module | หน้าที่ |
|---|---|
| `TCRoofCore` | โมเดลงาน, schema ฟอร์มทั้ง 10 หัวข้อ (ตรงกับแผ่นงาน NO.224), คำนวณความครบถ้วน, เก็บงาน/รูปใน `Documents/SolarSurvey`, นำเข้า/ส่งออก JSON ของเว็บแอป, แปลน/Truss/เข็มทิศแบบ vector |
| `ExcelExport` | เติมข้อมูลลงสำเนา workbook ของบริษัท (`Resources/template.xlsx`) — ช่องเดิม, ติ๊ก checkbox, วางรูปในกรอบ, สร้างแผ่นเพิ่มเมื่อหลังคา/ถัง/ตู้ไฟเกินช่อง, เติมค่าใน SmartArt มิเตอร์–หม้อแปลง–MDB |
| `PDFReport` | รายงาน A4 แบบ NO.215 (UIGraphicsPDFRenderer + ฟอนต์ Sarabun ที่แนบมา) |
| `DriveSync` | Google Drive REST v3: โฟลเดอร์ `Solar Survey Projects/NO.xxx ชื่อโครงการ`, อัปโหลด PDF/Excel/survey-data.json, เปิดงานจาก Drive |
| `TCRoofUI` | ระบบออกแบบ (`Theme`, คอมโพเนนต์ `TC*`) และหน้าจอ SwiftUI ใน `Survey/`: รายการงาน, ตัวแก้ไข (แถบซ้ายแบ่งตามแผ่นงาน), ถ่ายรูป/คลังภาพ, ลายเซ็น Apple Pencil, ส่งออก, Drive, ตั้งค่า |

ใช้งานใน SwiftUI:

```swift
import TCRoofUI
NavigationStack { SolarSurveyReportView() }
```

## Google Drive
1. Google Cloud Console → เปิด **Google Drive API**
2. Credentials → OAuth client ID ชนิด **iOS** → Bundle ID `com.tcroof.internal`
3. ในแอป: แบบสำรวจ NO.224 → ⋯ → ตั้งค่า → วาง Client ID → ลงชื่อเข้าใช้ Google

ใช้ OAuth + PKCE ผ่าน `ASWebAuthenticationSession` (ไม่ต้องเพิ่ม SDK) สิทธิ์ `drive.file` — แอปเห็นเฉพาะไฟล์ที่แอปสร้างเอง
ไฟล์ `survey-data*.json` ใช้รูปแบบเดียวกับเว็บแอป จึงเปิดข้ามกันได้ (เว็บ → iPad ให้ใช้ "นำเข้าไฟล์ข้อมูล")

## ทดสอบ
```
swift test          # macOS (Xcode 26+)
# Linux, from the repository root:
tools/linux-swift/test.sh --build-only
tools/linux-swift/test.sh --filter ReviewTests
tools/linux-swift/test.sh --filter 'OAuthTokenSessionTests|BackgroundWorkTests'
```
`EXPORT_DIR=/tmp/out swift test` จะเขียน `native-test.xlsx` และหน้า PDF แบบ SVG ไว้ตรวจด้วยตา

## เปลี่ยนแม่แบบ Excel
แทนที่ `Sources/ExcelExport/Resources/template.xlsx` ได้ ถ้าเลย์เอาต์แผ่นงานไม่เปลี่ยน ถ้าตำแหน่งช่องเปลี่ยน แก้ที่ `ExcelExporter.swift` (struct `Fill`) และ `template_meta.json` (สไตล์ checkbox)
