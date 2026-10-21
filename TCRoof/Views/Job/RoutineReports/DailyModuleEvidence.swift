import SwiftUI
import PhotosUI
import VisionKit
import TCRoofUI

/// The checklist's evidence photos (docs/specs/module-install-rules.md §7.3): the daily report's own photos, tagged
/// `module.<kind>`, so they are saved with the report, travel through Drive (`PhotoSync`) and print with a caption. The
/// day's photo card leaves them to the checklist.
enum ModuleEvidence: String, CaseIterable, Identifiable {
    case torque, cable, ground, rejected
    var id: String { rawValue }

    static let prefix = "module."
    var tag: String { Self.prefix + rawValue }

    var title: String {
        switch self {
        case .torque: "รูปประแจวัดแรงขันน็อต"
        case .cable: "รูปการเดินสาย"
        case .ground: "รูปจุดต่อสายดิน"
        case .rejected: "รูปแผงที่คัดออก (เห็นเลขซีเรียล)"
        }
    }

    /// The PDF's caption.
    var caption: String { "ตรวจติดตั้งแผง | " + title.replacingOccurrences(of: "รูป", with: "") }

    static func isEvidence(_ tag: String) -> Bool { tag.hasPrefix(prefix) }
    static func kind(_ tag: String) -> ModuleEvidence? { tag.hasPrefix(prefix) ? ModuleEvidence(rawValue: String(tag.dropFirst(prefix.count))) : nil }
}

/// One evidence slot of the checklist: its photos, the camera and the library.
struct ModuleEvidenceRow: View {
    let kind: ModuleEvidence
    @Binding var photos: [DraftPhoto]
    @State private var items: [PhotosPickerItem] = []
    @State private var camera = false

    private var mine: [DraftPhoto] { photos.filter { $0.tag == kind.tag } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: mine.isEmpty ? "camera" : "checkmark.circle.fill")
                    .foregroundStyle(mine.isEmpty ? Theme.pending : Theme.okText)
                Text(kind.title).font(.sarabun(15)).foregroundStyle(Theme.navy)
                Spacer(minLength: 4)
                Button { addFromCamera() } label: { Image(systemName: "camera").frame(width: touchMin, height: touchMin) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("ถ่าย" + kind.title)
                    .accessibilityIdentifier("moduleEvidence.\(kind.rawValue).camera")
                PhotosPicker(selection: $items, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo.on.rectangle").frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("เลือก" + kind.title + "จากคลังภาพ")
            }
            if !mine.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(mine) { p in
                            Thumbnail(data: p.data).frame(width: 84, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.removeAll { $0.id == p.id } } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(Theme.onMedia, .black.opacity(0.6)).frame(width: touchMin, height: touchMin)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("ลบรูป")
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moduleEvidence.\(kind.rawValue)")
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) { photos.append(.init(data: ImageUtil.compressed(data), tag: kind.tag)) }
                }
                items = []
            }
        }
        .fullScreenCover(isPresented: $camera) { StampedCamera { photos.append(.init(data: $0, tag: kind.tag)) } }
    }

    private func addFromCamera() {
        #if DEBUG
        // `-dailyModuleCameraStub YES`: a drawn photo instead of the camera, for UI tests
        if UserDefaults.standard.bool(forKey: "dailyModuleCameraStub") {
            photos.append(.init(data: DailyOnePage.demoPhoto(photos.count), tag: kind.tag))
            return
        }
        #endif
        camera = true
    }
}

/// `สแกนเลขซีเรียล`: the Scan tab's barcode scanner (`BarcodeScannerView`) for the module serials, or the barcodes in
/// a photo where live scanning isn't available. `add` takes the codes found; the list is the checklist's own.
struct ModuleSerialScanSheet: View {
    let title: String
    let add: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var found: [String] = []
    @State private var item: PhotosPickerItem?
    @State private var note: String?

    private var live: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if live {
                        BarcodeScannerView { code in if !found.contains(code) { found.append(code) } }
                    } else {
                        Text("อุปกรณ์นี้สแกนสดไม่ได้ | เลือกรูปที่เห็นบาร์โค้ด").font(.sarabun(15)).foregroundStyle(Theme.onMedia)
                            .multilineTextAlignment(.center).padding()
                    }
                }
                .frame(maxHeight: 360)
                List {
                    Section {
                        PhotosPicker(selection: $item, matching: .images) { Label("อ่านบาร์โค้ดจากรูป", systemImage: "photo") }
                        if let note { Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted) }
                    }
                    Section("พบ \(found.count) เลข") {
                        ForEach(found, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                            .onDelete { found.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม \(found.count) เลข") { add(found); dismiss() }.disabled(found.isEmpty)
                        .accessibilityIdentifier("moduleScan.add")
                }
            }
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        let codes = await ImageUtil.detectBarcodes(in: img)
                        for c in codes where !found.contains(c) { found.append(c) }
                        note = codes.isEmpty ? "ไม่พบบาร์โค้ดในรูป" : "พบ \(codes.count) บาร์โค้ดในรูป"
                    }
                    item = nil
                }
            }
            #if DEBUG
            // `-dailyModuleScanStub YES`: three serials found, as the scanner would, for UI tests
            .task {
                if UserDefaults.standard.bool(forKey: "dailyModuleScanStub") {
                    found = ["ZX7523351920A001", "ZX7523351920A002", "ZX7523351920A003"]
                }
            }
            #endif
        }
    }
}
