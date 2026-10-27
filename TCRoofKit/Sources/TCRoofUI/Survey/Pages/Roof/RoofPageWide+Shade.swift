#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// แผงบนหลังคา on iPad: the card under the plan is `เงาบังแผง | Shade` (docs/ui/survey-c1-ipad-shade): one face group
/// at a time (the faces in use, then the whole roof), its metrics (DC capacity, module, tilt | azimuth, Sun Access,
/// TOF, TSRF) and three charts drawn as `Sketch`es (`RoofShade`), from the same hourly run as the energy card
/// (`RoofMountYield.estimateAndShade`, RoofPageWide+Energy). The plan marks the modules in shadow at 21 ธ.ค. 09:00
/// (`planShade`). iPhone keeps its closed row section.
extension RoofPageWide {
    /// One face group of the segments, from the layout (before or without a shade report).
    struct ShadeGroupLine: Identifiable {
        var id: String, title: String, modules: Int, kWp: Double, orientations: [RoofShade.Orientation]
    }

    /// The faces in use by direction, then `รวมทั้งหลังคา` when there are several.
    var shadeGroups: [ShadeGroupLine] {
        guard let i = mountYieldInputs, i.modules > 0 else { return [] }
        let wp = i.moduleWp / 1000
        var out = i.faces.map { f in
            ShadeGroupLine(id: f.id, title: "ด้าน" + RoofFace.direction(f.azimuthDeg), modules: f.modules, kWp: Double(f.modules) * wp,
                           orientations: [.init(tilt: f.tiltDeg, azimuth: f.azimuthDeg)])
        }
        if out.count > 1 {
            out.append(ShadeGroupLine(id: "all", title: "รวมทั้งหลังคา", modules: i.modules, kWp: i.kWp, orientations: out.flatMap(\.orientations)))
        }
        return out
    }

    /// The shade report of the layout on screen.
    var currentShade: RoofShade.Outcome? {
        guard let s = mountShade, let i = mountYieldInputs, mountYieldFor == i else { return nil }
        return s
    }

    /// The modules in shadow and the obstacles' shadows at 21 ธ.ค. 09:00, for the plan (iPad PV mode).
    var planShade: RoofPlan.ShadeMoment? {
        guard mode == .pv, !narrow, let m = shownMount, let s = RoofObstacleShade(m) else { return nil }
        return s.moment(latitude: latitude ?? m.latitude, longitude: longitude ?? 100.5)
    }

    var shadeCard: some View {
        let groups = shadeGroups
        let sel = groups.firstIndex { $0.id == shadeGroup } ?? 0
        let line = groups.indices.contains(sel) ? groups[sel] : nil
        let report = currentShade?.shade
        let group = report?.groups.first { $0.id == line?.id }
        return card {
            shadeHeader(groups, selected: sel, caption: group?.caption ?? line.map { groups.count > 2 && $0.id != "all" ? $0.title + "ของสันหลังคา" : $0.id == "all" ? "ทั้งหลังคา" : $0.title })
            if let line {
                shadeMetrics(line, group: group, moduleName: report?.moduleName)
                if let report, let group {
                    shadeCharts(report, group).frame(maxHeight: .infinity)
                } else {
                    Text(shadeStatus).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(report?.sourceLine ?? shadeReason ?? "PVYield รายชั่วโมง")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(RoofShade.noLayout).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("เงาบังแผง")
    }

    /// Why there is no report (no GPS, weather too far), nil while it computes or once it's there.
    var shadeReason: String? {
        if case .unavailable(let why)? = currentShade { return why }
        return nil
    }

    var shadeStatus: String { shadeReason ?? (mountYieldBusy || currentShade == nil ? "กำลังคำนวณเงา…" : RoofShade.noLayout) }

    func shadeHeader(_ groups: [ShadeGroupLine], selected: Int, caption: String?) -> some View {
        HStack(spacing: 8) {
            (Text("เงาบังแผง | Shade").bold().underline() + Text(caption.map { " | " + $0 } ?? "").foregroundColor(Theme.inkMuted).font(.sarabunFixed(13)))
                .font(.sarabunFixed(15)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if groups.count > 1 {
                RoofSegments(options: groups.map(\.title), selected: selected, minSegment: 84, height: 36) { shadeGroup = groups[$0].id }
                    .frame(maxWidth: 360)
            }
        }
    }

    /// Eight columns: DC capacity, module × count (2), tilt | azimuth (2), Sun Access, TOF, TSRF.
    func shadeMetrics(_ line: ShadeGroupLine, group: RoofShade.Group?, moduleName: String?) -> some View {
        let busy = group == nil && shadeReason == nil
        func pct(_ x: Double?) -> String { x.map { String(format: "%.1f%%", $0 * 100) } ?? (busy ? "กำลังคำนวณเงา…" : "—") }
        let module = moduleName ?? RoofMountYield.catalogModule(wp: (mountYieldInputs?.moduleWp ?? 0), length: mountYieldInputs?.moduleLength ?? 0,
                                                                width: mountYieldInputs?.moduleWidth ?? 0).map { String($0.model.split(separator: " ").first ?? "").uppercased() + " \($0.w) W" }
            ?? String(format: "แผง %.0f W", mountYieldInputs?.moduleWp ?? 0)
        let tilts = Set(line.orientations.map { Int($0.tilt.rounded()) }).sorted().map { "\($0)°" }.joined(separator: ", ")
        let tiles: [(String, String, Int)] = [
            ("DC capacity", String(format: "%.1f kWp", line.kWp), 1),
            ("ผู้ผลิตแผง | จำนวน", "\(module) × \(line.modules)", 2),
            ("Tilt | Azimuth", tilts + " | " + line.orientations.map(\.azimuthText).joined(separator: ", "), 2),
            ("Sun Access", pct(group?.sunAccess), 1), ("TOF", pct(group?.tof), 1), ("TSRF", pct(group?.tsrf), 1),
        ]
        return GeometryReader { geo in
            let unit = (geo.size.width - 7 * 6) / 8
            HStack(spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    shadeTile(t.0, t.1).frame(width: unit * CGFloat(t.2) + 6 * CGFloat(t.2 - 1))
                }
            }
        }
        .frame(height: 44)
    }

    func shadeTile(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(key)
        .accessibilityValue(value)
        .accessibilityIdentifier("shade-" + key)
    }

    func shadeCharts(_ r: RoofShade, _ g: RoofShade.Group) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ShadeChart(title: "Sun-path Diagram", sketch: r.sunPathSketch(g))
                .frame(maxWidth: 140)
                .accessibilityLabel("Sun-path diagram เส้นทางดวงอาทิตย์ 21 มิ.ย. 21 มี.ค. 21 ธ.ค." + (g.silhouettes.isEmpty ? "" : " และสิ่งกีดขวาง \(g.silhouettes.count) จุด"))
            ShadeChart(title: "Monthly Sun Access & Shading Averages", sketch: r.monthlySketch(g))
                .accessibilityLabel("Sun Access รายเดือน " + g.monthlySunAccess.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: " "))
            ShadeChart(title: "Hour-Month Sun Access", sketch: r.hourMonthSketch(g))
                .accessibilityLabel("Sun Access รายชั่วโมงและเดือน")
        }
    }
}

/// One of the shade card's charts: its title and its sketch fitted under it.
struct ShadeChart: View {
    let title: String
    let sketch: Sketch
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(11.5, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { geo in
                SketchCanvas(ops: sketch.ops, fit: SketchFit(sketch.width, sketch.height, in: geo.size))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
    }
}
#endif
