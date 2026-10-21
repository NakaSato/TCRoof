import SwiftUI
import TCRoofUI

/// A signature box: the pad, or the signed-in person's saved signature (`MySignature`) once it is picked or kept.
/// Style and size it as `SignaturePad`.
struct AccountSignatureCanvas: View {
    @Binding var signature: Data?
    @State private var my = MySignature.shared

    var body: some View {
        if let s = signature, s == my.png, let image = my.image {
            ZStack {
                Theme.paper
                Image(uiImage: image).resizable().scaledToFit().padding(12)
            }
            .accessibilityElement()
            .accessibilityLabel("ลายเซ็นของฉัน")
        } else {
            SignaturePad(signature: $signature)
        }
    }
}

/// `ใช้ลายเซ็นของฉัน` and `จำลายเซ็นนี้ไว้ในเครื่อง`, under an `AccountSignatureCanvas` the signed-in person signs.
struct MySignatureActions: View {
    @Binding var signature: Data?
    @State private var my = MySignature.shared

    var body: some View {
        let usingSaved = signature != nil && signature == my.png
        if my.account?.isEmpty == false, !usingSaved, my.hasSignature || signature != nil {
            HStack(spacing: 12) {
                if my.hasSignature {
                    Button { signature = my.png } label: { Label("ใช้ลายเซ็นของฉัน", systemImage: "signature") }
                        .buttonStyle(TCButtonStyle(.text))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("signature.useMine")
                }
                Spacer(minLength: 0)
                if let s = signature {
                    Button(my.hasSignature ? "จำแทนลายเซ็นเดิม" : "จำลายเซ็นนี้ไว้ในเครื่อง") { my.save(s) }
                        .buttonStyle(TCButtonStyle(.text))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("signature.keep")
                }
            }
        }
    }
}

/// Settings › ลายเซ็นของฉัน: draw, replace or remove the account's signature. It stays on this device.
struct MySignatureSettingsPage: View {
    @State private var my = MySignature.shared
    @State private var drawn: Data?
    @State private var redrawing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(my.account.map { "บัญชี \($0)" } ?? "")
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                Group {
                    if let image = my.image, !redrawing {
                        ZStack { Theme.paper; Image(uiImage: image).resizable().scaledToFit().padding(16) }
                    } else {
                        SignaturePad(signature: $drawn)
                            .overlay(alignment: .bottomLeading) {
                                if drawn == nil {
                                    Text("เซ็นชื่อด้วย Apple Pencil หรือนิ้ว").font(.sarabun(12, relativeTo: .caption))
                                        .foregroundStyle(Theme.muted).padding(12).allowsHitTesting(false)
                                }
                            }
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.navy.opacity(0.45)))
                .accessibilityIdentifier("mySignature.pad")
                buttons
                Text("ลายเซ็นนี้เก็บไว้ในเครื่องนี้เท่านั้น ไม่ซิงก์และไม่อัปโหลด ใช้ได้ทุกที่ที่คุณต้องลงนาม (รายงานประจำวัน ใบเบิก แบบสำรวจ เอกสารงานบ้าน) โดยกด \"ใช้ลายเซ็นของฉัน\" เอกสารที่ลงนามแล้วจะเก็บสำเนาลายเซ็นไว้ในตัวเอกสารเอง")
                    .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .tcPageBackground()
        .navigationTitle("ลายเซ็นของฉัน")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 12) {
            if my.hasSignature && !redrawing {
                Button("เซ็นใหม่") { drawn = nil; redrawing = true }.buttonStyle(TCButtonStyle(.secondary))
                Spacer()
                Button("ลบลายเซ็น", role: .destructive) { my.remove() }.buttonStyle(TCButtonStyle(.text))
            } else {
                Button("ล้าง") { drawn = nil }.buttonStyle(TCButtonStyle(.text)).disabled(drawn == nil)
                if redrawing { Button("ยกเลิก") { drawn = nil; redrawing = false }.buttonStyle(TCButtonStyle(.text)) }
                Spacer()
                Button("บันทึกลายเซ็น") {
                    if let drawn { my.save(drawn) }
                    drawn = nil; redrawing = false
                }
                .buttonStyle(TCButtonStyle(.primary))
                .disabled(drawn == nil)
                .accessibilityIdentifier("mySignature.save")
            }
        }
    }
}
