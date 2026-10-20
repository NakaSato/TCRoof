#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// มาตรฐานโครงสร้างแผงบนถัง (docs/specs/tank-mounting-layout.md §1): the team's module and structure values for D1's
/// panel layout. Managers (`tank.standard`) change and save them; everyone else reads them. A save reaches the other
/// devices through Firestore (`config/tankStandard`, the app's CloudSync); a job already laid out keeps the standard it
/// was made with until its layout is made again.
struct TankStandardView: View {
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @State private var saved = TankStandard.Store.shared.current
    @State private var draft = TankStandard.Store.shared.current
    @State private var resetAsk = false

    var canEdit: Bool { permissions.can(.tankStandard) }
    var changed: Bool { !draft.sameValues(saved) }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection {
                    LabeledContent("ผลของค่าชุดนี้", value: draft.summary)
                    LabeledContent("ฉบับ", value: revisionText)
                } footer: {
                    Text(canEdit ? "งานที่จัดแผงไว้แล้วใช้ค่าเดิม จนกว่าจะกด จัดแผงใหม่ หรือ หาผังที่ได้พลังงานมากที่สุด ในงานนั้น"
                                 : "แก้ได้เฉพาะผู้จัดการ · งานที่จัดแผงไว้แล้วใช้ค่าเดิมจนกว่าจะจัดแผงใหม่")
                }
                ForEach(groups, id: \.self) { g in
                    PadSection(g) {
                        if g == "แผง" && canEdit { catalogPicker }
                        ForEach(TankStandard.fields.filter { $0.group == g }, id: \.label) { f in row(f) }
                    }
                }
                let problems = draft.problems
                if !problems.isEmpty {
                    PadSection("ยังบันทึกไม่ได้") {
                        ForEach(problems, id: \.self) { Text($0).foregroundStyle(Theme.danger) }
                    }
                }
                if canEdit {
                    Button("คืนค่าตามแบบ B1-C3") { resetAsk = true }
                        .buttonStyle(TCButtonStyle(.secondary))
                        .disabled(draft.sameValues(.builtIn))
                }
            }
            .navigationTitle("มาตรฐานโครงสร้างแผงบนถัง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(changed ? "ยกเลิก" : "ปิด") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("บันทึก") { save() }.disabled(!changed || !draft.problems.isEmpty)
                    }
                }
            }
            .confirmationDialog("คืนค่าตามแบบ B1-C3?", isPresented: $resetAsk, titleVisibility: .visible) {
                Button("คืนค่า") { keepRevision { draft = .builtIn } }
                Button("ยกเลิก", role: .cancel) {}
            } message: {
                Text("ค่าจะกลับเป็นแบบอ้างอิงกับแผงเริ่มต้นของแคตตาล็อก กด บันทึก เพื่อใช้กับทีม")
            }
        }
        .tint(Theme.primary)
    }

    var groups: [String] { TankStandard.fields.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } } }

    var revisionText: String {
        guard saved.revision > 0 else { return "ค่าเริ่มต้นตามแบบ B1-C3" }
        let date = saved.savedAt.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return ["rev \(saved.revision)", saved.savedBy ?? "", date].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func keepRevision(_ f: () -> Void) {
        let r = draft.revision, by = draft.savedBy, at = draft.savedAt
        f()
        draft.revision = r; draft.savedBy = by; draft.savedAt = at
    }

    func save() {
        guard let s = TankStandard.Store.shared.save(draft, by: permissions.email.isEmpty ? nil : permissions.email) else { return }
        saved = s; draft = s
    }

    /// `เลือกจากแคตตาล็อก`: fills the module's size and power.
    var catalogPicker: some View {
        Menu {
            ForEach(EquipmentCatalog.bundled.pv, id: \.id) { m in
                Button("\(m.model) · \(m.w) W · \(m.l) × \(m.wd) มม.") {
                    draft.moduleL = Double(m.l) / 1000; draft.moduleW = Double(m.wd) / 1000; draft.moduleKW = Double(m.w) / 1000
                }
            }
        } label: {
            HStack {
                Text("เลือกจากแคตตาล็อก")
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.inkMuted)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
    }

    @ViewBuilder func row(_ f: TankStandard.Field) -> some View {
        let value = Binding(get: { draft[keyPath: f.key] * f.scale }, set: { draft[keyPath: f.key] = $0 / f.scale })
        let bad = !f.range.contains(draft[keyPath: f.key])
        HStack(spacing: 10) {
            Text(f.label).frame(maxWidth: .infinity, alignment: .leading)
            if canEdit {
                NumberField(label: f.label, value: value, whole: f.unit == "W")
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    .padding(.horizontal, 8).frame(minHeight: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(bad ? Theme.danger : Theme.borderSubtle))
                    .accessibilityLabel(f.label)
            } else {
                Text(NumberField.show(value.wrappedValue, whole: f.unit == "W")).monospacedDigit()
            }
            Text(f.unit).foregroundStyle(Theme.inkMuted).frame(width: 28, alignment: .leading)
        }
        .foregroundStyle(draft[keyPath: f.key] != saved[keyPath: f.key] ? Theme.primary : Theme.navy)
    }
}
/// A decimal field that writes its value as it is typed (the decimal pad has no return key to commit with), and
/// takes a value set elsewhere (the catalogue, the reset) when it differs from what is typed.
private struct NumberField: View {
    let label: String
    @Binding var value: Double
    /// Watts: no decimals; metres: two or three.
    var whole = false
    @State private var text = ""

    static func show(_ v: Double, whole: Bool) -> String {
        v.formatted(.number.precision(.fractionLength(whole ? 0...0 : 2...3)).grouping(.never))
    }
    static func parse(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.decimalPad)
            .onAppear { text = Self.show(value, whole: whole) }
            .onChange(of: text) { _, t in if let v = Self.parse(t), abs(v - value) > 1e-9 { value = v } }
            .onChange(of: value) { _, v in if Self.parse(text).map({ abs($0 - v) > 1e-9 }) ?? true { text = Self.show(v, whole: whole) } }
    }
}
#endif
