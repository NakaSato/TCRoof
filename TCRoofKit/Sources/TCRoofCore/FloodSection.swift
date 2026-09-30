import Foundation

/// The A4 water-level cross-section as a vector `Sketch`, drawn the same way by the editor (SwiftUI Canvas) and the PDF report.
/// Coordinates follow docs/ui/survey-a4/iPadA4.dc.html (viewBox 0 100 540 420, 1.8 pt per cm), moved up by 100 so the sketch starts at 0.
public enum FloodSection {
    public static let width = 540.0, height = 420.0
    /// Ground line, in sketch coordinates.
    public static let groundY = 384.0

    static let ink = RGBA(hex: 0x1F2E24), blue = RGBA(hex: 0x1F6FB5), teal = RGBA(hex: 0x1C8A7E), muted = RGBA(hex: 0x5B6B82)

    /// Points per cm: 1.8, less when the minimum install level or the equipment would leave the drawing.
    public static func scale(minCm: Double, floorCm: Double, mountCm: Double) -> Double {
        var k = 1.8
        if minCm > 0 { k = min(k, (groundY - 30) / (minCm + 8)) }
        if floorCm + mountCm > 0 { k = min(k, (groundY - 30 - 110) / (floorCm + mountCm)) }
        return max(0.5, k)
    }
    /// The water level (cm) a vertical position in the sketch stands for.
    public static func cm(atY y: Double, scale k: Double) -> Double { (groundY - y) / k }

    public static func scale(_ job: Job) -> Double {
        let v = job.values
        return scale(minCm: Double(FloodCheck.minCm(v)), floorCm: FloodCheck.floorCm(v), mountCm: FloodCheck.mountCm(v))
    }

    /// "ภาพตัดระดับน้ำท่วม 80 ซม. และระดับติดตั้งอุปกรณ์ 130 ซม." for VoiceOver.
    public static func accessibilityLabel(_ job: Job) -> String {
        let r = job.floodCheck
        return "ภาพตัดระดับน้ำ" + (r.level > 0 ? "ท่วม \(Int(r.level)) ซม. " : " ") + "และระดับติดตั้งอุปกรณ์ \(r.minCm) ซม."
    }

