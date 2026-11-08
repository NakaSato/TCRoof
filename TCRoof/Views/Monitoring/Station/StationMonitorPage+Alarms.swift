import SwiftUI
import TCRoofUI
import TCRoofCore

// `ประวัติแจ้งเตือน` (CHA-73 §7): the filters and `รับทราบทั้งหมด`, the table, and the selected line's detail with
// Growatt's fix steps, its repeats, its work order and `รับทราบ`.

extension StationMonitorPage {
    func alarmsTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        let end = Calendar.current.date(byAdding: .day, value: -alarmDaysBack * alarmPeriod.days, to: now) ?? now
        let filter = Monitoring.AlarmFilter(period: alarmPeriod, end: end, device: alarmDevice, state: alarmState)
        let rows = filter.apply(d.events, acknowledged: acks.ids)
        let picked = rows.first { $0.id == selectedEvent } ?? rows.first
        return VStack(spacing: 14) {
            alarmFilters(d, filter: filter, rows: rows)
            HStack(alignment: .top, spacing: 14) {
                alarmTable(rows, picked: picked?.id).frame(maxWidth: .infinity)
                Group {
                    if let picked { alarmDetail(picked, s) } else {
                        emptyNote("ไม่มีแจ้งเตือน", "ไม่มีรายการตามตัวกรองนี้", symbol: "checkmark.seal")
                    }
                }
                .frame(width: 340)
            }
        }
    }

    private func alarmFilters(_ d: Monitoring.StationDetail, filter: Monitoring.AlarmFilter, rows: [Monitoring.AlarmEvent]) -> some View {
        let (start, stop) = filter.interval()
        let last = Calendar.current.date(byAdding: .day, value: -1, to: stop) ?? stop
        let title = alarmPeriod == .day ? Self.thaiDate(last) : Self.thaiDay(start) + " – " + Self.thaiDate(last)
        var devices: [(Monitoring.AlarmFilter.Device, String)] = [(.all, "ทุกอุปกรณ์")]
        devices += d.inverters.map { (.inverter($0.name), $0.name) }
        devices += [(.logger, "ดาต้าล็อกเกอร์"), (.tcroof, "TCRoof")]
        let unacked = rows.filter { !$0.isAcknowledged(acks.ids) }
        return HStack(spacing: 10) {
            stepper(title, back: { alarmDaysBack += 1 }, forward: alarmDaysBack > 0 ? { alarmDaysBack -= 1 } : nil)
            MonSwitch(options: [(Monitoring.AlarmFilter.Period.day, "วัน"), (.month, "30 วัน"), (.year, "ปี")], selection: $alarmPeriod)
            MonSwitch(options: devices, selection: $alarmDevice)
            MonSwitch(options: [(Monitoring.AlarmFilter.State.all, "ทั้งหมด"), (.open, "ยังไม่ปิด"), (.unacknowledged, "ยังไม่รับทราบ")],
                      selection: $alarmState)
            Spacer(minLength: 6)
            Button("รับทราบทั้งหมด") { acks.acknowledge(unacked.map(\.id)) }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .disabled(unacked.isEmpty)
                .accessibilityIdentifier("station.alarms.ackAll")
        }
    }

    private func alarmTable(_ rows: [Monitoring.AlarmEvent], picked: String?) -> some View {
        MonCard(padding: 0) {
            VStack(spacing: 0) {
                alarmHeader
                if rows.isEmpty {
                    Text("ไม่มีแจ้งเตือนในช่วงนี้").font(.sarabun(14)).foregroundStyle(Theme.inkMuted).padding(24)
                }
                ForEach(rows) { e in
                    Button { selectedEvent = e.id } label: { alarmRow(e, on: e.id == picked) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(e.id == picked ? .isSelected : [])
                        .accessibilityIdentifier("station.alarm." + e.id)
                }
                Spacer(minLength: 16)
                HStack {
                    Text("\(rows.count) รายการ · ยังไม่รับทราบ \(rows.filter { !$0.isAcknowledged(acks.ids) }.count)")
                        .accessibilityIdentifier("station.alarms.summary")
                    Spacer()
                    Text("Growatt alarm list · ตรวจจาก TCRoof · รับทราบเก็บในเครื่องนี้")
                }
                .font(.sarabun(13)).foregroundStyle(Theme.inkMuted).padding(16)
            }
            .frame(minHeight: 560, alignment: .top)
        }
    }

    private var alarmHeader: some View {
        HStack(spacing: 8) {
            Text("เวลาเกิด").frame(width: 100, alignment: .leading)
            Text("อุปกรณ์").frame(width: 120, alignment: .leading)
            Text("รุ่น · SN").frame(width: 120, alignment: .leading)
            Text("รหัส").frame(width: 90, alignment: .leading)
            Text("รายละเอียด").frame(maxWidth: .infinity, alignment: .leading)
            Text("นาน").frame(width: 90, alignment: .trailing)
            Text("สถานะ").frame(width: 110, alignment: .trailing)
        }
        .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    private func alarmRow(_ e: Monitoring.AlarmEvent, on: Bool) -> some View {
        let codeTint: Color = e.source == .growatt ? Theme.dangerText : e.source == .tcroof ? Theme.warningText : Theme.navy
        return HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(e.isOpen ? Theme.danger : Color.clear).frame(width: 7, height: 7).padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Calendar.current.isDate(e.firstSeen, inSameDayAs: now) ? "วันนี้" : Self.thaiDay(e.firstSeen))
                        .font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                    Text(MonFormat.time(e.firstSeen) + (e.repeats.count > 1 ? " · \(e.repeats.count) ครั้ง" : ""))
                        .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
            }
            .frame(width: 100, alignment: .leading)
            Text(e.device).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy).lineLimit(2).frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.model ?? (e.source == .tcroof ? "ตรวจจาก TCRoof" : MonFormat.dash)).font(.sarabun(13)).foregroundStyle(Theme.navy)
                Text(e.sn ?? MonFormat.dash).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1).frame(width: 120, alignment: .leading)
            Text(e.label).font(.sarabun(14, .bold)).foregroundStyle(codeTint).frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.titleTH).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                if !e.titleEN.isEmpty { Text(e.titleEN).font(.sarabun(12)).foregroundStyle(Theme.inkMuted) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(durationText(e)).font(.sarabun(13, e.isOpen ? .bold : .regular))
                .foregroundStyle(e.isOpen ? Theme.dangerText : Theme.inkStrong).frame(width: 90, alignment: .trailing)
            stateChip(e).frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .background(on ? Theme.rowSelected : Color.clear)
        .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// `ใหม่`, `รับทราบ`, `มีใบงาน TK-0412`.
    private func stateChip(_ e: Monitoring.AlarmEvent) -> some View {
        if let wo = e.workOrder { return MonChip("มีใบงาน " + wo, .bad) }
        return e.isAcknowledged(acks.ids) ? MonChip("รับทราบ", .muted) : MonChip("ใหม่", .warn)
    }

    /// `31 นาที`, `5 ชม. 5 น.+` while open, `ทั้งวัน`.
    private func durationText(_ e: Monitoring.AlarmEvent) -> String {
        if e.allDay { return "ทั้งวัน" }
        let m = Int(e.duration(now: now) / 60)
        let text = m >= 60 ? "\(m / 60) ชม. \(m % 60) น." : "\(m) นาที"
        return e.isOpen ? text + "+" : text
    }

    private func alarmDetail(_ e: Monitoring.AlarmEvent, _ s: Monitoring.Station) -> some View {
        let acked = e.isAcknowledged(acks.ids)
        return MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(e.label + " · " + Self.sourceTitle(e.source)).font(.sarabun(14, .bold))
                        .foregroundStyle(e.source == .growatt ? Theme.dangerText : Theme.navy)
                    Spacer()
                    stateChip(e)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.titleTH).font(.sarabun(20, .bold)).foregroundStyle(Theme.navy)
                    if !e.titleEN.isEmpty { Text(e.titleEN).font(.sarabun(14)).foregroundStyle(Theme.inkMuted) }
                }
                Divider().overlay(Theme.hairline)
                detailRow("อุปกรณ์", [e.device, e.sn].compactMap { $0 }.joined(separator: " · "))
                detailRow("รุ่น", e.model ?? MonFormat.dash)
                detailRow("เกิดครั้งแรก", dayTime(e.firstSeen))
                detailRow("สิ้นสุด", e.ended.map { dayTime($0) } ?? "ยังไม่ปิด")
                detailRow("นาน", durationText(e) + (e.isOpen ? " และยังไม่ปิด" : ""))
                if let fix = e.fix {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("วิธีแก้ (Growatt)").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                        ForEach(Array(fix.stepsTH.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). " + step).font(.sarabun(14)).foregroundStyle(Theme.inkStrong)
                        }
                        Text(fix.stepsEN).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if e.repeats.count > 1 {
                    Text("เกิดซ้ำ \(e.repeats.count) ครั้ง").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    Text(e.repeats.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(Locale(identifier: "en_GB"))) }
                        .joined(separator: " · "))
                        .font(.sarabun(13)).foregroundStyle(Theme.navy)
                }
                Spacer(minLength: 10)
                HStack(spacing: 10) {
                    Button { maintenance = s } label: {
                        Text(e.workOrder.map { "เปิดใบงาน " + $0 + " ›" } ?? "สร้างใบงานซ่อม").lineLimit(1)
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                    .accessibilityIdentifier("station.alarm.workOrder")
                    Button(acked ? "รับทราบแล้ว" : "รับทราบ") { acks.acknowledge([e.id]) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                        .disabled(acked)
                        .accessibilityIdentifier("station.alarm.ack")
                }
            }
            .frame(minHeight: 528, alignment: .top)
        }
    }

    private func detailRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.sarabun(14)).foregroundStyle(Theme.inkStrong)
            Spacer()
            Text(v).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    static func sourceTitle(_ s: Monitoring.Alarm.Source) -> String {
        switch s {
        case .growatt: "Growatt"
        case .lost: "ดาต้าล็อกเกอร์"
        case .tcroof: "ตรวจจาก TCRoof"
        }
    }
}
