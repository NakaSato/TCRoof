import Foundation

/// The roof layout's energy as the report prints it (docs/specs/energy-yield/preliminary-energy-yield.md §11): a range
/// from P90 to P50 rather than one figure, P50 never as a guarantee, the loss chain, the data source and its
/// attribution, the monthly figures and the lifetime total, and the disclaimer in Thai and English.
extension RoofMountYield {
    /// Under every printed estimate (§11).
    public static let disclaimerTH = "ประมาณการเบื้องต้นจากข้อมูลแสงแดดและค่าสูญเสียมาตรฐาน ไม่ใช่ค่ารับประกัน ผลจริงขึ้นกับอากาศ การล้างแผง เงา และอุปกรณ์ | ยืนยันแบบสุดท้ายด้วย PVsyst"
    public static let disclaimerEN = "Preliminary estimate from irradiance data and standard loss assumptions; not a guarantee. Actual output varies with weather, cleaning, shading and equipment. Final design to be confirmed with PVsyst."

    /// `พลังงานปีแรก 175.3–191.1 MWh (P90–P50) | 1,480 kWh/kWp | PR 80% | 129.6 kWp`, or SolarModel's single
    /// figure marked as a clear-sky estimate.
    public static func headline(_ e: Estimate) -> String {
        let tail = String(format: " | %@ kWh/kWp", grouped(e.kWhPerKWp)) + (e.performanceRatio.map { String(format: " | PR %.0f%%", $0 * 100) } ?? "")
            + String(format: " | %.1f kWp", e.kWp)
        guard let p90 = e.p90MWh else { return String(format: "พลังงานปีแรกประมาณ %.1f MWh (ท้องฟ้าใส)", e.mwh) + tail }
        return String(format: "พลังงานปีแรก %.1f–%.1f MWh (P90–P50)", p90, e.mwh) + tail
    }

    /// `รวม 25 ปี 4,512 MWh (แผงเสื่อมตามอายุ)`; nil from SolarModel.
    public static func lifetimeLine(_ e: Estimate) -> String? {
        guard let total = e.lifetimeMWh, e.lifetimeYears > 0 else { return nil }
        return "รวม \(e.lifetimeYears) ปี \(grouped(total)) MWh (แผงเสื่อมตามอายุ)"
    }

    /// `ค่าสูญเสีย: แสงบนระนาบแผง (Perez) +3.1% | อุณหภูมิแผง −8.2% | …`; nil from SolarModel.
    public static func lossLine(_ e: Estimate) -> String? {
        guard !e.losses.isEmpty else { return nil }
        return "จากแสงแนวราบถึงไฟเข้าระบบ: " + e.losses.map { l in
            l.label + " " + (l.percent >= 0 ? "+" : "−") + String(format: "%.1f%%", abs(l.percent))
        }.joined(separator: " | ")
    }

    /// The source, its attribution and the inverters: `คำนวณรายชั่วโมง | PVGIS-ERA5 TMY กรุงเทพฯ (ห่าง 8 กม.) | PVGIS
    /// © European Union | Growatt MAX 60KTL3 LV × 2 | DC/AC 1.08`.
    public static func sourceReportLine(_ e: Estimate) -> String {
        var parts = [e.sourceLine]
        if case .hourly(_, _, _, let attribution) = e.source { parts.append(attribution) }
        if let inv = e.inverterLine { parts.append(inv) }
        return parts.joined(separator: " | ")
    }

    /// MWh per month as bars with their values, January first; nil without monthly figures.
    public static func monthlyChart(_ e: Estimate, width W: Double = 760, height H: Double = 120) -> Sketch? {
        guard e.monthlyMWh.count == 12, let top = e.monthlyMWh.max(), top > 0 else { return nil }
        let left = 16.0, base = H - 18, bandTop = 26.0, slot = (W - 2 * left) / 12, k = (base - bandTop) / top
        let ink = RGBA(hex: 0x111111), muted = RGBA(hex: 0x6B7280), bar = RGBA(hex: 0x1F4F8F)
        var o: [DrawOp] = [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)]
        o.append(.text("พลังงานรายเดือน (MWh, P50 ปีแรก)", at: Pt(left, 10), size: 9, bold: true, color: ink))
        o.append(.line(Pt(left, base), Pt(W - left, base), width: 0.6, color: muted))
        let months = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]
        for (i, m) in e.monthlyMWh.enumerated() {
            let cx = left + (Double(i) + 0.5) * slot, h = m * k, w = slot * 0.62
            o.append(.rect(Box(cx - w / 2, base - h, w, h), stroke: nil, fill: bar.withAlpha(0.85)))
            o.append(.text(String(format: m >= 100 ? "%.0f" : "%.1f", m), at: Pt(cx, base - h - 6), size: 7.5, color: ink, align: .center))
            o.append(.text(months[i], at: Pt(cx, base + 9), size: 7.5, color: muted, align: .center))
        }
        return Sketch(width: W, height: H, ops: o)
    }

    static func grouped(_ x: Double) -> String {
        let n = Int(x.rounded()), s = String(abs(n))
        var out = ""
        for (i, c) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(",") }; out.append(c) }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
