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
            PadForm(maxWidth: 720) {
                PadSection("งาน MP") {
                    ForEach(tasks.map(Optional.some) + [nil], id: \.self) { t in
                        Button { task = t } label: {
                            HStack {
                                Text(t.map { "\($0.code) \($0.title)" } ?? "งานอื่น").foregroundStyle(Theme.navy)
                                Spacer()
                                if task == t { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                            }
                            .frame(minHeight: touchMin).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                PadSection("ตำแหน่ง (เลือกได้หลายที่)") {
                    ForEach(locations + extra, id: \.self) { l in
                        Button { if picked.contains(l) { picked.remove(l) } else { picked.insert(l) } } label: {
                            HStack {
                                Text(l).foregroundStyle(Theme.navy)
                                Spacer()
                                if picked.contains(l) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                            }
                            .frame(minHeight: touchMin).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                } footer: {
                    Text("หนึ่งบรรทัดต่อหนึ่งตำแหน่ง · ตั้งรายการตำแหน่งของสถานีได้ที่ ตั้งค่ารายงาน")
                }
                PadSection("รายละเอียด") {
                    TextField(task?.title ?? "รายละเอียดงาน", text: $description, axis: .vertical)
                }
            }
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
            PadForm(maxWidth: 640) {
                PadSection("ตรวจก่อนลงนาม") {
                    if warnings.isEmpty {
                        Label("ครบถ้วน พร้อมลงนาม", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.okText)
                    }
                    ForEach(warnings, id: \.self) { w in
                        Label(w.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.dangerText)
                    }
                } footer: {
                    if !warnings.isEmpty { Text("ลงนามได้ แต่ควรแก้รายการด้านบนก่อน") }
                }
                PadSection("Site Engineer") {
                    TextField("ชื่อผู้ลงนาม", text: $engineer)
                }
                PadSection {
                    Text("ลงนามแล้วระบบจะสร้าง PDF เก็บในเอกสารโครงการ (อัปโหลดขึ้น Drive ได้จากหน้างาน) และอัปเดตความก้าวหน้าในแผน MP")
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                }
            }
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
            PadForm(maxWidth: 560) {
                PadSection {
                    TextField("ชื่อ Inspector", text: $name)
                    DatePicker("วันที่", selection: $date, displayedComponents: .date)
                }
            }
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
    @State private var inspectionAt = Date()
    @State private var inspectionSubject = ""

    init(job: Job) {
        self.job = job
        _s = State(initialValue: job.routineSettings)
    }

    /// The PWA representative's inspection appointments: the `ตรวจรับ` rows of the PWA plan page's agenda.
    private var inspections: some View {
        PadSection("นัดตรวจรับ (ผู้แทน กปภ.)") {
            ForEach(s.inspections) { i in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.at.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
                        if !i.subject.isEmpty { Text(i.subject).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                    }
                    Spacer(minLength: 0)
                    PadRowButton("ลบนัดตรวจรับ", systemImage: "trash", destructive: true) { s.inspections.removeAll { $0.id == i.id } }
                }
            }
            DatePicker("วันและเวลา", selection: $inspectionAt)
            HStack {
                TextField("งานที่ตรวจ เช่น 2.5 Inverter", text: $inspectionSubject)
                Button("เพิ่ม") {
                    s.inspections.append(.init(at: inspectionAt, subject: inspectionSubject.trimmingCharacters(in: .whitespaces)))
                    s.inspections.sort { $0.at < $1.at }
                    inspectionSubject = ""
                }
            }
        } footer: {
            Text("นัดจะแสดงเป็นแถวตรวจรับในตารางงานของหน้าแผนงาน PWA")
        }
    }

    private static let weekdays = [(2, "จ."), (3, "อ."), (4, "พ."), (5, "พฤ."), (6, "ศ."), (7, "ส."), (1, "อา.")]

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection("โครงการ") {
                    TextField("ชื่อสัญญา / โครงการ", text: $s.contractName, axis: .vertical)
                    TextField("ผู้ว่าจ้าง", text: $s.employer)
                    TextField("ผู้รับจ้าง", text: $s.contractor)
                    TextField("ผู้รับเหมาช่วงที่ติดตั้ง (ชื่อย่อ เช่น A) · เว้นว่างถ้าทีม TC ติดตั้งเอง", text: $s.subcontractor)
                    TextField("Site Engineer", text: $s.siteEngineer)
                    TextField("Inspector", text: $s.inspector)
                }
                ListEditor(title: "ตำแหน่งในสถานี", placeholder: "เช่น หลังคา 1, ถังน้ำใส 1, ห้องอินเวอร์เตอร์", items: $s.locations)
                if !s.locations.isEmpty {
                    PadSection {
                        PadLink {
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
                PadSection("วันทำงาน") {
                    HStack(spacing: 6) {
                        ForEach(Self.weekdays, id: \.0) { d, label in
                            let on = s.workingWeekdays.contains(d)
                            Button(label) { if on { s.workingWeekdays.remove(d) } else { s.workingWeekdays.insert(d) } }
                                .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                                .frame(maxWidth: .infinity, minHeight: touchMin)
                                .background(on ? Theme.primary : Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
                                .buttonStyle(.plain)
                        }
                    }
                    ForEach(s.holidays, id: \.self) { h in
                        HStack {
                            Text(ISODate.date(h).map(RoutineReport.thaiDate) ?? h)
                            Spacer(minLength: 0)
                            PadRowButton("ลบวันหยุด", systemImage: "trash", destructive: true) { s.holidays.removeAll { $0 == h } }
                        }
                    }
                    HStack {
                        DatePicker("วันหยุด", selection: $holiday, displayedComponents: .date)
                        Button("เพิ่ม") {
                            let k = RoutineReport.dayKey(holiday)
                            if !s.holidays.contains(k) { s.holidays.append(k); s.holidays.sort() }
                        }
                    }
                } footer: {
                    Text("วันทำงานที่ไม่มีรายงานจะแสดงเป็นวันที่ขาดในรายงานสัปดาห์และเดือน")
                }
                inspections
                ListEditor(title: "ตำแหน่งงาน (กำลังคน)", placeholder: "เพิ่มตำแหน่ง", items: $s.roles)
                ListEditor(title: "เครื่องมือ", placeholder: "เพิ่มเครื่องมือ", items: $s.tools)
            }
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
        PadSection("ตำแหน่งของแต่ละงาน (คิด % ให้แผน MP)") {
            ForEach(MasterSchedule.Task.allCases.filter { $0.part != .permit }) { t in
                PadLink {
                    TaskLocationsPicker(task: t, all: s.locations, chosen: Binding(
                        get: { s.taskLocations[t.rawValue] ?? [] },
                        set: { s.taskLocations[t.rawValue] = $0.isEmpty ? nil : $0 }))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(t.code).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                        Text(t.title).lineLimit(1)
                        Spacer()
                        let n = s.taskLocations[t.rawValue]?.count ?? 0
                        Text(n == 0 ? "ตามที่รายงาน" : "\(n) ตำแหน่ง").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    }
                }
            }
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
        PadForm(maxWidth: 560) {
            PadSection {
                ForEach(all, id: \.self) { l in
                    Button {
                        chosen = chosen.contains(l) ? chosen.filter { $0 != l } : all.filter { chosen.contains($0) || $0 == l }
                    } label: {
                        HStack {
                            Text(l).foregroundStyle(Theme.navy)
                            Spacer()
                            if chosen.contains(l) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                        }
                        .frame(minHeight: touchMin).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(task.title)
            }
            if !chosen.isEmpty {
                PadSection {
                    Button("ล้าง (ใช้ตามที่รายงาน)", role: .destructive) { chosen = [] }
                        .foregroundStyle(Theme.danger).frame(maxWidth: .infinity, minHeight: touchMin)
                }
            }
        }
        .navigationTitle("\(task.code) ตำแหน่ง")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A section of strings with delete, move up and an add row.
struct ListEditor: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    @State private var typed = ""

    var body: some View {
        PadSection(title) {
            ForEach(Array(items.enumerated()), id: \.element) { i, item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer(minLength: 8)
                    if i > 0 { PadRowButton("เลื่อน \(item) ขึ้น", systemImage: "arrow.up") { items.swapAt(i, i - 1) } }
                    PadRowButton("ลบ \(item)", systemImage: "trash", destructive: true) { items.remove(at: i) }
                }
            }
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
