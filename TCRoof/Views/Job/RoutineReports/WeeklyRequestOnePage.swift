import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

/// คำขอรายสัปดาห์ (R1) on iPad regular width (docs/ui/weekly-request-ipad-map): the week's lines as pins on the
/// station's key plan with their day chips under it on the left; the week, the team and the signature on the right;
/// the state and the actions in the bottom bar. The page doesn't scroll; its cards do. `WeeklyRequestScreen` keeps
/// the request, saving, signing, the PDF and sending, as `DailyReportScreen` does for `DailyOnePage`.
struct WeeklyRequestOnePage: View {
    struct Actions {
        /// Keeps the request as a draft.
        var save: () -> Void
        var sign: () -> Void
        var clearSignature: () -> Void
        var preview: () -> Void
        var send: () -> Void
        /// `ถอนกลับมาแก้`: the team takes a sent request back (`sendBack`).
        var withdraw: () -> Void
        /// A week back (-1) or on (+1).
        var week: (Int) -> Void
        var openWeek: (Date) -> Void
        var toast: (String) -> Void
    }

    /// A week of the week list, with its request's state (nil: none yet).
    struct WeekChoice: Identifiable {
        let start: Date
        let status: RoutineReport.WeeklyRequest.Status?
        var id: Date { start }
    }

    /// The requester's drawn signature for the week.
    struct Signature: Equatable {
        let png: Data
        let at: Date
    }

    @Bindable var job: Job
    @Binding var request: RoutineReport.WeeklyRequest
    let settings: RoutineReport.Settings
    /// The MP plan's lines of the week at their places: the `+` ghosts and `เพิ่มงานทั้งหมดตามแผน MP`.
    let planned: [RoutineReport.PlanLine]
    let weeks: [WeekChoice]
    let signature: Signature?
    let editable: Bool
    /// The member may act on it at all (`weekly.request`); else the page is read only with no buttons.
    let mayAct: Bool
    /// The team may take a sent request back.
    let mayWithdraw: Bool
    /// The board's example: a drawn key plan, nothing uploaded.
    let demo: Bool
    let actions: Actions

