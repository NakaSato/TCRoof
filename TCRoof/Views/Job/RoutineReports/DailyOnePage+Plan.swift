import SwiftUI
import TCRoofUI
import TCRoofCore

// The key plan card (docs/ui/daily-report-ipad §3): the A2 site picture with the station's locations, today's lines
// as numbered pins in their colour, and a `+` pin for each MP task planned this week that today's report hasn't got.

extension DailyOnePage {
    /// Where a location stands: worked today (in the first line's colour), done, or not started.
    enum PlaceState { case today(Color), done, notStarted }

    func placeState(_ place: String) -> PlaceState {
        if let line = report.progress.first(where: { $0.location == place }) { return .today(color(line)) }
        var latest: [String: Double] = [:]
        for r in (previous + [report]).sorted(by: { $0.date < $1.date }) {
            for l in r.progress where l.location == place { latest[l.key] = l.percent }
        }
        return !latest.isEmpty && latest.values.allSatisfy { $0 >= 100 - 1e-9 } ? .done : .notStarted
    }

    var ghosts: [RoutineReport.ProgressLine] {
        RoutineReport.plannedNotReported(on: report, previous: previous, settings: settings, plan: plan)
    }

    /// A `+` pin: today's line for that task and place, 10 % on, selected.
    func start(_ planned: RoutineReport.ProgressLine) {
        let line = RoutineReport.startToday(planned)
        report.progress.append(line)
        selected = line.id
    }

    /// The key plan at the top of the left card's scroll (v2 §2–3).
    var keyPlanCard: some View {
        AnyView(planCanvas(large: false))
    }

