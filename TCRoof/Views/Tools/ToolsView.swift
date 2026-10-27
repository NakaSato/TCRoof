import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// The measuring-tool register, kept on this device (`Documents/Tools/instruments.json`). Not synced: a shared
/// register needs its own Firestore collection and rule. Its tools are borrowed and returned in the synced log
/// (`ToolLogCard`), which keeps each tool's name, so the log reads the same on a device without the register.
@Observable final class InstrumentStore {
    static let shared = InstrumentStore()
    private(set) var all: [Instrument] = []

    private static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tools", isDirectory: true).appendingPathComponent("instruments.json")
    }

    private init() {
        #if DEBUG
        // `-toolsDemo YES`: three sample tools (one overdue, one due soon), not saved
        if UserDefaults.standard.bool(forKey: "toolsDemo") {
            all = [Instrument(id: "demo1", name: "Fluke 376 FC", code: "TCR-MT-01", kind: "แคลมป์มิเตอร์", calibrationDue: Date.now.adding(days: -10)),
                   Instrument(id: "demo2", name: "Fluke 1587 FC", code: "TCR-MT-02", kind: "เครื่องวัดฉนวน", calibrationDue: Date.now.adding(days: 7)),
                   Instrument(id: "demo3", name: "DJI Mavic 3T", code: "TCR-DR-02", kind: "โดรนถ่ายภาพความร้อน", calibrationDue: Date.now.adding(days: 76))]
            return
        }
        #endif
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([Instrument].self, from: data) { all = saved }
    }

    /// Tools due for calibration within 30 days or past it: the count on the iPhone settings row `เครื่องมือวัด`.
    func dueCount(on now: Date = .now) -> Int { Instrument.dueCount(all, on: now) }

    func save(_ tool: Instrument) {
        if let i = all.firstIndex(where: { $0.id == tool.id }) { all[i] = tool } else { all.append(tool) }
        write()
    }

    func delete(_ id: String) {
        all.removeAll { $0.id == id }
        write()
    }

    private func write() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "toolsDemo") { return }
        #endif
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: Self.file, options: .atomic) }
    }
}

/// `เครื่องมือวัด`: the register of measuring tools with each one's calibration date, overdue first. On iPhone,
/// under the settings sheet's `เครื่องมือวัด` row, it also carries the modules that have no tab of their own (the
/// plan calendar, scan, install records).
struct ToolsView: View {
    /// The quick action of a tools notification that opened this screen (`คืนอุปกรณ์`, `ดูคิว`…).
    var request: String? = nil
    /// The iPhone tab root: module rows on top.
    var modules: [AppModule] = []

    @State private var store = InstrumentStore.shared
    @Environment(\.permissions) private var permissions
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: Instrument?
    @Query(sort: \Job.installStart) private var jobs: [Job]

    private var installChip: String? {
        jobs.lazy.compactMap { j in j.installDay(on: .now).map { "Day \($0)/\(j.installDays)" } }.first
    }

    /// The tool and vehicle log is the team's (`ToolLogCard`, `VehicleCard`).
    private var showsLog: Bool { permissions.role != .external }

    var body: some View {
        ScrollView {
            if sizeClass == .regular && showsLog {
                // iPad (the board's iPadToolsHub): the log on the left, the register and the vehicles on the right
                VStack(alignment: .leading, spacing: 12) {
                    moduleRows
                    HStack(alignment: .top, spacing: 16) {
                        ToolLogCard().frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) { header; register }.cardStyle()
                            VehicleCard()
                        }
                        .frame(width: 420)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 110)
                .frame(maxWidth: 1320).frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    moduleRows
                    if showsLog {
                        ToolLogCard().padding(.top, 4)
                        VehicleCard().padding(.top, 4)
                    }
                    header.padding(.top, modules.isEmpty && !showsLog ? 0 : 12)
                    register
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .navigationTitle("เครื่องมือวัด")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tcPadNavBar("เครื่องมือวัด", trail: ["หน้าหลัก"])
        .sheet(item: $editing) { tool in
            InstrumentForm(tool: tool, isNew: !store.all.contains { $0.id == tool.id }, save: store.save, delete: store.delete)
        }
    }

    @ViewBuilder private var moduleRows: some View {
        // the travel log is the team's own; contractors claim elsewhere
        ForEach(modules.filter { $0 != .travel || permissions.role != .external }) { module in
            NavigationLink { module.destination } label: {
                ModuleRow(size: .phone, module: module, chip: module.chip(surveyToday: 0, installDay: installChip))
            }
            .buttonStyle(.plain)
        }
        if let request, !request.isEmpty {
            Text("จากการแจ้งเตือน: \(request)").font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.primarySoft, in: Capsule())
        }
    }

