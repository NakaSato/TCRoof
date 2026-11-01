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
                    Text(InstallTrackingPage.avatarLetters(name.isEmpty ? email : name, count: 2)).font(.sarabunFixed(30, .bold))
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
