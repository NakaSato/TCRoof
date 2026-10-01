import Foundation

/// B3 "ระบบน้ำล้างแผง" (docs/ui/survey-b3): the water point is A2's `siteMarks` entry of kind `.water`, one per water
/// module, so A2, B3 and the report show the same point. No separate coordinate field is stored.
public enum WaterPoint {
    public static let marksKey = ModuleMarks.key
    public static let modeKey = "waterMode"
    public static let photoKeys = ["photoArea", "photoWide"]

    /// The stored `waterMode` choices; the design's card "ร่วมกับระบบน้ำเดิม" stores the second one.
    public enum Mode: String, CaseIterable, Sendable {
        case new = "ติดตั้งระบบน้ำใหม่"
        case existing = "ติดตั้งร่วมกับระบบน้ำเดิม"

        public var cardTitle: String { self == .new ? "ติดตั้งระบบน้ำใหม่" : "ร่วมกับระบบน้ำเดิม" }
        public var cardSub: String { self == .new ? "วางท่อและจุดจ่ายน้ำใหม่ทั้งหมด" : "ต่อแยกจากท่อที่มีอยู่" }
        public var tag: String { self == .new ? "ใหม่" : "ต่อแยก" }
        /// The pill under the pin.
        public var pinLabel: String { self == .new ? "ถังพัก / ปั๊มใหม่" : "จุดต่อแยก" }
        /// The chip at the top-left of the picture.
        public var legend: String { self == .new ? "จุดวางถังพัก / ปั๊มใหม่" : "จุดต่อแยกจากท่อประปาเดิม" }
        public var hint: String {
            self == .new ? "ถ่ายภาพจุดวางถัง/ปั๊ม · ระบุแหล่งน้ำในรายละเอียด"
                : "ถ่ายภาพจุดที่ต่อแยกจากท่อเดิมให้เห็นขนาดท่อ · ระบุขนาดท่อและวาล์วในรายละเอียด"
        }
        public var areaCaption: String { self == .new ? "จุดวางถังพักน้ำ / ปั๊มใหม่" : "จุดต่อแยกจากท่อเดิม" }
        public var placeholder: String {
            self == .new ? "ตัวอย่าง: วางถังพักน้ำ 1,000 ลิตร ข้างอาคาร · ใช้น้ำจากบ่อพักน้ำใส"
                : "ตัวอย่าง: ต่อแยกจากท่อ PVC 1 นิ้ว ข้างห้องปั๊ม มีวาล์วเดิม · แรงดันพอขึ้นหลังคา"
        }
    }

    public static func mode(_ v: Values) -> Mode? { v.choice(modeKey).flatMap(Mode.init(rawValue:)) }

    // MARK: the pin

    /// This module's water point, or nil when none has been placed.
    public static func mark(_ job: Job, module: UUID) -> MapMark? { ModuleMarks.mark(job, .water, of: .water, module: module) }

    /// Moves this module's water point to (x, y) in fractions of the A2 picture, creating it if there is none.
    /// The mark is linked to the module, so each water module keeps exactly one.
    public static func place(_ job: inout Job, module: UUID, x: Double, y: Double) {
        ModuleMarks.place(&job, .water, of: .water, module: module, x: x, y: y)
    }

    /// Drops the water point of a removed module.
    public static func remove(_ job: inout Job, module: UUID) { ModuleMarks.remove(&job, .water, of: .water, module: module) }

    // MARK: status

    /// Required photos still missing (0…2).
    public static func missingPhotos(_ v: Values) -> Int { photoKeys.filter { v.photo($0) == nil }.count }

    /// The bottom bar's line: complete, or the photos still missing; nil leaves the bar's own completion text.
    public static func statusLine(_ v: Values) -> String? {
        let k = missingPhotos(v)
        if k > 0 { return "ยังขาดภาพประกอบอีก \(k) ภาพ" }
        return mode(v) != nil ? "ครบช่องบังคับแล้ว · จุดจ่ายน้ำแสดงบนภาพ A2 และรายงาน" : nil
    }

    // MARK: summary

    /// Names of the roofs and tanks to wash (the C and D sections), or "—".
    public static func roofNames(_ job: Job) -> String {
        let names = job.modules.filter { $0.type == .roof || $0.type == .tank }.map { $0.name.trimmingCharacters(in: .whitespaces).isEmpty ? $0.spec.short : $0.name }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    /// Panels left after cuts on the roofs and tanks.
    public static func panelCount(_ job: Job) -> Int {
        Int(job.modules.filter { $0.type == .roof || $0.type == .tank }.reduce(0.0) { sum, m in
            sum + max(0, (m.values.number("panelsBefore") ?? 0) - (m.values.number("panelsCut") ?? 0))
        })
    }

    /// "416 แผง · 237.1 kWp", with the kWp from A1; "—" when neither is known.
    public static func panelSummary(_ job: Job) -> String {
        let n = panelCount(job)
        let kw = job.values.number("capacity").flatMap { $0 > 0 ? $0 : nil }
        let parts = [n > 0 ? "\(n) แผง" : nil, kw.map { fmt($0) + " kWp" }].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
