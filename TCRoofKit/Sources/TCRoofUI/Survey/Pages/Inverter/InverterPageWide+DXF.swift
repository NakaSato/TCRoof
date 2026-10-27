#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// B2 `ส่งออก DXF`: the station's top, front and side views with the team's components (`InverterStationDXF`), at
/// real scale, shared as a file.
extension InverterPageWide {
    struct DXFShare: Identifiable { let id = UUID(); let url: URL }

    var dxfButton: some View {
        Button(action: exportDXF) {
            Label("ส่งออก DXF", systemImage: "square.and.arrow.up")
                .font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
        }
        .buttonStyle(.plain)
        .accessibilityHint("แปลน รูปด้านหน้า รูปด้านข้าง และรายละเอียดฐานเสา เป็นไฟล์ CAD มาตราส่วนจริง")
    }

    func exportDXF() {
        do {
            if let f = try model.exportInverterDXF(job, moduleID: moduleID) { dxfShare = DXFShare(url: f.url) }
        } catch { dxfError = error.localizedDescription }
    }
}
#endif
