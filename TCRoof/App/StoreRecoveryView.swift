import SwiftUI
import TCRoofUI

/// Shown in place of the app when its SwiftData store won't open (`AppStore`): try again, or set the store aside and
/// start empty, sync bringing the records back. Nothing of an account shows here.
struct StoreRecoveryView: View {
    let store: AppStore
    @State private var confirming = false
    @State private var moveFailed: String?

    var body: some View {
        ContentUnavailableView {
            Label("เปิดข้อมูลในเครื่องไม่ได้", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("ข้อมูลงานที่เก็บในเครื่องนี้เปิดไม่ได้ อาจเกิดจากการอัปเดตแอป ลองเปิดอีกครั้ง หรือเก็บไฟล์เดิมไว้แล้วเริ่มใหม่ ข้อมูลที่ซิงก์แล้วจะดาวน์โหลดกลับมา")
        } actions: {
            VStack(spacing: Space.m) {
                Button("ลองเปิดอีกครั้ง") { store.open() }
                    .buttonStyle(TCButtonStyle(.primary))
                Button("เก็บไฟล์เดิมไว้แล้วเริ่มใหม่") { confirming = true }
                    .buttonStyle(TCButtonStyle(.secondary))
                if let failure = store.failure {
                    DisclosureGroup("รายละเอียด") {
                        Text(failure)
                            .font(.sarabun(12, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.sarabun(14, relativeTo: .subheadline))
                    .frame(maxWidth: 420)
                }
            }
        }
        .background(Theme.background)
        .confirmationDialog("เริ่มใหม่ด้วยข้อมูลว่าง?", isPresented: $confirming, titleVisibility: .visible) {
            Button("เก็บไฟล์เดิมไว้แล้วเริ่มใหม่", role: .destructive) {
                do { try store.startFresh() } catch { moveFailed = error.localizedDescription }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("ไฟล์เดิมจะเก็บไว้ในเครื่อง สิ่งที่ยังไม่ได้ซิงก์ เช่น รูปที่ยังไม่ขึ้น Drive จะอยู่ในไฟล์นั้นเท่านั้น")
        }
        .alert("เก็บไฟล์เดิมไม่สำเร็จ", isPresented: Binding(get: { moveFailed != nil }, set: { if !$0 { moveFailed = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(moveFailed ?? "")
        }
    }
}
