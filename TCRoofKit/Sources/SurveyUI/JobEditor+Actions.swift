#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync

/// The editor toolbar, the export check, links from the diagram, and adding or removing sections.
extension JobEditorView {
    // MARK: toolbar

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { withAnimation { sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { model.flush(job.id); showExport = true } label: {
                if compact { Label("ส่งออก", systemImage: "square.and.arrow.up") }
                else { Label("ส่งออก", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon) }
            }
            .overlay(alignment: .topTrailing) {
                // the export sheet explains the gap; this dot just says there is one
                if !job.missingGroups.isEmpty { Circle().fill(.orange).frame(width: 8, height: 8).offset(x: 4, y: -2) }
            }
        }
    }

    /// Warns before a PDF export while required answers or signatures are missing, listing them per page.
    func checked(_ go: @escaping () -> Void) {
        let groups = job.missingGroups
        let photos = PhotoGap(model: model, job: job)
        let unsigned = job.missingSignatures
        // ตรวจรูปทั้งหมด: required photo slots still empty, listed by group
        let slots = job.photoSlots.filter { $0.missingRequired > 0 }
        guard !groups.isEmpty || photos.missing > 0 || !slots.isEmpty else { return go() }
        let lines = (unsigned.isEmpty ? [] : ["PDF ที่ส่ง กปภ. ยังไม่มี" + unsigned.joined(separator: " และ")])
            + (photos.missing > 0 ? [photos.message] : [])
            + (slots.isEmpty ? [] : ["ยังขาดรูปบังคับ \(job.missingRequiredPhotos) รูป: " + slots.map { "\($0.id) \($0.missingRequired)" }.joined(separator: ", ")])
            + groups.map { "\($0.title): \($0.items.count) รายการ" }
        pendingExport = PendingExport(gaps: lines, target: unsigned.isEmpty ? groups.first?.target : .final, photos: !slots.isEmpty, go: go)
    }

    /// A tap or link on the single line diagram: close it and open the page (and item) it points at.
    func openFromDiagram(_ t: SLTarget) {
        showSLD = false
        switch t.page {
        case .info: select(.info)
        case .flood: select(.flood)
        case .module(let type):
            if let m = job.modules.first(where: { $0.type == type }) { select(.module(m.id)) } else { select(.electrical) }
        case .electrical:
            select(.electrical)
            if t.trafo != nil {
                // the page must be on screen before it can open the item
                DispatchQueue.main.async { electricalFocus = t; electricalRequest = t.trafo }
            }
        }
    }

    func page(for target: MissingGroup.Target) -> Page { Self.page(for: target) }
    static func page(for target: MissingGroup.Target) -> Page {
        switch target {
        case .info: return .info
        case .site: return .site
        case .electrical: return .electrical
        case .flood: return .flood
        case .module(let id): return .module(id)
        case .final: return .final
        }
    }

    /// Runs an export on the next run-loop turn so the busy overlay shows first.
    func run(_ message: String, _ work: @escaping () throws -> Void) {
        busy = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            do { try work() } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    // MARK: sections

    func add(_ t: ModuleType) {
        let m = SurveyModule(type: t)
        job.insertModule(m)
        page = .module(m.id)
    }
    func duplicate(_ m: SurveyModule) {
        guard let i = job.modules.firstIndex(where: { $0.id == m.id }) else { return }
        var c = SurveyModule(type: m.type, name: m.name)
        // text answers only; photos stay with the original
        for (k, v) in m.values.storage { switch v { case .photo, .photos: continue; default: c.values[k] = v } }
        job.modules.insert(c, at: i + 1)
        page = .module(c.id)
    }
    func remove(_ m: SurveyModule) {
        if page == .module(m.id) { page = .info }
        ModuleMarks.removeAll(&job, for: m)
        job.modules.removeAll { $0.id == m.id }
        confirmDelete = nil
    }
}
#endif
