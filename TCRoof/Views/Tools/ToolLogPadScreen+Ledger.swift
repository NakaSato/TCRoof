import SwiftUI
import TCRoofUI
import TCRoofCore

/// The ledger's left card, `สมุดบันทึกเครื่องมือและรถ` (docs/ui/tools-log-ipad §4 and §5 items 3–8): the kind tabs, what
/// is out now as a table, the log's filters and the log by day, and the footer with `ส่งออก CSV` and `โหลดเพิ่ม`.
extension ToolLogPadScreen {
    static let actions: [ToolLog.Action?] = [nil, .borrow, .giveBack, .carOut, .carIn, .fuel]

    var ledgerCard: some View {
        let all = events, now = Date.now
        let outs = ToolLog.outs(all, now: now).filter { kind == nil || $0.kind == kind }
        let list = rows(all, now: now)
        return VStack(spacing: 0) {
            ledgerHead(all)
            Rectangle().fill(Theme.headerLine).frame(height: 1)
            if loading {
                DataLoadingSkeleton(lines: 5).padding(18)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        outSection(outs, now: now)
                        filterBar(all)
                        if searching || !query.isEmpty { searchField }
                        logTable(Array(list.prefix(shown)), log: all, now: now)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                }
            }
            Rectangle().fill(Theme.headerLine).frame(height: 1)
            footer(list, log: all, now: now)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .cardShadow()
    }

    // MARK: head

