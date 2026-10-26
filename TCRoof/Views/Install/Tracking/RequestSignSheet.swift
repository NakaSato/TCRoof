import SwiftUI
import TCRoofUI
import TCRoofCore

/// `เซ็นชื่อ`: the pad, the name under the line, `ยกเลิก` and `ยืนยันลายเซ็น`.
struct RequestSignSheet: View {
    @State var name: String
    let onSign: (Data, String) -> Void
    @State private var signature: Data?
    @Environment(\.dismiss) private var dismiss

    init(name: String, onSign: @escaping (Data, String) -> Void) {
        _name = State(initialValue: name); self.onSign = onSign
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("ลายเซ็นผู้ส่งคำขอ | SITE ENGINEER").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.inkMuted)
                AccountSignatureCanvas(signature: $signature)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.45)))
                    .overlay(alignment: .bottomLeading) {
                        if signature == nil {
                            Text("เซ็นชื่อด้วย Apple Pencil หรือนิ้ว").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).padding(12).allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("signaturePad")
                MySignatureActions(signature: $signature)
                TextField("ชื่อผู้ส่งคำขอ", text: $name).font(.sarabunFixed(16)).textFieldStyle(OutlinedFieldStyle())
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("เซ็นชื่อ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ยืนยันลายเซ็น") { if let s = signature { onSign(s, name.trimmingCharacters(in: .whitespaces)); dismiss() } }
                        .bold().disabled(signature == nil).accessibilityIdentifier("requestSignConfirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
