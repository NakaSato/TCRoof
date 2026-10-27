import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `บันทึกการใช้เครื่องมือและรถ` (the board's `iPadToolsHub`): what is out now with its action, the last 7 days of
/// activity by day, and the ทั้งหมด / เครื่องมือ / รถ filter. The team's, synced (`ToolEvent`); hidden from contractors.
struct ToolLogCard: View {
    @Query(sort: \ToolEvent.at, order: .reverse) private var stored: [ToolEvent]
    @Query private var vehicles: [CompanyVehicle]
    @State private var filter = 0
    @State private var form: ToolLogForm?
    @State private var showAll = false
    @Environment(\.modelContext) private var context

    private var events: [ToolLog.Event] { ToolLogDemo.on ? ToolLogDemo.events : stored.map(\.event) }

    private func keeps(_ kind: ToolLog.Kind) -> Bool { filter == 0 || (filter == 1 ? kind == .tool : kind == .car) }

    var body: some View {
        let all = events, now = Date.now
        let outs = ToolLog.outs(all, now: now).filter { keeps($0.kind) }
        let days = ToolLog.days(all.filter { keeps($0.action.kind) }, now: now, days: showAll ? 60 : 7)
        return VStack(alignment: .leading, spacing: 14) {
            header(all, now: now)
            sectionTitle("ใช้งานอยู่ตอนนี้", count: "\(outs.count) รายการ")
            if outs.isEmpty {
                Text("ไม่มีรายการที่ยืมหรือออกใช้อยู่").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    ForEach(outs) { outCard($0, now: now) }
                }
            }
            HStack(spacing: 10) {
                TCButton("ยืมเครื่องมือ", systemImage: "arrow.up.right.square", kind: .secondary, size: .card) { form = .borrow }
                TCButton("ออกรถ", systemImage: "car", kind: .secondary, size: .card) { form = .carOut(nil) }
                    .disabled(vehicleList.isEmpty)
            }
            sectionTitle("ความเคลื่อนไหว", count: showAll ? "60 วันล่าสุด" : "7 วันล่าสุด")
            if days.isEmpty {
                Text("ยังไม่มีบันทึก").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            ForEach(days, id: \.day) { d in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.dayTitle(d.day, now: now) + " · \(d.events.count) รายการ")
                        .font(.sarabun(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                    ForEach(d.events) { activityRow($0) }
                }
            }
            Button(showAll ? "แสดง 7 วันล่าสุด" : "ดูบันทึกทั้งหมด ›") { showAll.toggle() }
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(item: $form) { ToolLogFormSheet(form: $0, events: events, vehicles: vehicleList) }
    }

    private var vehicleList: [ToolLog.Vehicle] { ToolLogDemo.on ? ToolLogDemo.vehicles : vehicles.map(\.vehicle) }

    private func header(_ all: [ToolLog.Event], now: Date) -> some View {
        let km = ToolLog.monthKm(all, now: now), fuel = ToolLog.monthFuel(all, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("บันทึกการใช้เครื่องมือและรถ").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                pill("chart.line.uptrend.xyaxis", "\(km.formatted()) กม.", "เดือนนี้")
                pill("fuelpump", "\(Int(fuel.rounded()).formatted()) บาท", "ค่าน้ำมัน")
                Spacer(minLength: 0)
            }
            TCCountSegments([.init("ทั้งหมด", count: all.count), .init("เครื่องมือ", count: all.filter { $0.action.kind == .tool }.count),
                             .init("รถ", count: all.filter { $0.action.kind == .car }.count)],
                            selection: $filter, equalWidths: false, fontSize: 15)
                .fixedSize()
        }
    }

    private func pill(_ symbol: String, _ value: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(value).font(.sarabun(13, .bold, relativeTo: .footnote))
            Text(title).font(.sarabun(13, relativeTo: .footnote))
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.primarySoft, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: String, count: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            Text(count).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// An item out: what, who and for which job, since when, and its action (`รับคืน`, `ทวงคืน` when late, `คืนรถ`).
    private func outCard(_ o: ToolLog.Out, now: Date) -> some View {
        let e = o.event, car = o.kind == .car
        let kindTitle = o.late ? "เกินกำหนดคืน" : car ? "ออกใช้งานมาแล้ว" : "ยืมมาแล้ว"
        let since = car ? "ออก " + Self.time(e.at, now: now) + (e.odometer.map { " · ไมล์ \($0.formatted())" } ?? "")
            : "ยืม " + Self.time(e.at, now: now) + (e.due.map { " · ครบคืน " + Self.time($0, now: now) } ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: car ? "car.fill" : "wrench.and.screwdriver.fill").font(.system(size: 15))
                    .foregroundStyle(o.late ? Theme.dangerText : Theme.primary)
                    .frame(width: 32, height: 32).background(o.late ? Theme.surface : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 0) {
                    Text(kindTitle).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(o.late ? Theme.dangerText : Theme.inkMuted)
                    Text(ToolLog.duration(from: e.at, to: now)).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                }
            }
            Text(e.itemName).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy).lineLimit(2)
            Text([e.person, e.job].filter { !$0.isEmpty }.joined(separator: " · ")).font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            Text(since).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            Button {
                if car { form = .carIn(e) } else if o.late { remind(e) } else { form = .giveBack(e) }
            } label: {
                Text(car ? "คืนรถ · บันทึกไมล์" : o.late ? "ทวงคืน" : "รับคืน").frame(maxWidth: .infinity)
            }
            .buttonStyle(TCButtonStyle(o.late ? .danger : .secondary, size: .card))
            if o.late {
                Button("รับคืน") { form = .giveBack(e) }.font(.sarabun(14, .semibold, relativeTo: .subheadline)).frame(minHeight: 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(o.late ? Theme.dangerSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .contain)
    }

    /// `ทวงคืน`: a `remind` entry in the log, so the team sees who was chased and when.
    private func remind(_ e: ToolLog.Event) {
        guard !ToolLogDemo.on else { return }
        context.insert(ToolEvent(ToolLog.Event(action: .remind, item: e.item, itemName: e.itemName, person: TravelStore.person,
                                               personEmail: TravelStore.owner, job: e.job, note: "ทวงคืนจาก " + e.person)))
        try? context.save()
    }

    private func activityRow(_ e: ToolLog.Event) -> some View {
        let symbol = switch e.action {
        case .borrow, .giveBack: "wrench.and.screwdriver"
        case .carOut, .carIn: "car"
        case .fuel: "fuelpump"
        case .remind: "bell"
        }
        let kind: TCStatusChip.Kind = switch e.action {
        case .borrow, .carOut: .active
        case .giveBack, .carIn: .ok
        case .fuel: .pending
        case .remind: .overdue
        }
        var details = [e.person, e.job].filter { !$0.isEmpty }
        if let odo = e.odometer { details.append("ไมล์ \(odo.formatted())") }
        if let l = e.litres { details.append("\(l.formatted(.number.precision(.fractionLength(0...1)))) ลิตร") }
        if let b = e.baht { details.append("\(Int(b.rounded()).formatted()) บาท") }
        if !e.note.isEmpty { details.append(e.note) }
        return HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.itemName).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                    TCStatusChip(e.action.title, kind: kind)
                }
                Text(details.joined(separator: " · ")).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Self.clock(e.at)).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).monospacedDigit()
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    static func clock(_ d: Date) -> String {
        let c = MasterSchedule.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `09:02` today, else `26/9`.
    static func time(_ d: Date, now: Date) -> String {
        let cal = MasterSchedule.calendar
        if cal.isDate(d, inSameDayAs: now) { return clock(d) }
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }

    /// `วันนี้ · พ. 30 ก.ย.`, `อ. 29 ก.ย.`
    static func dayTitle(_ d: Date, now: Date) -> String {
        let cal = MasterSchedule.calendar
        let c = cal.dateComponents([.day, .month, .weekday], from: d)
        let text = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."][(c.weekday ?? 1) - 1] + " \(c.day ?? 0) " + RoutineReport.thaiMonthsShort[(c.month ?? 1) - 1]
        return cal.isDate(d, inSameDayAs: now) ? "วันนี้ · " + text : text
    }
}

