import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import PDFReport
import ExcelExport

/// The routine reports of one job (docs/specs/routine-reports-swift.md): its daily-report logs, the MP feed, and the
/// PDFs filed into the job's documents (and so to Drive) under the report folders of §4.6.
extension Job {
    /// Install logs that carry a daily report, oldest first.
    var dailyLogs: [InstallLog] { logs.filter { $0.reportJSON != nil }.sorted { $0.date < $1.date } }

    /// Every daily report of the job, oldest first.
    var dailyReports: [RoutineReport.Daily] { dailyLogs.compactMap(\.report) }

    func dailyLog(on date: Date) -> InstallLog? {
        let key = RoutineReport.dayKey(date)
        return dailyLogs.first { RoutineReport.dayKey($0.date) == key }
    }

    /// The station name printed on reports and file names.
    var stationName: String { projectName.isEmpty ? customerName : projectName }

    var reportStation: RoutineReportPages.Station {
        .init(name: stationName, code: code, mpNumber: mpNumber, capacityKWp: capacityKW, settings: routineSettings)
    }

    var reportSchedule: RoutineReportPages.Schedule? {
        scheduleInput.map { .init(input: $0, actual: scheduleActual) }
    }

    func weeklyRequest(for week: Date) -> RoutineReport.WeeklyRequest? {
        let key = MasterSchedule.Actual.key(week)
        return weeklyRequests.first { $0.id == key }
    }

    func saveRequest(_ r: RoutineReport.WeeklyRequest) {
        weeklyRequests = weeklyRequests.filter { $0.id != r.id } + [r]
    }

    /// Books the daily reports' progress into the MP actual (§3 "Feed MP"); no-op without a plan.
    func feedMP() {
        guard let input = scheduleInput else { return }
        var a = scheduleActual
        RoutineReport.feed(&a, reports: dailyReports, settings: routineSettings, over200kVA: input.over200kVA)
        if a != scheduleActual { scheduleActual = a }
    }

    /// Today's chip on the job card: ส่งแล้ว / ร่าง / ยังไม่ทำ.
    enum DailyState { case signed, draft, none }
    func dailyState(on date: Date) -> DailyState {
        guard let log = dailyLog(on: date) else { return .none }
        return log.engineerSignedAt != nil ? .signed : .draft
    }

    /// Weeks with a daily report or inside the install window, for the R3 week picker.
    var reportRange: ClosedRange<Date> {
        let first = min(dailyLogs.first?.date ?? installStart, installStart)
        return first...max(Date(), installEnd)
    }
}

extension InstallLog {
    /// The log's photos as report photos, captioned with the progress line each is tagged with.
    func dayPhotos(_ r: RoutineReport.Daily) -> (photos: [RoutineReportPages.DayPhoto], images: [UUID: Data]) {
        var out: [RoutineReportPages.DayPhoto] = [], images: [UUID: Data] = [:]
        for asset in sortedPhotos {
            let p = Photo(fileName: "log.jpg", width: 0, height: 0, takenAt: asset.createdAt)
            images[p.id] = asset.data
            let line = r.progress.first { $0.id.uuidString == asset.tag }
            out.append(.init(photo: p, date: r.date, caption: line?.title ?? ""))
        }
        return (out, images)
    }
}

/// Builds report PDFs and files them as job documents.
@MainActor
enum RoutineReportFiles {
    struct Built {
        let pages: [ReportLayout.Page]
        let images: [UUID: Data]
        let name: String
        let folder: [String]
        let title: String

        var data: Data {
            PDFRenderer.pdf(pages: pages, title: title) { p in images[p.id].flatMap(UIImage.init(data:)) }
        }
    }

    /// Every daily report with its photos and signatures.
    static func entries(_ job: Job) -> (entries: [RoutineReportPages.DailyEntry], images: [UUID: Data]) {
        var images: [UUID: Data] = [:]
        let entries = job.dailyLogs.compactMap { log -> RoutineReportPages.DailyEntry? in
            guard let r = log.report else { return nil }
            let (photos, imgs) = log.dayPhotos(r)
            images.merge(imgs) { a, _ in a }
            return .init(report: r, photos: photos, engineerSignedAt: log.engineerSignedAt, inspectorAckAt: log.inspectorAckAt)
        }
        return (entries, images)
    }

    static func daily(_ job: Job, log: InstallLog) -> Built? {
        guard let r = log.report else { return nil }
        var (photos, images) = log.dayPhotos(r)
        let key = job.reportKeyPlan()
        if let key { images[key.plan.photo.id] = key.image }
        let pages = RoutineReportPages(station: job.reportStation, measure: PDFRenderer.Measure())
            .daily(.init(report: r, photos: photos, engineerSignedAt: log.engineerSignedAt, inspectorAckAt: log.inspectorAckAt),
                   all: job.dailyReports, keyPlan: key?.plan)
        return Built(pages: pages, images: images, name: RoutineReport.fileName(.daily, date: r.date, station: job.stationName),
                     folder: RoutineReport.folder(.daily, date: r.date), title: RoutineReport.Kind.daily.title)
    }

