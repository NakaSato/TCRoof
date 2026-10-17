import Foundation

/// A job's folder on the company's center Drive (docs/reference/forms/pwa/projects/solar-rooftop-energy-mgmt/project.json
/// `folders`, the user's layout of 2026-10-17): `1. เอกสารส่งมอบ/` holds the numbered hand-over folders and file names,
/// `2. เอกสารระหว่างก่อสร้าง/` the construction records in their own folders (routine reports, IEC 62446, ICL).
/// `HandoverFoldersTests` keeps the slots the same as project.json.
public enum HandoverFolders {
    public static let handover = "1. เอกสารส่งมอบ"
    public static let construction = "2. เอกสารระหว่างก่อสร้าง"

    /// Where one station paper (a `StationDocs.Kind` id) goes, its folder below `handover` and its file name with
    /// `{station_name}`, `{branch}` and `{region}` still in it.
    public struct Slot: Equatable, Sendable {
        public let folder: [String]
        public let name: String
    }

    static let install = "1. รายงานติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ฯ และผลการทดสอบระบบต่าง ๆ"
    static let manual = "2. คู่มือการใช้งานและบำรุงรักษาระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ฯ (Instruction Manual)"
    static let asBuilt = "3. แบบ As-Built Drawing"
    static let permits = "4. เอกสารสำหรับการยื่นขออนุญาตที่เกี่ยวข้องให้กับผู้ว่าจ้าง"
    static let building = "1. ใบอนุญาตขอดัดแปลงอาคาร (อ.1)"
    static let grid = "2. เอกสารยื่นขอเชื่อมต่อระบบผลิตไฟฟ้า (ขนานไฟ)"
    static let pk2 = "3. ใบอนุญาตผลิตพลังงานควบคุม (พค.2)"

    /// Every slot by paper id, in project.json's order. A paper in two folders (the install photo report) has two.
    public static let slots: [String: [Slot]] = {
        var out: [String: [Slot]] = [:]
        func add(_ ids: String, _ folder: [String], _ name: String) {
            for id in ids.split(separator: "|").map(String.init) { out[id, default: []].append(Slot(folder: folder, name: name)) }
        }
        add("install_photo_report", [install, "1. รายงานการติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ฯ"], "รายงานติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ฯ {station_name}.pdf")
        add("thermal_report", [install, "2. ภาพถ่ายความร้อน"], "ภาพถ่ายความร้อน {station_name}.pdf")
        add("iec62446_report", [install, "3. ผลการทดสอบระบบต่าง ๆ"], "IEC Test {station_name}.pdf")
        add("iv_photo_report", [install, "3. ผลการทดสอบระบบต่าง ๆ"], "รายงานตรวจสอบระบบก่อนและหลังการเชื่อมต่อ {station_name}.pdf")
        add("punch_list", [install, "4. Punch list"], "Punch list {station_name}.pdf")
        add("om_manual", [manual], "คู่มือการใช้งานและบำรุงรักษาระบบผลิตไฟฟ้าฯ พื้นที่{region}.pdf")
        add("asbuilt", [asBuilt], "AS-Built {station_name} {branch}.pdf")
        add("elec_calc", [asBuilt], "รายการคำนวณทางไฟฟ้า {station_name}.pdf")
        add("building_permit_request|building_exempt_notice", [permits, building], "1. เอกสารที่เกี่ยวข้องสำหรับยื่นดัดแปลงอาคาร.pdf")
        add("structural_plan", [permits, building], "2. แบบแปลน Forcon.pdf")
        add("structural_calc", [permits, building], "3. รายการคำนวณโยธา.pdf")
        add("electric_bill", [permits, grid], "1. ใบแจ้งค่าไฟฟ้า.pdf")
        add("pwa_act", [permits, grid], "2. พ.ร.บ.จัดตั้ง.pdf")
        add("site_map", [permits, grid], "3. แผนผังแสดงที่ตั้งของสถานที่ติดตั้ง.pdf")
        add("install_photo_report", [permits, grid], "4. ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า.pdf")
        add("other_equipment", [permits, grid], "5. อุปกรณ์อื่นๆ ที่เกี่ยวข้อง.pdf")
        add("sld", [permits, grid], "6. Single Line Diagram + เอกสารวิศวกรไฟฟ้า.pdf")
        add("pv_datasheet", [permits, grid], "7. แผงเซลล์แสงอาทิตย์.pdf")
        add("inverter_datasheet", [permits, grid], "8. เครื่องแปลงไฟฟ้า.pdf")
        add("pwa_poa_order", [permits, grid], "9. คำสั่งการประปาส่วนภูมิภาค (หนังสือมอบอำนาจ).pdf")
        add("grantor_docs", [permits, grid], "10. เอกสารผู้มอบอำนาจ.pdf")
        add("grantee_docs", [permits, grid], "11. เอกสารผู้รับมอบอำนาจ.pdf")
        return out
    }()

    /// Every hand-over folder, made empty on the center Drive so the job's folder shows the whole layout
    /// (4.3 พค.2 only for a station of 200 kVA and over).
    public static func folders(over200kVA: Bool) -> [[String]] {
        var out: [[String]] = [[install, "1. รายงานการติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ฯ"], [install, "2. ภาพถ่ายความร้อน"],
                               [install, "3. ผลการทดสอบระบบต่าง ๆ"], [install, "4. Punch list"], [manual], [asBuilt],
                               [permits, building], [permits, grid]]
        if over200kVA { out.append([permits, pk2]) }
        return out.map { [handover] + $0 }
    }

    /// The paper's first slot, its folder from the job's folder and its file name filled in, keeping the
    /// file's own extension (a paper attached as a picture stays one).
    public static func place(_ kindID: String, station: String, branch: String = "", region: String = "",
                             ext: String = "pdf") -> (folder: [String], name: String)? {
        places(kindID, station: station, branch: branch, region: region, ext: ext).first
    }

    /// Every slot of the paper (the install photo report is in two folders), filled in as `place`.
    public static func places(_ kindID: String, station: String, branch: String = "", region: String = "",
                              ext: String = "pdf") -> [(folder: [String], name: String)] {
        (slots[kindID] ?? []).map { fill($0, station: station, branch: branch, region: region, ext: ext) }
    }

    private static func fill(_ slot: Slot, station: String, branch: String, region: String, ext: String) -> (folder: [String], name: String) {
        let filled = slot.name
            .replacingOccurrences(of: "{station_name}", with: station)
            .replacingOccurrences(of: "{branch}", with: branch)
            .replacingOccurrences(of: "{region}", with: region)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: " .pdf", with: ".pdf")
            .replacingOccurrences(of: "/", with: "-")
        let base = (filled as NSString).deletingPathExtension
        return ([handover] + slot.folder, base + "." + (ext.isEmpty ? "pdf" : ext.lowercased()))
    }
}
