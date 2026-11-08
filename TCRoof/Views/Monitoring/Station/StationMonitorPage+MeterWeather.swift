import SwiftUI
import TCRoofUI
import TCRoofCore

// `มิเตอร์` (CHA-73 §4) and `สภาพอากาศ` (§5).

extension StationMonitorPage {
    // MARK: meter

    func meterTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        Group {
            if let m = d.meter {
                VStack(spacing: 14) {
                    meterCards(m, d)
                    meterChart(m, d)
                    meterPhases(m, d)
                }
            } else {
                emptyNote("ไม่มีข้อมูลมิเตอร์",
                          "ยังไม่ได้อ่านค่ามิเตอร์กันย้อนจาก Growatt (meter_last_data) สำหรับสถานีนี้",
                          symbol: "gauge.with.dots.needle.bottom.50percent")
            }
        }
    }

    private func meterCards(_ m: Monitoring.Meter, _ d: Monitoring.StationDetail) -> some View {
        let load: Double? = offline ? nil : (d.loadCurve.indices.contains(nowSlot) ? d.loadCurve[nowSlot] : nil)
        let pvNow: Double? = offline ? nil : station.powerNow
        let total = MonFormat.energy(m.importTotal)
        let exportTotal = MonFormat.energy(m.exportTotal)
        return HStack(spacing: 12) {
            figureCard("ซื้อจากการไฟฟ้า ตอนนี้", MonFormat.number(m.importNow, 1), "kW",
                       caption: "ใช้ไฟ " + MonFormat.number(load, 1) + " kW · PV " + MonFormat.number(pvNow, 1) + " kW")
            figureCard("ซื้อจากการไฟฟ้า วันนี้", MonFormat.number(m.importToday), "kWh", caption: "ถึง " + MonFormat.time(m.lastData))
            figureCard("ซื้อสะสม", total.value, total.unit, caption: "ตั้งแต่ติดตั้งมิเตอร์")
            figureCard("ไหลย้อน วันนี้", MonFormat.number(m.exportToday), "kWh", caption: zeroExportText(d) ?? MonFormat.dash)
            figureCard("ไหลย้อนสะสม", exportTotal.value, exportTotal.unit,
                       caption: (m.exportTotal ?? 1) == 0 ? "ไม่เคยไหลย้อน" : "ตั้งแต่ติดตั้งมิเตอร์")
        }
    }

    private func meterChart(_ m: Monitoring.Meter, _ d: Monitoring.StationDetail) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("กำลังที่มิเตอร์ (kW) · ทุก 5 นาที · วันนี้").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                Text("meter_last_data · บวก = ซื้อจากการไฟฟ้า · ลบ = ไหลย้อน").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                DayLinesChart(now: now, lines: [
                    .init(id: "meter", values: m.curve, color: Theme.jobOrange, filled: true),
                    .init(id: "load", values: d.loadCurve, color: Theme.teamPurple),
                ], yAxis: true)
                .frame(height: 300)
                HStack(spacing: 14) {
                    legend(Theme.jobOrange, "ซื้อจากการไฟฟ้า")
                    legend(Theme.teamPurple, "ใช้ไฟของสถานี")
                    Spacer()
                    Text("ถึง " + MonFormat.time(m.lastData)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    private func meterPhases(_ m: Monitoring.Meter, _ d: Monitoring.StationDetail) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    cardTitle("ค่าแต่ละเฟส", note: [m.model, m.sn.map { "SN " + $0 }].compactMap { $0 }.joined(separator: " · "))
                    Spacer()
                    if let z = zeroExportText(d) { MonChip("On-grid · " + z, .ok) }
                }
                .padding(.bottom, 6)
                phaseRow("เฟส", "V", "A", "kW", "kvar", "PF", header: true)
                ForEach(m.phases, id: \.name) { p in
                    phaseRow(p.name, MonFormat.number(p.volts, 1), MonFormat.number(p.amps, 1), MonFormat.number(p.kW, 1),
                             MonFormat.number(p.kvar, 1), MonFormat.number(p.pf, 2))
                }
                let t = m.total
                phaseRow("รวม", "", "", MonFormat.number(t.kW, 1), MonFormat.number(t.kvar, 1), MonFormat.number(t.pf, 2))
                    .background(Theme.background)
            }
        }
    }

    private func phaseRow(_ a: String, _ v: String, _ i: String, _ p: String, _ q: String, _ pf: String, header: Bool = false) -> some View {
        HStack {
            Text(a).frame(width: 60, alignment: .leading)
            Text(v).frame(maxWidth: .infinity, alignment: .trailing)
            Text(i).frame(maxWidth: .infinity, alignment: .trailing)
            Text(p).frame(maxWidth: .infinity, alignment: .trailing).fontWeight(header ? .regular : .bold)
            Text(q).frame(maxWidth: .infinity, alignment: .trailing)
            Text(pf).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.sarabun(header ? 13 : 15)).foregroundStyle(header ? Theme.inkMuted : Theme.navy).monospacedDigit()
        .frame(minHeight: 34)
        .overlay(alignment: .top) { if !header { Rectangle().fill(Theme.hairline).frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }

    // MARK: weather

    func weatherTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        Group {
            if let w = d.sensor {
                VStack(spacing: 14) {
                    weatherCards(w, s)
                    weatherChart(w, s)
                }
            } else {
                emptyNote("สถานีนี้ไม่มีเซนเซอร์สภาพอากาศ",
                          "ไม่มีความเข้มแสงที่วัดได้ จึงไม่แสดงค่า PR · พลังงานที่คาดคิดจากพิกัดสถานี (Monitoring.Forecast)",
                          symbol: "sun.max.trianglebadge.exclamationmark")
                .accessibilityIdentifier("station.noSensor")
            }
        }
    }

    private func weatherCards(_ w: Monitoring.Sensor, _ s: Monitoring.Station) -> some View {
        let pr = w.pr(energy: s.energyToday, kWp: s.kWp)
        return HStack(spacing: 12) {
            figureCard("ความเข้มแสงตอนนี้", MonFormat.number(w.irradianceNow), "W/m²",
                       caption: "สูงสุดวันนี้ " + MonFormat.number(w.irradiancePeak) + " W/m²")
            figureCard("แสงสะสมวันนี้", MonFormat.number(w.insolationToday, 2), "kWh/m²", caption: "ถึง " + MonFormat.time(w.lastData))
            figureCard("อุณหภูมิแผง", MonFormat.number(w.moduleTemp, 1), "°C",
                       caption: "สูงสุดวันนี้ " + MonFormat.number(w.moduleTempPeak, 1) + " °C")
            figureCard("อุณหภูมิอากาศ", MonFormat.number(w.airTemp, 1), "°C", caption: "จากเซนเซอร์สถานี")
            figureCard("PR วันนี้", MonFormat.number(pr.map { $0 * 100 }), "%", caption: "จากแสงที่วัดได้ · ถึง " + MonFormat.time(w.lastData))
        }
    }

    private func weatherChart(_ w: Monitoring.Sensor, _ s: Monitoring.Station) -> some View {
        // three units on one plot: each over its own scale (0–1,000 W/m², 0–kWp kW, 0–80 °C), as the board draws them
        let power: [Double?] = s.curve.map { v in v.map { s.kWp > 0 ? $0 / s.kWp : 0 } }
        return MonCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("ความเข้มแสงกับกำลังผลิต · ทุก 5 นาที · วันนี้").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                Text([w.model, w.sn, "ข้อมูลล่าสุด " + MonFormat.time(w.lastData)].compactMap { $0 }.joined(separator: " · "))
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                DayLinesChart(now: now, lines: [
                    .init(id: "irr", values: w.irradianceCurve.map { $0.map { $0 / 1000 } }, color: Theme.jobOrange, filled: true),
                    .init(id: "pv", values: power, color: Theme.primary),
                    .init(id: "temp", values: w.moduleTempCurve.map { $0.map { $0 / 80 } }, color: Theme.danger, dashed: true),
                ])
                .frame(height: 420)
                HStack(spacing: 14) {
                    legend(Theme.jobOrange, "ความเข้มแสง (0–1,000 W/m²)")
                    legend(Theme.primary, "กำลังผลิตรวม (0–" + MonFormat.number(s.kWp) + " kW)")
                    legend(Theme.danger, "อุณหภูมิแผง (0–80 °C)", dashed: true)
                    Spacer()
                    Text("ถึง " + MonFormat.time(w.lastData)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }
}