    static func request(_ job: Job, _ r: RoutineReport.WeeklyRequest) -> Built {
        let pages = RoutineReportPages(station: job.reportStation, measure: PDFRenderer.Measure()).request(r)
        return Built(pages: pages, images: [:], name: RoutineReport.fileName(.request, date: r.weekStart, station: job.stationName),
                     folder: RoutineReport.folder(.request, date: r.weekStart), title: RoutineReport.Kind.request.title)
    }

    static func weekly(_ job: Job, week: Date) -> Built {
        let (entries, images) = entries(job)
        let ws = MasterSchedule.weekStart(week)
        let next = job.weeklyRequest(for: RoutineReport.calendar.date(byAdding: .day, value: 7, to: ws)!)
        let pages = RoutineReportPages(station: job.reportStation, measure: PDFRenderer.Measure())
            .weekly(week: ws, entries: entries, all: job.dailyReports, schedule: job.reportSchedule, nextRequest: next,
                    installStart: job.installStart)
        return Built(pages: pages, images: images, name: RoutineReport.fileName(.weekly, date: ws, station: job.stationName),
                     folder: RoutineReport.folder(.weekly, date: ws), title: RoutineReport.Kind.weekly.title)
    }

    static func monthly(_ job: Job, month: Date) -> Built {
        let (entries, images) = entries(job)
        let first = RoutineReport.month(of: month).lowerBound
        let pages = RoutineReportPages(station: job.reportStation, measure: PDFRenderer.Measure())
            .monthly(month: first, entries: entries, all: job.dailyReports, schedule: job.reportSchedule, installStart: job.installStart)
        return Built(pages: pages, images: images, name: RoutineReport.fileName(.monthly, date: first, station: job.stationName),
                     folder: RoutineReport.folder(.monthly, date: first), title: RoutineReport.Kind.monthly.title)
    }

    /// A finished file to keep with the job.
    struct Ready {
        let name: String
        let folder: [String]
        let data: Data
    }

    /// R2 as the clean Excel workbook, named like its PDF.
    static func dailyExcel(_ job: Job, log: InstallLog) -> Ready? {
        guard let r = log.report else { return nil }
        let s = job.routineSettings
        let h = DailyReportExcel.Header(project: s.contractName.isEmpty ? job.stationName : s.contractName, station: job.stationName,
                                        employer: s.employer, contractor: s.contractor, engineer: s.siteEngineer, inspector: s.inspector,
                                        engineerSignedAt: log.engineerSignedAt, inspectorAckAt: log.inspectorAckAt)
        guard let data = try? DailyReportExcel.export(r, all: job.dailyReports, header: h) else { return nil }
        let pdf = RoutineReport.fileName(.daily, date: r.date, station: job.stationName)
        return Ready(name: String(pdf.dropLast(4)) + ".xlsx", folder: RoutineReport.folder(.daily, date: r.date), data: data)
    }

    /// Adds the PDF to the job's documents, replacing an earlier one of the same name, so the Drive upload files it.
    @discardableResult
    static func file(_ built: Built, job: Job, context: ModelContext) -> Data {
        let data = built.data
        file(Ready(name: built.name, folder: built.folder, data: data), job: job, context: context)
        return data
    }

    static func file(_ ready: Ready, job: Job, context: ModelContext) {
        for old in job.documents where old.name == ready.name { context.delete(old) }
        let doc = DocumentAsset(name: ready.name, data: ready.data)
        doc.folderPath = ready.folder.joined(separator: "/")
        context.insert(doc)
        doc.job = job
    }

    /// Writes the PDF to a temporary file to share or preview.
    static func temporaryURL(_ built: Built, data: Data? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(built.name)
        try (data ?? built.data).write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Small shared views

/// − n + with 44 pt buttons.
struct CountStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.body).foregroundStyle(Theme.navy).lineLimit(2)
            Spacer(minLength: 8)
            Button { value = max(range.lowerBound, value - 1) } label: {
                Image(systemName: "minus").frame(width: touchMin, height: touchMin)
            }
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("ลด \(title)")
            Text("\(value)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.navy).frame(minWidth: 36)
            Button { value = min(range.upperBound, value + 1) } label: {
                Image(systemName: "plus").frame(width: touchMin, height: touchMin)
            }
            .accessibilityLabel("เพิ่ม \(title)")
        }
        .buttonStyle(.bordered)
    }
}

/// A report section card with a title and an optional trailing control.
struct ReportCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.navy)
                Spacer()
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// A shared PDF file for the share sheet.
struct ReportShare: Identifiable { let id = UUID(); let url: URL }
