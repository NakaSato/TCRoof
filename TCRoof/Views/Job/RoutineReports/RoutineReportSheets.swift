import SwiftUI
import TCRoofUI
import TCRoofCore

// MARK: - + งาน

/// task → locations (multi) → description; one line per location (§4.2 §5).
struct AddWorkSheet: View {
    let locations: [String]
    let plan: [MasterSchedule.PlannedTask]?
    let onAdd: ([RoutineReport.ProgressLine]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// nil = งานอื่น.
    @State private var task: MasterSchedule.Task? = .structure
    @State private var picked: Set<String> = []
    @State private var extra: [String] = []
    @State private var typed = ""
    @State private var description = ""

    /// The site's tasks: construction and commissioning, those planned around today first.
    private var tasks: [MasterSchedule.Task] {
        let site = MasterSchedule.Task.allCases.filter { $0.part != .permit }
        guard let plan else { return site }
        let now = Date()
        func active(_ t: MasterSchedule.Task) -> Bool {
            plan.first { $0.task == t }.map { p in (p.start ?? .distantFuture) <= now.adding(days: 7) && (p.end ?? .distantPast) >= now.adding(days: -7) } ?? false
        }
        return site.filter(active) + site.filter { !active($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("งาน MP") {
                    Picker("งาน", selection: $task) {
                        ForEach(tasks) { t in Text("\(t.code) \(t.title)").tag(Optional(t)) }
                        Text("งานอื่น").tag(MasterSchedule.Task?.none)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section {
                    ForEach(locations + extra, id: \.self) { l in
                        Button { if picked.contains(l) { picked.remove(l) } else { picked.insert(l) } } label: {
                            HStack {
                                Text(l).foregroundStyle(Theme.navy)
                                Spacer()
                                if picked.contains(l) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                            }
                            .frame(minHeight: touchMin)
                        }
                    }
                    HStack {
                        TextField("เพิ่มตำแหน่ง เช่น หลังคา 6", text: $typed)
                        Button("เพิ่ม") {
                            let l = typed.trimmingCharacters(in: .whitespaces)
                            if !l.isEmpty, !(locations + extra).contains(l) { extra.append(l) }
                            if !l.isEmpty { picked.insert(l) }
                            typed = ""
                        }
                    }
                } header: {
                    Text("ตำแหน่ง (เลือกได้หลายที่)")
                } footer: {
                    Text("หนึ่งบรรทัดต่อหนึ่งตำแหน่ง · ตั้งรายการตำแหน่งของสถานีได้ที่ ตั้งค่ารายงาน")
                }
                Section("รายละเอียด") {
                    TextField(task?.title ?? "รายละเอียดงาน", text: $description, axis: .vertical)
                }
            }
            .tcFormStyle()
            .navigationTitle("เพิ่มงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม") {
                        let places = (locations + extra).filter(picked.contains)
                        let d = description.trimmingCharacters(in: .whitespaces)
                        onAdd((places.isEmpty ? [""] : places).map { .init(task: task, description: d, location: $0) })
                        dismiss()
                    }
                    .disabled(task == nil && description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - ตรวจ & ลงนาม

struct DailySignSheet: View {
    let warnings: [RoutineReport.Warning]
    let onSign: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var engineer: String

    init(warnings: [RoutineReport.Warning], engineer: String, onSign: @escaping (String) -> Void) {
        self.warnings = warnings; self.onSign = onSign
        _engineer = State(initialValue: engineer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if warnings.isEmpty {
                        Label("ครบถ้วน พร้อมลงนาม", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.okText)
                    }
                    ForEach(warnings, id: \.self) { w in
                        Label(w.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.dangerText)
                    }
                } header: {
                    Text("ตรวจก่อนลงนาม")
                } footer: {
                    if !warnings.isEmpty { Text("ลงนามได้ แต่ควรแก้รายการด้านบนก่อน") }
                }
                Section("Site Engineer") {
                    TextField("ชื่อผู้ลงนาม", text: $engineer)
                }
                Section {
                    Text("ลงนามแล้วระบบจะสร้าง PDF เก็บในเอกสารโครงการ (อัปโหลดขึ้น Drive ได้จากหน้างาน) และอัปเดตความก้าวหน้าในแผน MP")
                        .font(.footnote).foregroundStyle(Theme.inkMuted)
                }
            }
            .tcFormStyle()
            .navigationTitle("ตรวจ & ลงนาม")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ลงนาม") { onSign(engineer.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .bold().disabled(engineer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Inspector

/// The Inspector's acknowledgement (R2) or approval (R1), typed in after the paper or LINE reply.
struct InspectorAckSheet: View {
    let title: String
    let onSave: (String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var date: Date

    init(title: String, name: String, date: Date, onSave: @escaping (String, Date) -> Void) {
        self.title = title; self.onSave = onSave
        _name = State(initialValue: name); _date = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("ชื่อ Inspector", text: $name)
                DatePicker("วันที่", selection: $date, displayedComponents: .date)
            }
            .tcFormStyle()
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { onSave(name.trimmingCharacters(in: .whitespaces), date); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Settings (§2.3)

/// The station facts the reports print, and the lists the daily report picks from.
struct RoutineSettingsSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @State private var s: RoutineReport.Settings
    @State private var holiday = Date()

    init(job: Job) {
        self.job = job
        _s = State(initialValue: job.routineSettings)
    }

    private static let weekdays = [(2, "จ."), (3, "อ."), (4, "พ."), (5, "พฤ."), (6, "ศ."), (7, "ส."), (1, "อา.")]

    var body: some View {
        NavigationStack {
            Form {
                Section("โครงการ") {
                    TextField("ชื่อสัญญา / โครงการ", text: $s.contractName, axis: .vertical)
                    TextField("ผู้ว่าจ้าง", text: $s.employer)
                    TextField("ผู้รับจ้าง", text: $s.contractor)
                    TextField("Site Engineer", text: $s.siteEngineer)
                    TextField("Inspector", text: $s.inspector)
                }
                ListEditor(title: "ตำแหน่งในสถานี", placeholder: "เช่น หลังคา 1, ถังน้ำใส 1, ห้องอินเวอร์เตอร์", items: $s.locations)
                if !s.locations.isEmpty {
                    Section {
                        NavigationLink {
                            KeyPlanEditor(job: job, settings: $s)
                        } label: {
                            let placed = s.locations.filter { s.keyPoint($0) != nil }.count
                            LabeledContent("ผังตำแหน่ง (Key plan)", value: "วางแล้ว \(placed)/\(s.locations.count)")
                        }
                    } footer: {
                        Text("วางตำแหน่งบนภาพสถานที่ (A2) ของแบบสำรวจ รายงานประจำวันจะแสดงจุดที่มีงานวันนี้เป็นสีแดง")
                    }
                    taskLocations
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(Self.weekdays, id: \.0) { d, label in
                            let on = s.workingWeekdays.contains(d)
                            Button(label) { if on { s.workingWeekdays.remove(d) } else { s.workingWeekdays.insert(d) } }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: touchMin)
                                .background(on ? Theme.primary : Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
                                .buttonStyle(.plain)
                        }
                    }
                    ForEach(s.holidays, id: \.self) { h in
                        Text(ISODate.date(h).map(RoutineReport.thaiDate) ?? h)
                    }
                    .onDelete { s.holidays.remove(atOffsets: $0) }
                    HStack {
                        DatePicker("วันหยุด", selection: $holiday, displayedComponents: .date)
                        Button("เพิ่ม") {
                            let k = RoutineReport.dayKey(holiday)
                            if !s.holidays.contains(k) { s.holidays.append(k); s.holidays.sort() }
                        }
                    }
                } header: {
                    Text("วันทำงาน")
                } footer: {
                    Text("วันทำงานที่ไม่มีรายงานจะแสดงเป็นวันที่ขาดในรายงานสัปดาห์และเดือน")
                }
                ListEditor(title: "ตำแหน่งงาน (กำลังคน)", placeholder: "เพิ่มตำแหน่ง", items: $s.roles)
                ListEditor(title: "เครื่องมือ", placeholder: "เพิ่มเครื่องมือ", items: $s.tools)
            }
            .tcFormStyle()
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("ตั้งค่ารายงานประจำ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { job.routineSettings = s; dismiss() }.bold()
                }
            }
        }
    }
}

extension RoutineSettingsSheet {
    /// Which locations each task's % is averaged over for the MP; a task left empty uses the places it was reported at.
    var taskLocations: some View {
        Section {
            ForEach(MasterSchedule.Task.allCases.filter { $0.part != .permit }) { t in
                NavigationLink {
                    TaskLocationsPicker(task: t, all: s.locations, chosen: Binding(
                        get: { s.taskLocations[t.rawValue] ?? [] },
                        set: { s.taskLocations[t.rawValue] = $0.isEmpty ? nil : $0 }))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(t.code).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.primary)
                        Text(t.title).lineLimit(1)
                        Spacer()
                        let n = s.taskLocations[t.rawValue]?.count ?? 0
                        Text(n == 0 ? "ตามที่รายงาน" : "\(n) ตำแหน่ง").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        } header: {
            Text("ตำแหน่งของแต่ละงาน (คิด % ให้แผน MP)")
        } footer: {
            Text("% ของงานใน MP = เฉลี่ย % สะสมของทุกตำแหน่งที่เลือก ตำแหน่งที่ยังไม่เริ่มนับเป็น 0% ถ้าไม่เลือก ใช้เฉพาะตำแหน่งที่มีในรายงานแล้ว")
        }
    }
}

struct TaskLocationsPicker: View {
    let task: MasterSchedule.Task
    let all: [String]
    @Binding var chosen: [String]

    var body: some View {
        List {
            Section {
                ForEach(all, id: \.self) { l in
                    Button {
                        chosen = chosen.contains(l) ? chosen.filter { $0 != l } : all.filter { chosen.contains($0) || $0 == l }
                    } label: {
                        HStack {
                            Text(l).foregroundStyle(Theme.navy)
                            Spacer()
                            if chosen.contains(l) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                        }
                        .frame(minHeight: touchMin)
                    }
                }
            } footer: {
                Text(task.title)
            }
            if !chosen.isEmpty {
                Button("ล้าง (ใช้ตามที่รายงาน)", role: .destructive) { chosen = [] }
            }
        }
        .tcFormStyle()
        .navigationTitle("\(task.code) ตำแหน่ง")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A section of strings with delete, move and an add row.
struct ListEditor: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    @State private var typed = ""

    var body: some View {
        Section(title) {
            ForEach(items, id: \.self) { Text($0) }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                TextField(placeholder, text: $typed).onSubmit(add)
                Button("เพิ่ม", action: add).disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let t = typed.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, !items.contains(t) { items.append(t) }
        typed = ""
    }
}