    var fullPlan: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("ผังสถานี | งานวันนี้ | " + RoutineReport.thaiWeekdayDate(date)).font(.sarabunFixed(18, .bold))
                Text("แตะหมุดเพื่อเลือกงาน แล้วปิดเพื่อกรอก").font(.sarabunFixed(14)).opacity(0.85)
                Spacer()
                Button { mapFull = false } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        .background(Theme.onPrimary.opacity(0.18), in: Circle())
                }
                .accessibilityLabel("ปิดผัง")
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Theme.navySolid.ignoresSafeArea(edges: .top))
            planCanvas(large: true).padding(16)
        }
        .background(Theme.navySolid.ignoresSafeArea())
    }

    @ViewBuilder private func planCanvas(large: Bool) -> some View {
        if let image = keyPlanImage {
            ZStack {
                Theme.paper
                Image(uiImage: image).resizable().scaledToFit().saturation(0.75)
                    .overlay { GeometryReader { g in AnyView(markers(in: g.size, large: large)) } }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) { if !large { planBadge.padding(8) } }
            .overlay(alignment: .topTrailing) { if !large { planButtons.padding(4) } }
            .overlay(alignment: .bottomLeading) { legend.padding(8) }
        } else {
            AnyView(placeList)
        }
    }

    /// `KEY PLAN | หน้า 2`: it prints on the DAILY REPORT's page 2.
    private var planBadge: some View {
        HStack(spacing: 6) {
            Text("KEY PLAN").font(.sarabunFixed(12, .bold)).tracking(1).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.navySolid, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("หน้า 2").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy)
        }
        .padding(4).padding(.trailing, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ผังตำแหน่งงาน หน้า 2 ของรายงาน")
    }

    var planButtons: some View {
        HStack(spacing: 0) {
            uploadButton
            Button { mapFull = true } label: {
                planChip(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .bold)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ขยายผังเต็มจอ")
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(Theme.primary, "ทำวันนี้")
            legendItem(Theme.success, "เสร็จแล้ว")
            legendItem(Theme.inkFaint, "ยังไม่เริ่ม")
            Text("+ = งานตามแผน MP").font(.sarabunFixed(11)).foregroundStyle(Theme.navy)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.surface.opacity(0.92), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).strokeBorder(c, lineWidth: 2).frame(width: 14, height: 10)
            Text(t).font(.sarabunFixed(11)).foregroundStyle(Theme.navy)
        }
    }

    // MARK: markers

    private func point(_ place: String, in size: CGSize) -> CGPoint? {
        settings.keyPoint(place).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    private func markers(in size: CGSize, large: Bool) -> some View {
        let lines = report.progress, ghosts = self.ghosts
        return ZStack(alignment: .topLeading) {
            ForEach(settings.locations, id: \.self) { place in
                // above the place's pins, clear of the selected one
                if let p = point(place, in: size) { placeLabel(place).position(x: p.x, y: p.y - 42) }
            }
            ForEach(Array(ghosts.enumerated()), id: \.offset) { i, g in
                if let p = point(g.location, in: size) {
                    ghostPin(g).position(x: p.x - 22 - CGFloat(i % 2) * 6, y: p.y + 24 + CGFloat(i / 2 % 3) * 6)
                }
            }
            ForEach(lines) { line in
                if let p = point(line.location, in: size) {
                    // lines at one place step aside so each pin stays tappable
                    let n = lines.filter { $0.location == line.location }.firstIndex { $0.id == line.id } ?? 0
                    pin(line, large: large).position(x: p.x + CGFloat(n) * 30, y: p.y + CGFloat(n) * 8)
                }
            }
        }
    }

    private func placeLabel(_ place: String) -> some View {
        let state = placeState(place)
        let (ink, fill, dashed): (Color, Color, Bool) = switch state {
        case .today(let c): (c, c, false)
        case .done: (Theme.success, Theme.success, false)
        case .notStarted: (Theme.inkFaint, Theme.surface, true)
        }
        return Text(place).font(.sarabunFixed(11, .bold)).lineLimit(1).fixedSize()
            .foregroundStyle(dashed ? Theme.navy : Theme.onPrimary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(dashed ? fill.opacity(0.92) : fill, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : [])))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func pin(_ line: RoutineReport.ProgressLine, large: Bool) -> some View {
        let on = selected == line.id, c = color(line)
        let size: CGFloat = (on ? 40 : 32) * (large ? 1.2 : 1)
        return Button { selected = line.id } label: {
            VStack(spacing: 2) {
                Text("\(number(line))").font(.sarabunFixed(on ? 17 : 14, .heavy)).foregroundStyle(Theme.onPrimary)
                    .frame(width: size, height: size).background(c, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2.5))
                    .shadow(color: Theme.navySolid.opacity(0.3), radius: 3, y: 1)
                Text(on ? "\(line.location) | \(RoutineReport.percent(line.percent))" : RoutineReport.percent(line.percent))
                    .font(.sarabunFixed(11, .bold)).foregroundStyle(on ? Theme.onPrimary : Theme.navy).lineLimit(1).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(on ? c : Theme.paper, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(selected == nil || on ? 1 : 0.35)
        .zIndex(on ? 3 : 2)
        .accessibilityLabel("งาน \(number(line)) \(line.title) \(RoutineReport.percent(line.percent))")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func ghostPin(_ g: RoutineReport.ProgressLine) -> some View {
        Button { start(g) } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.navy)
                .frame(width: 26, height: 26).background(Theme.paper.opacity(0.92), in: Circle())
                .overlay(Circle().strokeBorder(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เพิ่มงานตามแผน MP \(g.task?.code ?? "") \(g.location) สะสม \(RoutineReport.percent(g.percent))")
    }

    // MARK: no picture

    /// No key plan on this device: the locations as chips, each with its pins and `+`, and the upload button.
    private var placeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("ยังไม่มีผังของสถานีนี้ (อัปโหลดผัง หรือภาพ A2 จากแบบสำรวจ) | แสดงตำแหน่งเป็นรายการ")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 8)
                uploadButton
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(settings.locations, id: \.self) { place in
                        HStack(spacing: 6) {
                            placeLabel(place)
                            ForEach(report.progress.filter { $0.location == place }) { pin($0, large: false) }
                            ForEach(Array(ghosts.filter { $0.location == place }.enumerated()), id: \.offset) { _, g in ghostPin(g) }
                            Spacer(minLength: 0)
                        }
                        .padding(8).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            legend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
