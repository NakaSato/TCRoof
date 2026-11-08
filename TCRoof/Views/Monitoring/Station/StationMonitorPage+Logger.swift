import SwiftUI
import TCRoofUI
import TCRoofCore

// `ดาต้าล็อกเกอร์` (CHA-73 §3): the logger's facts, the devices on it, and 7 days of its 5-minute sends.

extension StationMonitorPage {
    func loggerTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        Group {
            if let l = d.logger {
                HStack(alignment: .top, spacing: 14) {
                    loggerFacts(l).frame(width: 420)
                    VStack(spacing: 14) {
                        loggerDevices(l)
                        loggerWeek(l)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                emptyNote("ไม่มีข้อมูลดาต้าล็อกเกอร์", "สถานีนี้ยังไม่จับคู่กับ Plant ของ Growatt", symbol: "antenna.radiowaves.left.and.right.slash")
            }
        }
    }

    private func loggerFacts(_ l: Monitoring.Logger) -> some View {
        let online: String = l.online.map { $0 ? "ออนไลน์" : "ขาดการติดต่อ" } ?? MonFormat.dash
        let rows: [(String, String)] = [
            ("SN", l.sn ?? MonFormat.dash),
            ("รุ่น", l.model ?? MonFormat.dash),
            ("การเชื่อมต่อ", online),
            ("ข้อมูลล่าสุด", dayTime(l.lastData)),
            ("รอบข้อมูล", l.intervalMinutes.map { "ทุก \($0) นาที" } ?? MonFormat.dash),
            ("เก็บย้อนหลังที่ Growatt", l.growattHistoryDays.map { "ราว \($0) วัน" } ?? MonFormat.dash),
            ("TCRoof เก็บถาวร", l.archive ?? "ยังไม่มี"),
            ("ระบบ", "Growatt OpenAPI · อ่านอย่างเดียว"),
        ]
        return MonCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    cardTitle("ดาต้าล็อกเกอร์")
                    Spacer()
                    if let on = l.online { MonChip(on ? "ออนไลน์" : "ขาดการติดต่อ", on ? .ok : .bad) }
                }
                .padding(.bottom, 6)
                ForEach(rows, id: \.0) { k, v in
                    HStack {
                        Text(k).font(.sarabun(14)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        Text(v).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    }
                    .frame(minHeight: 34)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func loggerDevices(_ l: Monitoring.Logger) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 0) {
                cardTitle("อุปกรณ์ที่ต่ออยู่กับดาต้าล็อกเกอร์").padding(.bottom, 8)
                HStack {
                    Text("อุปกรณ์").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SN").frame(width: 150, alignment: .leading)
                    Text("ข้อมูลล่าสุด").frame(width: 150, alignment: .leading)
                    Text("สถานะ").frame(width: 90, alignment: .trailing)
                }
                .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                if l.devices.isEmpty {
                    Text("ไม่มีข้อมูล").font(.sarabun(14)).foregroundStyle(Theme.inkMuted).padding(.vertical, 12)
                }
                ForEach(l.devices) { dev in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(dev.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                            Text(dev.detail).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(dev.sn ?? MonFormat.dash).frame(width: 150, alignment: .leading)
                        Text(dayTime(dev.lastData)).frame(width: 150, alignment: .leading)
                        statusChip(dev.status).frame(width: 90, alignment: .trailing)
                    }
                    .font(.sarabun(14)).foregroundStyle(Theme.navy)
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func loggerWeek(_ l: Monitoring.Logger) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cardTitle("การส่งข้อมูล 7 วัน")
                    Spacer()
                    if l.receivedShare != nil {
                        Text("ขาดหายรวม " + MonFormat.number(l.missingHours, 1) + " ชม. · ได้รับ " + MonFormat.percent(l.receivedShare, digits: 1))
                            .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    }
                }
                if l.days.isEmpty {
                    Text("ไม่มีข้อมูล · ยังไม่ได้อ่านประวัติการส่งข้อมูลจาก Growatt").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(l.days) { day in dayBar(day) }
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 74)
                        ForEach(["00:00", "06:00", "12:00", "18:00", "24:00"], id: \.self) { t in
                            Text(t).font(.sarabun(11)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(width: 50)
                    }
                    HStack(spacing: 12) {
                        swatch(Theme.success, "ส่งข้อมูล")
                        swatch(Theme.jobOrange, "ขาดหาย")
                        swatch(Theme.track, "ยังไม่ถึงเวลา")
                    }
                }
            }
        }
        .accessibilityIdentifier("station.loggerWeek")
    }

    private func dayBar(_ day: Monitoring.LoggerDay) -> some View {
        let isToday = Calendar.current.isDate(day.start, inSameDayAs: now)
        let share = day.receivedShare
        return HStack(spacing: 12) {
            Text(isToday ? "วันนี้" : Self.thaiDay(day.start)).font(.sarabun(13)).foregroundStyle(Theme.inkStrong)
                .frame(width: 62, alignment: .leading)
            GeometryReader { g in
                let w = g.size.width, n = CGFloat(Monitoring.slots)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Rectangle().fill(Theme.success).frame(width: w * CGFloat(day.dueSlots) / n)
                    ForEach(Array(day.gaps.enumerated()), id: \.offset) { _, gap in
                        let lo = CGFloat(max(gap.lowerBound, 0)), hi = CGFloat(min(gap.upperBound, day.dueSlots))
                        if hi > lo {
                            Rectangle().fill(Theme.jobOrange).frame(width: max(w * (hi - lo) / n, 3)).offset(x: w * lo / n)
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            Text(MonFormat.percent(share)).font(.sarabun(13, (share ?? 1) < 1 ? .bold : .regular))
                .foregroundStyle((share ?? 1) < 1 ? Theme.warningText : Theme.inkStrong)
                .frame(width: 50, alignment: .trailing)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((isToday ? "วันนี้" : Self.thaiDay(day.start)) + " ได้รับ " + MonFormat.percent(share))
    }
}
