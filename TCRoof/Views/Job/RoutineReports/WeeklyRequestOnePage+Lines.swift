import SwiftUI
import TCRoofUI
import TCRoofCore

// The left card under the key plan (docs/ui/weekly-request-ipad-map §4.3): the week's lines grouped by place, each with
// its six day chips, its days and `ตาม MP | แก้วัน`, and on the selected one its hazards and `เอาออก`.

extension WeeklyRequestOnePage {
    func leftCard(planHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            keyPlanCard.frame(height: planHeight)
            if request.work.isEmpty {
                emptyWeek
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(places, id: \.self) { place in
                                AnyView(group(place))
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("requestLines")
                    .onChange(of: selected) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dailyCard()
    }

    /// The places of the request's lines, in the order their first line comes.
    var places: [String] {
        var seen: [String] = []
        for l in request.work where !seen.contains(l.location) { seen.append(l.location) }
        return seen
    }

    private func group(_ place: String) -> some View {
        let lines = request.work.filter { $0.location == place }
        let days = lines.reduce(0) { $0 + $1.days.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "house").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                Text(place.isEmpty ? "ไม่ระบุตำแหน่ง" : place).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text("\(lines.count) งาน รวม \(days) วัน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .padding(.horizontal, 4).padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(lines) { line in lineCard(line).id(line.id) }
        }
    }

    // MARK: a line

    private func lineCard(_ line: RoutineReport.PlanLine) -> some View {
        let on = selected == line.id, c = color(line)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(number(line))").font(.sarabunFixed(14, .heavy)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 28, height: 28).background(c, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.description.isEmpty ? (line.task?.title ?? "งาน") : line.description)
                        .font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(planLine(line)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                dayChips(line, color: c)
                daysTag(line, color: c).frame(width: 72, alignment: .trailing)
            }
            if on { AnyView(lineFooter(line)) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? c : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { selected = line.id }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "เลือกงาน") { selected = line.id }
        .accessibilityIdentifier("requestLine\(number(line))")
    }

    /// `MP 2.4 แผนทำวัน จ อ พ`, or the plan's lack of it.
    private func planLine(_ line: RoutineReport.PlanLine) -> String {
        guard let t = line.task else { return "งานนอกแผน MP" }
        let days = plannedDays(line) ?? []
        return "MP \(t.code) " + (days.isEmpty ? "ไม่มีวันในแผนสัปดาห์นี้" : "แผนทำวัน " + Self.dayNames(days))
    }

    /// The week's working days as chips, `จ 4` … `ส 9`: filled in the line's colour when asked for; a tap toggles it.
    private func dayChips(_ line: RoutineReport.PlanLine, color c: Color) -> some View {
        HStack(spacing: 5) {
            ForEach(workingDays, id: \.self) { d in
                let picked = line.days.contains(d)
                let date = RoutineReport.calendar.component(.day, from: request.date(ofDay: d))
                Button { request.toggleDay(line: line.id, day: d) } label: {
                    Text("\(Self.dayName(d)) \(date)").font(.sarabunFixed(14, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.navy)
                        .frame(width: 50, height: 44)
                        .background(picked ? c.opacity(0.28) : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(picked ? c : Theme.borderOutdoor, lineWidth: picked ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .disabled(!editable)
                .accessibilityLabel("\(Self.dayName(d)) \(date)")
                .accessibilityValue(picked ? "เลือกแล้ว" : "ไม่ได้เลือก")
                .accessibilityAddTraits(picked ? .isSelected : [])
                .accessibilityIdentifier("requestDay\(number(line))-\(d)")
            }
        }
    }

    /// `n วัน` and `ตาม MP` (the plan's days) or `แก้วัน`.
    private func daysTag(_ line: RoutineReport.PlanLine, color c: Color) -> some View {
        let follows = plannedDays(line).map { $0.sorted() == line.days.sorted() }
        return VStack(alignment: .trailing, spacing: 2) {
            Text("\(line.days.count) วัน").font(.sarabunFixed(18, .bold)).foregroundStyle(line.days.isEmpty ? Theme.warningText : c)
            if let follows {
                Text(follows ? "ตาม MP" : "แก้วัน").font(.sarabunFixed(11.5, .bold))
                    .foregroundStyle(follows ? Theme.primary : Theme.warningText)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(follows ? Theme.primarySoft : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityIdentifier("requestTag\(number(line))")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The selected line: its hazards and `เอาออก`.
    private func lineFooter(_ line: RoutineReport.PlanLine) -> some View {
        HStack(spacing: 8) {
            Text("ความเสี่ยง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            let hazards = request.hazards(of: line)
            if hazards.isEmpty {
                Text("ไม่มีความเสี่ยงตามรายการ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) { ForEach(hazards) { hazardChip($0, line: line) } }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
            if editable {
                Button { remove(line) } label: {
                    Label("เอาออก", systemImage: "xmark").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("requestRemove")
            }
        }
        .padding(.leading, 40)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1).offset(y: -5) }
    }

    /// A hazard on a line: its short name and its band, or `ยังไม่ประเมิน` dashed orange; a tap opens the risk sheet.
    private func hazardChip(_ h: RoutineReport.Hazard, line: RoutineReport.PlanLine) -> some View {
        let risk = request.risk(for: h)
        return Button {
            riskEdit = RiskEdit(hazard: h, line: line.id, likelihood: risk?.likelihood ?? h.likelihood, severity: risk?.severity ?? h.severity)
        } label: {
            HStack(spacing: 6) {
                Text(Self.shortName(h)).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                if let band = risk?.band ?? risk.map({ Self.band(of: $0.level) }) {
                    Text(band.title).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.riskBands[band.rawValue], in: Capsule())
                } else {
                    Text("ยังไม่ประเมิน").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.warningText)
                }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(risk == nil ? Theme.warningSoft : Theme.segmentTrack, in: Capsule())
            .overlay {
                if risk == nil { Capsule().strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel(Self.shortName(h))
        .accessibilityValue(risk?.band?.title ?? (risk == nil ? "ยังไม่ประเมิน" : risk!.level.title))
        .accessibilityIdentifier("requestHazard")
    }

    /// `การทำงานบนที่สูง`: the name before its English part.
    static func shortName(_ h: RoutineReport.Hazard) -> String {
        h.name.components(separatedBy: " (").first ?? h.name
    }

    /// An unscored (older) risk's band, from its level.
    static func band(of level: RoutineReport.RiskLevel) -> RoutineReport.RiskBand {
        switch level {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    private func remove(_ line: RoutineReport.PlanLine) {
        let n = number(line)
        request.work.removeAll { $0.id == line.id }
        selected = request.work.first?.id
        actions.toast("เอางาน \(n) ออกจากคำขอแล้ว")
    }

    // MARK: empty week

    private var emptyWeek: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.primary)
            Text("ยังไม่มีงานในคำขอสัปดาห์นี้").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
            Text(planned.isEmpty ? "แผน MP ไม่มีงานในสัปดาห์นี้"
                 : "แผน MP มี \(planned.count) งานในสัปดาห์นี้ แตะ + บนผังเพื่อเพิ่มทีละงาน หรือเพิ่มทั้งหมด")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            if editable && !planned.isEmpty {
                Button {
                    for p in planned { add(p) }
                    selected = request.work.first?.id
                } label: {
                    Label("เพิ่มงานทั้งหมดตามแผน MP", systemImage: "plus").font(.sarabunFixed(16, .bold)).padding(.horizontal, 8)
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
                .accessibilityIdentifier("requestAddAll")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
