#if canImport(UIKit)
import SwiftUI
import VisionKit
import Vision
import TCRoofCore

/// What a nameplate scan reads: one field, or a transformer plate's kVA, voltage, vector group, %Z and year.
enum PlateKind {
    case single(NameplateParser.Target)
    case transformer

    /// The values found in recognised text.
    func fields(in text: String) -> [NameplateParser.Field] {
        switch self {
        case .single(let t):
            return NameplateParser.value(t, in: text).map { [NameplateParser.Field(key: t.rawValue, label: "", value: $0, display: t.display($0))] } ?? []
        case .transformer:
            return NameplateParser.transformerFields(NameplateParser.read(text))
        }
    }

    var hint: String {
        switch self {
        case .single(.kva), .transformer: return "ส่องป้ายพิกัดหม้อแปลง | แตะบรรทัดที่ต้องการอ่าน"
        case .single(.breakerAT): return "ส่องป้ายเบรกเกอร์ | แตะบรรทัดที่มีค่า In หรือ AT"
        case .single(.meterNumber): return "ส่องหน้ามิเตอร์ | แตะหมายเลขมิเตอร์"
        }
    }
}

/// "อ่านจากป้าย": opens the camera with Live Text on a nameplate and hands back the values the surveyor confirms,
/// with the frame they were read from (docs/specs/hardware-assist-swift.md §H1). Hidden where the device has no Live Text.
struct NameplateScanButton: View {
    let kind: PlateKind
    /// Called only after ใช้ค่านี้; the caller writes each value with `FillSource.nameplate`, and may keep the frame
    /// as the nameplate photo when that slot is empty.
    let apply: ([NameplateParser.Field], UIImage?) -> Void
    var compact = false
    @State private var open = false
    @State private var caps = DeviceCaps.shared

    init(kind: PlateKind, compact: Bool = false, apply: @escaping ([NameplateParser.Field], UIImage?) -> Void) {
        self.kind = kind; self.compact = compact; self.apply = apply
    }
    /// One field: the confirmed value.
    init(target: NameplateParser.Target, apply: @escaping (String) -> Void, compact: Bool = false) {
        self.init(kind: .single(target), compact: compact) { f, _ in if let v = f.first?.value { apply(v) } }
    }

