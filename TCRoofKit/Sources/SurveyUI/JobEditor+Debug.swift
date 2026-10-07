#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync

#if DEBUG
extension JobEditorView {
    /// `-surveyAutofill fill|conflict` writes docs/ui/a2-a3-autofill's A2 symbols (PEA meter, TX 1 630 kVA, MDP-1 800 AT, กันย้อน MV)
    /// into the opened job, linked and filled into A3 / B4 for `fill`; `conflict` first gives A3 one transformer of 500 kVA and leaves them for A3 to link.
    func seedAutofill() {
        guard let state = UserDefaults.standard.string(forKey: "surveyAutofill") else { return }
        job.values["trafos"] = state == "conflict" ? .transformers([Transformer(kva: "500")]) : nil
        for i in 0..<Transformer.maxTransformers { job.values["tr\(i)_feed"] = nil }
        if let k = job.modules.firstIndex(where: { $0.type == .backfeed }) { job.modules[k].values[ZeroExport.levelKey] = nil }
        job.values["siteMarks"] = .marks([
            MapMark(kind: .meter, x: 0.86, y: 0.08),
            MapMark(kind: .zeroExport, x: 0.86, y: 0.2, value: "MV"),
            MapMark(kind: .trafo, x: 0.78, y: 0.72, value: "630", label: "TX 1"),
            MapMark(kind: .mdb, x: 0.62, y: 0.95, value: "800", label: "MDP-1"),
        ])
        if job.values.photo("siteMap") == nil {
            // a plain green site picture so A2 has a stage to draw on
            let img = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1000)).image { ctx in
                UIColor(red: 0.42, green: 0.55, blue: 0.36, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
                UIColor(white: 0.78, alpha: 1).setFill(); ctx.fill(CGRect(x: 1180, y: 0, width: 140, height: 1000))
            }
            job.values["siteMap"] = model.addPhoto(img, to: job.id).map { .photo($0) }
        }
        if state == "fill" { SiteSync.push(&job) }
    }
}

/// Launch-argument helpers for simulator checks: open a page, and write wide pages offscreen to Documents.
extension JobEditorView {
    /// `-surveyPage site` opens A2, `electrical` A3, `sld` the single line diagram, `inverter` the first B2, `panels` the first B1, `flood` A4,
    /// `water` the first B3, `backfeed` the first B4, `fts` the first B5, `roof` the first C1, `tank` the first D1, `final` E1.
    /// `-surveyPlatePhoto YES` gives TX 1 an empty transformer and a rendered nameplate photo (630 kVA, 416/240 V, Dyn11,
    /// 4.0 %, 2022), so A3 shows `พบในรูปป้าย` from the photo reader.
    func seedPlatePhoto() {
        guard UserDefaults.standard.bool(forKey: "surveyPlatePhoto") else { return }
        var a = job.values.transformers("trafos")
        if a.isEmpty { a = [Transformer()] }
        a[0].kva = ""; a[0].voltage = ""; a[0].vectorGroup = ""; a[0].impedance = ""; a[0].year = ""
        job.values["trafos"] = .transformers(a)
        let lines = ["THREE PHASE TRANSFORMER", "RATED POWER 630 kVA   FREQ 50 Hz", "HV 22000 V   LV 416/240 V",
                     "VECTOR GROUP Dyn11", "IMPEDANCE VOLTAGE 4.0 %", "YEAR 2022   SERIAL No. 6S-2207-0153"]
        let img = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 900)).image { ctx in
            UIColor(white: 0.82, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1400, height: 900))
            let font = UIFont.monospacedSystemFont(ofSize: 54, weight: .bold)
            for (k, l) in lines.enumerated() {
                (l as NSString).draw(at: CGPoint(x: 70, y: 90 + k * 125), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
        job.values["tr0_plate"] = model.addPhoto(img, to: job.id).map { .photo($0) }
    }

    func openDebugPage() {
        seedAutofill()
        seedPlatePhoto()
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
            // no template has a tank: the demo job gets an empty D1 so the D1 checks run on any simulator
            if first(.tank) == nil { job.insertModule(SurveyModule(type: .tank)) }
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
                let page = TankPageWide(job: .constant(job), moduleID: id, width: w, stacked: free < 1100, tab: .constant(1))
                    .environment(model).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("tank-\(Int(free))x\(Int(h)).png")) }
            }
            // iPhone: the step line and sub-step 1 at 393 pt, without its scroll view (ImageRenderer leaves those blank)
            let phone = TankPageWide(job: .constant(job), moduleID: id, width: 361, stacked: true, tab: .constant(1), phoneLayout: true)
            let cards = VStack(spacing: 8) { PageStepBar(job: job, here: .module(id), compact: true, chip: phone.photoChip); phone.phoneSizeCards }
                .foregroundStyle(Home.navy).environment(model).padding(16).frame(width: 393).background(Home.lockedCard)
            let r = ImageRenderer(content: cards); r.scale = 3
            if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("tank-phone.png")) }
        }
    }
}
#endif
#endif