    public static func sketch(_ job: Job) -> Sketch {
        let v = job.values, r = job.floodCheck
        let floor = FloodCheck.floorCm(v), mount = FloodCheck.mountCm(v), lvl = r.level, minCm = Double(r.minCm)
        let k = scale(job), g = groundY
        func y(_ cm: Double) -> Double { g - cm * k }
        let refName = v.choice("floodRef") ?? "ดินเดิม"
        let flooded = r.state == .flooded
        var o: [DrawOp] = [.rect(Box(0, 0, width, height), stroke: nil, fill: .white)]
        func halo(_ t: String, _ p: Pt, size: Double, color: RGBA, align: TextAlign = .left) {
            let w = Double(t.count) * size * 0.56
            let x0 = align == .left ? p.x : align == .right ? p.x - w : p.x - w / 2
            o.append(.rect(Box(x0 - 2, p.y - size * 0.62, w + 4, size * 1.24), stroke: nil, fill: RGBA(1, 1, 1, 0.85)))
            o.append(.text(t, at: p, size: size, bold: true, color: color, align: align))
        }
        // water body, then the structures on top of it
        let wy = y(lvl)
        if lvl > 0 {
            o.append(.rect(Box(0, wy, width, g - wy), stroke: nil, fill: RGBA(hex: 0xE3EEF8)))
            var ly = wy + 6
            while ly < g { var lx = 3.0; while lx < width { o.append(.line(Pt(lx, ly), Pt(lx + 10, ly), width: 0.8, color: RGBA(hex: 0x9FC3E4))); lx += 24 }; ly += 8 }
            o.append(.line(Pt(0, wy), Pt(width, wy), width: 1.6, color: blue, dash: flooded ? [] : [8, 5]))
        }
        // existing main board
        o.append(.rect(Box(44, 42, 84, g - 42), stroke: ink, fill: .white, width: 1.4))
        o.append(.line(Pt(44, 68), Pt(128, 68), width: 0.8, color: ink))
        o.append(.text(r.mdbName.replacingOccurrences(of: "MDB", with: "MDB ") + " (เดิม)", at: Pt(86, 55), size: 12, bold: true, color: ink, align: .center))
        // inverter room on its slab
        let fy = y(floor), fh = floor * k
        if floor > 0 {
            o.append(.rect(Box(176, fy, 324, fh), stroke: ink, fill: RGBA(hex: 0xF1F3F5), width: 1.4))
            var dy = fy + 3; var row = 0
            while dy < g - 1 { var dx = row % 2 == 0 ? 180.0 : 184.0; while dx < 498 { o.append(.circle(Pt(dx, dy), r: 0.8, stroke: nil, fill: RGBA(hex: 0x8E959B))); dx += 8 }; dy += 5; row += 1 }
        }
        o.append(.line(Pt(186, fy), Pt(186, 12), width: 2.4, color: ink))
        o.append(.line(Pt(185, 12), Pt(491, 12), width: 2.4, color: ink))
        o.append(.line(Pt(490, 12), Pt(490, fy), width: 2.4, color: ink))
        let inverterTag = job.sectionsByCategory.flatMap(\.sections).first { $0.module.type == .inverter }?.number
        o.append(.text("ห้อง Inverter" + (inverterTag.map { " (\($0))" } ?? ""), at: Pt(338, 24), size: 12, bold: true, color: ink, align: .center))
        let mountY = y(floor + mount)
        o.append(.rect(Box(250, mountY - 110, 64, 110), stroke: blue, fill: .white, width: 1.8))
        o.append(.text("INV", at: Pt(282, mountY - 55), size: 12, bold: true, color: blue, align: .center))
        o.append(.rect(Box(332, mountY - 90, 46, 90), stroke: blue, fill: .white, width: 1.8))
        o.append(.text("SMDB", at: Pt(355, mountY - 45), size: 10, bold: true, color: blue, align: .center))
        if floor > 0 { halo("พื้นห้อง +" + String(format: "%.2f", floor / 100), Pt(338, fy + (floor * k >= 16 ? 14 : -8)), size: 11, color: ink, align: .center) }
        // minimum install level
        let my = y(minCm)
        o.append(.line(Pt(0, my), Pt(width, my), width: 1.4, color: teal, dash: [14, 4, 3, 4]))
        // ground
        o.append(.rect(Box(0, g, width, 36), stroke: nil, fill: RGBA(hex: 0xEFEAE2)))
        o.append(.hatch(Box(0, g, width, 36), color: RGBA(hex: 0x8C7B63), spacing: 7))
        o.append(.line(Pt(0, g), Pt(width, g), width: 2, color: ink))
        func marker(_ x: Double, _ yy: Double, _ c: RGBA) { o.append(.polygon([Pt(x - 7, yy - 11), Pt(x + 7, yy - 11), Pt(x, yy)], stroke: c, fill: .white, width: 1.4)) }
        marker(18, my, teal)
        halo("+" + String(format: "%.2f", minCm / 100) + " ระดับติดตั้งต่ำสุด", Pt(30, my - 10), size: 11.5, color: teal)
        if lvl > 0 {
            marker(470, wy, blue)
            let year = v.text("floodYear").trimmingCharacters(in: .whitespaces)
            halo("+" + String(format: "%.2f", lvl / 100) + (flooded ? " น้ำสูงสุด" + (year.isEmpty ? "" : " ปี " + year) : " ระดับน้ำประเมิน (GISTDA)"),
                 Pt(456, wy - 10), size: 11.5, color: blue, align: .right)
            // freeboard dimension
            o.append(.line(Pt(160, wy), Pt(160, my), width: 1, color: teal))
            for yy in [wy, my] { o.append(.line(Pt(155, yy + 5), Pt(165, yy - 5), width: 1, color: teal)) }
            o.append(.text("ระยะเผื่อ \(Int(FloodCheck.freeboardCm))", at: Pt(152, (wy + my) / 2), size: 11, bold: true, color: teal, align: .center, angle: -90))
        }
        marker(18, g, ink)
        halo("±0.00 " + refName, Pt(30, g - 10), size: 11.5, color: ink)
        // dimension chain: floor height, mounting height
        o.append(.line(Pt(514, g), Pt(514, mountY), width: 1, color: ink))
        for yy in [g, fy, mountY] { o.append(.line(Pt(509, yy + 5), Pt(519, yy - 5), width: 1, color: ink)) }
        o.append(.line(Pt(500, fy), Pt(520, fy), width: 1, color: ink))
        o.append(.line(Pt(378, mountY), Pt(520, mountY), width: 1, color: ink, dash: [3, 3]))
        if floor > 0 { o.append(.text("\(Int(floor.rounded()))", at: Pt(528, (g + fy) / 2), size: 11, color: ink, align: .center, angle: -90)) }
        o.append(.text("\(Int(mount.rounded()))", at: Pt(528, (fy + mountY) / 2), size: 11, color: ink, align: .center, angle: -90))
        o.append(.text("หน่วย: ซม. (ระดับเป็นเมตร)", at: Pt(528, 412), size: 10.5, color: muted, align: .right))
        return Sketch(width: width, height: height, ops: o)
    }
}
