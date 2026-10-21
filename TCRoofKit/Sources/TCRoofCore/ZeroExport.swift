import Foundation

/// B4 "ระบบกันย้อน" (docs/ui/survey-b4): the level (`level`, shared with the SLD page and B2's card), the pole for HV
/// (`pole`), and at least four photos whose labels follow the level. `photoDetail` stays optional in the schema so old
/// jobs keep their meaning there; the four-photo rule is counted here, in `Progress` and on the wide page.
public enum ZeroExport {
    public static let levelKey = "level"
    public static let poleKey = "pole"
    public static let lv = "กันย้อนที่แรงต่ำ"
    public static let hv = "กันย้อนที่แรงสูง"
    public static let poles = ["เสาเดิม", "เสาใหม่"]
    /// The 2 × 2 grid in order: the two original photos, then the two added by the owner's board.
    public static let photoKeys = ["photoArea", "photoDetail", "photoRating", "photoAccess"]
    public static var minPhotos: Int { photoKeys.count }

    public static func isHV(_ v: Values) -> Bool { v.choice(levelKey) == hv }

    // MARK: photos

    /// The label of photo slot `slot` (0…3) for the level; `board` is A3's connection board name ("MDP-1").
    public static func photoLabel(_ slot: Int, hv: Bool, board: String) -> String {
        let lvLabels = ["ตู้ \(board) | วงจุดติดตั้ง CT", "ช่องว่างสำหรับรีเลย์", "ป้ายพิกัด ACB เมน / CT เดิม", "บัสบาร์ขาออก ACB | วัดขนาดสำหรับ CT"]
        let hvLabels = ["เสาหลังมิเตอร์ | จุด CT/VT", "ระยะห่างสายแรงสูง", "ป้ายมิเตอร์ กฟภ. / CT-VT เดิม", "ทางเข้ารถกระเช้า | พื้นที่ทำงาน"]
        return (hv ? hvLabels : lvLabels)[slot]
    }

    public static func photoCount(_ v: Values) -> Int { photoKeys.filter { v.photo($0) != nil }.count }
    public static func missingPhotos(_ v: Values) -> Int { minPhotos - photoCount(v) }

    /// The required photo the schema leaves optional for old jobs (`photoDetail`); `Progress` adds it to B4's count.
    static let extraRequired = ["photoDetail"]
    static func extraCompletion(_ v: Values) -> Completion {
        Completion(filled: extraRequired.filter { v.photo($0) != nil }.count, total: extraRequired.count)
    }
    static func extraMissing(_ v: Values) -> [String] {
        extraRequired.filter { v.photo($0) == nil }.compactMap { id in Schema.spec(.backfeed).groups.flatMap(\.fields).first { $0.id == id }?.plainLabel }
    }

    // MARK: status

    /// The bottom bar's line: the photos still missing, else the level / pole still to choose, else complete.
    public static func statusLine(_ v: Values) -> String {
        let k = missingPhotos(v)
        if k > 0 { return "ยังขาด: ภาพประกอบอีก \(k) ภาพ (ต้องมีอย่างน้อย \(minPhotos) ภาพ)" }
        if v.choice(levelKey) == nil { return "ยังขาด: ตำแหน่งกันย้อน" }
        if isHV(v) && v.choice(poleKey) == nil { return "ยังขาด: เสา" }
        return "ครบช่องบังคับแล้ว | SLD และ B2 อัปเดตตามตำแหน่งกันย้อน"
    }
    public static func isComplete(_ v: Values) -> Bool {
        missingPhotos(v) == 0 && v.choice(levelKey) != nil && (!isHV(v) || v.choice(poleKey) != nil)
    }

    // MARK: what the job says

    /// A3's connection board name as the SLD resolves it, "?" when unknown.
    public static func boardName(_ sl: SingleLine) -> String {
        let n = sl.connectionBoard?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "?" : n
    }
    /// A1/A3's metering kV ("22"), "?" when unknown.
    public static func kv(_ job: Job) -> String {
        let k = (job.values.choice("meterKV") ?? job.values.text("meterKV")).trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? "?" : k
    }

    public struct Item: Hashable, Sendable {
        public let title: String
        public let sub: String
    }

    /// "อุปกรณ์ที่ต้องติดตั้ง": three rows from A3 (the board and its main breaker) and B2 (the inverter count).
    public static func equipment(_ job: Job, _ v: Values, _ sl: SingleLine) -> [Item] {
        let n = sl.pv.inverterCount.map(String.init) ?? "?"
        let control = Item(title: "สายสัญญาณควบคุม", sub: "ไปอินเวอร์เตอร์ \(n) เครื่อง (B2)")
        if isHV(v) {
            let pole = v.choice(poleKey).map { $0 == "เสาเดิม" ? "ใช้เสาเดิม" : "ปักเสาใหม่" } ?? "เสา ?"
            return [Item(title: "CT/VT แรงสูง \(kv(job)) kV", sub: "หลังมิเตอร์ กฟภ."), Item(title: "รีเลย์กันย้อนแรงสูง", sub: pole), control]
        }
        let board = boardName(sl)
        let main = sl.connectionBoard?.main
        let at = main.flatMap { $0.at.isMissing ? nil : $0.at.text.trimmingCharacters(in: .whitespaces) } ?? "?"
        let type = main.flatMap { $0.type.text.split(separator: ",").first.map(String.init) } ?? "ACB"
        return [Item(title: "CT 3 ตัว", sub: "ที่เมน \(type) \(at) ตู้ \(board)"),
                Item(title: "รีเลย์กันย้อน (Zero export)", sub: "ในตู้ \(board)"), control]
    }

    /// The A2 picture's กันย้อน symbol for this B4: the one linked to it, else the n-th unlinked one (A2 places them).
    public static func mark(_ job: Job, module: UUID) -> MapMark? { ModuleMarks.mark(job, .zeroExport, of: .backfeed, module: module) }
}
