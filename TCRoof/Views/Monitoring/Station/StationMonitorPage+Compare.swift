import SwiftUI
import Charts
import TCRoofUI
import TCRoofCore

// `เปรียบเทียบค่า` (CHA-73 §6): the station's devices on the left; the date, the range, the chart with removable
// legend chips and the picked device's values on the right. At most 4 lines in at most 2 units (left and right axes).

extension StationMonitorPage {
    func compareTab(_ s: Monitoring.Station, _ d: Monitoring.StationDetail) -> some View {
        let devices = d.compareDevices
        let picked = devices.first { $0.id == compareDevice } ?? devices.first
        return HStack(alignment: .top, spacing: 14) {
            compareDeviceList(devices, picked: picked?.id).frame(width: 260)
            VStack(spacing: 14) {
                compareChartCard(devices)
                if let picked { compareValues(picked) }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: stationID + String(compareSeeded)) {
            // the first inverter's PAC to start with, as the board; once per station, so taking every line off stays off
            guard !compareSeeded else { return }
            compareSeeded = true
            if compare.lines.isEmpty, let first = devices.first, let pac = first.metrics.first {
                compare.add(Monitoring.CompareLine(deviceID: first.id, deviceName: first.name, metric: pac))
            }
        }
    }

    private func compareDeviceList(_ devices: [Monitoring.CompareDevice], picked: String?) -> some View {
        MonCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    cardTitle("อุปกรณ์")
                    Spacer()
                    Text("เลือกแล้ว \(compare.lines.count)/\(Monitoring.CompareSelection.maxLines) เส้น")
                        .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                        .accessibilityIdentifier("station.compare.count")
                }
                ForEach([Monitoring.CompareDevice.Kind.inverter, .meter, .sensor], id: \.self) { kind in
                    let group = devices.filter { $0.kind == kind }
                    if !group.isEmpty {
                        Text(Self.kindTitle(kind) + " (\(group.count))").font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted)
                            .padding(.top, 6)
                        ForEach(group) { dev in deviceRow(dev, on: dev.id == picked) }
                    }
                }
                if devices.isEmpty {
                    Text("ไม่มีอุปกรณ์").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    static func kindTitle(_ k: Monitoring.CompareDevice.Kind) -> String {
        switch k {
        case .inverter: "อินเวอร์เตอร์"
        case .meter: "มิเตอร์"
        case .sensor: "เซนเซอร์สภาพอากาศ"
        }
    }

    private func deviceRow(_ dev: Monitoring.CompareDevice, on: Bool) -> some View {
        let n = compare.count(device: dev.id)
        return Button { compareDevice = dev.id } label: {
            HStack(spacing: 8) {
                dot(dev.status)
                VStack(alignment: .leading, spacing: 0) {
                    Text(dev.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                    Text(dev.detail.ifEmpty(MonFormat.dash)).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if n > 0 {
                    Text("\(n)").font(.sarabun(12, .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 22, height: 22).background(Theme.primary, in: Circle())
                }
            }
            .padding(.horizontal, 10).frame(minHeight: 48)
            .background(on ? Theme.primarySoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.primary : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("station.compare.device." + dev.id)
    }

    private func compareChartCard(_ devices: [Monitoring.CompareDevice]) -> some View {
        let day = Calendar.current.date(byAdding: .day, value: -compareDaysBack, to: now) ?? now
        let hasData = compareRange == .fiveMinutes && compareDaysBack == 0
        return MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    stepper(Self.thaiDate(day), back: { compareDaysBack += 1 },
                            forward: compareDaysBack > 0 ? { compareDaysBack -= 1 } : nil)
                    MonSwitch(options: [(CompareRange.fiveMinutes, "ทุก 5 นาที"), (.daily, "รายวัน"), (.monthly, "รายเดือน"), (.yearly, "รายปี")],
                              selection: $compareRange)
                    Spacer()
                    Text("queryHistoricalData · meter_last_data").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                if hasData {
                    CompareChart(lines: compare.lines, units: compare.units, devices: devices, now: now).frame(height: 380)
                } else {
                    Text("ไม่มีข้อมูลย้อนหลังของอุปกรณ์ในช่วงนี้ · แอปยังอ่านเฉพาะค่าทุก 5 นาทีของวันนี้")
                        .font(.sarabun(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 380)
                }
                HStack(spacing: 8) {
                    ForEach(Array(compare.lines.enumerated()), id: \.element.id) { i, l in legendChip(l, i, devices) }
                    Spacer()
                    Text("ค่าตอนนี้ " + MonFormat.time(station.lastReading)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    func stepper(_ title: String, back: @escaping () -> Void, forward: (() -> Void)?) -> some View {
        HStack(spacing: 0) {
            Button(action: back) {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("ก่อนหน้า")
            Text(title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1).fixedSize()
            Button { forward?() } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(forward == nil)
            .accessibilityLabel("ถัดไป")
        }
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.navy)
        .buttonStyle(.plain)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func legendChip(_ l: Monitoring.CompareLine, _ i: Int, _ devices: [Monitoring.CompareDevice]) -> some View {
        let values = devices.first { $0.id == l.deviceID }?.history[l.metric.id] ?? []
        let current = nowSlot < values.count ? values[nowSlot] : nil
        return HStack(spacing: 6) {
            Capsule().fill(CompareChart.color(i)).frame(width: 16, height: 3)
            Text(l.deviceName + " · " + l.metric.id).font(.sarabun(13)).foregroundStyle(Theme.inkStrong)
            Text(MonFormat.number(current, 1) + " " + l.metric.unit).font(.sarabun(13, .bold)).foregroundStyle(Theme.navy)
            Button { compare.remove(l); compareNote = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เอา " + l.deviceName + " " + l.metric.id + " ออก")
        }
        .padding(.leading, 10)
        .background(Theme.background, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSubtle))
    }

    private func compareValues(_ dev: Monitoring.CompareDevice) -> some View {
        let metrics = dev.metrics.filter { $0.group == compareGroup }
        return MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cardTitle("ค่าของ " + dev.name, note: dev.detail)
                    Spacer()
                    MonSwitch(options: Monitoring.CompareGroup.allCases.map { ($0, $0.title) }, selection: $compareGroup)
                }
                if metrics.isEmpty {
                    Text("อุปกรณ์นี้ไม่มีค่าในกลุ่มนี้").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(metrics) { m in metricButton(dev, m) }
                    }
                }
                Text(compareNote ?? "เลือกได้ไม่เกิน \(Monitoring.CompareSelection.maxLines) เส้น · หน่วยต่างกันได้ \(Monitoring.CompareSelection.maxUnits) หน่วย (แกนซ้ายและขวา) · ค่าทุก 5 นาทีเก็บที่ Growatt ราว 95 วัน")
                    .font(.sarabun(13, compareNote == nil ? .regular : .bold))
                    .foregroundStyle(compareNote == nil ? Theme.inkMuted : Theme.dangerText)
                    .accessibilityIdentifier("station.compare.note")
            }
        }
    }

    private func metricButton(_ dev: Monitoring.CompareDevice, _ m: Monitoring.CompareMetric) -> some View {
        let line = Monitoring.CompareLine(deviceID: dev.id, deviceName: dev.name, metric: m)
        let on = compare.contains(line)
        return Button {
            compareNote = compare.toggle(line)?.note
        } label: {
            HStack(spacing: 6) {
                if on { Circle().fill(Theme.primaryLight).frame(width: 7, height: 7) }
                Text(m.id).font(.sarabun(13, on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Theme.navySolid : Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.clear : Theme.borderSubtle))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("station.compare.metric." + m.id)
    }
}

/// The compare chart: the first unit on the left axis, the second scaled onto it with its own labels on the right.
struct CompareChart: View {
    let lines: [Monitoring.CompareLine]
    let units: [String]
    let devices: [Monitoring.CompareDevice]
    let now: Date

    static let palette: [Color] = [Theme.primary, Theme.danger, Theme.success, Theme.teamPurple]
    static func color(_ i: Int) -> Color { palette[i % palette.count] }

    private func values(_ l: Monitoring.CompareLine) -> [Double?] {
        devices.first { $0.id == l.deviceID }?.history[l.metric.id] ?? []
    }

    private func peak(_ unit: String) -> Double {
        lines.filter { $0.metric.unit == unit }.flatMap { values($0).compactMap { $0 } }.max() ?? 1
    }

    /// The right unit's factor onto the left axis.
    private var factor: Double {
        guard units.count == 2 else { return 1 }
        let l = peak(units[0]), r = peak(units[1])
        return r > 0 ? max(l, 1) / r : 1
    }

    var body: some View {
        let start = Calendar.current.startOfDay(for: now)
        let window = (6 * 60 / Monitoring.slotMinutes)...(18 * 60 / Monitoring.slotMinutes)
        func x(_ i: Int) -> Date { start.addingTimeInterval(TimeInterval(i * Monitoring.slotMinutes * 60)) }
        let f = factor, right = units.count == 2 ? units[1] : nil
        let empty = lines.allSatisfy { values($0).allSatisfy { $0 == nil } }
        return Group {
            if lines.isEmpty || empty {
                Text(lines.isEmpty ? "เลือกค่าจากด้านล่างเพื่อเพิ่มเส้น" : "ไม่มีข้อมูล · ยังไม่ได้อ่านค่าของอุปกรณ์จาก Growatt")
                    .font(.sarabun(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { n, l in
                        let scale = l.metric.unit == right ? f : 1
                        let vs = values(l)
                        ForEach(Array(window), id: \.self) { i in
                            if i < vs.count, let v = vs[i] {
                                LineMark(x: .value("เวลา", x(i)), y: .value("ค่า", v * scale), series: .value("ชุด", l.id))
                                    .foregroundStyle(Self.color(n)).lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }
                }
                .chartXScale(domain: x(window.lowerBound)...x(window.upperBound))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).font(.sarabun(11))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.sarabun(11)) }
                    if right != nil {
                        AxisMarks(position: .trailing) { v in
                            AxisValueLabel {
                                if let d = v.as(Double.self) { Text(MonFormat.number(d / f)).font(.sarabun(11)) }
                            }
                        }
                    }
                }
                .chartYAxisLabel(position: .topLeading) { Text(units.first ?? "").font(.sarabun(12, .bold)) }
                .chartYAxisLabel(position: .topTrailing) { Text(right ?? "").font(.sarabun(12, .bold)) }
                .chartLegend(.hidden)
            }
        }
        .accessibilityIdentifier("station.compare.chart")
    }
}
