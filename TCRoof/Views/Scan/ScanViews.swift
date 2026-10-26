import SwiftUI
import TCRoofUI
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var filtered: [Job] {
        jobs.filter { window.overlaps($0.installInterval) && $0.matches(search) }
    }

    var body: some View {
        if sizeClass == .compact { PhoneScanList() } else { padList }
    }

    /// iPad; the phone has `PhoneScanList`.
    private var padList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QueueFilterBar(listTitle: "รายการงานติดตั้ง", prefix: "คิวติดตั้ง", window: $window, search: $search, count: filtered.count)
                if filtered.isEmpty {
                    TCEmptyState("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนตัวกรองหรือคำค้นหา"))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            TCNavBar(title: "สแกนอุปกรณ์", trail: ["หน้าหลัก"], current: "สแกนอุปกรณ์") {
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            TCFab("barcode.viewfinder", accessibilityLabel: "สแกนอุปกรณ์", gradient: Theme.tealGradient) { showPicker = true }
                .tcFabPlacement(compact: isPhone)
        }
        .toolbar(.hidden, for: .navigationBar)
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
        JobCardStrip(key: "แผงที่สแกน", value: "\(panels)/\(job.estimatedPanels)" + (others > 0 ? " | อุปกรณ์อื่น \(others)" : ""),
                     progress: job.estimatedPanels > 0 ? Double(panels) / Double(job.estimatedPanels) : nil)
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var pendingDelete: ScannedDevice?

    /// White count cards (docs/ui/components), then the serials of each kind with a delete button.
    private var pad: Bool { sizeClass != .compact }

    var body: some View {
        PadForm(maxWidth: 1100) {
            Text("\(job.code) | \(job.projectName)").font(.sarabun(12.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(DeviceKind.allCases) { kind in
                    let count = job.devices.filter { $0.kind == kind }.count
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: kind.symbol).font(.sarabun(22, relativeTo: .title2)).foregroundStyle(Theme.primary)
                        Text(kind.title).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                        Text(kind == .panel ? "\(count) / \(job.estimatedPanels)" : "\(count)")
                            .font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(pad ? 16 : 12)
                    .tcCard()
                }
            }

            ForEach(DeviceKind.allCases) { kind in
                let items = job.devices.filter { $0.kind == kind }.sorted { $0.scannedAt > $1.scannedAt }
                if !items.isEmpty {
                    PadSection("\(kind.title) (\(items.count))") {
                        ForEach(items) { device in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.serial).font(.body.monospaced()).textSelection(.enabled)
                                    Text("\(device.scannedAt.thaiShort) | \(device.scannedBy)")
                                        .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                                PadRowButton("ลบ \(device.serial)", systemImage: "trash", destructive: true) { pendingDelete = device }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("ลบซีเรียลนี้?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { device in
            Button("ลบ \(device.serial)", role: .destructive) { context.delete(device); pendingDelete = nil }
        }
        .navigationTitle("อุปกรณ์ที่ติดตั้ง")
        // inline on the phone: the large title drew over the job line while collapsing
        .navigationBarTitleDisplayMode(isPhone ? .inline : .automatic)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showManual = true } label: { Label("พิมพ์ซีเรียล", systemImage: "keyboard") }
                Button { showScanner = true } label: { Label("สแกน", systemImage: "barcode.viewfinder") }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .tcPadNavBar("อุปกรณ์ที่ติดตั้ง", trail: ["หน้าหลัก", job.code]) {
            HStack(spacing: 12) {
                TCButton("พิมพ์ซีเรียล", systemImage: "keyboard", kind: .secondary) { showManual = true }
                TCButton("สแกน", systemImage: "barcode.viewfinder") { showScanner = true }
            }
        }
        .fullScreenCover(isPresented: $showScanner) { ScannerView(job: job) }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                PadForm(maxWidth: 560) {
                    PadSection {
                        PadPicker("ประเภทอุปกรณ์", selection: $manualKind) {
                            ForEach(DeviceKind.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("Serial No.", text: $manualSerial)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
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
                // on the black camera page, so not `TCEmptyState` (its ink is navy)
                VStack(spacing: 10) {
                    Image(systemName: "camera.metering.unknown").font(.system(size: 40, weight: .semibold)).accessibilityHidden(true)
                    Text("กล้องสแกนไม่พร้อมใช้งาน").font(.sarabun(17, .bold, relativeTo: .headline))
                    Text("อุปกรณ์นี้ไม่รองรับการสแกนสด เลือกรูปจากคลังภาพหรือพิมพ์ซีเรียลแทน").font(.sarabun(14, relativeTo: .subheadline))
                }
                .multilineTextAlignment(.center).foregroundStyle(Theme.onMedia).padding(.horizontal, 24)
            }
            ScanFrame().allowsHitTesting(false)
            VStack(spacing: 16) {
                topBar
                kindPicker
                Spacer()
                if let message {
                    Text(message)
                        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.onMedia)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.teal, in: Capsule())
                        .transition(.opacity)
                }
                Button { showTips = true } label: {
                    Label("คำแนะนำในการสแกนอุปกรณ์", systemImage: "doc.text.magnifyingglass")
                        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                        .underline()
                        .foregroundStyle(Theme.onMedia)
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
                Text(job.code).font(.sarabun(17, .semibold, relativeTo: .headline))
                Text(job.projectName).font(.sarabun(12, relativeTo: .caption))
            }
            .foregroundStyle(Theme.onMedia)
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
            .font(.sarabun(20, .bold, relativeTo: .title3))
            .foregroundStyle(Theme.navy)
            .frame(width: 48, height: 48)
            .background(Theme.surface.opacity(0.9), in: Circle())
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeviceKind.allCases) { option in
                    Button { kind = option } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(kind == option ? Theme.onPrimary : Theme.navy)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(kind == option ? Theme.primary : Theme.surface.opacity(0.9), in: Capsule())
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
                        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                }
            } else {
                Text("เล็งกล้องไปที่บาร์โค้ด\(kind.title)")
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(action: saveFound) {
                Image(systemName: "checkmark")
                    .font(.sarabun(20, .bold, relativeTo: .title3))
                    .foregroundStyle(Theme.onMedia)
                    .frame(width: 48, height: 48)
                    .background(found.isEmpty ? Theme.muted : Theme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(found.isEmpty)
            .accessibilityLabel("บันทึก \(found.count) รายการ")
        }
        .padding(14)
        .frame(maxWidth: 640)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var foundList: some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection {
                    ForEach(found, id: \.self) { code in
                        HStack {
                            Text(code).font(.body.monospaced())
                            Spacer(minLength: 0)
                            PadRowButton("เอา \(code) ออก", systemImage: "xmark.circle", destructive: true) { found.removeAll { $0 == code } }
                        }
                    }
                }
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
            PadForm(maxWidth: 560) {
                PadSection {
                    ForEach(tips, id: \.1) { tip in
                        Label { Text(tip.1) } icon: { Image(systemName: tip.0).foregroundStyle(Theme.primary) }
                    }
                }
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
    @FocusState private var searching: Bool

    var body: some View {
        PadForm {
            // iPad searches from its nav bar
            if isPhone { PhoneSearchField(text: $search, focused: $searching, prompt: "ค้นหาซีเรียลหรือโครงการ") }
            PadSection {
                ForEach(devices.filter { search.isEmpty || $0.serial.localizedCaseInsensitiveContains(search) || ($0.job?.matches(search) ?? false) }) { device in
                    HStack(spacing: 12) {
                        Image(systemName: device.kind.symbol).foregroundStyle(Theme.primary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.serial).font(.body.monospaced())
                            Text("\(device.kind.title) | \(device.job?.code ?? "-") | \(device.job?.projectName ?? "")")
                                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(device.scannedAt.thaiShort).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .navigationTitle("ประวัติการสแกน")
        .tcPadNavBar("ประวัติการสแกน", trail: ["หน้าหลัก", "สแกนอุปกรณ์"]) {
            TCBarSearchField(text: $search, prompt: "ค้นหาซีเรียลหรือโครงการ")
        }
    }
}
