import Foundation
import TCRoofCore

/// IEC 62446 · 9 ภาพถ่ายติดตั้งระบบ as A4 pages: the cover with its contents, then one page per `IECReport.InstallPage`
/// (the design canvas's `IECInstallCover` and `IECInstall1–12`). The geometry is the boards', drawn at 794 × 1123 px and
/// scaled to the page: every element on one column 98–700 px, two photo frames a page (one tall frame when the page has
/// one photo), the roof's name above its photos, `n / total` at the foot. A slot without a photo keeps its empty
/// frame with `ยังไม่มีรูป`, so the page count and the order stay as in the report. Photos are fitted in their frame,
/// not cropped, so a date / GPS stamp in a corner stays in view.
public struct InstallPhotoPages {
    public struct Slot: Sendable {
        public var caption: String
        public var photo: Photo?
        public init(caption: String, photo: Photo?) { self.caption = caption; self.photo = photo }
    }

    public struct Page: Sendable {
        public var title: String
        public var group: String
        public var slots: [Slot]
        public init(title: String, group: String, slots: [Slot]) { self.title = title; self.group = group; self.slots = slots }
    }

    /// `สถานีจ่ายน้ำแพรกหนามแดง การประปาส่วนภูมิภาคสาขาสมุทรสงคราม`.
    public var station: String
    /// `209.76`.
    public var capacity: String
    /// The cover's foot: `ตุลาคม 2569`.
    public var month: String
    public var pages: [Page]
    /// The PWA and PEA marks on the cover; either may be missing.
    public var logos: [Photo]
    let measure: TextMeasuring

    public init(station: String, capacity: String, month: String, pages: [Page], logos: [Photo] = [],
                measure: TextMeasuring = ApproxMeasure()) {
        self.station = station; self.capacity = capacity; self.month = month; self.pages = pages; self.logos = logos
        self.measure = measure
    }

    /// The board's `px` size in points, smaller when the line is wider than `width` px (the boards' TH SarabunPSK is
    /// narrower than the PDF's Sarabun).
    func fit(_ line: String, _ px: Double, width: Double = 602, bold: Bool = false) -> Double {
        let pt = Self.size(px), room = Self.size(width)
        let w = measure.width(line, size: pt, bold: bold)
        return w > room ? pt * room / w : pt
    }

    static let project = "โครงการจัดการพลังงานไฟฟ้าจากระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา (Solar Rooftop)"
    /// Board px → PDF points.
    static let k = ReportLayout.pageW / 794
    static let frame = RGBA(hex: 0x1F3864), muted = RGBA(hex: 0x6B7A90)

    static func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { Box(x * k, y * k, w * k, h * k) }
    static func at(_ x: Double, _ y: Double) -> Pt { Pt(x * k, y * k) }
    static func size(_ px: Double) -> Double { px * k }

    /// The cover, then the photo pages.
    public func render() -> [ReportLayout.Page] {
        [ReportLayout.Page(ops: cover())] + pages.enumerated().map { n, p in ReportLayout.Page(ops: page(p, number: n + 1)) }
    }

    /// The page header's station line: the board prints `การประปาส่วนภูมิภาค` before the station, unless the station
    /// line already names it.
    var stationLine: String {
        station.contains("การประปาส่วนภูมิภาค") ? station : "การประปาส่วนภูมิภาค " + station
    }

