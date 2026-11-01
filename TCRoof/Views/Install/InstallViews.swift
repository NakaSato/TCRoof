import SwiftUI
import TCRoofUI
import SwiftData

/// `บันทึกงานติดตั้ง และใบตรวจรับงาน` across jobs: the phone's list (`PhoneInstallList`), on any width. The iPad has no list of
/// its own: a job's install logs and ICL open from its job screen, and the iPad tools tab doesn't offer this module.
struct InstallRecordsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case logs = "บันทึกงานติดตั้ง"
        case inspection = "ใบตรวจรับงานติดตั้ง (ICL)"
        var id: String { rawValue }
    }

    var body: some View { PhoneInstallList() }

    /// The ICL state of a job, for the iPhone status box.
    static func inspectionStatus(_ job: Job) -> (text: String, color: Color) {
        guard let inspection = job.inspection else { return ("ยังไม่เริ่มตรวจรับ", Theme.muted) }
        if inspection.submittedAt != nil {
            return inspection.allPassed ? ("ตรวจรับแล้ว | ผ่านทุกข้อ", Theme.success) : ("ตรวจรับแล้ว | มีข้อไม่ผ่าน", Theme.danger)
        }
        return ("กำลังตรวจ \(inspection.completedCount)/\(InspectionStep.all.count) ขั้นตอน", .orange)
    }
}

// MARK: - Logs of one job

struct JobInstallLogsView: View {
    let job: Job
    @State private var showForm = false

    private var logs: [InstallLog] { job.logs.sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let header = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                header {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.projectName).font(.sarabun(28, .bold, relativeTo: .title)).foregroundStyle(Theme.navy)
                        Text("\(job.code) | \(job.installStart.thaiLong) – \(job.installEnd.thaiLong)")
                            .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    }
                    if !isPhone { Spacer() }
                    NavigationLink { InspectionView(job: job) } label: {
                        Label("ใบตรวจรับงาน (ICL)", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
                if logs.isEmpty {
                    TCEmptyState("ยังไม่มีบันทึกงานติดตั้ง", systemImage: "hammer",
                                           description: Text("กด + เพื่อบันทึกงานประจำวันพร้อมรูปถ่าย"))
                }
                ForEach(logs) { log in
                    NavigationLink { InstallLogDetailView(log: log) } label: { LogCard(log: log, job: job) }
                        .buttonStyle(.plain)
                }
            }
            .padding(isPhone ? 16 : 24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("บันทึกงานติดตั้ง")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showForm = true } label: { Label("เพิ่มบันทึก", systemImage: "plus") }
            }
        }
        .tcPadNavBar("บันทึกงานติดตั้ง", trail: ["หน้าหลัก", job.code]) {
            TCButton("เพิ่มบันทึก", systemImage: "plus") { showForm = true }
        }
        .sheet(isPresented: $showForm) { InstallLogFormView(job: job, log: nil) }
    }
}

fileprivate extension InstallLog {
    var routineStatus: (text: String, color: Color, fill: Color)? {
        guard reportJSON != nil else { return nil }
        if inspectorAckAt != nil { return ("อนุมัติแล้ว", Theme.successInk, Theme.successSoft) }
        if engineerSignedAt != nil { return ("รอรับทราบ", Theme.pending, Theme.warningSoft) }
        return ("ร่าง", Theme.muted, Theme.paperBand)
    }
}

