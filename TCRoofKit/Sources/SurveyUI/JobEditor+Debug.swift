#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync

#if DEBUG
/// Launch-argument helpers for simulator checks: open a page, and write wide pages offscreen to Documents.
extension JobEditorView {
    /// `-surveyPage site` opens A2, `electrical` A3, `sld` the single line diagram, `inverter` the first B2, `panels` the first B1, `flood` A4,
    /// `water` the first B3, `backfeed` the first B4, `fts` the first B5, `roof` the first C1, `tank` the first D1, `final` E1.
    func openDebugPage() {
        let first: (ModuleType) -> Page? = { t in job.modules.first { $0.type == t }.map { .module($0.id) } }
        switch UserDefaults.standard.string(forKey: "surveyPage") {
        case "site": select(.site)
        case "electrical": select(.electrical)
        case "sld": select(.electrical); showSLD = true
        case "inverter": if let p = first(.inverter) { select(p) }
        case "panels": if let p = first(.panel) { select(p) }
        case "flood": select(.flood)
        case "water": if let p = first(.water) { select(p) }
        case "backfeed":
            if let p = first(.backfeed) { select(p) }
            // `-surveyB4Render YES` also writes B4 at free widths 1366 / 1180 to Documents/backfeed-<w>x<h>.png
            if UserDefaults.standard.bool(forKey: "surveyB4Render"), let m = job.modules.first(where: { $0.type == .backfeed }) { renderBackfeed(m.id) }
        case "fts": if let p = first(.fts) { select(p) }
        case "roof":
            if let p = first(.roof) { select(p) }
            // `-surveyRoofRender YES` also writes C1 at free widths 980 / 1100 / 1318 to Documents/roof-<w>.png (no rotation here)
            if UserDefaults.standard.bool(forKey: "surveyRoofRender"), let m = job.modules.first(where: { $0.type == .roof }) { renderRoof(m.id) }
        case "final":
            select(.final)
            // `-surveyFinalRender YES` also writes E1 at free widths 1366 / 1180 to Documents/final-<w>x<h>.png
            if UserDefaults.standard.bool(forKey: "surveyFinalRender") { renderFinal() }
        case "tank":
            if let p = first(.tank) { select(p) }
            // `-surveyTankRender YES` also writes D1 at free widths 1366 / 1180 / 1100 to Documents/tank-<w>x<h>.png
            if UserDefaults.standard.bool(forKey: "surveyTankRender"), let m = job.modules.first(where: { $0.type == .tank }) { renderTank(m.id) }
        default: break
        }
    }

    func renderRoof(_ id: UUID) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // free width × free height: 13" landscape ≈ 848 pt high, 11" ≈ 636; stacked ones are drawn unscrolled, taller
        // after `-surveyC1` has seeded the example roof
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0), (980.0, 1500.0)] {
                let w = min(free, 1318 + 48) - 48
                let page = RoofPageWide(job: .constant(job), moduleID: id, width: w, stacked: free < 1100, scrolls: false)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("roof-\(Int(free))x\(Int(h)).png")) }
            }
        }
    }

    func renderFinal() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0)] {
                let w = min(free, 1240 + 48) - 48
                let page = FinalPageWide(job: .constant(job), width: w, scrolls: false)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("final-\(Int(free))x\(Int(h)).png")) }
            }
        }
    }

    func renderBackfeed(_ id: UUID) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Task { @MainActor in
            // let `-surveyB4` seed the job first
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0)] {
                let page = BackfeedPageWide(job: .constant(job), moduleID: id, width: min(free, 1318 + 48) - 48)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("backfeed-\(Int(free))x\(Int(h)).png")) }
            }
            // the one-column layout at an iPhone's width, without its scroll view (ImageRenderer leaves those blank)
            let phone = BackfeedPageWide(job: .constant(job), moduleID: id, width: 370, stacked: true)
            let cards = phone.stackedCards(phone.line).environment(model).padding(16).frame(width: 402).background(Paper.page)
            let r = ImageRenderer(content: cards); r.scale = 1
            if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("backfeed-phone.png")) }
        }
    }

    func renderTank(_ id: UUID) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Task { @MainActor in
            // let `-surveyD1` seed the job first
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0), (1100.0, 848.0)] {
                let w = min(free, 1318 + 48) - 48
                let page = TankPageWide(job: .constant(job), moduleID: id, width: w, stacked: free < 1100)
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("tank-\(Int(free))x\(Int(h)).png")) }
            }
        }
    }
}
#endif
#endif
