# TCRoof

iPad-first & iPhone SwiftUI application for solar site surveys, engineering drawings, and installation project tracking.

## Key Features

- **Solar Site Survey (กปภ. & Residential):** Structured field survey forms (A1–E1), automatic 2D roof & water tank drawings, PV module layout optimization, shade analysis, Single Line Diagram (SLD) generation, and hardware-assisted capture (Live Text OCR, inclinometer/compass, photo quality checks).
- **Engineering & Report Exports:** Generates company PDF survey reports (NO.215), Excel workbooks (NO.224), CAD drawings (`.dxf`), IEC 62446 workbooks (`.xlsx`) & photo appendices (`.docx`), and weekly meeting slides (`.pptx`).
- **Installation & Project Tracking:** Master Project Schedule (MP Plan & WBS) with Excel round-trip import/export, routine reports (weekly work requests, daily reports, monthly summaries), Site ICL checklists, IEC 62446 commissioning tests, and station permit/ERC exemption tracking.
- **Team Operations & Sync:** Role-based access control (`manager`, `internal`, `external`), offline-first Firestore sync, background Google Drive uploads, tool/vehicle logs, travel & expense claims, and an AI Project Assistant.

## Repository Structure

```text
TCRoof/                 # iOS/iPadOS app target (SwiftUI, SwiftData, Firebase, Google Drive sync)
TCRoofKit/              # Reusable Swift package
├── Sources/
│   ├── TCRoofCore/     # Domain models, calculators, CAD/DXF, SLD, layout & schedule engines
│   ├── TCRoofUI/       # Design system (Theme, TC* components) and survey editor UI
│   ├── PDFReport/      # Vector PDF report renderer
│   ├── ExcelExport/    # Excel (.xlsx), Word (.docx), and PowerPoint (.pptx) exporters
│   ├── PVYield/        # Hourly PVsyst-style solar energy yield engine
│   ├── ModuleRules/    # Module installation rules & validation engine
│   └── DriveSync/      # Google Drive client and background upload manager
└── Tests/              # Unit and golden fixture tests
TCRoofUITests/          # Xcode UI automation tests (iPad & iPhone)
functions/              # Firebase Cloud Functions (TypeScript)
tools/                  # Firestore rules tests, Master Plan Apps Script, and CAD/plan utilities
docs/                   # Feature specifications (docs/specs/) and UI references (docs/ui/)
```

## Getting Started

### Prerequisites

- **Xcode 26+** (Swift 6.2 toolchain, iOS 18+ app target; `TCRoofKit` supports iOS 17+ / macOS 14+)
- **Node.js** (optional, for Firebase Cloud Functions and Firestore security rules tests)

### Configuration

1. Copy the secrets template:
   ```bash
   cp Secrets.example.xcconfig Secrets.xcconfig
   ```
2. Fill in optional API keys (such as `GISTDA_API_KEY`) in `Secrets.xcconfig`. The app builds and runs without it.

### Build & Run

Open `TCRoof.xcodeproj` in Xcode, select the **TCRoof** scheme, and run on an iPad or iPhone simulator/device.

Command-line simulator build:

```bash
xcodebuild -project TCRoof.xcodeproj \
  -scheme TCRoof \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TCRoofDerivedData \
  build
```

## Testing

**Swift Package Tests (fast, macOS):**

```bash
cd TCRoofKit
swift test --parallel
```

**Single Test Class or Case:**

```bash
cd TCRoofKit
swift test --filter InverterStationTests
```

**Cloud Functions & Firestore Rules Tests:**

```bash
# Cloud Functions
cd functions && npm install && npm test

# Firestore Security Rules (requires Firebase CLI & Java)
cd tools/firestore-rules-tests && npm install && npm test
```