private struct LogCard: View {
    let log: InstallLog
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(log.date.thaiLong).font(.sarabun(17, .semibold, relativeTo: .headline))
                if let day = job.installDay(on: log.date) {
                    Text("Day \(day)/\(job.installDays)").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
                }
                Spacer()
                if let status = log.routineStatus {
                    Text(status.text)
                        .font(.sarabun(12, .bold, relativeTo: .caption))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(status.fill, in: Capsule())
                }
                if !log.recorder.isEmpty {
                    Text(log.recorder)
                        .font(.sarabun(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Theme.pending)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            Text(log.detailLines.prefix(3).joined(separator: " | "))
                .font(.sarabun(15, relativeTo: .subheadline))
                .lineLimit(2)
            let photos = log.sortedPhotos
            if !photos.isEmpty {
                let limit = isPhone ? 4 : 6
                HStack(spacing: 8) {
                    ForEach(photos.prefix(limit)) { Thumbnail(data: $0.data).frame(width: isPhone ? 56 : 72, height: isPhone ? 56 : 72) }
                    if photos.count > limit {
                        Text("+\(photos.count - limit)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .foregroundStyle(Theme.navy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Log form

struct InstallLogFormView: View {
    let job: Job
    let log: InstallLog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""

    @State private var date = Date()
    @State private var recorder = ""
    @State private var details = ""
    @State private var photos: [Data] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection {
                    InfoRow(title: "โครงการ", value: "\(job.code) | \(job.projectName)")
                    DatePicker("วันที่บันทึก", selection: $date, displayedComponents: .date)
                    TextField("ผู้บันทึก", text: $recorder)
                }
                PadSection("รายละเอียดงาน") {
                    TextField("เช่น งานติดตั้ง Pull Box", text: $details, axis: .vertical)
                        .lineLimit(4...12)
                } footer: {
                    Text("พิมพ์หนึ่งรายการต่อบรรทัด")
                }
                PadSection("รูปภาพงานติดตั้ง") {
                    PhotoPickerSection(images: $photos)
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle(log == nil ? "เพิ่มบันทึกงานติดตั้ง" : "แก้ไขบันทึก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก", action: save)
                        .bold()
                        .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let log {
            date = log.date
            recorder = log.recorder
            details = log.details
            photos = log.sortedPhotos.map(\.data)
        } else {
            recorder = userName
            if job.installDay(on: .now) == nil { date = job.installStart }
        }
    }

    private func save() {
        let target: InstallLog
        if let log {
            target = log
            target.date = date
            target.recorder = recorder
            target.details = details
            target.photos.forEach(context.delete)
        } else {
            target = InstallLog(date: date, recorder: recorder, details: details)
            context.insert(target)
            target.job = job
            if job.status == .confirmed || job.status == .interested { job.status = .installing }
        }
        for data in photos {
            let photo = PhotoAsset(data: data)
            context.insert(photo)
            photo.log = target
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Log detail

struct InstallLogDetailView: View {
    let log: InstallLog
    @State private var showEdit = false
    @State private var exportURLs: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("วันที่บันทึก").font(.sarabun(17, .semibold, relativeTo: .headline))
                            Spacer()
                            Text(log.date.thaiLong)
                        }
                        Divider()
                        HStack {
                            Text("ผู้บันทึก :")
                            Text(log.recorder)
                                .bold()
                                .foregroundStyle(Theme.pending)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            Spacer()
                            if let status = log.routineStatus {
                                Text(status.text)
                                    .font(.sarabun(12, .bold, relativeTo: .caption))
                                    .foregroundStyle(status.color)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(status.fill, in: Capsule())
                            }
                        }
                        if let job = log.job, log.reportJSON != nil {
                            Divider()
                            NavigationLink {
                                DailyReportScreen(job: job, date: log.date)
                            } label: {
                                HStack {
                                    Label("เปิดรายงานประจำวัน (R2)", systemImage: "doc.text.magnifyingglass")
                                        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                                        .foregroundStyle(Theme.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(Theme.navy)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("รายละเอียด").font(.sarabun(17, .semibold, relativeTo: .headline))
                        ForEach(Array(log.detailLines.enumerated()), id: \.offset) { index, line in
                            Text("\(index + 1). \(line)")
                        }
                        Text("รูปภาพงานติดตั้ง").font(.sarabun(17, .semibold, relativeTo: .headline)).padding(.top, 12)
                        if log.sortedPhotos.isEmpty {
                            Text("ไม่มีรูปภาพ").foregroundStyle(Theme.muted)
                        } else {
                            PhotoGrid(images: log.sortedPhotos.map(\.data), minSize: 160)
                        }
                    }
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .padding(24)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            if !exportURLs.isEmpty {
                ShareLink(items: exportURLs) {
                    Label("ดาวน์โหลดไฟล์ทั้งหมด (\(exportURLs.count))", systemImage: "arrow.down.doc.fill")
                        .font(.sarabun(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: 600, minHeight: 54)
                        .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("บันทึกงานติดตั้งและรูป")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEdit = true } label: { Label("แก้ไข", systemImage: "pencil") }
            }
        }
        .tcPadNavBar("บันทึกงานติดตั้งและรูป", trail: ["หน้าหลัก", log.job?.code ?? "บันทึกงานติดตั้ง"],
                     current: log.date.thaiLong) {
            TCButton("แก้ไข", systemImage: "pencil", kind: .secondary) { showEdit = true }
        }
        .sheet(isPresented: $showEdit, onDismiss: export) {
            if let job = log.job { InstallLogFormView(job: job, log: log) }
        }
        .onAppear(perform: export)
    }

    private func export() {
        let prefix = "\(log.job?.code ?? "log")-\(ThaiFormat.short.string(from: log.date).replacingOccurrences(of: " ", with: ""))"
        exportURLs = ImageUtil.exportFiles(log.sortedPhotos.map(\.data), prefix: prefix)
    }
}

struct InstallLogHistoryView: View {
    @Query(sort: \InstallLog.date, order: .reverse) private var logs: [InstallLog]

    var body: some View {
        PadForm {
            if logs.isEmpty {
                TCEmptyState("ยังไม่มีบันทึก", systemImage: "hammer")
            }
            PadSection {
                ForEach(logs) { log in
                    PadLink { InstallLogDetailView(log: log) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(log.job?.code ?? "-") | \(log.job?.projectName ?? "")").bold()
                                Spacer()
                                if let status = log.routineStatus {
                                    Text(status.text)
                                        .font(.sarabun(11, .bold, relativeTo: .caption2))
                                        .foregroundStyle(status.color)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(status.fill, in: Capsule())
                                }
                            }
                            Text("\(log.date.thaiLong) | \(log.recorder) | \(log.sortedPhotos.count) รูป")
                                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                            Text(log.detailLines.joined(separator: " | ")).font(.sarabun(15, relativeTo: .subheadline)).lineLimit(1)
                        }
                        .foregroundStyle(Theme.navy)
                    }
                }
            }
        }
        .navigationTitle("ประวัติบันทึกทั้งหมด")
        .tcPadNavBar("ประวัติบันทึกทั้งหมด", trail: ["หน้าหลัก", "บันทึกงานติดตั้งและใบตรวจรับงาน"])
    }
}