    private func ledgerHead(_ all: [ToolLog.Event]) -> some View {
        HStack(spacing: 16) {
            Text("สมุดบันทึกเครื่องมือและรถ").font(.sarabunFixed(19, .bold)).foregroundStyle(Theme.navy)
                .lineLimit(1).minimumScaleFactor(0.8).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                kindTab("ทั้งหมด", count: all.count, value: nil, id: "all")
                kindTab("เครื่องมือ", count: all.filter { $0.action.kind == .tool }.count, value: .tool, id: "tool")
                kindTab("รถ", count: all.filter { $0.action.kind == .car }.count, value: .car, id: "car")
            }
            recordMenu {
                Label("บันทึกรายการ", systemImage: "plus").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.6)))
            }
            .accessibilityIdentifier("toollog.add")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    /// An underlined tab of the strip: `ทั้งหมด 13`.
    private func kindTab(_ title: String, count: Int, value: ToolLog.Kind?, id: String) -> some View {
        let on = kind == value
        return Button { kind = value } label: {
            Text("\(title) \(count)").font(.sarabunFixed(15, on ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.navy).frame(height: 3) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(count) รายการ")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("toollog.kind.\(id)")
    }

    // MARK: out now

    private func outSection(_ outs: [ToolLog.Out], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("กำลังใช้อยู่ ").bold() + Text("(\(outs.count))"))
                .font(.sarabunFixed(15)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                outHeader
                if outs.isEmpty {
                    Text("ไม่มีรายการที่ยืมหรือออกใช้อยู่").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                ForEach(outs) { o in
                    Rectangle().fill(Theme.headerLine).frame(height: 1)
                    outRow(o, now: now)
                }
            }
            .tableFrame()
        }
    }

    private var outHeader: some View {
        HStack(spacing: 8) {
            Text("รายการ").frame(maxWidth: .infinity, alignment: .leading)
            Text("ผู้ใช้").frame(width: 58, alignment: .leading)
            Text("งาน").frame(width: 112, alignment: .leading)
            Text("ออกเมื่อ").frame(width: 92, alignment: .leading)
            Text("กำหนดคืน").frame(width: 114, alignment: .leading)
            Text("ใช้มาแล้ว").frame(width: 80, alignment: .trailing)
            Color.clear.frame(width: 96, height: 1)
        }
        .tableHeaderStyle()
    }

    private func outRow(_ o: ToolLog.Out, now: Date) -> some View {
        let e = o.event, car = o.kind == .car
        let cal = MasterSchedule.calendar
        let due: String = if let d = e.due {
            cal.isDate(d, inSameDayAs: now) ? "วันนี้ " + ToolLogCard.clock(d) : ToolLogCard.time(d, now: now)
        } else { car ? "วันนี้" : "—" }
        return HStack(spacing: 8) {
            Text(e.itemName).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.person).frame(width: 58, alignment: .leading)
            Text(e.job.isEmpty ? "—" : e.job).foregroundStyle(Theme.inkMuted).frame(width: 112, alignment: .leading)
            Text(Self.stamp(e.at, now: now)).frame(width: 92, alignment: .leading)
            Group {
                if o.late {
                    Text(due + " (เกิน \(ToolLog.daysLate(e, now: now)) วัน)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.dangerText)
                } else {
                    Text(due)
                }
            }
            .frame(width: 114, alignment: .leading)
            Text(ToolLog.duration(from: e.at, to: now)).frame(width: 80, alignment: .trailing)
            Button(car ? "บันทึกคืนรถ" : "บันทึกคืน") { form = car ? .carIn(e) : .giveBack(e) }
                .buttonStyle(TCButtonStyle(.text, size: .card))
                .frame(width: 96, alignment: .trailing)
                .accessibilityIdentifier("toollog.out.\(e.item)")
        }
        .font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(o.late ? Theme.dangerSoft.opacity(0.5) : Color.clear)
        .accessibilityElement(children: .contain)
    }

    // MARK: filters

    private func filterBar(_ all: [ToolLog.Event]) -> some View {
        let rangeIndex = Binding<Int>(get: { ToolLog.Period.allCases.firstIndex(of: range) ?? 1 },
                                      set: { range = ToolLog.Period.allCases[$0] })
        let actionIndex = Binding<Int>(get: { Self.actions.firstIndex(of: action) ?? 0 }, set: { action = Self.actions[$0] })
        let segments = HStack(spacing: 8) {
            LedgerSegments(ToolLog.Period.allCases.map(\.title), selection: rangeIndex, id: "toollog.range")
            LedgerSegments(Self.actions.map { $0?.title ?? "ทั้งหมด" }, selection: actionIndex, id: "toollog.action")
        }
        let tools = HStack(spacing: 8) {
            whoMenu(all)
            Button {
                searching.toggle()
                if !searching { query = "" }
            } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44)
                    .background(searching ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searching ? "ปิดการค้นหา" : "ค้นหาในบันทึก")
            .accessibilityIdentifier("toollog.search")
        }
        let title = Text("บันทึก").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
        // one line on the board's width, two when the card is narrower
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { title; segments; Spacer(minLength: 0); tools }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { title; Spacer(minLength: 0); tools }
                ScrollView(.horizontal, showsIndicators: false) { segments }
            }
        }
    }

    /// `ผู้ใช้ · งาน ▾`: the people and the jobs in the log.
    private func whoMenu(_ all: [ToolLog.Event]) -> some View {
        let people = Set(all.map(\.person).filter { !$0.isEmpty }).sorted()
        let jobs = Set(all.map(\.job).filter { !$0.isEmpty }).sorted()
        return Menu {
            Button { who = .all } label: { menuLabel("ทั้งหมด", on: who == .all) }
            Section("ผู้ใช้") { ForEach(people, id: \.self) { p in Button { who = .person(p) } label: { menuLabel(p, on: who == .person(p)) } } }
            Section("งาน") { ForEach(jobs, id: \.self) { j in Button { who = .job(j) } label: { menuLabel(j, on: who == .job(j)) } } }
        } label: {
            HStack(spacing: 4) {
                Text(who.title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .font(.sarabunFixed(15, .bold)).foregroundStyle(who == .all ? Theme.navy : Theme.primary)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(who == .all ? Theme.surface : Theme.primarySoft, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.6)))
        }
        .accessibilityIdentifier("toollog.who")
    }

    @ViewBuilder private func menuLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    var searchField: some View {
        TCSearchField("ค้นหารายการ ผู้ใช้ งาน หรือทะเบียนรถ", text: $query).accessibilityIdentifier("toollog.query")
    }

    // MARK: log

    private func logTable(_ list: [ToolLog.Event], log: [ToolLog.Event], now: Date) -> some View {
        let km = ToolLog.driven(in: log)
        var days: [(day: Date, events: [ToolLog.Event])] = []
        for e in list {
            let day = MasterSchedule.calendar.startOfDay(for: e.at)
            if days.last?.day == day { days[days.count - 1].events.append(e) } else { days.append((day, [e])) }
        }
        return VStack(spacing: 0) {
            logHeader
            ForEach(days, id: \.day) { d in
                Rectangle().fill(Theme.headerLine).frame(height: 1)
                Text(ToolLogCard.dayTitle(d.day, now: now)).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).padding(.horizontal, 14)
                    .background(Theme.background)
                    .accessibilityAddTraits(.isHeader)
                ForEach(d.events) { e in
                    Rectangle().fill(Theme.headerLine).frame(height: 1)
                    logRow(e, km: km[e.id])
                }
            }
        }
        .tableFrame()
    }

    private var logHeader: some View {
        HStack(spacing: 8) {
            Text("เวลา").frame(width: 52, alignment: .leading)
            Text("ประเภท").frame(width: 92, alignment: .leading)
            Text("รายการ").frame(maxWidth: .infinity, alignment: .leading)
            Text("ผู้ใช้").frame(width: 58, alignment: .leading)
            Text("รายละเอียด").frame(maxWidth: .infinity, alignment: .leading)
        }
        .tableHeaderStyle()
    }

    private func logRow(_ e: ToolLog.Event, km: Int?) -> some View {
        HStack(spacing: 8) {
            Text(ToolLogCard.clock(e.at)).monospacedDigit().frame(width: 52, alignment: .leading)
            TCStatusChip(e.action.title, kind: Self.chip(e.action)).frame(width: 92, alignment: .leading)
            Text(e.itemName).font(.sarabunFixed(15, .bold)).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.person).frame(width: 58, alignment: .leading)
            Text(Self.detail(e, km: km)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toollog.log.\(e.id)")
    }

    /// Borrow and car out are info, give back and car in done, fuel pending, a reminder overdue.
    static func chip(_ a: ToolLog.Action) -> TCStatusChip.Kind {
        switch a {
        case .borrow, .carOut: .active
        case .giveBack, .carIn: .ok
        case .fuel: .pending
        case .remind: .overdue
        }
    }

    /// `NO.212 · วิ่ง 212 กม. · ไมล์ 120,455`, `45.2 ลิตร · 1,450 บาท`, `NO.215 · สภาพปกติ`.
    static func detail(_ e: ToolLog.Event, km: Int?) -> String {
        var parts = [e.job].filter { !$0.isEmpty }
        if let km { parts.append("วิ่ง \(km.formatted()) กม.") }
        if let odo = e.odometer { parts.append("ไมล์ \(odo.formatted())") }
        if let l = e.litres { parts.append("\(l.formatted(.number.precision(.fractionLength(0...1)))) ลิตร") }
        if let b = e.baht { parts.append("\(Int(b.rounded()).formatted()) บาท") }
        if !e.note.isEmpty { parts.append(e.note) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// `วันนี้ 09:02`, `26/9 08:15`.
    static func stamp(_ d: Date, now: Date) -> String {
        MasterSchedule.calendar.isDate(d, inSameDayAs: now) ? "วันนี้ " + ToolLogCard.clock(d)
            : ToolLogCard.time(d, now: now) + " " + ToolLogCard.clock(d)
    }

    // MARK: footer

    private func footer(_ list: [ToolLog.Event], log: [ToolLog.Event], now: Date) -> some View {
        let count = min(shown, list.count)
        return HStack(spacing: 14) {
            Text("แสดง \(count) จาก \(list.count) รายการ" + (list.isEmpty ? " · ไม่มีรายการตามตัวกรองนี้" : ""))
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                .accessibilityIdentifier("toollog.footer")
            Spacer(minLength: 8)
            Button("ส่งออก CSV") { export(list, log: log, now: now) }
                .buttonStyle(TCButtonStyle(.text, size: .card))
                .disabled(list.isEmpty)
                .accessibilityIdentifier("toollog.csv")
            if list.count > shown {
                Button("โหลดเพิ่ม") { shown += Self.page }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    .accessibilityIdentifier("toollog.more")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(minHeight: 64)
    }
}

/// The ledger's segmented filters (`วันนี้ | 7 วัน | 30 วัน | ทั้งหมด`): segments as wide as their text on a grey track,
/// the selected one white; 44 pt high.
struct LedgerSegments: View {
    let options: [String]
    @Binding var selection: Int
    let id: String

    init(_ options: [String], selection: Binding<Int>, id: String) {
        self.options = options; self._selection = selection; self.id = id
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selection
                Button { selection = i } label: {
                    Text(options[i]).font(.sarabunFixed(14, on ? .bold : .regular))
                        .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.surface)
                                    .shadow(color: Theme.navySolid.opacity(0.16), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(id).\(i)")
            }
        }
        .padding(2)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

private extension View {
    /// The ledger's bordered tables.
    func tableFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.borderSubtle))
    }

    /// A table's header row: muted 13 pt on the page tint.
    func tableHeaderStyle() -> some View {
        font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Theme.background)
    }
}
