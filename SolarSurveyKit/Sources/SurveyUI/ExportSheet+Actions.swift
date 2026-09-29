#if canImport(UIKit)
import SwiftUI
import SurveyCore
import DriveSync


/// Build, preview, share and save to Drive, with the confirmations before sending.
extension ExportSheet {
    func file(_ f: Format, _ job: Job) throws -> SurveyModel.ExportFile {
        switch f {
        case .report: return try model.exportPDF(job)
        case .summary: return try model.exportSummaryPDF(job)
        case .excel: return try model.exportExcel(job)
        case .data: return try model.exportBackup([job.id])
        case .photos: throw DriveFailure(message: "รูปภาพบันทึกลง Google Drive เท่านั้น")
        }
    }

    /// Builds on the next run-loop turn so the progress line shows first.
    func run(_ message: String, _ work: @escaping () async throws -> Void) {
        busy = message; error = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    func previewPDF(_ f: Format) {
        guard let job = model.job(jobID) else { return }
        run("กำลังสร้าง \(f.title)…") {
            let out = try file(f, job)
            preview = PDFPreviewItem(url: out.url, title: (f == .summary ? "สรุป " : "") + job.projectName)
        }
    }

    /// Runs `go` at once, or after the user agrees to export without the photos this device lacks.
    func confirmPhotos(_ go: @escaping () -> Void) {
        guard let job = model.job(jobID) else { return }
        let gap = PhotoGap(model: model, job: job)
        if gap.missing == 0 { go() } else { pendingGo = PendingGo(gap: gap, go: go) }
    }

    /// Runs `go`, first asking before a PDF leaves without both signatures.
    func confirmSigned(pdf: Bool, _ go: @escaping () -> Void) {
        let names = pdf ? model.job(jobID)?.missingSignatures ?? [] : []
        if names.isEmpty { go() } else { pendingUnsigned = PendingUnsigned(names: names, go: go) }
    }

    func fetchPhotos() {
        run("กำลังดาวน์โหลดรูปจาก Google Drive…") {
            if !model.google.isSignedIn { try await model.google.signIn() }
            signedIn = true
            await model.fetchMissingPhotos(jobID)
            if let f = model.photoFetch[jobID], f.failed > 0 {
                throw DriveFailure(message: "ดาวน์โหลดรูปไม่สำเร็จ \(f.failed) รูป" + (f.error.map { ": " + $0 } ?? ""))
            }
        }
    }

    func share() { confirmSigned(pdf: pdfSelected) { confirmPhotos(doShare) } }
    func doShare() {
        guard let job = model.job(jobID) else { return }
        let formats = selected.filter(\.shareable)
        log = []
        run("กำลังสร้างไฟล์…") {
            var urls: [URL] = []
            for f in formats {
                busy = "กำลังสร้าง \(f.title)…"
                await Task.yield()
                let out = try file(f, job)
                urls.append(out.url)
                log.append("✓ " + out.summary)
            }
            shared = Shared(urls: urls)
        }
    }

    func signIn() {
        run("กำลังลงชื่อเข้าใช้ Google…") {
            try await model.google.signIn()
            signedIn = true
        }
    }

    func saveToDrive() { confirmSigned(pdf: selected.contains(.report)) { confirmPhotos(doSaveToDrive) } }
    func doSaveToDrive() {
        guard let job = model.job(jobID) else { return }
        let kinds = driveKinds, photos = selected.contains(.photos)
        log = []
        run("กำลังบันทึกลง Google Drive…") {
            do {
                if !model.google.isSignedIn { try await model.google.signIn() }
                signedIn = true
                _ = try await model.saveToDrive(job, kinds: kinds, photos: photos) { step in
                    Task { @MainActor in
                        switch step {
                        case .folder(let n): log.append("✓ โฟลเดอร์ \(n)")
                        case .building(let k): log.append("… กำลังสร้าง \(k.label)")
                        case .uploading(let k, let bytes): log.append("… อัปโหลด \(k.rawValue.uppercased()) \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                        case .uploaded(_, let f): log.append("✓ \(f.name)")
                        case .photos(let done, let total):
                            // one line that counts up instead of a line per photo
                            let line = total == 0 ? "✓ รูปภาพอยู่ใน Drive ครบแล้ว" : done < total ? "… อัปโหลดรูป \(done)/\(total)" : "✓ รูปภาพ \(total) รูป"
                            if log.last?.hasPrefix("… อัปโหลดรูป") == true { log[log.count - 1] = line } else { log.append(line) }
                        }
                    }
                }
                log.append("บันทึกลง Google Drive เรียบร้อย")
            } catch let e as DriveSync.Interrupted {
                throw DriveFailure(message: e.localizedDescription + "\nรูปที่อัปโหลดแล้วถูกบันทึกไว้ — กดบันทึกอีกครั้งเพื่อส่งรูปที่เหลือ")
            } catch {
                throw DriveFailure(message: error.localizedDescription + "\nไฟล์อาจอัปโหลดไปแล้วบางส่วน — ตรวจสอบในโฟลเดอร์ก่อนบันทึกซ้ำ")
            }
        }
    }

    struct DriveFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
}
#endif
