import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPad page's `คำขอรายสัปดาห์` tab (docs/ui/install-tracking-ipad-weekly-request): the R1 request in the page, a
/// header card over the form (crew × day, tools, work × day, risks) and the approval panel on the right
/// (`InstallTrackingPage+RequestPanel.swift`). It keeps the request as `WeeklyRequestScreen` does (`WeeklyRequestStore`).
extension InstallTrackingPage {
    enum RequestSheet: String, Identifiable { case sign, pdf, approve, addLine; var id: String { rawValue } }

    var reqExternal: Bool { permissions.role == .external }
    /// The contractor sends it; the team approves, sends back and reopens it.
    var reqMayAct: Bool { permissions.can(.weeklyRequest, on: job.access) }
    func reqEditable(_ r: RoutineReport.WeeklyRequest) -> Bool { reqMayAct && r.isEditable(external: reqExternal) }

    var reqSettings: RoutineReport.Settings { job.routineSettings }
    var reqDays: [Int] { RoutineReport.WeeklyRequest.workingDays(reqSettings) }

    /// ISO week of the request's Saturday, as the page's other weeks.
    static func weekNumber(_ r: RoutineReport.WeeklyRequest) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: r.date(ofDay: 5))
    }

    /// Changes the request and keeps it (the board's example keeps nothing).
    func reqChange(_ f: (inout RoutineReport.WeeklyRequest) -> Void) {
        guard var r = request else { return }
        f(&r)
        guard r != request else { return }
        request = r
        #if DEBUG
        if Debug.demo { return }
        #endif
        WeeklyRequestStore.save(r, job: job, external: reqExternal, file: false, context: context)
    }

    /// The week's request with its kept signature (none in the board's example), and the requester's name.
    func loadRequest() {
        #if DEBUG
        if Debug.demo { request = Self.demoRequest(week: requestWeekStart, back: -requestWeek); reqSignature = nil; reqName = "นายสมชาย ใจดี"; return }
        #endif
        let r = WeeklyRequestStore.load(job, requestWeekStart)
        request = r
        let drawn = job.requestSignature(r)
        reqSignature = drawn?.data
        reqSignedAt = drawn?.createdAt
        reqName = reqSettings.siteEngineer
    }

    /// The tab: the header card, then the form scrolling on the left and the panel on the right.
    @ViewBuilder func requestTab() -> some View {
        if let r = request {
            let editable = reqEditable(r)
            VStack(spacing: 14) {
                requestHeader(r, editable: editable)
                HStack(alignment: .top, spacing: 14) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                crewCard(r, editable: editable)
                                toolsCard(r, editable: editable)
                                workCard(r, editable: editable)
                                riskCard(r, editable: editable)
                            }
                            // the last card scrolls clear of the dock
                            .padding(.bottom, 110)
                            Color.clear.frame(height: 1).id("requestEnd")
                        }
                        .scrollIndicators(.hidden)
                        .accessibilityIdentifier("requestForm")
                        #if DEBUG
                        // `-installScrollEnd YES` opens the form at its end (board state 09)
                        .task {
                            guard Debug.scrollEnd else { return }
                            try? await Task.sleep(for: .milliseconds(500))
                            proxy.scrollTo("requestEnd", anchor: .bottom)
                        }
                        #endif
                    }
                    requestPanel(r, editable: editable).frame(width: 340)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14)
            .overlay(alignment: .bottom) { if let t = reqToast { toast(t) } }
            .sheet(item: $reqSheet) { requestSheet($0, r) }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reqCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func numbered(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
        }
    }

    func requestStatusChip(_ r: RoutineReport.WeeklyRequest) -> some View {
        let (text, tone): (String, InstallPageData.Tone) = switch r.status {
        case .draft: ("ร่าง | ยังไม่ส่ง", .info)
        case .sent: ("ส่งแล้ว | รอผู้ตรวจ กฟภ. อนุมัติ", .waiting)
        case .approved: ("อนุมัติแล้ว", .ok)
        }
        return chip(text, tone).fixedSize().accessibilityIdentifier("requestStatus")
    }

    func stepperPair(_ name: String, minus: Bool, plus: Bool, id: String, change: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { change(-1) } label: { Image(systemName: "minus").frame(width: 52, height: 44).contentShape(Rectangle()) }
                .disabled(!minus).accessibilityLabel("ลด " + name).accessibilityIdentifier(id + "Minus")
            Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 24)
            Button { change(1) } label: { Image(systemName: "plus").frame(width: 52, height: 44).contentShape(Rectangle()) }
                .disabled(!plus).accessibilityLabel("เพิ่ม " + name).accessibilityIdentifier(id + "Plus")
        }
        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primary)
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    static func dayTitle(_ r: RoutineReport.WeeklyRequest, _ d: Int) -> String {
        ["จ", "อ", "พ", "พฤ", "ศ", "ส"][d] + " \(RoutineReport.calendar.component(.day, from: r.date(ofDay: d)))"
    }

    // MARK: header

    private func requestHeader(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let cal = RoutineReport.calendar, sat = r.date(ofDay: 5)
        return reqCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("คำขอปฏิบัติงานรายสัปดาห์").font(.sarabunFixed(19, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text("ส่งก่อนเริ่มสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(spacing: 6) {
                    weekButton("chevron.left", "สัปดาห์ก่อน") { requestWeek -= 1 }
                    VStack(spacing: 0) {
                        Text("สัปดาห์ที่ \(Self.weekNumber(r))").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                        Text("\(cal.component(.day, from: r.date(ofDay: 0)))–" + RoutineReport.thaiDate(sat)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                    .frame(minWidth: 180).accessibilityElement(children: .combine).accessibilityIdentifier("requestWeek")
                    weekButton("chevron.right", "สัปดาห์ถัดไป") { requestWeek += 1 }.disabled(requestWeek >= 0)
                }
                requestStatusChip(r)
                Spacer(minLength: 8)
                deadlineLine(r)
                if editable {
                    TCButton(reqPulling ? "กำลังดึง…" : "ดึงจากแผน MP", systemImage: "arrow.down.to.line", kind: .secondary) { pullFromPlan() }
                        .disabled(reqPulling).fixedSize()
                }
                TCButton("ดู PDF", systemImage: "doc", kind: .secondary) { reqSheet = .pdf }.fixedSize().accessibilityIdentifier("requestPDF")
            }
        }
    }

    private func weekButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    /// A draft: when it is due and how many days are left; sent or approved: when.
    private func deadlineLine(_ r: RoutineReport.WeeklyRequest) -> some View {
        let (label, text, ink): (String, String, Color)
        if let at = r.approvedAt {
            (label, text, ink) = ("อนุมัติแล้ว", RoutineReport.thaiDate(at) + (r.approvedBy.isEmpty ? "" : " | \(r.approvedBy)"), Theme.successInk)
        } else if let at = r.sentAt ?? r.engineerSignedAt {
            (label, text, ink) = ("ส่งแล้ว", RoutineReport.thaiDate(at), Theme.planInspect)
        } else {
            let due = RoutineReport.requestDeadline(r.weekStart)
            let cal = RoutineReport.calendar
            let left = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: due)).day ?? 0
            let when = "ส่งก่อน ศ. " + RoutineReport.thaiDate(due) + " " + String(format: "%02d:%02d", cal.component(.hour, from: due), cal.component(.minute, from: due))
            (label, text, ink) = ("กำหนดส่ง", when + (left > 0 ? " | อีก \(left) วัน" : left == 0 ? " | วันนี้" : " | เลยกำหนด \(-left) วัน"),
                                  left < 0 ? Theme.dangerText : Theme.warningInk)
        }
        return VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// `ดึงจากแผน MP`: the plan's lines for the week again, lines added outside the plan kept.
    private func pullFromPlan() {
        reqPulling = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            #if DEBUG
            let draft = Debug.demo ? Self.demoRequest(week: requestWeekStart, back: 0) : WeeklyRequestStore.draft(job, requestWeekStart)
            #else
            let draft = WeeklyRequestStore.draft(job, requestWeekStart)
            #endif
            reqChange { $0 = $0.refreshed(from: draft) }
            reqPulledAt = .now
            reqPulling = false
        }
    }

    // MARK: 1 กำลังคน

    private static let roleFills: [Color] = [Theme.track, Theme.primarySoft, Theme.warningSoft, Theme.successSoft]

    private func crewCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let days = reqDays, prev = previousRequest(r)
        let delta = prev.map { r.perDay - $0.perDay }
        return reqCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    numbered(1, "กำลังคน")
                    if editable { Text("แตะช่องวันเพื่อให้ตำแหน่งนั้นหยุด").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("ต่อวัน").foregroundStyle(Theme.inkMuted)
                        Text("\(r.perDay) คน").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                        if let d = delta, d != 0 { Text((d > 0 ? "+" : "") + "\(d) จากสัปดาห์ก่อน").bold().foregroundStyle(Theme.primary) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("ทั้งสัปดาห์").foregroundStyle(Theme.inkMuted)
                        Text("\(r.manDays(days: days))").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityIdentifier("crewManDays")
                        Text("คน·วัน").foregroundStyle(Theme.inkMuted)
                    }
                }
                .font(.sarabunFixed(13))
                VStack(spacing: 0) {
                    crewRow { Text("ตำแหน่ง") } days: { d in Text(Self.dayTitle(r, d)) } total: { Text("คน·วัน") } tail: { Text("จำนวน") }
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(height: 40)
                    ForEach(Array(r.crew.enumerated()), id: \.element.id) { i, c in
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        crewRow {
                            roleLabel(c, index: i, prev: prev)
                        } days: { d in
                            crewCell(r, role: i, day: d, editable: editable)
                        } total: {
                            Text("\(r.manDays(role: i, days: days))").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        } tail: {
                            if editable {
                                stepperPair(c.name, minus: c.count > 0, plus: true, id: "crew\(i)") { d in
                                    reqChange { $0.crew[i].count = max(0, $0.crew[i].count + d) }
                                }
                            }
                        }
                        .frame(minHeight: 60)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    crewRow { Text("รวมต่อวัน").foregroundStyle(Theme.inkMuted) } days: { d in
                        Text(r.hasWork(d) ? "\(r.people(on: d))" : "–").bold().foregroundStyle(r.hasWork(d) ? Theme.navy : Theme.inkFaint)
                            .accessibilityIdentifier("crewDay\(d)")
                    } total: { Text("\(r.manDays(days: days))").bold().foregroundStyle(Theme.navy) } tail: { EmptyView() }
                        .font(.sarabunFixed(15)).frame(height: 48)
                }
                .padding(.horizontal, 12)
                .background(Theme.phonePage.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// One line of the crew table: the role, one cell a working day, the man-days and the stepper.
    private func crewRow<A: View, B: View, C: View, D: View>(@ViewBuilder _ role: () -> A, @ViewBuilder days: @escaping (Int) -> B,
                                                              @ViewBuilder total: () -> C, @ViewBuilder tail: () -> D) -> some View {
        HStack(spacing: 8) {
            role().frame(width: 230, alignment: .leading)
            ForEach(reqDays, id: \.self) { d in days(d).frame(maxWidth: .infinity) }
            total().frame(width: 64)
            tail().frame(width: 120)
        }
    }

    private func roleLabel(_ c: RoutineReport.Count, index i: Int, prev: RoutineReport.WeeklyRequest?) -> some View {
        let before = prev?.crew.first { $0.name == c.name }?.count
        let symbols = ["person", "person.badge.shield.checkmark", "bolt", "person.2"]
        return HStack(spacing: 10) {
            Image(systemName: symbols[i % symbols.count]).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(width: 34, height: 34).background(Self.roleFills[i % Self.roleFills.count], in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(c.name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                if let b = before {
                    Text(b == c.count ? "เท่าสัปดาห์ก่อน" : "สัปดาห์ก่อน \(b) (\(c.count > b ? "+" : "")\(c.count - b))")
                        .font(.sarabunFixed(12.5)).foregroundStyle(b == c.count ? Theme.inkMuted : Theme.primary)
                }
            }
        }
    }

    private func crewCell(_ r: RoutineReport.WeeklyRequest, role i: Int, day d: Int, editable: Bool) -> some View {
        let n = r.people(role: i, day: d), off = r.isOff(role: i, day: d) && r.hasWork(d)
        let name = r.crew[i].name + " " + Self.dayTitle(r, d)
        return Button {
            if editable, r.hasWork(d) { reqChange { $0.toggleOff(role: i, day: d) } }
        } label: {
            Group {
                if let n, !off {
                    Text("\(n)").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Self.roleFills[i % Self.roleFills.count], in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else if off {
                    Text("หยุด").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.dangerText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.dangerText.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                } else {
                    Text("–").foregroundStyle(Theme.inkFaint).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name + (off ? " ไม่มา" : n.map { " \($0) คน" } ?? " ไม่มีงาน"))
        .accessibilityIdentifier("crewCell\(i)-\(d)")
    }

    /// Last week's request, for the comparison lines.
    func previousRequest(_ r: RoutineReport.WeeklyRequest) -> RoutineReport.WeeklyRequest? {
        let prev = RoutineReport.add(r.weekStart, -7)
        #if DEBUG
        if Debug.demo { var p = Self.demoRequest(week: prev, back: 1); p.crew = p.crew.map { c in var c = c; if c.name == "ผู้ปฏิบัติงาน" { c.count = 3 }; return c }; return p }
        #endif
        return job.weeklyRequest(for: prev)
    }

    // MARK: 2 เครื่องมือ

    private func toolsCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        reqCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    numbered(2, "เครื่องมือ")
                    Spacer()
                    Text("รวม \(r.tools.reduce(0) { $0 + $1.count }) ชิ้น | \(r.tools.count) รายการ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                }
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 8, height: 8)
                    Text("เครื่องวัดสอบเทียบแล้ว | ดึงจากทะเบียนเครื่องมือ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(r.tools.enumerated()), id: \.element.id) { i, t in toolCard(t, index: i, editable: editable) }
                }
            }
        }
    }

    private func toolCard(_ t: RoutineReport.Count, index i: Int, editable: Bool) -> some View {
        let cal = calibration(t.name)
        let soon = cal.map { if case .dueSoon = $0.state { true } else if case .overdue = $0.state { true } else { false } } ?? false
        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 34, height: 34).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                    if let cal { Text(cal.text).font(.sarabunFixed(12.5)).foregroundStyle(cal.ink).lineLimit(1).minimumScaleFactor(0.8) }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(t.count)").font(.sarabunFixed(26, .bold)).foregroundStyle(Theme.navy)
                Text("ชิ้น").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 4)
                if editable {
                    stepperPair(t.name, minus: t.count > 0, plus: true, id: "tool\(i)") { d in reqChange { $0.tools[i].count = max(0, $0.tools[i].count + d) } }
                }
            }
        }
        .padding(14)
        .background(soon ? Theme.warningSoft.opacity(0.45) : Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
    }

    /// The register's calibration of a tool of that name: `สอบเทียบถึง …`, `สอบเทียบครบ …` within 30 days or late, or
    /// `ไม่ต้องสอบเทียบ`; nil for a tool not in the register.
    func calibration(_ name: String) -> (text: String, ink: Color, state: Instrument.Calibration)? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        #if DEBUG
        let all = Debug.demo ? Self.demoInstruments : InstrumentStore.shared.all
        #else
        let all = InstrumentStore.shared.all
        #endif
        guard let tool = all.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }) else { return nil }
        let state = tool.calibration(on: .now)
        let due = tool.calibrationDue.map { ThaiFormat.short.string(from: $0) } ?? ""
        return switch state {
        case .none: ("ไม่ต้องสอบเทียบ", Theme.inkMuted, state)
        case .ok: ("สอบเทียบถึง " + due, Theme.successInk, state)
        case .dueSoon, .overdue: ("สอบเทียบครบ " + due, Theme.warningInk, state)
        }
    }

    // MARK: 3 งานที่ขอเข้าปฏิบัติ

    private func workCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let plan = job.scheduleInput.map { MasterSchedule.plan($0) }
        return reqCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    numbered(3, "งานที่ขอเข้าปฏิบัติ")
                    Text("\(r.work.count) งาน | \(r.work.count - r.linesWithoutDay) มีวัน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    if let at = reqPulledAt { chip("✓ ดึงจากแผน MP " + String(format: "%02d:%02d", RoutineReport.calendar.component(.hour, from: at), RoutineReport.calendar.component(.minute, from: at)), .ok).fixedSize() }
                    Spacer(minLength: 8)
                    legendSwatch(Theme.primary, "วันทำงาน", outlined: false)
                    legendSwatch(Theme.warning, "ยกมา", outlined: false)
                    legendSwatch(Theme.warning, "ยังไม่มีวัน", outlined: true)
                }
                VStack(spacing: 0) {
                    workRow {
                        Text("MP")
                    } title: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("งาน | ตำแหน่ง | ปริมาณ")
                            if editable { Text("แตะช่องวันเพื่อเลือก / ยกเลิก").font(.sarabunFixed(12)) }
                        }
                    } days: { d in Text(Self.dayTitle(r, d)) } tail: { EmptyView() }
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(height: 46)
                    ForEach(Array(r.work.enumerated()), id: \.element.id) { i, line in
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        workLine(r, line, index: i, late: lateDays(line, plan: plan, weekStart: r.weekStart), editable: editable)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    workRow { EmptyView() } title: { Text("งานต่อวัน").foregroundStyle(Theme.inkMuted) } days: { d in
                        let n = r.lines(on: d)
                        Text(n > 0 ? "\(n) งาน" : "–").bold().foregroundStyle(n > 0 ? Theme.navy : Theme.inkFaint).accessibilityIdentifier("workDay\(d)")
                    } tail: { EmptyView() }
                        .font(.sarabunFixed(14)).frame(height: 46)
                }
                .padding(.horizontal, 12)
                .background(Theme.phonePage.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if editable {
                    Button { reqSheet = .addLine } label: { Label("เพิ่มงานนอกแผน MP", systemImage: "plus").font(.sarabunFixed(15, .bold)) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).accessibilityIdentifier("requestAddLine")
                }
            }
        }
    }

    private func legendSwatch(_ c: Color, _ title: String, outlined: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(outlined ? Color.clear : c).frame(width: 12, height: 12)
                .overlay { if outlined { RoundedRectangle(cornerRadius: 3).strokeBorder(c, lineWidth: 1.5) } }
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func workRow<A: View, B: View, C: View, D: View>(@ViewBuilder _ code: () -> A, @ViewBuilder title: () -> B,
                                                              @ViewBuilder days: @escaping (Int) -> C, @ViewBuilder tail: () -> D) -> some View {
        HStack(spacing: 8) {
            code().frame(width: 52, alignment: .leading)
            title().frame(width: 300, alignment: .leading)
            ForEach(reqDays, id: \.self) { d in days(d).frame(maxWidth: .infinity) }
            tail().frame(width: 44)
        }
    }

    private func workLine(_ r: RoutineReport.WeeklyRequest, _ line: RoutineReport.PlanLine, index i: Int, late: Int?, editable: Bool) -> some View {
        let outside = r.work.prefix(i + 1).filter { $0.task == nil }.count
        let (tag, tone): (String, InstallPageData.Tone) = line.task == nil ? ("นอกแผน MP", .idle)
            : line.days.isEmpty ? ("ยังไม่มีวัน | รอนัด", .warn) : late.map { ("ยกมา | ช้า \($0) วัน", .warn) } ?? ("จากแผน MP", .info)
        let qty = line.qty > 0 ? (line.qty.formatted(.number.precision(.fractionLength(0...2))) + (line.unit.isEmpty ? "" : " " + line.unit)) : ""
        return workRow {
            Text(line.task?.code ?? "+\(outside)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).monospacedDigit()
        } title: {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.description.isEmpty ? (line.task?.title ?? "งานอื่น") : line.description)
                    .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                HStack(spacing: 6) {
                    chip(tag, tone).fixedSize()
                    Text([line.location, qty].filter { !$0.isEmpty }.joined(separator: " | ")).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
        } days: { d in
            workCell(r, line, day: d, carried: late != nil && line.days.first == d, editable: editable)
        } tail: {
            if editable {
                Button {
                    reqChange { $0.work.removeAll { $0.id == line.id } }
                    showToast("เอาออกจากคำขอแล้ว | ยังอยู่ในแผน MP")
                } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("เอางานออกจากคำขอ")
            }
        }
        .frame(minHeight: 64)
    }

    private func workCell(_ r: RoutineReport.WeeklyRequest, _ line: RoutineReport.PlanLine, day d: Int, carried: Bool, editable: Bool) -> some View {
        let on = line.days.contains(d), none = line.days.isEmpty
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button { if editable { reqChange { $0.toggleDay(line: line.id, day: d) } } } label: {
            ZStack {
                if on {
                    shape.fill(carried ? Theme.warning : Theme.primary)
                    if carried { Text("ยกมา").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary) }
                } else if none {
                    shape.strokeBorder(Theme.warning.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.fill(Theme.hairline)
                }
            }
            .frame(height: 30).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.dayTitle(r, d) + (on ? " มีงาน" : " ไม่มีงาน"))
        .accessibilityIdentifier("workCell\(line.task?.code ?? line.id.uuidString)-\(d)")
    }

    /// A line carried over: its task should have ended before this week; how many days late it is by Monday.
    func lateDays(_ line: RoutineReport.PlanLine, plan: [MasterSchedule.PlannedTask]?, weekStart: Date) -> Int? {
        #if DEBUG
        if Debug.demo { return line.task == .monitoring ? 1 : nil }
        #endif
        guard let t = line.task, let end = plan?.first(where: { $0.task == t })?.end, end < weekStart else { return nil }
        let monday = RoutineReport.add(weekStart, 1)
        return max(1, RoutineReport.calendar.dateComponents([.day], from: RoutineReport.day(end), to: monday).day ?? 1)
    }

    // MARK: 4 ประเมินความเสี่ยง

    private func riskCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let missing = RoutineReport.commonRisks.filter { c in !r.risks.contains { $0.description.contains(c) } }
        return reqCard {
            VStack(alignment: .leading, spacing: 12) {
                numbered(4, "ประเมินความเสี่ยง")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(r.risks) { risk in riskBox(risk, editable: editable) }
                }
                if editable && !missing.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(missing, id: \.self) { m in
                            Button("+ " + m) { reqChange { $0.risks.append(.init(description: m)) } }
                                .font(.sarabunFixed(14, .bold)).buttonStyle(TCButtonStyle(.secondary, size: .card))
                        }
                    }
                }
            }
        }
    }

    /// A text of one risk, found by its id when read and when written (and saved through `reqChange`).
    private func riskText(_ id: UUID, _ field: WritableKeyPath<RoutineReport.Risk, String>) -> Binding<String> {
        Binding(get: { request?.risks.first { $0.id == id }?[keyPath: field] ?? "" },
                set: { v in reqChange { $0.updateRisk(id) { $0[keyPath: field] = v } } })
    }

    private func riskBox(_ risk: RoutineReport.Risk, editable: Bool) -> some View {
        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if editable {
                    TextField("ความเสี่ยง", text: riskText(risk.id, \.description))
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                } else {
                    Text(risk.description).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                }
                Spacer(minLength: 4)
                if editable {
                    Button { reqChange { $0.risks.removeAll { $0.id == risk.id } } } label: { Image(systemName: "xmark").foregroundStyle(Theme.inkMuted).frame(width: 32, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel("ลบความเสี่ยง")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("ป้องกัน:").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                if editable {
                    TextField("แนวทางป้องกัน", text: riskText(risk.id, \.prevention), axis: .vertical)
                        .font(.sarabunFixed(13))
                } else {
                    Text(risk.prevention).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
            }
            HStack(spacing: 6) {
                ForEach(RoutineReport.RiskLevel.allCases, id: \.self) { l in
                    let on = risk.level == l
                    let (ink, fill): (Color, Color) = switch l {
                    case .low: (Theme.successInk, Theme.successSoft)
                    case .medium: (Theme.warningInk, Theme.warningSoft)
                    case .high: (Theme.dangerText, Theme.dangerSoft)
                    }
                    Button { if editable { reqChange { $0.updateRisk(risk.id) { $0.level = l } } } } label: {
                        Text(l.title).font(.sarabunFixed(13, .bold)).foregroundStyle(on ? ink : Theme.inkMuted)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(on ? fill : Theme.hairline, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
    }

    // MARK: toast

    func showToast(_ text: String) {
        reqToast = text
        Task { try? await Task.sleep(for: .seconds(2.2)); if reqToast == text { reqToast = nil } }
    }

    private func toast(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.navySolid.opacity(0.9), in: Capsule())
            .padding(.bottom, 110)
            .transition(.opacity)
            .accessibilityIdentifier("requestToast")
    }
}
