import Foundation

/// B5 "ปุ่ม Emergency" (docs/ui/survey-b5): the FTS switch (Emergency) button's photo, place text, height and its point
/// on the A2 picture. The height is A4's `emgMountCm` (job-wide), so the flood check reads the same value. The FTS
/// cabinet itself is no longer located (owner's decision); `photoFTS` stays optional for old jobs.
public enum EmergencyButton {
    public static let photoKey = "photoEmg"
    public static let placeKey = "emgPlace"
    public static let heightKey = "emgMountCm"

    /// Stepper: 0.05 m steps within 0.80–1.80 m, stored in cm.
    public static let stepCm = 5.0
    public static let rangeCm: ClosedRange<Double> = 80...180
    /// The recommended height; outside it the page warns (it never blocks completion).
    public static let recommendedCm: ClosedRange<Double> = 110...150

    /// The stored height, or A4's default when none is stored.
    public static func heightCm(_ job: Job) -> Double { FloodCheck.emergencyCm(job.values) }
    public static func isRecommended(_ cm: Double) -> Bool { recommendedCm.contains(cm) }
    /// "1.40 ม."
    public static func meters(_ cm: Double) -> String { String(format: "%.2f ม.", cm / 100) }

    /// Steps the height by `steps` × 5 cm from the shown value, clamped to the range, and stores it in `emgMountCm`.
    public static func step(_ job: inout Job, by steps: Int) {
        let v = ((heightCm(job) + Double(steps) * stepCm) / stepCm).rounded() * stepCm
        job.values[heightKey] = .text(fmt(min(rangeCm.upperBound, max(rangeCm.lowerBound, v))))
    }

    /// What the button cuts: the FTS cabinet and every inverter, with B2's count when known.
    public static func cuts(_ job: Job) -> String {
        let n = job.modules.filter { $0.type == .inverter }.reduce(0) { $0 + Int($1.values.number("inverterCount") ?? 0) }
        return n > 0 ? "ตู้ FTS + อินเวอร์เตอร์ทั้ง \(n) เครื่อง" : "ตู้ FTS + อินเวอร์เตอร์ทุกเครื่อง"
    }

    // MARK: the pin

    public static func mark(_ job: Job, module: UUID) -> MapMark? { ModuleMarks.mark(job, .emergency, of: .fts, module: module) }
    public static func place(_ job: inout Job, module: UUID, x: Double, y: Double) {
        ModuleMarks.place(&job, .emergency, of: .fts, module: module, x: x, y: y)
    }

    // MARK: status

    public static func photoMissing(_ v: Values) -> Bool { v.photo(photoKey) == nil }

    /// The bottom bar's line: the missing photo, else a height outside the recommended range, else complete.
    public static func statusLine(_ job: Job, _ v: Values) -> String {
        if photoMissing(v) { return "ยังขาดภาพบังคับ 1 ภาพ" }
        if !isRecommended(heightCm(job)) { return "ความสูงปุ่มแนะนำ 1.10–1.50 ม." }
        return "ครบช่องบังคับแล้ว | ตำแหน่งแสดงบนภาพ A2 และ SLD"
    }
}