/// `บันทึกการใช้รถ`: each company vehicle with its state, odometer, tank and service, and the selected one's actions.
struct VehicleCard: View {
    @Query(sort: \ToolEvent.at) private var stored: [ToolEvent]
    @Query private var vehicles: [CompanyVehicle]
    @State private var selected: String?
    @State private var form: ToolLogForm?

    var body: some View {
        let events = ToolLogDemo.on ? ToolLogDemo.events : stored.map(\.event)
        let list = (ToolLogDemo.on ? ToolLogDemo.vehicles : vehicles.map(\.vehicle)).sorted { $0.name < $1.name }
        let current = list.first { $0.id == selected } ?? list.first
        let out = current.flatMap { ToolLog.out($0.id, in: events) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "car.2").foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("บันทึกการใช้รถ").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text("\(list.count) คัน · ออกอยู่ \(list.filter { ToolLog.out($0.id, in: events) != nil }.count)")
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                TCButton("เพิ่มรถ", systemImage: "plus", kind: .secondary, size: .card) { form = .vehicle(nil) }
            }
            if list.isEmpty {
                Text("ยังไม่มีรถในรายการ แตะ เพิ่มรถ เพื่อบันทึกชื่อ ทะเบียน และรอบเช็กระยะ")
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 64)
            }
            ForEach(list) { v in row(v, events: events, on: v.id == current?.id) }
            if let current {
                HStack(spacing: 10) {
                    TCButton(out != nil ? "คืนรถ · บันทึกไมล์" : "ออกรถคันนี้", kind: .primary, size: .card) {
                        form = out.map { .carIn($0) } ?? .carOut(current)
                    }
                    TCButton("เติมน้ำมัน", systemImage: "fuelpump", kind: .secondary, size: .card) { form = .fuel(current) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(item: $form) { ToolLogFormSheet(form: $0, events: events, vehicles: list) }
    }

    private func row(_ v: ToolLog.Vehicle, events: [ToolLog.Event], on: Bool) -> some View {
        let out = ToolLog.out(v.id, in: events), last = ToolLog.lastReading(v.id, in: events)
        let line = out.map { [$0.person, $0.job].filter { !$0.isEmpty }.joined(separator: " · ") + " · ออก " + ToolLogCard.time($0.at, now: .now) }
            ?? "จอดอยู่"
        let left = v.serviceAtKm.flatMap { s in last.odometer.map { s - $0 } }
        return Button { selected = v.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(v.name).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text(v.plate).font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 4)
                    TCStatusChip(out != nil ? "ออกใช้งาน" : "ว่าง", kind: out != nil ? .active : .ok)
                }
                Text(line).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                HStack(spacing: 12) {
                    Text("ไมล์ ").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                        + Text(last.odometer.map { $0.formatted() } ?? "—").font(.sarabun(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.navy)
                    if let f = last.fuel {
                        HStack(spacing: 4) {
                            Text("น้ำมัน").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                            Capsule().fill(Theme.track).frame(width: 54, height: 6)
                                .overlay(alignment: .leading) { Capsule().fill(f < 0.35 ? Theme.danger : Theme.primary).frame(width: 54 * f, height: 6) }
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel("น้ำมัน \(Int(f * 100)) เปอร์เซ็นต์")
                    }
                    Spacer(minLength: 0)
                    if let left {
                        Text(left > 0 ? "เช็กระยะอีก \(left.formatted()) กม." : "ถึงรอบเช็กระยะ")
                            .font(.sarabun(13, left <= 500 ? .bold : .regular, relativeTo: .footnote))
                            .foregroundStyle(left <= 500 ? Theme.pending : Theme.inkMuted)
                    }
                }
            }
            .padding(10)
            .background(on ? Theme.background : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("แก้ไขรถ", systemImage: "pencil") { form = .vehicle(v) } }
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityAction(named: "แก้ไขรถ") { form = .vehicle(v) }
    }
}
