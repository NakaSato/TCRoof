import SwiftUI
import TCRoofUI

/// The iPhone lists' search field (docs/ui/tcroof-survey-list-iphone): 44 high, r12, a 1 pt border that turns
/// into a 2 pt primary one while focused, bold typed text, and a 32 pt ✕ with a 44 pt target.
struct PhoneSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var prompt = "ค้นหาชื่อลูกค้า หรือรหัสโครงการ"
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
            TextField(text: $text) { Text(prompt).foregroundStyle(Theme.inkMuted) }
                .font(.sarabun(14, text.isEmpty ? .regular : .bold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32).background(Theme.segmentTrack, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(.leading, 12).padding(.trailing, text.isEmpty ? 12 : 0)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // the 2 pt border is drawn inside, so the text does not move when focused
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.primary : Theme.borderSubtle, lineWidth: focused.wrappedValue ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}
