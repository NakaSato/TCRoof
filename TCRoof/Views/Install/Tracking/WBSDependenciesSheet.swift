import SwiftUI
import TCRoofCore
import TCRoofUI

/// Configure explicit links without interpreting the workbook's human-readable predecessor descriptions.
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
        return draft.filter { !parents.contains($0.code) && !$0.notForThisStation && $0.baselineStart != nil && $0.baselineEnd != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("เลือกงานย่อย แล้วกำหนดงานที่ต้องเสร็จก่อน วันรอเป็นวันทำงานตามปฏิทินโครงการ วันรอ 0 เริ่มวันทำงานถัดไป วันที่ Baseline ไม่เปลี่ยน")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.dangerText) } }
                if !result.issues.isEmpty {
                    Section("ตรวจสอบงานก่อนหน้า") {
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in Text(issue.message).foregroundStyle(Theme.dangerText) }
                    }
                }
                Section("งานย่อย WBS") {
                    ForEach(rows) { item in
                        NavigationLink {
                            WBSDependencyEditor(items: $draft, code: item.code)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.code + " " + item.title.trimmingCharacters(in: .whitespaces))
                                if let links = item.dependencies, !links.isEmpty {
                                    Text(links.map { $0.predecessor + " +\($0.lagDays) วัน" }.joined(separator: ", ")).font(.caption)
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

private struct WBSDependencyEditor: View {
    @Binding var items: [MasterSchedule.WorkItem]
    let code: String

    private var links: [MasterSchedule.WBSDependency] { items.first { $0.code == code }?.dependencies ?? [] }
    private var candidates: [MasterSchedule.WorkItem] {
        let parents = items.parentCodes
        return items.filter { $0.code != code && !parents.contains($0.code) && !$0.notForThisStation && $0.baselineStart != nil && $0.baselineEnd != nil }
    }
    private func set(_ predecessor: String, on: Bool, lag: Int? = nil) {
        guard let i = items.firstIndex(where: { $0.code == code }) else { return }
        var next = links.filter { $0.predecessor != predecessor }
        if on { next.append(.init(predecessor: predecessor, lagDays: lag ?? links.first { $0.predecessor == predecessor }?.lagDays ?? 0)) }
        items[i].dependencies = next.isEmpty ? nil : next.sorted { $0.predecessor < $1.predecessor }
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
            let unavailable = links.filter { !available.contains($0.predecessor) }
            if !unavailable.isEmpty {
                Section("งานก่อนหน้าที่ใช้ไม่ได้") {
                    ForEach(unavailable, id: \.predecessor) { link in
                        Button("ลบ " + link.predecessor, role: .destructive) { set(link.predecessor, on: false) }
                    }
                }
            }
            Section("ต้องเสร็จก่อนเริ่มงานนี้") {
                ForEach(candidates) { candidate in
                    let link = links.first { $0.predecessor == candidate.code }
                    VStack(alignment: .leading) {
                        Toggle(candidate.code + " " + candidate.title.trimmingCharacters(in: .whitespaces),
                               isOn: Binding(get: { links.contains { $0.predecessor == candidate.code } }, set: { set(candidate.code, on: $0) }))
                        if link != nil {
                            Stepper("รอ \(link!.lagDays) วันทำงาน", value: Binding(get: { links.first { $0.predecessor == candidate.code }?.lagDays ?? 0 },
                                                                            set: { set(candidate.code, on: true, lag: $0) }), in: 0...3650)
                        }
                    }
                }
            }
        }
        .navigationTitle(code)
    }
}
