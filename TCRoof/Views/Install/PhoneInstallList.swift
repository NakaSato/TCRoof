import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// iPhone install list (compact width), in the style of the survey list (docs/ui/tcroof-survey-list-iphone):
/// gradient header with the count, segmented บันทึก / ICL and date filters, the search field, and one compact card per job.
/// The root of the `ติดตั้ง` tab.
struct PhoneInstallList: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var tab: InstallRecordsView.Tab = .logs
    @State private var window: DateWindow = .week
    @State private var search = ""
    @FocusState private var searching: Bool
    @State private var showPicker = false
    @State private var pendingJob: Job?
    @State private var newLogJob: Job?

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    /// As on the survey list, an active query searches every job and ignores the date window.
    private var filtered: [Job] {
        jobs.filter { query.isEmpty ? window.overlaps($0.installInterval) : $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filtered.isEmpty {
                    Text("ไม่พบงานติดตั้ง").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 16)
                }
                ForEach(filtered) { InstallJobCompactCard(job: $0, tab: tab) }
            }
            // the last card clears the FAB (60 + 16); the tab bar is already a safe-area inset
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 76)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TCGradientHeader(title: "บันทึกงานติดตั้ง",
                                 subtitle: query.isEmpty ? "งานติดตั้ง \(filtered.count) งาน" : "ผลการค้นหา \(filtered.count) งาน") {
                    NavigationLink { InstallLogHistoryView() } label: { TCHeaderIcon("clock") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("ประวัติบันทึกทั้งหมด")
                }
                controls
            }
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            TCFab("plus", accessibilityLabel: "เพิ่มบันทึกงานติดตั้ง", gradient: Theme.tealGradient) { showPicker = true }
                .tcFabPlacement(compact: true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPicker, onDismiss: {
            if let job = pendingJob {
                pendingJob = nil
                newLogJob = job
            }
        }) {
            JobPickerSheet(title: "เลือกงานที่จะบันทึก") { pendingJob = $0 }
        }
        .sheet(item: $newLogJob) { job in InstallLogFormView(job: job, log: nil) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            TCSegmented(["บันทึกประจำวัน", "ใบตรวจรับ ICL"],
                        selection: Binding(get: { tab == .logs ? "บันทึกประจำวัน" : "ใบตรวจรับ ICL" },
                                           set: { tab = $0 == "บันทึกประจำวัน" ? .logs : .inspection }),
                        fontSize: 14, style: .filter)
            TCSegmented(DateWindow.allCases.map(\.shortLabel),
                        selection: Binding(get: { window.shortLabel },
                                           set: { t in window = DateWindow.allCases.first { $0.shortLabel == t } ?? .week }),
                        fontSize: 14, style: .filter)
            PhoneSearchField(text: $search, focused: $searching)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }
}

/// The iPhone install card: project and team, code and kW, the install dates, then the day's log count
/// or the ICL state. The whole card opens the job's logs or its inspection. A job installing today has a primary border.
struct InstallJobCompactCard: View {
    let job: Job
    let tab: InstallRecordsView.Tab

    private var today: Int? { job.installDay(on: .now) }
    private var when: String {
        InstallWhen.label(daysToStart: RelativeDay.days(from: .now, to: job.installStart), day: today, total: job.installDays,
                          start: job.installStart.thaiShort, end: job.installEnd.thaiShort)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        NavigationLink {
            switch tab {
            case .logs: JobInstallLogsView(job: job)
            case .inspection: InspectionView(job: job)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                codeRow.padding(.top, -4)
                whenRow
                statusBox
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(today != nil ? Theme.primary : Theme.borderSubtle))
            .shadow(color: Theme.navy.opacity(0.08), radius: 4, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(job.projectName).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(job.team.rawValue).font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(job.team.color)
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(job.team.color.opacity(0.1), in: Capsule())
                .fixedSize()
        }
    }

    private var codeRow: some View {
        HStack(spacing: 6) {
            Text(job.code)
            Text(verbatim: "·")
            Image(systemName: "bolt").font(.system(size: 11, weight: .medium))
            Text(job.capacityKW.kw)
        }
        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }

    private var whenRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.primary)
            Text(when).font(.sarabun(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(today != nil ? Theme.primary : Theme.navy).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "mappin").font(.system(size: 12, weight: .medium))
                Text(job.province).lineLimit(1)
            }
            .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// `บันทึกประจำวัน · 3 รายการ` or `ใบตรวจรับ · กำลังตรวจ 4/9 ขั้นตอน`, with a chevron.
    private var statusBox: some View {
        let (key, value, color): (String, String, Color) = switch tab {
        case .logs:
            ("บันทึกประจำวัน", job.logs.isEmpty ? "ยังไม่มีบันทึก" : "\(job.logs.count) รายการ", job.logs.isEmpty ? Theme.inkMuted : Theme.navy)
        case .inspection:
            { let s = InstallRecordsView.inspectionStatus(job); return ("ใบตรวจรับ", s.text, s.color) }()
        }
        return HStack(spacing: 6) {
            Text(key).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabun(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(color).lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.progressBoxIdle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
