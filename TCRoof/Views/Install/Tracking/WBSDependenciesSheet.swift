import SwiftUI
import SwiftData
import TCRoofCore
import TCRoofUI

/// Configure explicit links without interpreting the workbook's human-readable predecessor descriptions. A link joins
/// two sub-tasks or two task lines (as a REV 11 plan file links 2.1–2.10), finish-to-start, start-to-start or
/// finish-to-finish (CHA-76).
struct WBSDependenciesSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @State private var draft: [MasterSchedule.WorkItem]
    @State private var original: [MasterSchedule.WorkItem]
    @State private var error: String?

    init(job: Job) {
        self.job = job
        _draft = State(initialValue: job.scheduleWBS)
        _original = State(initialValue: job.scheduleWBS)
    }

    private var result: WBSDependencies.Result { WBSDependencies.schedule(draft, settings: job.routineSettings) }
    private var rows: [MasterSchedule.WorkItem] {
        let parents = draft.parentCodes
        return draft.filter { $0.linkable(parents) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("เลือกงาน แล้วกำหนดงานก่อนหน้า: เริ่มหลังเสร็จ (FS), เริ่มตาม (SS) หรือเสร็จตาม (FF) วันรอเป็นวันทำงานตามปฏิทินโครงการ FS รอ 0 เริ่มวันทำงานถัดไป SS / FF รอ 0 คือวันเดียวกัน ผูกทั้งงาน (2.1) แล้วงานย่อยเลื่อนตาม วันที่ Baseline ไม่เปลี่ยน")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.dangerText) } }
                if !result.issues.isEmpty {
                    Section("ตรวจสอบงานก่อนหน้า") {
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in Text(issue.message).foregroundStyle(Theme.dangerText) }
                    }
                }
                Section("งาน WBS") {
                    ForEach(rows) { item in
                        NavigationLink {
                            WBSDependencyEditor(items: $draft, code: item.code)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.code + " " + item.title.trimmingCharacters(in: .whitespaces))
                                if let links = item.dependencies, !links.isEmpty {
                                    Text(links.map(\.label).joined(separator: ", ")).font(.caption)
                                } else { Text("ยังไม่กำหนดงานก่อนหน้า").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("งานก่อนหน้า WBS")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก", action: save).disabled(!result.isValid || !permissions.can(.mpSetup, on: job.access))
                }
            }
        }
    }

    private func save() {
        guard permissions.can(.mpSetup, on: job.access), result.isValid else { return }
        guard job.scheduleWBS == original else { error = "แผนเปลี่ยนระหว่างแก้ไข กรุณาปิดแล้วเปิดใหม่"; return }
        let previous = job.scheduleWBS, actual = job.scheduleActual
        job.scheduleWBS = draft
        do { try context.save(); dismiss() }
        catch { job.scheduleWBS = previous; job.scheduleActual = actual; self.error = error.localizedDescription }
    }
}

private extension MasterSchedule.WorkItem {
    /// A sub-task or a task line this station has, with dates: what a link can join.
    func linkable(_ parents: Set<String>) -> Bool {
        !notForThisStation && baselineStart != nil && baselineEnd != nil && (!parents.contains(code) || WBSDependencies.isTaskLine(code))
    }
}

private extension MasterSchedule.WBSDependency.Kind {
    var title: String {
        switch self {
        case .finishToStart: return "เริ่มหลังเสร็จ (FS)"
        case .startToStart: return "เริ่มตาม (SS)"
        case .finishToFinish: return "เสร็จตาม (FF)"
        }
    }
}

private struct WBSDependencyEditor: View {
    typealias Link = MasterSchedule.WBSDependency
    @Binding var items: [MasterSchedule.WorkItem]
    let code: String

    private var links: [Link] { items.first { $0.code == code }?.dependencies ?? [] }
    private var candidates: [MasterSchedule.WorkItem] {
        let parents = items.parentCodes
        return items.filter { $0.code != code && $0.linkable(parents) }
    }
    private func links(_ predecessor: String) -> [Link] { links.filter { $0.predecessor == predecessor } }

