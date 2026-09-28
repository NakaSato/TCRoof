import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

struct ScanJobListView: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var window: DateWindow = .week
    @State private var search = ""
    @State private var showPicker = false
    @State private var pendingJob: Job?
    @State private var scanJob: Job?

    private var filtered: [Job] {
        jobs.filter { window.overlaps($0.installInterval) && $0.matches(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "สแกนอุปกรณ์", symbol: AppModule.scan.symbol) {
                    HeaderLink(title: "ประวัติการสแกน") { ScanHistoryView() }
                }
                QueueFilterBar(listTitle: "รายการงานติดตั้ง", prefix: "คิวติดตั้ง", window: $window, search: $search, count: filtered.count)
                if filtered.isEmpty {
                    ContentUnavailableView("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนตัวกรองหรือคำค้นหา"))
                } else {
                    LazyVGrid(columns: cardColumns, spacing: 16) {
                        ForEach(filtered) { job in
                            JobCard(job: job, dateLabel: "วันเริ่มติดตั้ง", date: job.installStart) {
                                JobDevicesView(job: job)
                            } footer: {
                                DeviceSummaryStrip(job: job)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(systemImage: "barcode.viewfinder", accessibilityLabel: "สแกนอุปกรณ์") { showPicker = true }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker, onDismiss: {
            if let job = pendingJob {
                pendingJob = nil
                scanJob = job
            }
        }) {
            JobPickerSheet(title: "เลือกงานที่จะสแกนอุปกรณ์") { pendingJob = $0 }
        }
        .fullScreenCover(item: $scanJob) { job in ScannerView(job: job) }
    }
}

private struct DeviceSummaryStrip: View {
    let job: Job

    var body: some View {
        let panels = job.devices.filter { $0.kind == .panel }.count
        let others = job.devices.count - panels
        HStack(spacing: 16) {
            Label("แผง \(panels)/\(job.estimatedPanels)", systemImage: DeviceKind.panel.symbol)
            Label("อุปกรณ์อื่น \(others)", systemImage: DeviceKind.inverter.symbol)
            Spacer()
            ProgressView(value: min(Double(panels), Double(job.estimatedPanels)), total: Double(max(job.estimatedPanels, 1)))
                .frame(width: 100)
                .tint(Theme.teal)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.navy)
        .padding(10)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Devices of one job

struct JobDevicesView: View {
    let job: Job

    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""
    @State private var showScanner = false
    @State private var showManual = false
    @State private var manualSerial = ""
    @State private var manualKind: DeviceKind = .panel

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(DeviceKind.allCases) { kind in
                        let count = job.devices.filter { $0.kind == kind }.count
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: kind.symbol).font(.title2).foregroundStyle(Theme.primary)
                            Text(kind.title).font(.subheadline).foregroundStyle(Theme.navy)
                            Text(kind == .panel ? "\(count) / \(job.estimatedPanels)" : "\(count)")
                                .font(.title2.bold()).foregroundStyle(Theme.navy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("\(job.code) · \(job.projectName)")
            }

            ForEach(DeviceKind.allCases) { kind in
                let items = job.devices.filter { $0.kind == kind }.sorted { $0.scannedAt > $1.scannedAt }
                if !items.isEmpty {
                    Section("\(kind.title) (\(items.count))") {
                        ForEach(items) { device in
                            HStack {
                                Text(device.serial).font(.body.monospaced()).textSelection(.enabled)
                                Spacer()
                                Text("\(device.scannedAt.thaiShort) · \(device.scannedBy)")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { items[$0] }.forEach(context.delete)
                        }
                    }
                }
            }
        }
        .navigationTitle("อุปกรณ์ที่ติดตั้ง")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showManual = true } label: { Label("พิมพ์ซีเรียล", systemImage: "keyboard") }
                Button { showScanner = true } label: { Label("สแกน", systemImage: "barcode.viewfinder") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .fullScreenCover(isPresented: $showScanner) { ScannerView(job: job) }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                Form {
                    Picker("ประเภทอุปกรณ์", selection: $manualKind) {
                        ForEach(DeviceKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Serial No.", text: $manualSerial)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .navigationTitle("เพิ่มซีเรียลด้วยตนเอง")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { showManual = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("เพิ่ม") {
                            addManual()
                            showManual = false
                        }
                        .disabled(manualSerial.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func addManual() {
        let serial = manualSerial.trimmingCharacters(in: .whitespaces)
        guard !job.devices.contains(where: { $0.serial == serial }) else { return }
        let device = ScannedDevice(kind: manualKind, serial: serial, scannedBy: userName)
        context.insert(device)
        device.job = job
        manualSerial = ""
    }
}

// MARK: - Scanner

struct ScannerView: View {
    let job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""

    @State private var kind: DeviceKind = .panel
    @State private var found: [String] = []
    @State private var torch = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showTips = false
    @State private var showFound = false
    @State private var showManual = false
    @State private var manualSerial = ""
    @State private var message: String?

    private var existing: Set<String> { Set(job.devices.map(\.serial)) }
    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if scannerAvailable {
                BarcodeScannerView(onFound: add).ignoresSafeArea()
            } else {
                ContentUnavailableView("กล้องสแกนไม่พร้อมใช้งาน",
                                       systemImage: "camera.metering.unknown",
                                       description: Text("อุปกรณ์นี้ไม่รองรับการสแกนสด เลือกรูปจากคลังภาพหรือพิมพ์ซีเรียลแทน"))
                    .foregroundStyle(.white)
            }
            ScanFrame().allowsHitTesting(false)
            VStack(spacing: 16) {
                topBar
                kindPicker
                Spacer()
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.teal, in: Capsule())
                        .transition(.opacity)
                }
                Button { showTips = true } label: {
                    Label("คำแนะนำในการสแกนอุปกรณ์", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .underline()
                        .foregroundStyle(.white)
                }
                resultBar
            }
            .padding(24)
        }
        .onChange(of: torch) { _, on in ImageUtil.setTorch(on) }
        .onDisappear { if torch { ImageUtil.setTorch(false) } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    let codes = await ImageUtil.detectBarcodes(in: image)
                    codes.forEach(add)
                    flash(codes.isEmpty ? "ไม่พบบาร์โค้ดในรูป" : "พบ \(codes.count) บาร์โค้ด")
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showTips) { ScanTipsView() }
        .sheet(isPresented: $showFound) { foundList }
        .alert("พิมพ์ Serial No.", isPresented: $showManual) {
            TextField("Serial No.", text: $manualSerial)
                .textInputAutocapitalization(.characters)
            Button("เพิ่ม") {
                add(manualSerial.trimmingCharacters(in: .whitespaces))
                manualSerial = ""
            }
            Button("ยกเลิก", role: .cancel) { manualSerial = "" }
        }
    }

    private var topBar: some View {
        HStack {
            circle("chevron.left", label: "ปิด") { dismiss() }
            if ImageUtil.hasTorch {
                circle(torch ? "bolt.fill" : "bolt.slash", label: "ไฟฉาย") { torch.toggle() }
            }
            Spacer()
            VStack(spacing: 2) {
                Text(job.code).font(.headline)
                Text(job.projectName).font(.caption)
            }
            .foregroundStyle(.white)
            Spacer()
            circle("keyboard", label: "พิมพ์ซีเรียล") { showManual = true }
            PhotosPicker(selection: $photoItem, matching: .images) {
                circleLabel("photo")
            }
            .accessibilityLabel("สแกนจากรูปภาพ")
        }
    }

    private func circle(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol) }.accessibilityLabel(label)
    }

    private func circleLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3.bold())
            .foregroundStyle(Theme.navy)
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.9), in: Circle())
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeviceKind.allCases) { option in
                    Button { kind = option } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(kind == option ? .white : Theme.navy)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(kind == option ? Theme.primary : .white.opacity(0.9), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var resultBar: some View {
        HStack(spacing: 12) {
            if let first = found.first {
                Text(first).font(.body.monospaced()).foregroundStyle(Theme.navy)
                if found.count > 1 {
                    Button("ดูเพิ่มเติม (\(found.count))") { showFound = true }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("เล็งกล้องไปที่บาร์โค้ด\(kind.title)")
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(action: saveFound) {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(found.isEmpty ? Theme.muted : Theme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(found.isEmpty)
            .accessibilityLabel("บันทึก \(found.count) รายการ")
        }
        .padding(14)
        .frame(maxWidth: 640)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var foundList: some View {
        NavigationStack {
            List {
                ForEach(found, id: \.self) { Text($0).font(.body.monospaced()) }
                    .onDelete { found.remove(atOffsets: $0) }
            }
            .navigationTitle("\(kind.title) ที่พบ (\(found.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { showFound = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ code: String) {
        guard !code.isEmpty else { return }
        if existing.contains(code) {
            flash("\(code) ถูกบันทึกไว้แล้ว")
            return
        }
        guard !found.contains(code) else { return }
        found.append(code)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveFound() {
        for serial in found {
            let device = ScannedDevice(kind: kind, serial: serial, scannedBy: userName)
            context.insert(device)
            device.job = job
        }
        try? context.save()
        flash("บันทึก \(kind.title) \(found.count) รายการ")
        found = []
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func flash(_ text: String) {
        withAnimation { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if message == text { message = nil } }
        }
    }
}

private struct ScanFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.6, 520)
            let h = w * 0.6
            let rect = CGRect(x: (geo.size.width - w) / 2, y: (geo.size.height - h) / 2, width: w, height: h)
            Path { p in
                let l: CGFloat = 40
                for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                         (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                         (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                         (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
                    p.addLine(to: corner)
                    p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
                }
            }
            .stroke(Theme.primaryLight, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        .ignoresSafeArea()
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode()],
                                                   qualityLevel: .accurate,
                                                   recognizesMultipleItems: true,
                                                   isHighFrameRateTrackingEnabled: false,
                                                   isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onFound(payload)
                }
            }
        }
    }
}

private struct ScanTipsView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(String, String)] = [
        ("sun.max", "สแกนในที่มีแสงเพียงพอ หลีกเลี่ยงแสงสะท้อนบนฉลาก"),
        ("viewfinder", "ให้บาร์โค้ดอยู่ภายในกรอบ ห่างจากกล้องประมาณ 15–30 ซม."),
        ("square.grid.3x3", "เลือกประเภทอุปกรณ์ให้ถูกต้องก่อนกดบันทึก"),
        ("rectangle.stack", "สแกนได้หลายบาร์โค้ดพร้อมกัน ตรวจสอบรายการก่อนกดยืนยัน"),
        ("photo", "หากสแกนสดไม่ได้ ให้ถ่ายรูปฉลากแล้วเลือกจากคลังภาพ"),
    ]

    var body: some View {
        NavigationStack {
            List(tips, id: \.1) { tip in
                Label(tip.1, systemImage: tip.0).padding(.vertical, 4)
            }
            .navigationTitle("คำแนะนำในการสแกนอุปกรณ์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เข้าใจแล้ว") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct ScanHistoryView: View {
    @Query(sort: \ScannedDevice.scannedAt, order: .reverse) private var devices: [ScannedDevice]
    @State private var search = ""

    var body: some View {
        List {
            ForEach(devices.filter { search.isEmpty || $0.serial.localizedCaseInsensitiveContains(search) || ($0.job?.matches(search) ?? false) }) { device in
                HStack(spacing: 12) {
                    Image(systemName: device.kind.symbol).foregroundStyle(Theme.primary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.serial).font(.body.monospaced())
                        Text("\(device.kind.title) · \(device.job?.code ?? "-") · \(device.job?.projectName ?? "")")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(device.scannedAt.thaiShort).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .searchable(text: $search, prompt: "ค้นหาซีเรียลหรือโครงการ")
        .navigationTitle("ประวัติการสแกน")
    }
}
