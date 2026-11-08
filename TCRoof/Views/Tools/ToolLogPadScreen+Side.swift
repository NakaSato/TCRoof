import SwiftUI
import TCRoofUI
import TCRoofCore

/// The ledger's right column (docs/ui/tools-log-ipad §5 items 9–10): `เครื่องมือวัด` (four KPIs, the chase list and
/// `ทะเบียน ›`) and `บันทึกการใช้รถ` (one row per vehicle and the selected one's two actions).
extension ToolLogPadScreen {
    /// A line of the chase list: a tool past its due day, or an instrument past its calibration.
    enum Chase: Identifiable {
        case late(ToolLog.Event, days: Int)
        case calibration(Instrument, days: Int)

        var id: String {
            switch self {
            case .late(let e, _): "late-" + e.id
            case .calibration(let t, _): "cal-" + t.id
            }
        }
        var days: Int {
            switch self {
            case .late(_, let d), .calibration(_, let d): d
            }
        }
    }

    // MARK: เครื่องมือวัด

    var instrumentsCard: some View {
        let all = events, now = Date.now, tools = instruments.all
        let outs = ToolLog.outs(all, now: now).filter { $0.kind == .tool }
        let late = outs.filter(\.late)
        let dueSoon = tools.filter { if case .dueSoon = $0.calibration(on: now) { true } else { false } }
        var overdue: [(tool: Instrument, days: Int)] = []
        for t in tools { if case .overdue(let d) = t.calibration(on: now) { overdue.append((tool: t, days: d)) } }
        // `งดใช้ / ซ่อม` (§7 question 3): calibration run out, or given back damaged and not out since; each item once
        let overdueIDs = Set(overdue.map(\.tool.id))
        let repair = overdue.count + ToolLog.damaged(all).filter { !overdueIDs.contains($0.item) }.count
        let chase: [Chase] = (late.map { Chase.late($0.event, days: ToolLog.daysLate($0.event, now: now)) }
                              + overdue.map { Chase.calibration($0.tool, days: $0.days) })
            .sorted { $0.days > $1.days }
        return VStack(alignment: .leading, spacing: 12) {
            cardHead(symbol: "gauge.with.dots.needle.50percent", tint: Theme.okText, fill: Theme.okSoft, title: "เครื่องมือวัด",
                     subtitle: "\(tools.count) เครื่อง · ยืม-คืน · สอบเทียบ") {
                NavigationLink { ToolsView(registerOnly: true) } label: {
                    HStack(spacing: 6) {
                        Text("ทะเบียน")
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    }
                }
                .buttonStyle(TCButtonStyle(.text, size: .card))
                .accessibilityIdentifier("toollog.register")
            }
            HStack(spacing: 8) {
                kpi("ใช้งานอยู่", outs.count, Theme.navy, id: "out")
                kpi("เกินกำหนดคืน", late.count, Theme.dangerText, id: "late")
                kpi("สอบเทียบใกล้ครบ", dueSoon.count, Theme.pending, id: "dueSoon")
                kpi("งดใช้ / ซ่อม", repair, Theme.inkMuted, id: "repair")
            }
            chaseList(Array(chase.prefix(3)), now: now)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .cardShadow()
    }

    func cardHead<Trailing: View>(symbol: String, tint: Color, fill: Color, title: String, subtitle: String,
                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(fill, in: RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(19, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func kpi(_ title: String, _ value: Int, _ color: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.75)
            Text("\(value)").font(.sarabunFixed(22, .bold)).foregroundStyle(color).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityIdentifier("toollog.kpi.\(id)")
    }

    /// At most three, the most overdue first: a late tool asks before `ทวงคืน`, an instrument opens its form.
    @ViewBuilder private func chaseList(_ chase: [Chase], now: Date) -> some View {
        if chase.isEmpty {
            Text("ไม่มีรายการที่ต้องตาม").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(chase.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(Theme.headerLine).frame(height: 1) }
                    chaseRow(c, now: now)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.borderSubtle))
        }
    }

    private func chaseRow(_ c: Chase, now: Date) -> some View {
        let (title, subtitle, chip): (String, String, String) = switch c {
        case .late(let e, let d):
            (e.itemName, [e.person, e.job, e.due.map { "ครบคืน " + ToolLogCard.time($0, now: now) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
             "เกิน \(d) วัน")
        case .calibration(let t, let d):
            (t.name, "งดใช้" + (t.calibrationDue.map { " · ใบรับรองหมด " + ToolLogCard.time($0, now: now) } ?? ""), "สอบเทียบเกิน \(d) วัน")
        }
        return Button {
            switch c {
            case .late(let e, _): chasing = e
            case .calibration(let t, _): editing = t
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text(subtitle).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                TCStatusChip(chip, kind: .overdue)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toollog.chase.\(c.id)")
    }

    // MARK: บันทึกการใช้รถ

    /// The selected vehicle: the one picked, else the first out, else the first.
    func currentVehicle(_ all: [ToolLog.Event]) -> ToolLog.Vehicle? {
        vehicles.first { $0.id == selectedVehicle } ?? vehicles.first { ToolLog.out($0.id, in: all) != nil } ?? vehicles.first
    }

    var vehiclesCard: some View {
        let all = events, now = Date.now, list = vehicles
        let current = currentVehicle(all)
        let out = current.flatMap { ToolLog.out($0.id, in: all) }
        let outCount = list.filter { ToolLog.out($0.id, in: all) != nil }.count
        let summary = "\(list.count) คัน · ออกอยู่ \(outCount) · เดือนนี้ \(ToolLog.monthKm(all, now: now).formatted()) กม. · น้ำมัน "
            + "\(Int(ToolLog.monthFuel(all, now: now).rounded()).formatted()) บาท"
        return VStack(alignment: .leading, spacing: 12) {
            cardHead(symbol: "car.fill", tint: Theme.primary, fill: Theme.primarySoft, title: "บันทึกการใช้รถ", subtitle: summary) {
                Button("ประวัติ") {
                    guard let current else { return }
                    kind = .car; range = .all; query = current.plate.isEmpty ? current.name : current.plate; searching = true
                }
                .buttonStyle(TCButtonStyle(.text, size: .card))
                .disabled(current == nil)
                .accessibilityIdentifier("toollog.history")
            }
            if list.isEmpty {
                Text("ยังไม่มีรถในรายการ แตะ เพิ่มรถ เพื่อบันทึกชื่อ ทะเบียน และรอบเช็กระยะ")
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 64)
                TCButton("เพิ่มรถ", systemImage: "plus", kind: .secondary, size: .card) { form = .vehicle(nil) }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, v in
                            if i > 0 { Rectangle().fill(Theme.headerLine).frame(height: 1) }
                            vehicleRow(v, events: all, now: now, on: v.id == current?.id)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.borderSubtle))
                if let current {
                    HStack(spacing: 10) {
                        Button(out != nil ? "คืนรถ · บันทึกไมล์" : "ออกรถคันนี้") { form = out.map { .carIn($0) } ?? .carOut(current) }
                            .buttonStyle(TCButtonStyle(.primary, size: .page, fullWidth: true))
                            .accessibilityIdentifier("toollog.vehicle.primary")
                        Button("เติมน้ำมัน") { form = .fuel(current) }
                            .buttonStyle(TCButtonStyle(.secondary, size: .page, fullWidth: true))
                            .frame(maxWidth: 170)
                            .accessibilityIdentifier("toollog.vehicle.fuel")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .cardShadow()
    }

    private func vehicleRow(_ v: ToolLog.Vehicle, events: [ToolLog.Event], now: Date, on: Bool) -> some View {
        let out = ToolLog.out(v.id, in: events), last = ToolLog.lastReading(v.id, in: events)
        let back = events.filter { $0.item == v.id && $0.action == .carIn }.max { $0.at < $1.at }
        let line: String
        if let o = out {
            line = [o.person, o.job].filter { !$0.isEmpty }.joined(separator: " · ") + " · ออก " + Self.short(o.at, now: now)
        } else if let b = back {
            let by: String = b.person.isEmpty ? "" : " โดย " + b.person
            line = "จอดที่สำนักงาน · คืน " + Self.short(b.at, now: now) + by
        } else {
            line = "จอดที่สำนักงาน"
        }
        return Button { selectedVehicle = v.id } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(v.name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    if !v.plate.isEmpty {
                        Text(v.plate).font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.navy.opacity(0.7)))
                    }
                    Spacer(minLength: 4)
                    TCStatusChip(out != nil ? "ออกใช้งาน" : "ว่าง", kind: out != nil ? .active : .ok)
                }
                Text(line).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                readings(v, last: last, events: events)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.rowSelected : Color.clear)
            .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("แก้ไขรถ", systemImage: "pencil") { form = .vehicle(v) }
            Button("เพิ่มรถ", systemImage: "plus") { form = .vehicle(nil) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "แก้ไขรถ") { form = .vehicle(v) }
        .accessibilityIdentifier("toollog.vehicle.\(v.id)")
    }

    /// `ไมล์ 85,210`, the fuel bar and `เช็กระยะอีก 2,790 กม.` / `ถึงรอบเช็กระยะ 500 กม.`.
    private func readings(_ v: ToolLog.Vehicle, last: (odometer: Int?, fuel: Double?), events: [ToolLog.Event]) -> some View {
        let left = ToolLog.serviceLeft(v, in: events)
        let warn = left.map { $0 <= ToolLog.serviceWarningKm } ?? false
        return HStack(spacing: 12) {
            (Text("ไมล์ ").foregroundStyle(Theme.inkMuted)
             + Text(last.odometer.map { $0.formatted() } ?? "—").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary))
                .font(.sarabunFixed(14))
            if let f = last.fuel {
                HStack(spacing: 6) {
                    Text("น้ำมัน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    Capsule().fill(Theme.track).frame(width: 56, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(f < 0.35 ? Theme.danger : Theme.success).frame(width: 56 * min(max(f, 0), 1), height: 6)
                        }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("น้ำมัน \(Int(f * 100)) เปอร์เซ็นต์")
            }
            Spacer(minLength: 0)
            if let left {
                Text(left < 0 ? "เลยรอบเช็กระยะ \((-left).formatted()) กม." : warn ? "ถึงรอบเช็กระยะ \(left.formatted()) กม." : "เช็กระยะอีก \(left.formatted()) กม.")
                    .font(.sarabunFixed(13.5, warn ? .bold : .regular))
                    .foregroundStyle(warn ? Theme.pending : Theme.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    /// `07:40` today, else `29/9 18:10`.
    static func short(_ d: Date, now: Date) -> String {
        MasterSchedule.calendar.isDate(d, inSameDayAs: now) ? ToolLogCard.clock(d) : ToolLogCard.time(d, now: now) + " " + ToolLogCard.clock(d)
    }
}
