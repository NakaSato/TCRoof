import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore
import SurveyUI

/// iPhone survey list (compact width, docs/ui/tcroof-survey-list-iphone): gradient header with the count,
/// a segmented date filter, the search field with recent searches, and one compact card per job.
/// The root of the `สำรวจ` tab; when it is pushed (from the home module row) the header shows a back chevron.
struct PhoneSurveyList: View {
    @Query(sort: \Job.surveyDate) private var jobs: [Job]
    @State private var window: DateWindow = Self.debugWindow ?? .week
    @State private var search = Self.debugQuery ?? ""
    @State private var showNewJob = false
    @FocusState private var searching: Bool
    @AppStorage("surveyList.recentSearches") private var recentRaw = ""
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    /// As on the board, an active query searches every job and ignores the date window.
    private var filtered: [Job] {
        jobs.filter { query.isEmpty ? window.overlaps($0.surveyInterval) : $0.matches(query) }
    }

    private var recent: [String] { RecentSearches.decode(recentRaw) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filtered.isEmpty {
                    Text("ไม่พบงานสำรวจ").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 16)
                }
                ForEach(filtered) { SurveyJobCompactCard(job: $0) }
            }
            // the last card clears the FAB (60 + 16); the tab bar is already a safe-area inset
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 76)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                controls
            }
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            TCFab("person.badge.plus", accessibilityLabel: "เพิ่มลูกค้าใหม่", gradient: Theme.tealGradient) { showNewJob = true }
                .tcFabPlacement(compact: true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewJob) { NewJobView() }
        .onChange(of: searching) { _, focused in
            if !focused { remember(search) }
        }
        #if DEBUG
        .task {
            seedDraft()
            if UserDefaults.standard.bool(forKey: "surveySearchFocus") { try? await Task.sleep(for: .seconds(1)); searching = true }
        }
        #endif
    }

    #if DEBUG
    /// `-surveyWindow month|all`, `-surveySearch <text>` and `-surveySearchFocus YES` open those states
    /// (docs/ui/tcroof-survey-list-iphone states 02–06); seed `ค้นหาล่าสุด` with `-surveyList.recentSearches "a\nb"`.
    private static var debugWindow: DateWindow? {
        switch UserDefaults.standard.string(forKey: "surveyWindow") {
        case "month": .month
        case "all": .all
        default: nil
        }
    }
    private static var debugQuery: String? { UserDefaults.standard.string(forKey: "surveySearch") }

    /// `-surveyListDraft YES`: today's first job gets a draft with the roof and electrical groups filled
    /// (`ทำต่อ · ค่าไฟ`, as states/01b-card-today-crop), for simulator checks.
    private func seedDraft() {
        guard UserDefaults.standard.bool(forKey: "surveyListDraft"),
              let job = jobs.first(where: { $0.surveyDate.isToday }), job.surveyDraft == nil else { return }
        let draft = SurveyForm.blankDraft(surveyor: "สมชาย")
        draft.roofType = SurveyOptions.roofTypes[0]; draft.roofAreaSqm = 40
        draft.orientation = SurveyOptions.orientations[0]; draft.shading = SurveyOptions.shadings[0]
        draft.utility = SurveyOptions.utilities[0]; draft.meterPhase = "1 เฟส"; draft.mainBreakerAmp = 63
        context.insert(draft)
        draft.job = job
        try? context.save()
    }
    #else
    private static var debugWindow: DateWindow? { nil }
    private static var debugQuery: String? { nil }
    #endif

    // MARK: header

    private var header: some View {
        HStack(spacing: 2) {
            // a tab root has nothing to go back to; `หน้าหลัก` is in the tab bar
            if isPresented {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("กลับหน้าหลัก")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("สำรวจหน้างาน").font(.sarabun(19, .bold, relativeTo: .title3)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(query.isEmpty ? "นัดสำรวจ \(filtered.count) งาน" : "ผลการค้นหา \(filtered.count) งาน")
                    .font(.sarabun(13, relativeTo: .caption)).opacity(0.92).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink { SurveyHistoryView() } label: {
                Image(systemName: "clock").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ประวัติการสำรวจ")
        }
        .foregroundStyle(.white)
        .padding(.leading, isPresented ? 6 : 16).padding(.trailing, 8)
        .padding(.top, 6).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: filter and search

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TCSegmented(DateWindow.allCases.map(\.shortLabel),
                        selection: Binding(get: { window.shortLabel },
                                           set: { t in window = DateWindow.allCases.first { $0.shortLabel == t } ?? .week }),
                        fontSize: 14, style: .filter)
            searchField
            if searching && search.isEmpty && !recent.isEmpty { recentChips }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
            TextField(text: $search) { Text("ค้นหาชื่อลูกค้า หรือรหัสโครงการ").foregroundStyle(Theme.inkMuted) }
                .font(.sarabun(14, search.isEmpty ? .regular : .bold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .onSubmit { remember(search) }
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32).background(Theme.segmentTrack, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(.leading, 12).padding(.trailing, search.isEmpty ? 12 : 0)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // the 2 pt border is drawn inside, so the text does not move when focused
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(searching ? Theme.primary : Theme.borderSubtle, lineWidth: searching ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { searching = true }
    }

    private var recentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ค้นหาล่าสุด").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(recent, id: \.self) { q in
                    Button {
                        search = q
                        searching = false
                    } label: {
                        Text(q).font(.sarabun(13, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderOutdoor))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, -2)
    }

    private func remember(_ q: String) {
        let list = RecentSearches.adding(q, to: recent)
        if list != recent { recentRaw = RecentSearches.encode(list) }
    }
}

// MARK: - Compact card

/// The iPhone survey card: the body (project, team, code, kW, appointment, province) opens `JobDetailView`;
/// the progress box opens the draft, the saved survey, or a new one. Today's job has a primary border.
struct SurveyJobCompactCard: View {
    let job: Job

    private var days: Int { RelativeDay.days(from: .now, to: job.surveyDate) }
    private var when: String { RelativeDay.label(days: days, time: ThaiFormat.time.string(from: job.surveyDate)) }
    private var progress: SurveyCardProgress {
        SurveyCardProgress(draft: job.surveyDraft.map(SurveyOptions.progress), hasSaved: !job.savedSurveys.isEmpty)
    }

    var body: some View {
        let p = progress
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { JobDetailView(job: job) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("รายละเอียดงาน \(job.projectName) \(when)")
            NavigationLink { form } label: { progressBox(p) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.shortValue) แบบสำรวจ")
                .accessibilityValue("\(p.shortKey) \(p.percent)%")
                .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(days == 0 ? Theme.primary : Theme.borderSubtle))
        .shadow(color: Theme.navy.opacity(0.08), radius: 4, y: 3)
    }

    /// `SurveyFormView(job:)` opens the draft or starts one; with only a saved survey, `ดูแบบสำรวจ` opens that.
    @ViewBuilder private var form: some View {
        if job.surveyDraft == nil, let saved = job.savedSurveys.first {
            SurveyFormView(survey: saved)
        } else {
            SurveyFormView(job: job)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            codeRow.padding(.top, -4)
            whenRow
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
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
                .foregroundStyle(days == 0 ? Theme.primary : Theme.navy).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "mappin").font(.system(size: 12, weight: .medium))
                Text(job.province).lineLimit(1)
            }
            .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func progressBox(_ p: SurveyCardProgress) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(p.shortKey).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                Text(p.shortValue).font(.sarabun(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(p.percent)%").font(.sarabun(12.5, .bold, relativeTo: .caption)).monospacedDigit()
                    .foregroundStyle(p.percent == 0 ? Theme.progressZero : p.tone == .complete ? Theme.progressFull : Theme.primary)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
            }
            HStack(spacing: 3) {
                ForEach(p.segments.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(p.segments[i].color).frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(p.tone == .draft ? Theme.progressBox : Theme.progressBoxIdle, in: shape)
        .contentShape(shape)
    }
}

extension SurveyCardProgress.Segment {
    /// Done green, current blue, to do grey.
    var color: Color {
        switch self {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .todo: Theme.borderSubtle
        }
    }
}