    private func write(_ next: [Link]) {
        guard let i = items.firstIndex(where: { $0.code == code }) else { return }
        let order = Link.Kind.allCases
        items[i].dependencies = next.isEmpty ? nil : next.sorted {
            ($0.predecessor, order.firstIndex(of: $0.type)!) < ($1.predecessor, order.firstIndex(of: $1.type)!)
        }
    }
    private func set(_ predecessor: String, on: Bool) {
        let others = links.filter { $0.predecessor != predecessor }
        write(on ? others + (links(predecessor).isEmpty ? [Link(predecessor: predecessor)] : links(predecessor)) : others)
    }
    private func replace(_ old: Link, with new: Link) {
        write(links.filter { $0 != old } + [new])
    }
    private func add(_ predecessor: String) {
        let used = Set(links(predecessor).map(\.type))
        guard let type = Link.Kind.allCases.first(where: { !used.contains($0) }) else { return }
        write(links + [Link(predecessor: predecessor, type: type)])
    }

    var body: some View {
        Form {
            if let i = items.firstIndex(where: { $0.code == code }) {
                Section("รายละเอียดงานย่อย WBS") {
                    LabeledContent("ชื่องาน") {
                        TextField("ชื่องานย่อย", text: Binding(
                            get: { items[i].title.trimmingCharacters(in: .whitespaces) },
                            set: { v in
                                let indent = items[i].title.prefix { $0 == " " }
                                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !t.isEmpty { items[i].title = String(indent) + t }
                            }
                        )).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("น้ำหนัก (%)") {
                        TextField("0", value: $items[i].weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("ผู้รับผิดชอบ") {
                        TextField("เช่น วศ., ผรม.", text: Binding(
                            get: { items[i].responsible ?? "" },
                            set: { v in
                                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                items[i].responsible = t.isEmpty ? nil : t
                            }
                        )).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("หลักฐาน") {
                        TextField("หลักฐาน / เลขที่เอกสาร", text: Binding(
                            get: { items[i].evidence ?? "" },
                            set: { v in
                                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                items[i].evidence = t.isEmpty ? nil : t
                            }
                        )).multilineTextAlignment(.trailing)
                    }
                }
            }
            let available = Set(candidates.map(\.code))
            let unavailable = Array(Set(links.map(\.predecessor)).subtracting(available)).sorted()
            if !unavailable.isEmpty {
                Section("งานก่อนหน้าที่ใช้ไม่ได้") {
                    ForEach(unavailable, id: \.self) { predecessor in
                        Button("ลบ " + predecessor, role: .destructive) { set(predecessor, on: false) }
                    }
                }
            }
            Section("งานก่อนหน้า") {
                ForEach(candidates) { candidate in
                    VStack(alignment: .leading) {
                        Toggle(candidate.code + " " + candidate.title.trimmingCharacters(in: .whitespaces),
                               isOn: Binding(get: { !links(candidate.code).isEmpty }, set: { set(candidate.code, on: $0) }))
                        ForEach(links(candidate.code), id: \.type) { link in linkRow(link) }
                        if !links(candidate.code).isEmpty, links(candidate.code).count < Link.Kind.allCases.count {
                            Button("เพิ่มเงื่อนไข", systemImage: "plus") { add(candidate.code) }
                                .font(.callout).frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .navigationTitle(code)
    }

    /// One link's type and lag: `เริ่มตาม (SS)` `รอ 3 วันทำงาน`, and a remove button when the row has another.
    @ViewBuilder private func linkRow(_ link: Link) -> some View {
        let used = Set(links(link.predecessor).map(\.type)).subtracting([link.type])
        HStack {
            Picker("ความสัมพันธ์", selection: Binding(get: { link.type }, set: { t in
                var next = link; next.type = t; replace(link, with: next)
            })) {
                ForEach(Link.Kind.allCases.filter { !used.contains($0) }, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            Stepper("รอ \(link.lagDays) วันทำงาน", value: Binding(get: { link.lagDays }, set: { v in
                var next = link; next.lagDays = v; replace(link, with: next)
            }), in: 0...3650)
            if links(link.predecessor).count > 1 {
                Button("ลบเงื่อนไข", systemImage: "minus.circle", role: .destructive) { write(links.filter { $0 != link }) }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
    }
}