    private var header: some View {
        let due = store.dueCount()
        return HStack(spacing: 8) {
            Text("ทะเบียนเครื่องมือวัด").font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            if due > 0 { TCStatusChip("ต้องสอบเทียบ \(due)", kind: .overdue) }
            Spacer(minLength: 8)
            TCButton("เพิ่ม", systemImage: "plus", kind: .secondary, size: .card) { editing = Instrument(name: "") }
        }
    }

    @ViewBuilder private var register: some View {
        if store.all.isEmpty {
            Text("ยังไม่มีเครื่องมือในทะเบียน แตะ เพิ่ม เพื่อบันทึกเครื่องและวันครบกำหนดสอบเทียบ")
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 88).multilineTextAlignment(.center)
        } else {
            ForEach(Instrument.sorted(store.all, on: .now)) { tool in row(tool) }
        }
    }

    private func row(_ tool: Instrument) -> some View {
        let state = tool.calibration(on: .now)
        let kind: TCStatusChip.Kind? = switch state {
        case .none: nil
        case .ok: .ok
        case .dueSoon: .pending
        case .overdue: .overdue
        }
        let due = tool.calibrationDue.map { "สอบเทียบครบ " + ThaiFormat.short.string(from: $0) }
        let overdue = if case .overdue = state { true } else { false }
        return TCListRow(symbol: "gauge.with.dots.needle.50percent", title: tool.name, code: tool.code.isEmpty ? nil : tool.code,
                         subtitle: [tool.kind, due ?? state.title].filter { !$0.isEmpty }.joined(separator: " | "),
                         status: kind.map { (state.title, $0) }, overdue: overdue) { editing = tool }
    }
}

/// Add or edit one tool of the register.
private struct InstrumentForm: View {
    @State var tool: Instrument
    let isNew: Bool
    let save: (Instrument) -> Void
    let delete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasDue = false
    @State private var due = Date.now.adding(months: 12)

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection {
                    TextField("ชื่อเครื่อง เช่น Fluke 376 FC", text: $tool.name)
                    TextField("รหัสเครื่อง เช่น TCR-MT-01", text: $tool.code)
                    TextField("ประเภท เช่น แคลมป์มิเตอร์", text: $tool.kind)
                    TextField("Serial", text: $tool.serial)
                }
                PadSection("สอบเทียบ") {
                    Toggle("ต้องสอบเทียบ", isOn: $hasDue).tint(Theme.primary)
                    if hasDue { DatePicker("ครบกำหนด", selection: $due, displayedComponents: .date) }
                } footer: {
                    Text("แท็บเครื่องมือจะขึ้นตัวเลขเมื่อเหลือไม่เกิน \(Instrument.warningDays) วัน หรือเลยกำหนด")
                }
                if !isNew {
                    PadSection {
                        Button("ลบเครื่องนี้", role: .destructive) { delete(tool.id); dismiss() }
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle(isNew ? "เพิ่มเครื่องมือ" : "แก้ไขเครื่องมือ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        tool.calibrationDue = hasDue ? due : nil
                        save(tool)
                        dismiss()
                    }
                    .bold().disabled(tool.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                hasDue = tool.calibrationDue != nil || isNew
                if let d = tool.calibrationDue { due = d }
            }
        }
    }
}
