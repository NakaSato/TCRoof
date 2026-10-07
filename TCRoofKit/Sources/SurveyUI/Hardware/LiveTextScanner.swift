#if canImport(UIKit)
import SwiftUI
import VisionKit
import TCRoofCore

/// "อ่านจากป้าย": opens the camera with Live Text on a nameplate and hands back the value the surveyor confirms
/// (docs/specs/hardware-assist-swift.md §H1). Hidden where the device has no Live Text.
struct NameplateScanButton: View {
    let target: NameplateParser.Target
    /// Called only after ใช้ค่านี้; the caller writes the value with `FillSource.nameplate`.
    let apply: (String) -> Void
    var compact = false
    @State private var open = false
    @State private var caps = DeviceCaps.shared

    var body: some View {
        if caps.liveText {
            Button { open = true } label: {
                if compact {
                    Image(systemName: "text.viewfinder").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                } else {
                    Label("อ่านจากป้าย", systemImage: "text.viewfinder").font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain).foregroundStyle(Home.primary)
            .accessibilityLabel("อ่านจากป้ายด้วยกล้อง")
            .fullScreenCover(isPresented: $open) {
                NameplateScannerView(target: target) { v in
                    open = false
                    if let v { apply(v) }
                }
            }
        }
    }
}

/// The camera with Live Text: everything recognised is parsed for the target; tapping a line reads that line only.
/// The value is proposed with ใช้ค่านี้ / ไม่ใช่ and never written on its own.
struct NameplateScannerView: View {
    let target: NameplateParser.Target
    let done: (String?) -> Void
    @State private var candidate: String?
    @State private var rejected: Set<String> = []
    @State private var unavailable = false

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(onText: { lines, tapped in propose(lines, tapped: tapped) }, unavailable: $unavailable)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                if unavailable {
                    Text("ใช้กล้องไม่ได้ · อนุญาตการใช้กล้องใน การตั้งค่า แล้วลองใหม่").multilineTextAlignment(.center)
                } else if let c = candidate {
                    Text("พบ \(target.display(c))").font(.system(size: 22, weight: .bold))
                    HStack(spacing: 12) {
                        Button { rejected.insert(c); candidate = nil } label: {
                            Text("ไม่ใช่").frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        Button { done(c) } label: {
                            Text("ใช้ค่านี้").bold().frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text(hint).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                Button("ปิด") { done(nil) }.frame(minHeight: 44)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(16)
        }
    }

    private var hint: String {
        switch target {
        case .kva: return "ส่องป้ายพิกัดหม้อแปลง · แตะบรรทัดที่มี kVA"
        case .breakerAT: return "ส่องป้ายเบรกเกอร์ · แตะบรรทัดที่มีค่า In หรือ AT"
        case .meterNumber: return "ส่องหน้ามิเตอร์ · แตะหมายเลขมิเตอร์"
        }
    }

    /// A tapped line wins; otherwise the whole view is read. A value the surveyor said ไม่ใช่ to is not offered again.
    private func propose(_ lines: [String], tapped: String?) {
        if let tapped {
            let v = NameplateParser.value(target, in: tapped)
                ?? (target == .meterNumber ? digitsOnly(tapped) : nil)
            if let v { rejected.remove(v); candidate = v }
            return
        }
        guard candidate == nil, let v = NameplateParser.value(target, in: lines.joined(separator: "\n")), !rejected.contains(v) else { return }
        candidate = v
    }

    private func digitsOnly(_ s: String) -> String? {
        let d = s.filter { $0.isNumber || $0 == "-" }
        return d.filter(\.isNumber).count >= 6 ? d : nil
    }
}

/// VisionKit's data scanner reading text, reporting every recognised line and the one tapped.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onText: (_ lines: [String], _ tapped: String?) -> Void
    @Binding var unavailable: Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard !vc.isScanning else { return }
        if DataScannerViewController.isAvailable {
            try? vc.startScanning()
        } else {
            DispatchQueue.main.async { unavailable = true }
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
#endif
