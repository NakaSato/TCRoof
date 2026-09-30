#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// "ขนาด @ระยะห่าง" for one roof-structure member: pick the section and spacing from lists, or type anything else.
struct MemberPicker: View {
    @Binding var value: String
    let component: Int

    var body: some View {
        let parts = StructureSizes.split(value)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    let rec = StructureSizes.recommended(component)
                    if !rec.isEmpty {
                        Section("ที่ใช้บ่อย") { ForEach(rec, id: \.self) { s in Button(s) { setSize(s) } } }
                    }
                    ForEach(StructureSizes.sections, id: \.group) { g in
                        Menu(g.group) { ForEach(g.items, id: \.self) { s in Button(s) { setSize(s) } } }
                    }
                    Divider()
                    Button("ไม่มี ( - )") { value = "-" }
                } label: {
                    pickerLabel(parts.size.isEmpty ? "เลือกขนาด" : parts.size, placeholder: parts.size.isEmpty)
                }
                Menu {
                    ForEach(StructureSizes.spacings, id: \.self) { sp in Button(sp) { setSpacing(sp) } }
                    Divider()
                    Button("ไม่ระบุระยะห่าง") { setSpacing("") }
                } label: {
                    pickerLabel(parts.spacing.isEmpty ? "@ระยะห่าง" : parts.spacing, placeholder: parts.spacing.isEmpty)
                }
                .disabled(parts.size.isEmpty || parts.size == "-")
            }
            TextField("หรือพิมพ์เอง เช่น C-100x50x20x3.2 @1.00M หรือ -", text: $value)
                .textFieldStyle(.roundedBorder).font(.callout).foregroundStyle(Paper.value)
        }
    }

    func pickerLabel(_ text: String, placeholder: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.callout.weight(placeholder ? .regular : .semibold)).foregroundStyle(placeholder ? Color.secondary : Paper.value)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    func setSize(_ s: String) {
        var sp = StructureSizes.split(value).spacing
        if sp.isEmpty { sp = StructureSizes.defaultSpacing(component) ?? "" }
        value = StructureSizes.join(size: s, spacing: sp)
    }
    func setSpacing(_ sp: String) {
        value = StructureSizes.join(size: StructureSizes.split(value).size, spacing: sp)
    }
}
#endif