    @State var selected: UUID?
    @State var teamTab = 0
    @State var mapFull = false
    @State var pop: Pop?
    @State var riskEdit: RiskEdit?
    @State var editVersion = 0
    @State var keyPlanImage: UIImage?
    @State var keyPlanVersion = 0
    @State var uploadItem: PhotosPickerItem?
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) private var dismiss

    /// Which of the week row's popovers is open; one at a time.
    enum Pop: Hashable { case weeks, time }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { g in
                HStack(alignment: .top, spacing: 16) {
                    // the plan about as tall as its picture is at the card's width, leaving room for the lines
                    let width = g.size.width - 63 * 2 - 16 - 384
                    leftCard(planHeight: min(560, max(280, width * 0.66), g.size.height - 230))
                    rightColumn.frame(width: 384)
                }
                .padding(.horizontal, 63).padding(.top, 16).padding(.bottom, 12)
            }
            bottomBar
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $mapFull) { fullPlan }
        .overlay { if let e = riskEdit { riskSheet(e) } }
        .onChange(of: request) { _, _ in if Debug.savePhase == nil { editVersion += 1 } }
        .onChange(of: request.id) { _, _ in selected = request.work.first?.id }
        .onChange(of: job.uploadedKeyPlan?.needsDownload) { _, _ in keyPlanVersion += 1 }
        .onChange(of: uploadItem) { _, item in upload(item) }
        .task(id: keyPlanVersion) { loadKeyPlan() }
        .task {
            if selected == nil { selected = request.work.first?.id }
            #if DEBUG
            try? await Task.sleep(for: .milliseconds(300))
            debugState()
            #endif
        }
    }

    private func loadKeyPlan() {
        #if DEBUG
        if demo { keyPlanImage = Job.demoPicture.image; return }
        #endif
        keyPlanImage = job.keyPlanPicture?.image
    }

    /// `อัปโหลดผัง`: a picture from the library becomes the station's key plan (the places keep their points).
    private func upload(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), !demo {
                job.setKeyPlan(ImageUtil.compressed(data), context: context)
                keyPlanVersion += 1
            }
            uploadItem = nil
        }
    }

    // MARK: header

    /// ISO week of the request's Saturday, as the install page's weeks.
    var weekNumber: Int { WeeklyRequestScreen.weekNumber(request) }

    /// `4 – 10 ส.ค. 2568`: Monday to Sunday of the request's week.
    static func rangeText(_ r: RoutineReport.WeeklyRequest) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = RoutineReport.calendar.timeZone
        let a = r.date(ofDay: 0), b = RoutineReport.add(r.weekStart, 7)
        let (da, ma, ya) = (cal.component(.day, from: a), cal.component(.month, from: a), cal.component(.year, from: a))
        let (db, mb, yb) = (cal.component(.day, from: b), cal.component(.month, from: b), cal.component(.year, from: b))
        let m = RoutineReport.thaiMonthsShort
        if ya != yb { return "\(da) \(m[ma - 1]) \(ya + 543) – \(db) \(m[mb - 1]) \(yb + 543)" }
        if ma != mb { return "\(da) \(m[ma - 1]) – \(db) \(m[mb - 1]) \(yb + 543)" }
        return "\(da) – \(db) \(m[mb - 1]) \(yb + 543)"
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("ย้อนกลับ")
            VStack(alignment: .leading, spacing: 0) {
                Text("คำขอปฏิบัติงานสัปดาห์ที่ \(weekNumber) (\(Self.rangeText(request)))").font(.sarabunFixed(20, .bold)).lineLimit(1)
                    .accessibilityIdentifier("requestTitle")
                Text(job.stationName).font(.sarabunFixed(14)).opacity(0.9).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background {
            Theme.headerGradient
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous))
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: lines

    /// A line's colour: by its place in the request, cycling.
    func color(_ line: RoutineReport.PlanLine) -> Color {
        Theme.requestLines[(request.work.firstIndex { $0.id == line.id } ?? 0) % Theme.requestLines.count]
    }

    func number(_ line: RoutineReport.PlanLine) -> Int { (request.work.firstIndex { $0.id == line.id } ?? 0) + 1 }

    /// The days the plan has for this line's task and place (`ตาม MP` when the line keeps them).
    func plannedDays(_ line: RoutineReport.PlanLine) -> [Int]? {
        guard let t = line.task else { return nil }
        return (planned.first { $0.task == t && $0.location == line.location } ?? planned.first { $0.task == t })?.days
    }

    /// `จ อ พ`: day indexes as their short names.
    static func dayNames(_ days: [Int]) -> String { days.sorted().map { dayName($0) }.joined(separator: " ") }
    static func dayName(_ d: Int) -> String { ["จ", "อ", "พ", "พฤ", "ศ", "ส"][min(max(d, 0), 5)] }

    var workingDays: [Int] { RoutineReport.WeeklyRequest.workingDays(settings) }

    // MARK: readiness

    /// Why it can't be sent yet, in the board's order (§4.6).
    enum Blocker: Equatable {
        case noWork, noDay(Int), noCrew, unassessed(Int), unsigned

        var text: String {
            switch self {
            case .noWork: "ยังไม่มีงาน แตะ + บนผังเพื่อเพิ่มงานตามแผน MP"
            case .noDay(let i): "งาน \(i + 1) ยังไม่เลือกวัน"
            case .noCrew: "ยังไม่มีทีมงาน"
            case .unassessed(let i): "งาน \(i + 1) ยังไม่ประเมินความเสี่ยง"
            case .unsigned: "ผู้รายงานยังไม่ได้เซ็น"
            }
        }

        /// The line at fault, which a tap on the send button selects.
        var line: Int? {
            switch self {
            case .noDay(let i), .unassessed(let i): i
            default: nil
            }
        }
    }

    var blocker: Blocker? {
        if request.work.isEmpty { return .noWork }
        if let i = request.work.firstIndex(where: \.days.isEmpty) { return .noDay(i) }
        if request.perDay == 0 { return .noCrew }
        if let i = request.firstUnassessedLine { return .unassessed(i) }
        if signature == nil { return .unsigned }
        return nil
    }

    // MARK: bottom bar

    private var statusLine: (text: String, ok: Bool, icon: String) {
        switch request.status {
        case .draft:
            if let why = blocker { return ("ยังส่งไม่ได้: " + why.text, false, "exclamationmark") }
            return ("ครบทุกส่วนแล้ว พร้อมส่งขออนุมัติ", true, "checkmark")
        case .sent:
            return ("ส่งขออนุมัติแล้ว รอทีมภายในตรวจ แก้ไขได้เมื่อถูกส่งกลับ", true, "paperplane.fill")
        case .approved:
            let at = request.approvedAt.map(RoutineReport.thaiDate) ?? ""
            let by = request.approvedBy.isEmpty ? "" : " โดย \(request.approvedBy)"
            return ("อนุมัติแล้ว \(at)\(by) (ดูอย่างเดียว)", true, "checkmark")
        }
    }

    private var bottomBar: some View {
        let s = statusLine
        return HStack(spacing: 12) {
            Image(systemName: s.icon).font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.onPrimary).frame(width: 28, height: 28)
                .background(s.ok ? (request.status == .sent ? Theme.primary : Theme.success) : Theme.warning, in: Circle())
            Text(s.text).font(.sarabunFixed(14))
                .foregroundStyle(request.status == .sent ? Theme.navy : s.ok ? Theme.successText : Theme.navy).lineLimit(2)
                .accessibilityIdentifier("requestStatus")
            Spacer(minLength: 12)
            if editable {
                TCSaveButton.pad(width: 190, save: { actions.save(); return .now }, version: editVersion, savedTime: true, start: Debug.savePhase)
            }
            previewButton
            mainButton
        }
        .padding(.horizontal, 63).padding(.vertical, 10)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    private var previewButton: some View {
        Button(action: actions.preview) {
            VStack(spacing: 0) {
                Text("PDF 1 หน้า").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Text("ดูตัวอย่างคำขอ").font(.sarabunFixed(16, .bold))
            }
            .frame(width: 210, height: 44)
        }
        .buttonStyle(TCButtonStyle(.secondary, size: .card))
        .accessibilityLabel("ดูตัวอย่างคำขอ")
        .accessibilityIdentifier("requestPreview")
    }

    @ViewBuilder private var mainButton: some View {
        switch request.status {
        case .draft where editable: sendButton
        case .draft: EmptyView()
        case .sent:
            if mayWithdraw {
                Button(action: actions.withdraw) {
                    Text("ถอนกลับมาแก้").font(.sarabunFixed(16, .bold)).frame(width: 210, height: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .accessibilityIdentifier("requestWithdraw")
            }
        case .approved:
            Label("อนุมัติแล้ว", systemImage: "checkmark").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 210, height: 53)
                .background(Theme.success, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("requestApproved")
        }
    }

    /// `ส่งขออนุมัติ`: off while a whole-request reason blocks it; while a line blocks it, a tap selects that line.
    private var sendButton: some View {
        let why = blocker
        return Button {
            if let why {
                if let i = why.line, request.work.indices.contains(i) { selected = request.work[i].id }
                actions.toast(why.text)
            } else {
                actions.send()
            }
        } label: {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(why?.text ?? "ครบแล้ว").font(.sarabunFixed(12)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                    Text("ส่งขออนุมัติ").font(.sarabunFixed(16, .bold))
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
            }
            .frame(width: 210, height: 44)
        }
        .buttonStyle(TCButtonStyle(.primary, size: .card))
        .opacity(why == nil ? 1 : 0.45)
        .disabled(why != nil && why?.line == nil)
        .accessibilityLabel("ส่งขออนุมัติ")
        .accessibilityValue(why?.text ?? "พร้อมส่ง")
        .accessibilityIdentifier("requestSendNow")
    }

    // MARK: DEBUG

    /// `-requestState …` (with `-screen request -routineRequest onepage`): the board's states 02–13, in memory with
    /// `-requestDemo YES`. Release builds have none.
    enum Debug {
        #if DEBUG
        static let state = UserDefaults.standard.string(forKey: "requestState") ?? ""
        #else
        static let state = ""
        #endif
        static var savePhase: TCSaveButton.Phase? { nil }
    }

    #if DEBUG
    private func debugState() {
        switch Debug.state {
        case "line2": if request.work.count > 1 { selected = request.work[1].id }
        case "weeks": pop = .weeks
        case "worktime": pop = .time
        case "tools": teamTab = 1
        case "risk":
            if let line = request.work.first(where: { $0.id == selected }) ?? request.work.first,
               let h = request.hazards(of: line).first {
                selected = line.id
                riskEdit = RiskEdit(hazard: h, line: line.id, likelihood: request.risk(for: h)?.likelihood ?? h.likelihood,
                                    severity: request.risk(for: h)?.severity ?? h.severity)
            }
        case "nodays":
            if request.work.count > 1 { request.work[1].days = []; selected = request.work[1].id }
        case "map": mapFull = true
        default: break
        }
    }
    #endif
}
