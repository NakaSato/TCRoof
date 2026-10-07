#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation
import TCRoofCore
import ExcelExport
import PDFReport
import DriveSync

extension SurveyModel {
    // MARK: exports

    public struct ExportFile: Identifiable { public let id = UUID(); public let url: URL; public let summary: String }

    func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    static func safeName(_ s: String) -> String { s.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "-", options: .regularExpression) }
    func baseName(_ j: Job) -> String { Self.safeName("แบบสำรวจ NO.\(j.docNo.isEmpty ? "-" : j.docNo) \(j.projectName)".trimmingCharacters(in: .whitespaces)) }

    func excelData(_ job: Job) throws -> ExcelExporter.Result {
        let store = self.store
        return try ExcelExporter().export(job, photoData: { store.data(of: $0, in: job.id) }, planImage: { m in
            guard let sk = Drawings.plan(m.values, tank: m.type == .tank, width: 1100), let r = PDFRenderer.png(sk, scale: 1.5) else { return nil }
            return ExcelImage(data: r.0, width: r.1, height: r.2, isPNG: true)
        }, siteMapImage: markedSiteMap(job))
    }

    /// The site picture with its symbols drawn in, for the Excel frame (the PDF draws them as vectors).
    func markedSiteMap(_ job: Job) -> ExcelImage? {
        let marks = job.values.marks("siteMarks"), shapes = job.values.shapes(SiteShapes.key)
        guard !marks.isEmpty || !shapes.isEmpty, let p = job.values.photo("siteMap"), let img = image(p, in: job.id) else { return nil }
        let base = img.scaled(maxSide: 1600)
        let pic = base.size
        // legend strip below the picture, scaled to the picture's width
        let kinds = SiteMarks.usedKinds(marks), fs = max(9, Double(pic.width) * 0.014)
        let lh = SiteMarks.legendHeight(kinds, width: Double(pic.width), size: fs)
        let size = CGSize(width: pic.width, height: pic.height + CGFloat(lh))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            base.draw(in: CGRect(origin: .zero, size: pic))
            let box = Box(0, 0, Double(pic.width), Double(pic.height))
            PDFRenderer.draw(SiteShapes.ops(shapes, in: box, metersAcross: job.values.number(SiteShapes.scaleKey)), in: ctx.cgContext, photo: { _ in nil })
            PDFRenderer.draw(SiteMarks.ops(marks, in: box), in: ctx.cgContext, photo: { _ in nil })
            PDFRenderer.draw(SiteMarks.legend(kinds, in: Box(0, Double(pic.height), Double(pic.width), lh), size: fs), in: ctx.cgContext, photo: { _ in nil })
        }
        guard let data = out.jpegData(compressionQuality: 0.85) else { return nil }
        return ExcelImage(data: data, width: Int(size.width), height: Int(size.height), isPNG: false)
    }

    public func exportExcel(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let r = try excelData(job)
        let url = tempURL(baseName(job) + ".xlsx")
        try r.data.write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Excel \(r.sheets.count) แผ่น · \(r.pictures) รูป")
    }

    var reportHeader: ReportHeader { ReportHeader(company: settings.company, photoStamps: settings.printPhotoStamps) }

    public func pdfData(_ job: Job) -> Data {
        PDFRenderer.render(job: job, header: reportHeader, photo: { [weak self] p in self?.image(p, in: job.id) })
    }

    public func exportSummaryPDF(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let url = tempURL("สรุป " + baseName(job) + ".pdf")
        try PDFRenderer.renderSummary(job: job, header: reportHeader, photo: { [weak self] p in self?.image(p, in: job.id) }).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "PDF สรุป 1 หน้า")
    }

    /// The single line diagram alone on an A3 landscape page.
    public func exportSingleLinePDF(_ job: Job, hv: Bool? = nil) throws -> ExportFile {
        flush(job.id)
        let url = tempURL("SLD " + baseName(job) + ".pdf")
        try PDFRenderer.renderSingleLine(job: job, header: reportHeader, hv: hv, photo: { _ in nil }).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Single Line Diagram A3")
    }

    /// The single line diagram as DXF R12 at A3 paper scale (`SingleLineDXF`), for CAD programs.
    public func exportSingleLineDXF(_ job: Job, hv: Bool? = nil) throws -> ExportFile {
        flush(job.id)
        let url = tempURL("SLD " + baseName(job) + ".dxf")
        try SingleLineDXF.build(job, hv: hv).data.write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Single Line Diagram DXF")
    }

    /// A D1 tank's roof plan and panel layout as DXF R12 at real scale (`TankDXF`), named like C1's: `NO<job no>_D1.dxf`.
    public func exportTankDXF(_ job: Job, moduleID: UUID) throws -> ExportFile? {
        flush(job.id)
        guard let m = job.modules.first(where: { $0.id == moduleID }), let out = TankDXF.build(m.values) else { return nil }
        let section = job.sectionsByCategory.flatMap(\.sections).first { $0.id == moduleID }?.number ?? "D1"
        let url = tempURL(((job.docNo.isEmpty ? "" : "NO" + job.docNo + "_") + section).replacingOccurrences(of: " ", with: "") + ".dxf")
        try out.data.write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Tank plan DXF")
    }

    /// The A2 site plan (models, shapes, symbols over the picture's frame) as DXF R12 (`SiteDXF`): `NO<job no>_A2.dxf`.
    public func exportSiteDXF(_ job: Job) throws -> ExportFile? {
        flush(job.id)
        guard let out = SiteDXF.build(job) else { return nil }
        let url = tempURL(((job.docNo.isEmpty ? "" : "NO" + job.docNo + "_") + "A2").replacingOccurrences(of: " ", with: "") + ".dxf")
        try out.data.write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Site plan DXF")
    }

    public func exportPDF(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let url = tempURL(baseName(job) + ".pdf")
        try pdfData(job).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "รายงาน PDF")
    }

    public func exportBackup(_ ids: [UUID]? = nil) throws -> ExportFile {
        let list = ids.map { set in jobs.filter { set.contains($0.id) } } ?? jobs
        let url = tempURL("solar-survey-backup-\(ISODate.string(Date())).json")
        try WebBackup.exportBackup(list, store: store).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "สำรองข้อมูล \(list.count) งาน")
    }

    /// Imports a backup or survey-data file (from this app or the web version).
    public func importFile(_ url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let imported = try WebBackup.importJobs(Data(contentsOf: url), into: store)
        reload()
        return imported.count
    }
}
#endif