    func cover() -> [DrawOp] {
        typealias S = InstallPhotoPages
        var ops: [DrawOp] = []
        let marks = [S.box(335, 86, 62, 60), S.box(405, 84, 66, 64)]
        for (photo, b) in zip(logos, marks) { ops.append(.photo(photo, b)) }
        let title = "ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า", kind = "พลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา (Solar Rooftop)"
        ops.append(.text(title, at: S.at(399, 208), size: fit(title, 42, bold: true), bold: true, align: .center))
        ops.append(.text(kind, at: S.at(399, 253), size: fit(kind, 26, bold: true), bold: true, align: .center))
        for (i, line) in [S.project, station, "ขนาดกำลังการผลิตติดตั้ง \(capacity) กิโลวัตต์"].enumerated() {
            ops.append(.text(line, at: S.at(399, 314 + 27.6 * Double(i)), size: fit(line, 20.72), align: .center))
        }
        ops.append(.text("สารบัญ", at: S.at(399, 422), size: S.size(22), bold: true, align: .center))

        // the contents, one row a page: ลำดับ 64 px · รายการ · จำนวนรูป 92 px · หน้า 72 px across 98–700
        let rowH = 31.0, headH = 33.0, top = 444.0
        let rows = pages.enumerated().map { n, p in ["9.\(n + 1)", p.title, "\(p.slots.count)", "\(n + 1)"] }
        let bottom = top + headH + rowH * Double(rows.count)
        ops.append(.rect(S.box(98, top, 602, bottom - top), stroke: .black, fill: nil, width: 0.75))
        for x in [162.0, 536, 628] { ops.append(.line(S.at(x, top), S.at(x, bottom), width: 0.75, color: .black)) }
        for r in 0..<rows.count {
            let y = top + headH + rowH * Double(r)
            ops.append(.line(S.at(98, y), S.at(700, y), width: 0.75, color: .black))
        }
        func row(_ values: [String], y: Double, h: Double, bold: Bool) {
            let centres: [Double] = [130, 0, 582, 664]
            for (c, v) in values.enumerated() {
                ops.append(c == 1
                    ? .text(v, at: S.at(172, y + h / 2), size: fit(v, 18.23, width: 354, bold: bold), bold: bold)
                    : .text(v, at: S.at(centres[c], y + h / 2), size: S.size(18.23), bold: bold, align: .center))
            }
        }
        row(["ลำดับ", "รายการ", "จำนวนรูป", "หน้า"], y: top, h: headH, bold: true)
        for (i, r) in rows.enumerated() { row(r, y: top + headH + rowH * Double(i), h: rowH, bold: false) }

        if !month.isEmpty { ops.append(.text(month, at: S.at(399, 1044), size: S.size(20.72), align: .center)) }
        return ops
    }

    func page(_ p: Page, number: Int) -> [DrawOp] {
        typealias S = InstallPhotoPages
        var ops: [DrawOp] = []
        for (i, line) in [S.project, stationLine, "ขนาดกำลังการผลิตติดตั้ง \(capacity) กิโลวัตต์"].enumerated() {
            ops.append(.text(line, at: S.at(399, 107 + 27.6 * Double(i)), size: fit(line, 20.72), align: .center))
        }
        let grouped = !p.group.isEmpty
        if grouped { ops.append(.text(p.group, at: S.at(399, 214), size: fit(p.group, 18.23), align: .center)) }
        // the boards' frames: caption 34 px high, then the photo frame
        var frames: [(cap: Double, box: Double, h: Double)] = grouped
            ? [(233, 273, 340), (627, 667, 340)] : [(187, 227, 362), (601, 641, 362)]
        if p.slots.count == 1 { frames[0].h = grouped ? 734 : 776 }
        for (slot, f) in zip(p.slots, frames) {
            ops.append(.rect(S.box(98, f.cap, 602, 34), stroke: .black, fill: nil, width: 0.75))
            ops.append(.text(slot.caption, at: S.at(399, f.cap + 17), size: fit(slot.caption, 20.72, width: 590), align: .center))
            ops.append(.rect(S.box(98, f.box, 602, f.h), stroke: S.frame, fill: nil, width: 0.75))
            if let photo = slot.photo {
                ops.append(.photo(photo, S.box(102, f.box + 4, 594, f.h - 8)))
            } else {
                ops.append(.text("ยังไม่มีรูป", at: S.at(399, f.box + f.h / 2), size: S.size(18.23), color: S.muted, align: .center))
            }
        }
        ops.append(.text("\(number) / \(pages.count)", at: S.at(399, 1042), size: S.size(18.23), align: .center))
        return ops
    }
}
