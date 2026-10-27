import SwiftUI
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// The sheets of iPad `ตั้งค่าโครงการ`: the text editor and work time (state 09), the person (13), a drawing's history
/// (11) and the upload (12). The editors the iPhone opens (`JobAccessCard`, `RoutineSettingsSheet`,
/// `StationFactsSheet`) are called as they are.
extension InstallTrackingPage {
    @ViewBuilder func padSheetView(_ s: PadSettingsSheet) -> some View {
        switch s {
        case .text(let f):
            PadTextSheet(title: f.title, value: padText(f)) { setPadText(f, $0) }
        case .workTime:
            PadWorkTimeSheet(start: settingsShown.workStart, end: settingsShown.workEnd) { start, end in
                settingsDraft.workStart = start
                settingsDraft.workEnd = end
            }
        case .person(let email, let role):
            PadPersonSheet(email: email, name: personName(email), role: role,
                           canRemove: permissions.can(role.capability, on: job.access)) { removePerson(email, role) }
        case .access:
            NavigationStack {
                PhoneAccessScreen(job: job)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { padSheet = nil }.bold() } }
            }
        case .routine:
            RoutineSettingsSheet(job: job)
        case .station:
            StationFactsSheet(job: job)
        case .history(let id):
            if let d = padDrawings.first(where: { $0.id == id }) {
                DrawingHistorySheet(drawing: d, canUpload: uploadsDrawings, url: drawingURL) { padSheet = .upload(id) }
            }
        case .upload(let id):
            DrawingUploadSheet(drawings: padDrawings, picked: id, prefill: Self.prefillUpload) { upload, data in
                uploadDrawing(upload, data: data)
            }
        }
    }

    private func padText(_ f: SettingsDraft.Field) -> String {
        let s = settingsShown
        switch f {
        case .contractName: return s.contractName
        case .contractor: return s.contractor
        case .employer: return s.employer
        case .inspector: return s.inspector
        case .workTime, .weekdays, .sellsPower: return ""
        }
    }

    private func setPadText(_ f: SettingsDraft.Field, _ v: String) {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        switch f {
        case .contractName: settingsDraft.contractName = t
        case .contractor: settingsDraft.contractor = t
        case .employer: settingsDraft.employer = t
        case .inspector: settingsDraft.inspector = t
        case .workTime, .weekdays, .sellsPower: break
        }
    }

    #if DEBUG
    /// `-installSettingsState upload` opens the upload with a file and a reason already given.
    static var prefillUpload: Bool { Debug.demo && Debug.settingsState == "upload" }
    nonisolated(unsafe) private static var settingsStateApplied = false

    /// `-installSettingsState edit|dirty|history|upload|person` with `-installDemo YES`: states 09–13, in memory.
    func applySettingsState() {
        guard Debug.demo, let state = Debug.settingsState, !Self.settingsStateApplied else { return }
        Self.settingsStateApplied = true
        switch state {
        case "edit":
            padCategory = .header
            padSheet = .text(.contractName)
        case "dirty":
            padCategory = .routine
            settingsDraft.weekdays = Self.weekdayOptions[0].days
            settingsDraft.sellsPower = !padDemo.sellsPower
        case "history":
            padCategory = .drawings
            padSheet = padDemo.drawings.max { $0.revisions.count < $1.revisions.count }.map { .history($0.id) }
        case "upload":
            padCategory = .drawings
            padSheet = .upload(padDemo.drawings.max { $0.revisions.count < $1.revisions.count }?.id)
        case "person":
            padCategory = .team
            padSheet = padDemo.supervisor.map { .person($0, .supervisor) }
        default: break
        }
    }
    #else
    static var prefillUpload: Bool { false }
    #endif
}

