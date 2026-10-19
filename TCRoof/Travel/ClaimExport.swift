import Foundation
import SwiftData
import UIKit
import TCRoofCore
import TCRoofUI
import PDFReport
import ExcelExport

/// A month's claim as files (§B5): the PDF with every receipt, the Excel sheet, and their upload to the person's Drive
/// under `เบิกค่าใช้จ่าย/<ปี-เดือน>/<ชื่อ>/` when submitted (§B6).
@MainActor
struct ClaimExport {
    let month: String
    let context: ModelContext

    var trips: [Trip] { TravelStore.trips(context, month: month) }
    var expenses: [Expense] { TravelStore.expenses(context, month: month) }
    var claim: ClaimMonth? { TravelStore.claim(context, month: month) }
    var summary: TravelClaim.Summary { TravelClaim.Summary(days: trips.map(\.day), items: expenses.map(\.item)) }

    /// "2569-10", the folder and file names' month.
    var thaiKey: String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        return parts.count == 2 ? String(format: "%04d-%02d", parts[0] + 543, parts[1]) : month
    }
    var fileStem: String { "ใบเบิก \(thaiKey) \(TravelStore.person)" }

    func jobNames() -> [String: String] {
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        var out: [String: String] = [:]
        for j in jobs { if let id = j.syncID { out[id] = TravelStore.label(j) } }
        // a job removed since keeps the label stamped on its stop
        for t in trips { for s in t.stops { if let id = s.jobID, out[id] == nil { out[id] = s.label } } }
        return out
    }

    private func photo(_ key: String, _ data: Data) -> Photo {
        let size = UIImage(data: data)?.size ?? CGSize(width: 3, height: 4)
        return Photo(fileName: key, width: Int(size.width), height: Int(size.height))
    }

    func pages() -> (pages: [ReportLayout.Page], images: [String: Data]) {
        var images: [String: Data] = [:]
        var receipts: [String: Photo] = [:]
        for e in expenses {
            guard let id = e.syncID, let data = e.receipt else { continue }
            receipts[id] = photo("receipt-\(id)", data)
            images["receipt-\(id)"] = data
        }
        var odometers: [ClaimPages.Picture] = []
        for t in trips {
            for (end, data) in [("ออก", t.odoStartPhoto), ("กลับ", t.odoEndPhoto)] {
                guard let data, let id = t.syncID else { continue }
                let key = "odo-\(end)-\(id)"
                images[key] = data
                odometers.append(.init(photo: photo(key, data), caption: "เลขไมล์\(end) · \(RoutineReport.thaiDate(t.date))"))
            }
        }
        var signature: Photo?
        if let sig = claim?.signature {
            signature = photo("signature", sig)
            images["signature"] = sig
        }
        let header = ClaimPages.Header(company: TravelSettings.company, person: TravelStore.person, email: TravelStore.owner,
                                       month: TravelClaim.monthStart(month) ?? .now, submittedAt: claim?.submittedAt)
        let claimPages = ClaimPages(header: header, summary: summary, jobNames: jobNames(), receipts: receipts,
                                    odometers: odometers, signature: signature, measure: PDFRenderer.Measure())
        return (claimPages.pages(), images)
    }

    func pdf() -> Data {
        let (pages, images) = pages()
        return PDFRenderer.pdf(pages: pages, title: fileStem) { p in images[p.fileName].flatMap(UIImage.init(data:)) }
    }

    func excel() throws -> Data {
        let numbers = ClaimPages(header: .init(company: "", person: "", email: "", month: .now), summary: summary, jobNames: [:],
                                 receipts: Dictionary(uniqueKeysWithValues: expenses.compactMap { e in
                                     e.hasReceipt ? e.syncID.map { ($0, Photo(fileName: $0, width: 1, height: 1)) } : nil
                                 })).receiptNumbers
        return try ClaimExcel.export(company: TravelSettings.company, person: TravelStore.person, email: TravelStore.owner,
                                     month: TravelClaim.monthStart(month) ?? .now, submittedAt: claim?.submittedAt,
                                     summary: summary, jobNames: jobNames(), receiptNumbers: numbers)
    }

    /// Both files in the temporary folder, for the share sheet.
    func files() throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claims", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdfURL = dir.appendingPathComponent(fileStem + ".pdf")
        let xlsxURL = dir.appendingPathComponent(fileStem + ".xlsx")
        try pdf().write(to: pdfURL)
        try excel().write(to: xlsxURL)
        return [pdfURL, xlsxURL]
    }

    // MARK: submit

    /// ยื่นเบิก: locks the month with the signature and logs it. The upload follows (`upload`).
    func submit(signature: Data?) {
        let c = TravelStore.claim(context, month: month, create: true)!
        c.signature = signature
        c.submittedAt = .now
        c.addLog("ยื่นเบิก \(Self.stamp(.now)) · \(TravelClaim.baht(summary.total)) บาท")
        try? context.save()
    }

    /// ถอนการยื่น: unlocks the month for edits; the files on Drive stay as the record of what was sent.
    func withdraw(reason: String) {
        guard let c = claim else { return }
        c.submittedAt = nil
        c.addLog("ถอนการยื่น \(Self.stamp(.now))" + (reason.isEmpty ? "" : " · \(reason)"))
        try? context.save()
    }

    static func stamp(_ d: Date) -> String {
        let c = TravelClaim.calendar.dateComponents([.hour, .minute], from: d)
        return RoutineReport.thaiDate(d) + String(format: " %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// The claim's PDF and Excel, every receipt and odometer photo, into the person's own Drive. Each receipt keeps its
    /// Drive id, which reaches the person's other devices with the record.
    func upload(_ survey: SurveyModel) async throws {
        guard let c = claim else { return }
        let folder = try await survey.driveFolder(thaiKey, root: Self.driveRoot)
        let sub = try await survey.driveSubfolder([TravelStore.person], under: folder.id)
        for e in expenses {
            guard let data = e.receipt, e.receiptDriveID == nil, let id = e.syncID else { continue }
            let name = "ใบเสร็จ \(RoutineReport.thaiDate(e.date)) \(e.category.title) \(id.prefix(6)).jpg"
            e.receiptDriveID = try await survey.driveUpload(DriveUpload(name: name, data: data, mimeType: "image/jpeg"), to: sub)
            try? context.save()
        }
        for t in trips {
            let date = RoutineReport.thaiDate(t.date)
            if let data = t.odoStartPhoto, t.odoStartDriveID == nil {
                t.odoStartDriveID = try await survey.driveUpload(DriveUpload(name: "เลขไมล์ออก \(date).jpg", data: data, mimeType: "image/jpeg"), to: sub)
            }
            if let data = t.odoEndPhoto, t.odoEndDriveID == nil {
                t.odoEndDriveID = try await survey.driveUpload(DriveUpload(name: "เลขไมล์กลับ \(date).jpg", data: data, mimeType: "image/jpeg"), to: sub)
            }
            try? context.save()
        }
        c.pdfDriveID = try await survey.driveUpload(DriveUpload(name: fileStem + ".pdf", data: pdf(), mimeType: "application/pdf"), to: sub)
        c.excelDriveID = try await survey.driveUpload(
            DriveUpload(name: fileStem + ".xlsx", data: try excel(), mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            to: sub)
        c.driveFolderURL = "https://drive.google.com/drive/folders/\(sub)"
        try? context.save()
    }

    static let driveRoot = "เบิกค่าใช้จ่าย"
}
