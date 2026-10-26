#if canImport(UIKit)
import SwiftUI
import ModuleRules

/// The rules a form's answers raise (docs/specs/module-install-rules.md §5), most severe first: block red, warn amber
/// with the engineer's reason (required to save), info blue; then notes that raise no rule. Shared by the residential
/// survey's installation checks and C1's layout checks.
public struct ModuleRulesList: View {
    let validation: Validation
    let notes: [String]
    let empty: String
    let reason: ((String) -> Binding<String>)?

    public init(_ validation: Validation, notes: [String] = [], empty: String, reason: ((String) -> Binding<String>)? = nil) {
        self.validation = validation; self.notes = notes; self.empty = empty; self.reason = reason
    }

    public static func color(_ s: Severity) -> Color { s == .block ? Theme.dangerText : s == .warn ? Theme.pending : Theme.primary }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if validation.results.isEmpty {
                Label(empty, systemImage: "checkmark.seal").font(.sarabun(14)).foregroundStyle(Theme.okText)
            }
            ForEach(validation.results) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: r.severity == .block ? "xmark.octagon.fill" : r.severity == .warn ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundStyle(Self.color(r.severity))
                            .accessibilityLabel(r.severity == .block ? "ห้าม" : r.severity == .warn ? "เตือน" : "คำแนะนำ")
                        Text(r.id).font(.sarabun(13, .bold)).foregroundStyle(Self.color(r.severity))
                        Text(r.messageTH).font(.sarabun(14)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                    }
                    if r.severity == .warn, let reason {
                        TCTextField("เหตุผลที่ยังติดตั้งได้ (จำเป็น)", text: reason(r.id))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Self.color(r.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.md))
                .accessibilityElement(children: .contain)
            }
            ForEach(notes, id: \.self) { n in
                Label(n, systemImage: "note.text").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}
#endif
