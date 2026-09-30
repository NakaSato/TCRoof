#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SurveyCore
import DriveSync

/// Entry point of the survey-report feature. Put it inside a NavigationStack
/// (TCRoof pushes it from "สำรวจหน้างาน"; a standalone app wraps it in `SolarSurveyScene`).
public struct SolarSurveyReportView: View {
    @State private var model = SurveyModel.shared
    let title: String
    let subtitle: String
    /// - Parameters:
    ///   - title: heading of the job list, e.g. the client group "การประปาส่วนภูมิภาค".
    public init(title: String = "PWA Solar Survey",
                subtitle: String = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)") {
        self.title = title; self.subtitle = subtitle
    }
    public var body: some View { SurveyHomeView(title: title, subtitle: subtitle).environment(model) }
}

public extension SurveyModel {
    @MainActor static let shared = SurveyModel()
}

struct SurveyHomeView: View {
    var title = "PWA Solar Survey"
    var subtitle = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
    @Environment(SurveyModel.self) var model
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) var dismiss
    /// Pushed by the host app (TCRoof) rather than the root of its own scene — show a back button.
    @Environment(\.isPresented) var isPushed
    @State var search = ""
    @State var filter = Filter.all
    @State var sort = Sort.updated
    @State var showNew = false
    @State var open: Opening?
    @AppStorage("solarSurvey.lastOpened") var lastOpened = ""
    @State var importing = false
    @State var showSettings = false
    @State var showDriveOpen = false
    @State var share: SurveyModel.ExportFile?
    @State var toDelete: Job?
    @State var message: String?
    @State var error: String?
    @State var busy: String?
    @State var pendingSync: PendingSync?
    /// Home tab: surveys, installations, maintenance; kept between launches.
    @AppStorage("solarSurvey.homeTab") var tab = JobStage.survey
    @State var showInstallPicker = false
    /// Installation job whose tracking page is open.
    @State var tracking: UUID?

    /// A job to open, optionally at the step "continue" points to.
    struct Opening: Hashable { let id: UUID; var start: MissingGroup.Target? = nil }
    struct PendingSync: Identifiable { let id = UUID(); let notes: [String] }

    enum Filter: CaseIterable {
        case all, active, draft, unsynced
        var title: String { [.all: "ทั้งหมด", .active: "กำลังสำรวจ", .draft: "ร่าง", .unsynced: "รอซิงก์"][self]! }
        var detail: String { [.all: "งานในเครื่องนี้", .active: "ยังไม่ครบทุกขั้น", .draft: "ยังไม่ตั้งชื่อ / เลขที่", .unsynced: "ยังไม่ขึ้นคลาวด์"][self]! }
        var heading: String { self == .all ? "งานทั้งหมด" : title }
    }
    enum Sort: CaseIterable {
        case updated, docNo, progress
        var title: String { [.updated: "แก้ไขล่าสุด", .docNo: "เลขที่", .progress: "ความคืบหน้า"][self]! }
    }

    func matches(_ j: Job, _ f: Filter) -> Bool {
        switch f {
        case .all: return true
        case .active: return !j.projectName.isEmpty && !j.completion.isComplete
        case .draft: return j.projectName.isEmpty
        case .unsynced: return model.waitsForSync(j)
        }
    }

    /// The tab's jobs matching the search.
    var searched: [Job] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let jobs = model.jobs(in: tab)
        guard !q.isEmpty else { return jobs }
        return jobs.filter { j in
            [j.docNo, j.projectName, j.values.text("address"), j.values.text("coordinator"), j.values.text("engineer")].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var shown: [Job] {
        // the four filter boxes only show on the survey tab
        let list = tab == .survey ? searched.filter { matches($0, filter) } : searched
        switch sort {
        case .updated: return list.sorted { $0.updated > $1.updated }
        // numbered jobs in order, unnumbered drafts last
        case .docNo: return list.sorted { a, b in
            if a.docNo.isEmpty != b.docNo.isEmpty { return b.docNo.isEmpty }
            return a.docNo.localizedStandardCompare(b.docNo) == .orderedAscending
        }
        case .progress where tab == .install: return list.sorted { ($0.install?.percent ?? 0) > ($1.install?.percent ?? 0) }
        case .progress: return list.sorted { $0.completion.fraction > $1.completion.fraction }
        }
    }

    var compact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(Paper.tick) }
                    tabBar
                    if tab == .survey { stats }
                    if tab != .survey && model.jobs(in: tab).isEmpty {
                        stageEmpty
                    } else {
                        listHeading
                        if shown.isEmpty { empty } else { grid }
                    }
                }
                .padding(.horizontal, compact ? 16 : 24).padding(.top, 20)
                // room for the floating button under the last row
                .padding(.bottom, 110)
                .frame(maxWidth: 1240).frame(maxWidth: .infinity)
            }
        }
        .background(Paper.page)
        .overlay(alignment: .bottom) {
            HStack { Spacer(); floatingButton }
                .padding(.horizontal, compact ? 16 : 24).padding(.bottom, compact ? 12 : 24)
                .frame(maxWidth: 1240)
        }
        // the blue header replaces the navigation bar; navigationTitle stays for the editor's back menu
        .navigationTitle(title)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $open) { o in
            if let j = model.job(o.id) { JobEditorView(job: j, start: o.start).environment(model) }
        }
        .navigationDestination(item: $tracking) { id in
            if let j = model.job(id) { InstallTrackingView(job: j) }
        }
        #if DEBUG
        // `-surveyDemo YES` opens a job right away for simulator checks; add `-surveyDemoSection YES` to open its first section.
        // `-surveyNew YES` opens the new-survey sheet.
        .task { if UserDefaults.standard.bool(forKey: "surveyNew") { showNew = true } }
        .task {
            guard UserDefaults.standard.bool(forKey: "surveyDemo"), open == nil else { return }
            go(model.jobs.first ?? model.create(JobTemplate.all[0], engineer: model.settings.engineer))
        }
        #endif
        .sheet(isPresented: $showNew) {
            NewJobSheet { t in let j = model.create(t, engineer: model.settings.engineer); showNew = false; go(j) }
        }
        .sheet(isPresented: $showInstallPicker) {
            InstallPickerSheet(jobs: model.jobs(in: .survey).filter { $0.stage == .survey }) { id in
                guard model.moveToInstall(id) else { return }
                showInstallPicker = false
                withAnimation(.snappy) { tab = .install }
            }
        }
        #if DEBUG
        // `-surveyInstallPicker YES` opens "เพิ่มโครงการติดตั้ง" for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveyInstallPicker") { showInstallPicker = true } }
        #endif
        .sheet(isPresented: $showSettings) { SurveySettingsView().environment(model) }
        .sheet(isPresented: $showDriveOpen) { DriveOpenView { j in showDriveOpen = false; go(j) }.environment(model) }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { r in
            do {
                guard let url = try r.get().first else { return }
                let n = try model.importFile(url)
                message = "นำเข้า \(n) งานแล้ว"
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("ลบงานนี้?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { j in
            Button("ลบ \(j.projectName)", role: .destructive) { model.delete(j.id); toDelete = nil }
        } message: { _ in Text("ข้อมูลและรูปทั้งหมดของงานนี้ในเครื่องจะถูกลบ (ไฟล์ใน Google Drive ไม่ถูกลบ)") }
        .alert("ซิงก์ต่อหรือไม่?", isPresented: Binding(get: { pendingSync != nil }, set: { if !$0 { pendingSync = nil } }), presenting: pendingSync) { _ in
            Button("ซิงก์ต่อ") { pendingSync = nil; runSync() }
            Button("ยกเลิก", role: .cancel) { pendingSync = nil }
        } message: { p in Text(p.notes.joined(separator: "\n")) }
        .overlay { if let busy { BusyOverlay(text: busy) } }
        .errorAlert($error)
        .onAppear { model.reload() }
    }

    func go(_ j: Job, at start: MissingGroup.Target? = nil) {
        lastOpened = j.id.uuidString
        open = Opening(id: j.id, start: start)
    }

    // MARK: cards

    var grid: some View {
        LazyVGrid(columns: compact ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
            ForEach(shown) { j in
                let mode: JobCard.Mode = tab == .install ? .install : j.stage == .survey ? .survey : .locked
                Button { open(j, mode) } label: {
                    JobCard(job: j, mode: mode, pendingSync: model.waitsForSync(j), synced: model.isSynced(j), recent: j.id.uuidString == lastOpened)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    switch mode {
                    case .survey:
                        Button { go(j) } label: { Label("เปิดที่ A1", systemImage: "doc.text") }
                        Button { model.duplicate(j.id) } label: { Label("ทำสำเนา", systemImage: "plus.square.on.square") }
                        exportButton(j)
                        Button(role: .destructive) { toDelete = j } label: { Label("ลบงาน", systemImage: "trash") }
                    case .locked:
                        exportButton(j)
                    case .install:
                        Button { go(j) } label: { Label("ดูรายงานสำรวจ", systemImage: "doc.text.magnifyingglass") }
                        exportButton(j)
                    }
                }
            }
        }
    }

    func open(_ j: Job, _ mode: JobCard.Mode) {
        switch mode {
        case .survey: go(j, at: j.nextStep?.page)
        // the editor opens a moved survey read-only, on its summary
        case .locked: go(j)
        case .install: lastOpened = j.id.uuidString; tracking = j.id
        }
    }

    func exportButton(_ j: Job) -> some View {
        Button { do { share = try model.exportBackup([j.id]) } catch { self.error = error.localizedDescription } } label: {
            Label("ส่งออกข้อมูลงาน", systemImage: "square.and.arrow.up")
        }
    }

    var empty: some View {
        ContentUnavailableView {
            Label(model.jobs.isEmpty ? "ยังไม่มีงานสำรวจ" : "ไม่พบงาน", systemImage: "list.clipboard")
        } description: {
            Text(model.jobs.isEmpty ? "เริ่มงานใหม่ หรือเปิดงานที่บันทึกไว้จาก Google Drive / ไฟล์สำรอง"
                 : search.isEmpty ? "ไม่มีงานในกลุ่ม \"\(filter.title)\"" : "ลองคำค้นอื่น")
        } actions: {
            if model.jobs.isEmpty { Button("งานสำรวจใหม่") { showNew = true }.buttonStyle(.borderedProminent) }
        }
        .padding(.top, 40)
    }
}
#endif
