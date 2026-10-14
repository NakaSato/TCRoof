#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import TCRoofCore
import DriveSync

/// Entry point of the survey-report feature. Put it inside a NavigationStack
/// (TCRoof pushes it from "สำรวจหน้างาน"; a standalone app wraps it in `SolarSurveyScene`).
public struct SolarSurveyReportView: View {
    @State private var model = SurveyModel.shared
    let title: String
    let subtitle: String
    let unsyncedOnly: Bool
    let page: Page

    /// The project home, or the project settings page (docs/ui/pwa-solar-survey-iphone-v2 §7).
    public enum Page: Sendable { case project, settings }

    /// - Parameters:
    ///   - title: heading of the job list, e.g. the client group "การประปาส่วนภูมิภาค".
    ///   - unsyncedOnly: open on the รอซิงก์ filter (the sync notification's `ดูรายการ`).
    public init(title: String = "PWA Solar Survey",
                subtitle: String = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)", unsyncedOnly: Bool = false, page: Page = .project) {
        self.title = title; self.subtitle = subtitle; self.unsyncedOnly = unsyncedOnly; self.page = page
    }
    public var body: some View {
        SurveyHomeView(title: title, subtitle: subtitle, page: page, filter: unsyncedOnly ? .unsynced : .all).environment(model)
    }
}

public extension SurveyModel {
    @MainActor static let shared = SurveyModel()
}

struct SurveyHomeView: View {
    var title = "PWA Solar Survey"
    var subtitle = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
    var page = SolarSurveyReportView.Page.project
    @Environment(SurveyModel.self) var model
    @Environment(\.pwaOverview) var host
    @Environment(\.accessibilityReduceMotion) var reduceMotion
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
    /// Installation job to return to the survey tab, after confirming.
    @State var toSurvey: Job?
    @State var message: String?
    @State var error: String?
    @State var busy: String?
    @State var pendingSync: PendingSync?
    /// Home tab: surveys, installations, maintenance; kept between launches.
    @AppStorage("solarSurvey.homeTab") var tab = JobStage.survey
    @State var showInstallPicker = false
    @State var showMaintenancePicker = false
    /// iPad: the nav's `แผนงาน` is selected and the host's plan page is under it.
    @State var planOpen = false
    /// Installation job whose tracking page is open.
    @State var tracking: UUID?
    // the home page (docs/ui/pwa-solar-survey-iphone-v3, docs/ui/pwa-solar-survey-ipad-v3)
    /// The header's search button grown into its field.
    @State var searchOpen = false
    @State var showFilter = false
    /// Row filter of the install overview; nil until picked, then `ช้ากว่าแผน` when any station has a plan.
    @State var installFilter: InstallOverview.RowFilter?
    /// The contractor whose stations the install overview is narrowed to.
    @State var contractor: String?
    /// Row filter of the maintenance overview; nil until picked, then `มีปัญหา` when any station has a problem.
    @State var maintenanceFilter: MaintenanceOverview.RowFilter?

    /// A job to open, optionally at the step "continue" points to.
    struct Opening: Hashable { let id: UUID; var start: MissingGroup.Target? = nil }
    struct PendingSync: Identifiable { let id = UUID(); let notes: [String] }

    enum Filter: CaseIterable {
        case all, active, draft, unsynced
        var title: String { [.all: "ทั้งหมด", .active: "กำลังสำรวจ", .draft: "ร่าง", .unsynced: "รอซิงก์"][self]! }
        var heading: String { self == .all ? "งานทั้งหมด" : title }
    }
    enum Sort: CaseIterable {
        case updated, docNo, progress
        var title: String { [.updated: "แก้ไขล่าสุด", .docNo: "เลขที่", .progress: "ความคืบหน้า"][self]! }
    }