    var body: some View {
        if caps.liveText {
            Button { open = true } label: {
                if compact {
                    Image(systemName: "text.viewfinder").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                } else {
                    Label("อ่านจากป้าย", systemImage: "text.viewfinder").font(.sarabunFixed(14, .semibold))
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.primary)
            .accessibilityLabel("อ่านจากป้ายด้วยกล้อง")
            .fullScreenCover(isPresented: $open) {
                NameplateScannerView(kind: kind) { fields, image in
                    open = false
                    if !fields.isEmpty { apply(fields, image) }
                }
            }
        }
    }
}

/// The camera with Live Text: everything recognised is read for the plate's fields, a tapped line overrides what it
/// holds, and the values are proposed with a tick each, never written on their own.
struct NameplateScannerView: View {
    let kind: PlateKind
    let done: ([NameplateParser.Field], UIImage?) -> Void
    @State private var found: [NameplateParser.Field] = []
    @State private var off: Set<String> = []
    @State private var rejected: Set<NameplateParser.Field> = []
    @State private var unavailable = false
    @State private var saving = false
    @State private var scanner = ScannerHandle()

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(handle: scanner, onText: { lines, tapped in propose(lines, tapped: tapped) }, unavailable: $unavailable)
                .ignoresSafeArea()
            panel
                .padding(20)
                .frame(maxWidth: 520)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .padding(16)
        }
    }

    @ViewBuilder private var panel: some View {
        VStack(spacing: 12) {
            if unavailable {
                Text("ใช้กล้องไม่ได้ | อนุญาตการใช้กล้องใน การตั้งค่า แล้วลองใหม่").multilineTextAlignment(.center)
            } else if found.isEmpty {
                Text(kind.hint).multilineTextAlignment(.center).foregroundStyle(Theme.inkMuted)
            } else if case .single = kind, let f = found.first {
                Text("พบ \(f.display)").font(.sarabunFixed(22, .bold))
                buttons(confirm: "ใช้ค่านี้")
            } else {
                Text("พบในป้าย").font(.sarabun(17, .semibold, relativeTo: .headline))
                ForEach(found, id: \.key) { f in
                    Button { if off.contains(f.key) { off.remove(f.key) } else { off.insert(f.key) } } label: {
                        HStack {
                            Image(systemName: off.contains(f.key) ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(off.contains(f.key) ? Theme.disabledText : Theme.primary)
                            Text(f.label).foregroundStyle(Theme.inkMuted)
                            Spacer()
                            Text(f.display).bold()
                        }
                        .frame(minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                buttons(confirm: "ใช้ค่าที่เลือก")
            }
            Button("ปิด") { done([], nil) }.frame(minHeight: 44)
        }
    }

    private func buttons(confirm: String) -> some View {
        HStack(spacing: 12) {
            Button { rejected.formUnion(found); found = []; off = [] } label: {
                Text("ไม่ใช่").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            Button { confirmSelection() } label: {
                Group { if saving { ProgressView() } else { Text(confirm).bold() } }.frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .disabled(saving || found.allSatisfy { off.contains($0.key) })
        }
    }

    /// Takes the frame the values were read from, then hands both back.
    private func confirmSelection() {
        let chosen = found.filter { !off.contains($0.key) }
        saving = true
        Task { @MainActor in
            let image = try? await scanner.controller?.capturePhoto()
            done(chosen, image)
        }
    }

    /// A tapped line replaces what it holds; otherwise new fields from the whole view are added. Values the surveyor
    /// said ไม่ใช่ to are not offered again unless tapped.
    private func propose(_ lines: [String], tapped: String?) {
        if let tapped {
            var hits = kind.fields(in: tapped)
            if hits.isEmpty, case .single(.meterNumber) = kind, let d = digitsOnly(tapped) {
                hits = [NameplateParser.Field(key: "meterNumber", label: "", value: d, display: d)]
            }
            for h in hits {
                rejected.remove(h)
                found.removeAll { $0.key == h.key }
                found.append(h)
            }
        } else {
            for h in kind.fields(in: lines.joined(separator: "\n")) where !rejected.contains(h) && !found.contains(where: { $0.key == h.key }) {
                found.append(h)
            }
        }
        let order = NameplateParser.transformerKeys
        found.sort { (order.firstIndex(of: $0.key) ?? 0) < (order.firstIndex(of: $1.key) ?? 0) }
    }

    private func digitsOnly(_ s: String) -> String? {
        let d = s.filter { $0.isNumber || $0 == "-" }
        return d.filter(\.isNumber).count >= 6 ? d : nil
    }
}

/// Lets the sheet ask the running scanner for its frame.
final class ScannerHandle {
    weak var controller: DataScannerViewController?
}

/// VisionKit's data scanner reading text, reporting every recognised line and the one tapped.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let handle: ScannerHandle
    let onText: (_ lines: [String], _ tapped: String?) -> Void
    @Binding var unavailable: Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        handle.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard !vc.isScanning else { return }
        if DataScannerViewController.isAvailable {
            try? vc.startScanning()
        } else {
            Task { @MainActor in unavailable = true }
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable
        init(_ parent: DataScannerRepresentable) { self.parent = parent }

        private func lines(_ items: [RecognizedItem]) -> [String] {
            items.compactMap { if case .text(let t) = $0 { return t.transcript } else { return nil } }
        }
        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            parent.onText(lines(allItems), nil)
        }
        func dataScanner(_ s: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            parent.onText(lines(allItems), nil)
        }
        func dataScanner(_ s: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let t) = item { parent.onText([], t.transcript) }
        }
    }
}

// MARK: - photos already taken

/// Text recognition on a photo that is already in the job (Vision, on device, offline).
public enum PlatePhotoReader {
    public static func text(in image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["en-US"] + (supported.contains("th-TH") ? ["th-TH"] : [])
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

/// "พบในรูปป้าย: 630 kVA | Dyn11 | ใช้ค่านี้?": values the transformer's nameplate photo shows that its fields don't
/// have yet. Shown once per photo; ไม่ใช่ hides it until another photo is taken.
struct PlatePhotoSuggestion: View {
    let photo: Photo
    let jobID: UUID
    /// The transformer's current values by field key.
    let current: [String: String]
    let apply: ([NameplateParser.Field]) -> Void
    @Environment(SurveyModel.self) private var model
    @State private var found: [NameplateParser.Field] = []
    @State private var dismissed: UUID?

    private var fresh: [NameplateParser.Field] {
        found.filter { f in (current[f.key] ?? "").trimmingCharacters(in: .whitespaces) != f.value }
    }

    var body: some View {
        // a zero-height base so the reader's task starts while there is nothing to show yet (an empty view starts none)
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if dismissed != photo.id, !fresh.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "text.viewfinder").foregroundStyle(Theme.primary)
                    Text("พบในรูปป้าย: " + fresh.map(\.display).joined(separator: " | ")).font(.sarabunFixed(14, .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("ไม่ใช่") { dismissed = photo.id }.frame(minHeight: 44)
                    Button("ใช้ค่านี้") { apply(fresh); dismissed = photo.id }.bold().frame(minHeight: 44)
                }
                .padding(.horizontal, 12)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .task(id: photo.id) {
            guard let image = model.image(photo, in: jobID) else { return }
            found = NameplateParser.transformerFields(NameplateParser.read(await PlatePhotoReader.text(in: image)))
        }
    }
}
#endif
