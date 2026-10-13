#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// D1 `ส่งออก DXF` (docs/specs/cad-export-dxf phase 3): the tank plan and its panel layout at real scale, shared as a file.
extension TankPageWide {
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
        .disabled(TankPlan(values) == nil)
        .accessibilityHint("แปลนถังและผังแผงเป็นไฟล์ CAD มาตราส่วนจริง")
    }

    func exportDXF() {
        do {
            if let f = try model.exportTankDXF(job, moduleID: moduleID) { dxfShare = DXFShare(url: f.url) }
        } catch { dxfError = error.localizedDescription }
    }
}
#endif
