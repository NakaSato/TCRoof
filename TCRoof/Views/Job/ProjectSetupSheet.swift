import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `ตั้งค่าโครงการจากไฟล์`: the facts a plan file states that the station doesn't hold yet (`ProjectSetup.changes`), one
/// row each with what the station has now and what the file says. A row that fills an empty field starts ticked, one
/// that would replace what the team typed starts unticked.
struct ProjectSetupList: View {
    let changes: [ProjectSetup.Change]
    @Binding var picked: Set<ProjectSetup.Field>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(changes) { c in
                row(c)
                if c.id != changes.last?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }

    private func row(_ c: ProjectSetup.Change) -> some View {
        let on = picked.contains(c.field)
        return Button {
            if on { picked.remove(c.field) } else { picked.insert(c.field) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22)).foregroundStyle(on ? Theme.primary : Theme.chevron)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.field.label).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                    Text(c.proposed).font(.sarabun(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    Text(c.current.isEmpty ? "ยังไม่มีในแอป" : "ในแอปตอนนี้: " + c.current)
                        .font(.sarabun(13, relativeTo: .footnote))
                        .foregroundStyle(c.current.isEmpty ? Theme.inkMuted : Theme.warningText)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("projectSetup." + c.field.rawValue)
    }
}

/// The list on its own, from the Excel menu's `ตั้งค่าโครงการจากไฟล์…`: the facts of the station's kept plan file, to
/// take what an import left (it fills only empty fields) or to take the file's word over what was typed.
struct ProjectSetupSheet: View {
    @Bindable var job: Job
    let setup: ProjectSetup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var picked: Set<ProjectSetup.Field>
    @State private var changes: [ProjectSetup.Change]

    init(job: Job, setup: ProjectSetup) {
        self.job = job
        self.setup = setup
        let changes = job.setupChanges(setup)
        _changes = State(initialValue: changes)
        _picked = State(initialValue: ProjectSetup.defaultFields(changes))
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                if changes.isEmpty {
                    PadSection { Text("ข้อมูลโครงการในแอปตรงกับไฟล์แผนแล้ว").foregroundStyle(Theme.inkMuted) }
                } else {
                    PadSection("ข้อมูลในไฟล์ที่ต่างจากแอป (\(changes.count))") {
                        ProjectSetupList(changes: changes, picked: $picked)
                    } footer: {
                        Text("ติ๊กช่องที่จะใช้ตามไฟล์ ช่องที่ทีมกรอกไว้แล้วจะไม่ถูกแทนจนกว่าจะติ๊ก")
                    }
                }
                if let station = setup.inverterStation {
                    PadSection("Inverter station ตามไฟล์") {
                        Text(([station] + [setup.inverterStationDetail].compactMap { $0 }).joined(separator: " | "))
                            .foregroundStyle(Theme.navy)
                    } footer: { Text("อยู่ในหมายเหตุของงาน 2.5.1 ในแผน MP") }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("ตั้งค่าโครงการจากไฟล์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ใช้ \(picked.count) ช่อง") {
                        job.takeSetup(setup, fields: picked)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("projectSetup.apply")
                }
            }
        }
    }
}