    func matches(_ j: Job, _ f: Filter) -> Bool {
        switch f {
        case .all: return true
        case .active: return j.stage == .survey && !j.projectName.isEmpty && !j.completion.isComplete
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
        let list = tab == .survey ? searched.filter { matches($0, filter) } : searched
        switch sort {
        case .updated: return list.sorted { $0.updated > $1.updated }
        // numbered jobs in order, unnumbered drafts last
        case .docNo: return list.sorted { a, b in
            if a.docNo.isEmpty != b.docNo.isEmpty { return b.docNo.isEmpty }
            return a.docNo.localizedStandardCompare(b.docNo) == .orderedAscending
        }
        case .progress where tab == .install: return list.sorted { ($0.install?.percent ?? 0) > ($1.install?.percent ?? 0) }
        // completion walks the whole schema: work it out once per job, not in every comparison
        case .progress: return list.map { ($0, $0.completion.fraction) }.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    var compact: Bool { sizeClass == .compact }

    var body: some View {
        homePage
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
        // `-surveySettings YES` opens the survey settings (เครื่องนี้ lists the detected hardware).
        .task { if UserDefaults.standard.bool(forKey: "surveySettings") { showSettings = true } }
        .task { applyDebugHome() }
        .task {
            guard UserDefaults.standard.bool(forKey: "surveyDemo"), open == nil else { return }
            // `-surveyFreshJob YES` (UI tests): a new job each run, replacing the last test job, so earlier runs leave no state
            if UserDefaults.standard.bool(forKey: "surveyFreshJob") {
                for j in model.jobs where j.docNo == "UITEST" { model.delete(j.id) }
                var j = model.create(JobTemplate.all[0], engineer: "สมชาย")
                j.values["docNo"] = .text("UITEST"); j.values["projectName"] = .text("ทดสอบ REV")
                j.values["address"] = .text("55 ถ.พหลโยธิน ต.คลองหนึ่ง อ.คลองหลวง ปทุมธานี")
                model.update(j)
                return go(j)
            }
            // `-surveyTestJob YES`: the job `-surveyFreshJob` made last time, as it was left
            if UserDefaults.standard.bool(forKey: "surveyTestJob"), let j = model.jobs.first(where: { $0.docNo == "UITEST" }) { return go(j) }
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
        .sheet(isPresented: $showMaintenancePicker) {
            MaintenancePickerSheet(stations: installStations) { s in
                addToMaintenance(s)
                showMaintenancePicker = false
                maintenanceFilter = .all
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
        .confirmationDialog("ย้ายกลับเป็นงานสำรวจ?", isPresented: Binding(get: { toSurvey != nil }, set: { if !$0 { toSurvey = nil } }),
                            titleVisibility: .visible, presenting: toSurvey) { j in
            Button("ย้าย \(j.projectName) กลับ", role: .destructive) {
                toSurvey = nil
                guard model.moveBackToSurvey(j.id) else { return }
                withAnimation(.snappy) { tab = .survey }
            }
        } message: { j in
            let n = j.install?.doneSteps ?? 0
            Text(n > 0 ? "ความคืบหน้าติดตั้ง \(n)/\(InstallInfo.steps.count) ขั้น ทีม และวันส่งมอบจะถูกลบ งานจะแก้ไขได้อีกครั้งในแท็บงานสำรวจ"
                 : "งานจะกลับไปแก้ไขได้ในแท็บงานสำรวจ")
        }
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
        let stations = phaseStations
        return LazyVGrid(columns: compact ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: compact ? 10 : 16) {
            ForEach(shown) { j in
                let station = stations[j.id]
                let mode: JobCard.Mode = tab == .install ? .install : j.stage == .survey && station == nil ? .survey : .locked
                Button { if let station { openStation(station) } else { open(j, mode) } } label: {
                    JobCard(job: j, mode: mode, pendingSync: model.waitsForSync(j), synced: model.isSynced(j),
                            recent: j.id.uuidString == lastOpened, station: station)
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
                        // the card opens the install record, so the report is here
                        if station != nil { Button { go(j) } label: { Label("ดูรายงานสำรวจ", systemImage: "doc.text.magnifyingglass") } }
                        exportButton(j)
                    case .install:
                        Button { go(j) } label: { Label("ดูรายงานสำรวจ", systemImage: "doc.text.magnifyingglass") }
                        exportButton(j)
                        Button(role: .destructive) { toSurvey = j } label: { Label("ย้ายกลับเป็นงานสำรวจ", systemImage: "arrow.uturn.backward") }
                    }
                }
            }
        }
    }

    /// The station in the install overview of each job moved to installation, which makes its card an install-phase
    /// card (docs/ui/pwa-solar-survey-iphone-v3 §4).
    var phaseStations: [UUID: InstallStationSummary] {
        guard tab == .survey else { return [:] }
        #if DEBUG
        // `-surveyHomeDemo cards`: the second and third cards as the board's late and on-plan stations; nothing is saved
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "cards" {
            return Dictionary(uniqueKeysWithValues: zip(shown.dropFirst().prefix(2).map(\.id), [PWAOverviewDemo.install[1], PWAOverviewDemo.install[3]]))
        }
        #endif
        let stations = installStations
        var found: [UUID: InstallStationSummary] = [:]
        for j in shown where j.stage != .survey {
            found[j.id] = stations.first { $0.id == j.id.uuidString || $0.id == j.jobSyncID }
        }
        return found
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
        TCEmptyState(model.jobs.isEmpty ? "ยังไม่มีงานสำรวจ" : "ไม่พบงาน", systemImage: "list.clipboard",
                     description: Text(model.jobs.isEmpty ? "เริ่มงานใหม่ หรือเปิดงานที่บันทึกไว้จาก Google Drive / ไฟล์สำรอง"
                                       : search.isEmpty ? "ไม่มีงานในกลุ่ม \"\(filter.title)\"" : "ลองคำค้นอื่น")) {
            if model.jobs.isEmpty { Button("งานสำรวจใหม่") { showNew = true }.buttonStyle(TCButtonStyle(.primary, size: .card)) }
        }
        .padding(.top, 40)
    }
}
#endif