#if DEBUG
extension PadSettingsDemo {
    /// The board's station (docs/ui/install-tracking-ipad-settings/assets/sample-data.json), dated back from today.
    static func board() -> PadSettingsDemo {
        var d = PadSettingsDemo()
        d.settings.contractName = "จ้างติดตั้งระบบผลิตไฟฟ้าจากพลังงานแสงอาทิตย์บนหลังคา (Solar Rooftop) (ตัวอย่าง)"
        d.settings.employer = "การประปาส่วนภูมิภาค"
        d.settings.workStart = 8 * 60
        d.settings.workEnd = 18 * 60
        d.settings.inspector = "นายประเสริฐ มั่นคง"
        d.settings.siteEngineer = "นายวีระ ทองดี"
        d.branch = "กปภ.สาขาบ้านโป่ง | กปภ.ข.7"
        d.supervisor = "somchai@tcroof.test"
        d.team = ["weera@tcroof.test", "preeya@tcroof.test"]
        d.externals = ["anucha@contractor-a.test"]
        d.names = ["somchai@tcroof.test": "นายสมชาย ใจดี", "weera@tcroof.test": "นายวีระ ทองดี",
                   "preeya@tcroof.test": "น.ส.ปรียา แสงทอง", "anucha@contractor-a.test": "ผู้รับเหมา A | คุณอนุชา"]
        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now }
        func rev(_ r: String, _ n: Int, _ reason: String, _ by: String, _ id: String, _ ext: String) -> StationDrawing.Revision {
            .init(rev: r, date: day(n), reason: reason, by: by, file: StationDrawings.fileName(id: id, rev: r, ext: ext))
        }
        d.drawings = [
            StationDrawing(id: "E-01", title: "Single Line Diagram (SLD)", ext: "pdf",
                           revisions: [rev("00", 17, "ออกแบบครั้งแรก", "weera@tcroof.test", "E-01", "pdf"),
                                       rev("01", 9, "เปลี่ยนเบรกเกอร์ AC รวมตามผลสำรวจ", "weera@tcroof.test", "E-01", "pdf")]),
            StationDrawing(id: "A-01", title: "ผังแผงบนหลังคา (Roof layout)", ext: "dwg",
                           revisions: [rev("00", 17, "ออกแบบครั้งแรก", "weera@tcroof.test", "A-01", "dwg"),
                                       rev("01", 11, "ตัดแผงที่เงาถังน้ำบัง", "weera@tcroof.test", "A-01", "dwg"),
                                       rev("02", 5, "อนุมัติก่อสร้าง (IFC)", "somchai@tcroof.test", "A-01", "pdf")]),
            StationDrawing(id: "A-02", title: "ผังบริเวณ (Site plan)", ext: "pdf",
                           revisions: [rev("00", 17, "จากรายงานสำรวจ A2", "weera@tcroof.test", "A-02", "pdf")]),
            StationDrawing(id: "S-01", title: "โครงสร้างรองรับแผง (Mounting)", ext: "pdf",
                           revisions: [rev("00", 15, "แบบผู้ผลิตราง", "anucha@contractor-a.test", "S-01", "pdf")])]
        return d
    }
}
#endif

// MARK: - Sheets

/// A form sheet `ยกเลิก | <title> | เสร็จ`.
private struct PadFormSheet<Content: View>: View {
    let title: String
    var done = "เสร็จ"
    var canDone = true
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) { content() }.padding(24) }
                .background(Theme.groupedPage.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(done) { onDone(); dismiss() }.bold().disabled(!canDone).accessibilityIdentifier("padSheet.done")
                    }
                }
        }
    }
}

/// State 09: one text, into the draft on `เสร็จ`.
struct PadTextSheet: View {
    let title: String
    let onDone: (String) -> Void
    @State private var text: String

    init(title: String, value: String, onDone: @escaping (String) -> Void) {
        self.title = title
        self.onDone = onDone
        _text = State(initialValue: value)
    }

    var body: some View {
        PadFormSheet(title: title, onDone: { onDone(text) }) {
            TCTextField(title, text: $text, focused: true).accessibilityIdentifier("padSheet.text")
        }
    }
}

/// The site's working hours, into the draft on `เสร็จ`.
struct PadWorkTimeSheet: View {
    let onDone: (Int, Int) -> Void
    @State private var start: Date
    @State private var end: Date

    init(start: Int, end: Int, onDone: @escaping (Int, Int) -> Void) {
        self.onDone = onDone
        _start = State(initialValue: Self.date(start))
        _end = State(initialValue: Self.date(end))
    }

