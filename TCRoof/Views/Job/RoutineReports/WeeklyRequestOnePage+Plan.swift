import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

// The key plan (docs/ui/weekly-request-ipad-map §4.2): the station's plan with its places, the week's lines as numbered
// pins in their colour, and a `+` for each MP task planned that week at a place the request hasn't got. Drawn as the
// daily report's plan (`DailyOnePage+Plan`), whose views are its own.

extension WeeklyRequestOnePage {
    /// Where a place stands: asked for this week (in its first line's colour), done by the daily reports, or not started.
    enum PlaceState { case week(Color, selected: Bool), done, notStarted }

    func placeState(_ place: String) -> PlaceState {
        if let line = request.work.first(where: { $0.location == place }) {
            return .week(color(line), selected: request.work.contains { $0.location == place && $0.id == selected })
        }
        var latest: [String: Double] = [:]
        for r in job.dailyReports.sorted(by: { $0.date < $1.date }) {
            for l in r.progress where l.location == place { latest[l.key] = l.percent }
        }
        return !latest.isEmpty && latest.values.allSatisfy { $0 >= 100 - 1e-9 } ? .done : .notStarted
    }

    /// The MP lines of the week at a place the request hasn't got (a draft only).
    var ghosts: [RoutineReport.PlanLine] {
        guard editable, request.status == .draft else { return [] }
        return planned.filter { p in !p.location.isEmpty && !request.work.contains { $0.task == p.task && $0.location == p.location } }
    }

    /// A `+`: the planned line joins the request with the plan's days, selected.
    func add(_ planned: RoutineReport.PlanLine) {
        let line = RoutineReport.PlanLine(task: planned.task, description: planned.description, location: planned.location,
                                          qty: planned.qty, unit: planned.unit, days: planned.days)
        request.work.append(line)
        selected = line.id
    }

    var keyPlanCard: some View {
        AnyView(planCanvas(large: false))
    }

    var fullPlan: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("ผังสถานีและงานสัปดาห์นี้ | สัปดาห์ที่ \(weekNumber) (\(Self.rangeText(request)))").font(.sarabunFixed(18, .bold))
                Text("แตะหมุดเพื่อเลือกงาน แล้วปิดเพื่อแก้วัน").font(.sarabunFixed(14)).opacity(0.85)
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

    /// `KEY PLAN | คำขอ หน้า 1`.
    private var planBadge: some View {
        HStack(spacing: 6) {
            Text("KEY PLAN").font(.sarabunFixed(12, .bold)).tracking(1).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.navySolid, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("คำขอ หน้า 1").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy)
        }
        .padding(4).padding(.trailing, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ผังตำแหน่งงาน คำขอ หน้า 1")
    }

