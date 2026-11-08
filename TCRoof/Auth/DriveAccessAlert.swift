import SwiftUI
import TCRoofUI

/// Asks the signed-in account for the Drive access its role needs (`GoogleSession.driveAccessNeeded`, CHA-41) before
/// the Google page opens, so the second consent page isn't a surprise.
struct DriveAccessAlert: ViewModifier {
    @Environment(GoogleSession.self) private var session

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: asking, presenting: session.driveAccessNeeded) { _ in
                Button("ดำเนินการต่อ") { Task { await session.grantDriveAccess() } }
                Button("ภายหลัง", role: .cancel) { session.postponeDriveAccess() }
            } message: { access in
                Text(message(access))
            }
            .alert("ปรับสิทธิ์ Google Drive ไม่สำเร็จ", isPresented: failed) {
                Button("ตกลง", role: .cancel) { session.driveAccessError = nil }
            } message: {
                Text(session.driveAccessError ?? "")
            }
    }

    private var title: String {
        session.driveAccessNeeded == .full ? "อนุญาต Google Drive กลาง" : "ปรับสิทธิ์ Google Drive"
    }

    private func message(_ access: GoogleAuth.DriveAccess) -> String {
        switch access {
        case .full:
            "ทีม TC อัปโหลดเข้า Drive กลางของบริษัทเมื่ออนุญาตให้แอปเข้าถึง Google Drive ทั้งหมด จนกว่าจะอนุญาต ไฟล์จะขึ้นไปที่ Drive ของคุณเอง"
        case .contractor:
            "แอปจะขอสิทธิ์แค่อ่านไฟล์ที่ทีมแชร์ให้ และจัดการเฉพาะไฟล์ที่แอปสร้างใน Drive ของคุณ แทนสิทธิ์ทั้ง Drive แบบเดิม"
        }
    }

    private var asking: Binding<Bool> {
        Binding(get: { session.driveAccessNeeded != nil && session.driveAccessError == nil },
                set: { if !$0, session.driveAccessNeeded != nil { session.postponeDriveAccess() } })
    }

    private var failed: Binding<Bool> {
        Binding(get: { session.driveAccessError != nil }, set: { if !$0 { session.driveAccessError = nil } })
    }
}