    private static func date(_ minutes: Int) -> Date {
        RoutineReport.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private static func minutes(_ d: Date) -> Int {
        let c = RoutineReport.calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        PadFormSheet(title: "เวลาทำงาน", canDone: Self.minutes(end) > Self.minutes(start), onDone: { onDone(Self.minutes(start), Self.minutes(end)) }) {
            VStack(spacing: 0) {
                DatePicker("เริ่มงาน", selection: $start, displayedComponents: .hourAndMinute).frame(minHeight: 56)
                Divider()
                DatePicker("เลิกงาน", selection: $end, displayedComponents: .hourAndMinute).frame(minHeight: 56)
            }
            .font(.sarabunFixed(17))
            .environment(\.timeZone, RoutineReport.calendar.timeZone)
            .padding(.horizontal, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("ใช้เป็นค่าเริ่มของรายงานแต่ละวัน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// State 13: who the person is on this job, `ส่งอีเมล`, and `นำออกจากงานนี้` for whoever `JobAccessCard` lets assign them.
struct PadPersonSheet: View {
    let email: String
    let name: String
    let role: PadPersonRole
    let canRemove: Bool
    let onRemove: () -> Void
    @State private var asking = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(String((name.isEmpty ? email : name).prefix(2)).uppercased()).font(.sarabunFixed(30, .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 84, height: 84).background(InstallTrackingPage.ink(role.tone), in: Circle())
                        .accessibilityHidden(true)
                    VStack(spacing: 2) {
                        Text(name.isEmpty ? email : name).font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                        if !name.isEmpty { Text(email).font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted) }
                    }
                    card {
                        HStack {
                            Text("บทบาท").foregroundStyle(Theme.navy)
                            Spacer()
                            Text(role.chip).foregroundStyle(Theme.inkMuted)
                        }
                        .font(.sarabunFixed(17)).padding(.horizontal, 20).frame(minHeight: 56)
                    }
                    card {
                        Button { if let url = URL(string: "mailto:\(email)") { openURL(url) } } label: {
                            Text("ส่งอีเมล").frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(TCButtonStyle(.text, size: .card))
                        if canRemove {
                            Divider()
                            Button(role: .destructive) { asking = true } label: {
                                Text("นำออกจากงานนี้").frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(TCButtonStyle(.danger, size: .card))
                            .accessibilityIdentifier("padSheet.remove")
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.groupedPage.ignoresSafeArea())
            .navigationTitle(role.section)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() }.bold() } }
            .alert("นำ \(name.isEmpty ? email : name) ออกจากงานนี้?", isPresented: $asking) {
                Button("นำออก", role: .destructive) { onRemove(); dismiss() }
                Button("ยกเลิก", role: .cancel) {}
            } message: {
                Text(role == .external ? "ผู้รับเหมาจะไม่เห็นงานนี้อีก" : "งานนี้จะไม่อยู่ใน งานของฉัน ของคนนี้")
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// State 11: a drawing's revisions, newest first, each opened from this device or Drive.
struct DrawingHistorySheet: View {
    let drawing: StationDrawing
    let canUpload: Bool
    let url: (StationDrawing.Revision) -> URL?
    let upload: () -> Void
    @State private var preview: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(drawing.revisions.reversed().enumerated()), id: \.element.rev) { i, r in
                        revisionRow(r, latest: i == 0)
                    }
                }
                .padding(24)
            }
            .background(Theme.groupedPage.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if canUpload {
                    Button { upload() } label: { Text("อัปโหลด REV \(drawing.nextRev)").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.primary, size: .page))
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .background(Theme.surface)
                        .accessibilityIdentifier("padSheet.uploadNext")
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(drawing.id).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                        Text(drawing.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() }.bold() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .quickLookPreview($preview)
        }
    }

    private func revisionRow(_ r: StationDrawing.Revision, latest: Bool) -> some View {
        let link = url(r)
        return HStack(alignment: .top, spacing: 14) {
            InstallTrackingPage.revChip(r.rev, latest: latest).frame(width: 72, alignment: .leading)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.reason.isEmpty ? "ออกแบบครั้งแรก" : r.reason).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    Text([ThaiFormat.numericDate.string(from: r.date), TeamDirectory.shared.person(r.by)?.name ?? r.by, r.file]
                        .filter { !$0.isEmpty }.joined(separator: " | "))
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(latest ? "ล่าสุด | ใช้งาน" : "แทนที่แล้ว").font(.sarabunFixed(13, .bold))
                    .foregroundStyle(latest ? Theme.successInk : Theme.inkMuted)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(latest ? Theme.successSoft : Theme.segmentTrack, in: Capsule())
                    .fixedSize()
                Button("เปิด") {
                    guard let link else { return }
                    if link.isFileURL { preview = link } else { openURL(link) }
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .disabled(link == nil)
                .accessibilityHint(link == nil ? "ไฟล์ยังไม่อยู่ในเครื่องนี้และยังไม่ขึ้น Drive" : "")
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
    }
}

/// State 12: a drawing (or a new one), its file from Files or the document camera, the REV it becomes, and the reason
/// from REV 01. `อัปโหลด REV nn` stays off until it can go (`StationDrawings.problem`).
struct DrawingUploadSheet: View {
    let drawings: [StationDrawing]
    let onUpload: (StationDrawings.Upload, Data) -> Void
    @State private var upload: StationDrawings.Upload
    @State private var file: (data: Data, name: String)?
    @State private var importing = false
    @State private var scanning = false
    @Environment(\.dismiss) private var dismiss

    /// DWG has no system type; the Files picker matches it by its extension.
    private static let types: [UTType] = [.pdf, .jpeg, .png, UTType(filenameExtension: "dwg", conformingTo: .data) ?? .data]

    init(drawings: [StationDrawing], picked: String?, prefill: Bool, onUpload: @escaping (StationDrawings.Upload, Data) -> Void) {
        self.drawings = drawings
        self.onUpload = onUpload
        var u = StationDrawings.Upload(drawing: picked ?? drawings.first?.id)
        var f: (Data, String)?
        #if DEBUG
        if prefill {
            f = (DocumentCamera.stubPDF(), "แบบตัวอย่าง.pdf")
            u.ext = "pdf"
            u.reason = "ย้ายแนวราง (ตัวอย่าง)"
        }
        #endif
        _upload = State(initialValue: u)
        _file = State(initialValue: f)
    }

    private var rev: String { StationDrawings.rev(of: upload, in: drawings) }
    private var problem: String? { StationDrawings.problem(upload, in: drawings) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    picker
                    if upload.drawing == nil { newFields }
                    revInfo
                    fileZone
                    reasonField
                    if let problem { Text(problem).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).accessibilityIdentifier("padSheet.problem") }
                }
                .padding(24)
            }
            .background(Theme.groupedPage.ignoresSafeArea())
            .navigationTitle("อัปโหลดแบบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("อัปโหลด REV \(rev)") {
                        guard let file else { return }
                        onUpload(upload, file.data)
                        dismiss()
                    }
                    .bold().disabled(problem != nil || file == nil)
                    .accessibilityIdentifier("padSheet.uploadConfirm")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { imported($0) }
            .fullScreenCover(isPresented: $scanning) {
                DocumentCamera { pdf in
                    if let pdf { set(pdf, name: "สแกนแบบ \(Date.now.formatted(date: .omitted, time: .shortened)).pdf") }
                    scanning = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func heading(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(text).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
            if required { Text("*").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.danger) }
        }
    }

    private func chip(_ title: String, on: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: action) {
            Text(title).font(.sarabunFixed(15, on ? .bold : .regular)).foregroundStyle(on || dashed ? Theme.primary : Theme.navy)
                .lineLimit(1).padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Theme.optionSelected : Theme.surface, in: shape)
                .overlay(shape.strokeBorder(on ? Theme.primary : Theme.borderControl,
                                            style: StrokeStyle(lineWidth: on ? 2 : 1, dash: dashed ? [4, 3] : [])))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("แบบที่จะอัปโหลด")
            FlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(drawings) { d in
                    chip(d.id + " " + d.title, on: upload.drawing == d.id) { upload.drawing = d.id }
                        .accessibilityIdentifier("padSheet.pick.\(d.id)")
                }
                chip("+ แบบใหม่", on: upload.drawing == nil, dashed: true) { upload.drawing = nil }
                    .accessibilityIdentifier("padSheet.pick.new")
            }
        }
    }