    private var planButtons: some View {
        HStack(spacing: 0) {
            uploadButton
            Button { mapFull = true } label: {
                planChip(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .bold)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ขยายผังเต็มจอ")
        }
    }

    /// `อัปโหลดผัง`: a picture from the library (the daily report's menu also takes a PDF or a scan).
    private var uploadButton: some View {
        PhotosPicker(selection: $uploadItem, matching: .images) {
            planChip(Label("อัปโหลดผัง", systemImage: "square.and.arrow.up").font(.sarabunFixed(12, .bold)))
        }
        .buttonStyle(.plain)
        .disabled(demo)
        .accessibilityLabel("อัปโหลดผัง")
    }

    private func planChip<L: View>(_ label: L) -> some View {
        label.foregroundStyle(Theme.navy)
            .padding(.horizontal, 10).frame(minWidth: 36, minHeight: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(Theme.primary, "ทำสัปดาห์นี้")
            legendItem(Theme.success, "เสร็จแล้ว")
            legendItem(Theme.inkFaint, "ยังไม่เริ่ม")
            Text("+ คืองานในแผน MP ที่ยังไม่ได้ขอ").font(.sarabunFixed(11)).foregroundStyle(Theme.navy)
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
        let lines = request.work, ghosts = self.ghosts
        return ZStack(alignment: .topLeading) {
            ForEach(settings.locations, id: \.self) { place in
                if let p = point(place, in: size) { placeLabel(place).position(x: p.x, y: p.y - 44) }
            }
            ForEach(Array(ghosts.enumerated()), id: \.offset) { i, g in
                if let p = point(g.location, in: size) {
                    ghostPin(g).position(x: p.x - 22 - CGFloat(i % 2) * 6, y: p.y + 26 + CGFloat(i / 2 % 3) * 6)
                }
            }
            ForEach(lines) { line in
                if let p = point(line.location, in: size) {
                    // lines at one place step aside so each pin stays tappable
                    let n = lines.filter { $0.location == line.location }.firstIndex { $0.id == line.id } ?? 0
                    pin(line, large: large).position(x: p.x + CGFloat(n) * 34, y: p.y + CGFloat(n) * 8)
                }
            }
        }
    }

    func placeLabel(_ place: String) -> some View {
        let (ink, fill, dashed, strong): (Color, Color, Bool, Bool) = switch placeState(place) {
        case .week(let c, let on): (c, c, false, on)
        case .done: (Theme.success, Theme.success, false, false)
        case .notStarted: (Theme.inkFaint, Theme.surface, true, false)
        }
        return Text(place).font(.sarabunFixed(strong ? 12.5 : 11, .bold)).lineLimit(1).fixedSize()
            .foregroundStyle(dashed ? Theme.navy : Theme.onPrimary)
            .padding(.horizontal, strong ? 8 : 6).padding(.vertical, strong ? 3 : 2)
            .background(dashed ? fill.opacity(0.92) : fill, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(strong ? Theme.paper : ink,
                                                                    style: StrokeStyle(lineWidth: strong ? 2 : 1.5, dash: dashed ? [3, 2] : [])))
            .shadow(color: strong ? Theme.navySolid.opacity(0.3) : .clear, radius: 3, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    func pin(_ line: RoutineReport.PlanLine, large: Bool) -> some View {
        let on = selected == line.id, c = color(line)
        let size: CGFloat = (on ? 40 : 32) * (large ? 1.2 : 1)
        let days = line.days.isEmpty ? "0 วัน" : Self.dayNames(line.days)
        return Button { selected = line.id } label: {
            VStack(spacing: 2) {
                Text("\(number(line))").font(.sarabunFixed(on ? 17 : 14, .heavy)).foregroundStyle(Theme.onPrimary)
                    .frame(width: size, height: size).background(c, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2.5))
                    .padding(on ? 3 : 0)
                    .overlay { if on { Circle().strokeBorder(c.opacity(0.45), lineWidth: 3) } }
                    .shadow(color: Theme.navySolid.opacity(0.3), radius: 3, y: 1)
                Text(on ? "\(line.location) (\(days))" : "\(line.days.count) วัน")
                    .font(.sarabunFixed(11, .bold)).foregroundStyle(on ? Theme.onPrimary : Theme.navy).lineLimit(1).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(on ? c : Theme.paper, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(selected == nil || on ? 1 : 0.5)
        .zIndex(on ? 3 : 2)
        .accessibilityLabel("งาน \(number(line)) \(line.description) ที่ \(line.location)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("requestPin\(number(line))")
    }

    func ghostPin(_ g: RoutineReport.PlanLine) -> some View {
        Button { add(g) } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.navy)
                .frame(width: 26, height: 26).background(Theme.paper.opacity(0.92), in: Circle())
                .overlay(Circle().strokeBorder(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เพิ่มงานตามแผน MP \(g.task?.code ?? "") \(g.description) ที่ \(g.location)")
    }

    // MARK: no picture

    /// No key plan on this device: the daily report's text, the places as a list with their pins and `+`.
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
                            ForEach(request.work.filter { $0.location == place }) { pin($0, large: false) }
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
