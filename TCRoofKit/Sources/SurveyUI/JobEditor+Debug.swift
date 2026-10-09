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
        seedReview()
        let first: (ModuleType) -> Page? = { t in job.modules.first { $0.type == t }.map { .module($0.id) } }
        // `-surveyA1Render YES` writes A1 and its bar at free widths 1366 / 1180 to Documents/a1-<w>x<h>.png
        if UserDefaults.standard.bool(forKey: "surveyA1Render") { renderInfo() }
        switch UserDefaults.standard.string(forKey: "surveyPage") {
        case "site":
            select(.site)
            // `-surveySiteDXF YES` also writes the site plan's DXF to Documents/site.dxf (with `-surveyAutofill`'s symbols when given)
            if UserDefaults.standard.bool(forKey: "surveySiteDXF"), let out = SiteDXF.build(job) { writeDebugFile("site.dxf", out.data) }
        case "electrical": select(.electrical)
        case "photos": select(.photos)
        case "revisions": select(.revisions)
        case "sld":
            select(.electrical); showSLD = true
            // `-surveySLDDXF YES` also writes the diagram's DXF to Documents/sld.dxf
            if UserDefaults.standard.bool(forKey: "surveySLDDXF") { writeDebugFile("sld.dxf", SingleLineDXF.build(job).data) }
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
            // `-surveyTankDXF YES` also writes its DXF to Documents/tank.dxf, after `-surveyD1` has seeded the tank
            if UserDefaults.standard.bool(forKey: "surveyTankDXF"), let id = job.modules.first(where: { $0.type == .tank })?.id {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if let v = job.modules.first(where: { $0.id == id })?.values, let out = TankDXF.build(v) { writeDebugFile("tank.dxf", out.data) }
                }
            }
        default: break
        }
    }

    /// `-surveyReview sign|locked|rev01|broken`: the review lock's states (docs/specs/review-lock-revisions-swift.md) on the demo
    /// job. `sign` signs both after a moment (the lock sheet opens), `locked` issues REV 00, `rev01` issues it, opens REV 01
    /// and changes the name and the site picture, `broken` locks then edits job.json's answers behind the lock.
    func seedReview() {
        guard let state = UserDefaults.standard.string(forKey: "surveyReview") else { return }
        func picture(_ text: String, _ size: CGSize, png: Bool) -> Photo? {
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                if !png { UIColor(red: 0.55, green: 0.7, blue: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size)) }
                (text as NSString).draw(at: CGPoint(x: 30, y: size.height / 2 - 40),
                                        withAttributes: [.font: UIFont.italicSystemFont(ofSize: 64), .foregroundColor: UIColor.darkGray])
            }
            return model.addPhoto(img, to: job.id, png: png)
        }
        func sign(_ j: inout Job) {
            j.values["surveyorSign"] = picture("สมชาย", CGSize(width: 600, height: 200), png: true).map { .photo($0) }
            j.values["customerSign"] = picture("ประสาน", CGSize(width: 600, height: 200), png: true).map { .photo($0) }
        }
        if job.values.photo("siteMap") == nil { job.values["siteMap"] = picture("ภาพสถานที่", CGSize(width: 1200, height: 900), png: false).map { .photo($0) } }
        switch state {
        case "sign":
            job.values["surveyorSign"] = picture("สมชาย", CGSize(width: 600, height: 200), png: true).map { .photo($0) }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                job.values["customerSign"] = picture("ประสาน", CGSize(width: 600, height: 200), png: true).map { .photo($0) }
            }
        case "locked", "rev01", "broken":
            guard !job.isLocked, state == "locked" || (job.revisions ?? []).isEmpty else { return }
            var j = job
            sign(&j)
            job = j
            model.update(j)
            try? model.issue(job.id)
            if let issued = model.job(job.id) { job = issued }
            if state == "rev01" {
                openNextRevision(reason: "สถานีแจ้งขนาดหม้อแปลงใหม่", updateDate: true)
                job.values["projectName"] = .text(job.projectName + " (แก้ไข)")
                job.values["siteMap"] = picture("ภาพใหม่", CGSize(width: 1200, height: 900), png: false).map { .photo($0) }
                job.values["internet"] = .choice("ไม่มี", other: "")
            } else if state == "broken" {
                var edited = job
                edited.values["projectName"] = .text("แก้นอกแอป")
                model.applyRemote(edited)
                job = edited
                checkIntegrity()
            }
        default: break
        }
    }

    func writeDebugFile(_ name: String, _ data: Data) {
        try? data.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name))
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

    /// A1 in landscape (docs/ui/survey-a1-ipad) with the board's example answers on a copy of the job, then its bar
    /// (`-surveySave` picks the save button's state). Text fields show as placeholders in ImageRenderer.
    func renderInfo() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var sample = job
        for (k, v) in [("docNo", "224"), ("rev", "00"), ("date", "2026-09-29"), ("engineer", "สมชาย"),
                       ("projectName", "กปภ. สาขาตัวอย่าง — สถานีผลิตน้ำ 1"), ("capacity", "120"),
                       ("address", "ม.3 ต.หนองบัว อ.เมือง จ.ตัวอย่าง 60000"), ("coordinator", "คุณสมหญิง ใจดี"),
                       ("phone", "081-234-5678"), ("gps", "17.0062, 99.8235")] { sample.values[k] = .text(v) }
        sample.values["internet"] = .choice("มี", other: "")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for (free, h) in [(1366.0, 848.0), (1180.0, 636.0)] {
                let page = InfoPageWide(job: .constant(sample), width: min(free, 1240 + 48) - 48, fillHeight: h - 32)
                    .environment(model).environment(\.horizontalSizeClass, .regular)
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(width: free, height: h, alignment: .top).background(Paper.page)
                let r = ImageRenderer(content: page); r.scale = 1
                if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("a1-\(Int(free))x\(Int(h)).png")) }
            }
            let bar = InfoPageBar(job: sample, next: {}).environment(model).environment(\.horizontalSizeClass, .regular)
                .frame(width: 1366).background(Paper.page)
            let r = ImageRenderer(content: bar); r.scale = 2
            if let d = r.uiImage?.pngData() { try? d.write(to: dir.appendingPathComponent("a1-bar.png")) }
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