    private var newFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("ชื่อแบบ", required: true)
            TCTextField("เช่น ผังแผงบนหลังคา", text: $upload.newTitle).accessibilityIdentifier("padSheet.newTitle")
            heading("รหัสแบบ")
            TCTextField("เช่น A-03 (ว่างไว้ แอปตั้งให้)", text: $upload.newID)
        }
    }

    private var revInfo: some View {
        let from = upload.drawing.flatMap { id in drawings.first { $0.id == id } }?.latest
        return HStack(spacing: 10) {
            Text("จะบันทึกเป็น").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            InstallTrackingPage.revChip(rev)
            Text(from.map { "ต่อจาก REV \($0.rev) (\(ThaiFormat.numericDate.string(from: $0.date))) | REV เดิมย้ายไปประวัติ" } ?? "แบบใหม่เริ่มที่ REV 00")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fileZone: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 12) {
            if let file {
                Label(file.name, systemImage: "doc").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("padSheet.fileName")
            } else {
                Text("PDF | DWG | JPG / PNG | ถ่ายรูปแบบ").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 12) {
                Button { importing = true } label: { Label(file == nil ? "เลือกไฟล์" : "เปลี่ยนไฟล์", systemImage: "folder") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Button { scan() } label: { Label("ถ่ายรูปแบบ", systemImage: "doc.viewfinder") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    .disabled(!DocumentCamera.isAvailable)
                    .accessibilityIdentifier("padSheet.scan")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(file == nil ? Theme.surface : Theme.successSoft, in: shape)
        .overlay(shape.strokeBorder(file == nil ? Theme.borderControl : Theme.successInk, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("เหตุผลการแก้ไข", required: StationDrawing.needsReason(rev))
            TCTextField(StationDrawing.needsReason(rev) ? "เช่น ย้ายแนวราง" : "ไม่บังคับสำหรับ REV 00", text: $upload.reason)
                .accessibilityIdentifier("padSheet.reason")
        }
    }

    private func scan() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "pwaDocsCameraStub") {
            set(DocumentCamera.stubPDF(), name: "สแกนตัวอย่าง.pdf")
            return
        }
        #endif
        scanning = true
    }

    private func set(_ data: Data, name: String) {
        file = (data, name)
        upload.ext = (name as NSString).pathExtension.lowercased()
    }

    private func imported(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        set(data, name: url.lastPathComponent)
    }
}
