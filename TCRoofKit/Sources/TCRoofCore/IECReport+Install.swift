import Foundation

/// IEC 62446 · 9 ภาพถ่ายติดตั้งระบบ: the photo report of the installation that goes to the hand-over as
/// `4. ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า.pdf` (`HandoverFolders`, `StationDocs` `install_photo_report`). Its pages follow the
/// report as sent (the design canvas's `IECInstall1–12` and `iPad · IEC 62446 · 9`): two pages per roof, one per
/// inverter, then ตู้ AC, ตู้ DC, Smart energy, กราวน์ DC, กราวน์ AC / Inverter Station and PQM. The pages are derived
/// from the station's roofs (kept here) and inverters (step 1), so their number follows the job. An inverter's two
/// photos are the front and S/N photos of step 1's add-inverter sheet, shared, not copied.
public extension IECReport {
    struct InstallPhotos: Codable, Equatable, Sendable {
        /// A roof with its own two pages; `id` stays when it is renamed, so its photos stay with it.
        public struct Roof: Codable, Equatable, Identifiable, Sendable {
            public var id: String
            public var name: String
            public init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
        }

        /// Empty until the first roof is named or added: the report then has one roof, `หลังคา 1` (`effectiveRoofs`).
        public var roofs: [Roof]
        /// Slot id (`InstallSlot.id`) → stored photo id, for the slots this report keeps itself.
        public var photos: [String: String]

        public init(roofs: [Roof] = [], photos: [String: String] = [:]) { self.roofs = roofs; self.photos = photos }

        enum CodingKeys: String, CodingKey { case roofs, photos }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roofs = try c.decodeIfPresent([Roof].self, forKey: .roofs) ?? []
            photos = try c.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
        }

        /// The default roof's id, so photos taken before any roof was named keep their slots.
        public static let defaultRoofID = "roof1"

        /// The roofs the report has: the named ones, else one `หลังคา 1`.
        public var effectiveRoofs: [Roof] { roofs.isEmpty ? [Roof(id: Self.defaultRoofID, name: "หลังคา 1")] : roofs }

        /// Adds a roof after the others (the default one is kept first, so its photos stay).
        public mutating func addRoof(_ name: String) {
            if roofs.isEmpty { roofs = effectiveRoofs }
            roofs.append(Roof(name: name))
        }

        public mutating func renameRoof(_ id: String, to name: String) {
            if roofs.isEmpty { roofs = effectiveRoofs }
            if let i = roofs.firstIndex(where: { $0.id == id }) { roofs[i].name = name }
        }

        /// Removes a roof and returns the photo ids it held, for the caller to delete. The last roof stays.
        public mutating func removeRoof(_ id: String) -> [String] {
            if roofs.isEmpty { roofs = effectiveRoofs }
            guard roofs.count > 1, let i = roofs.firstIndex(where: { $0.id == id }) else { return [] }
            roofs.remove(at: i)
            let prefix = id + "."
            let gone = photos.filter { $0.key.hasPrefix(prefix) }
            gone.keys.forEach { photos[$0] = nil }
            return Array(gone.values)
        }
    }

    /// One photo of the report: its heading in the report and the hint shown where it is taken.
    struct InstallSlot: Equatable, Identifiable, Sendable {
        public enum Source: Equatable, Sendable {
            /// Kept in `installPhotos.photos` under the slot's id.
            case own
            /// Step 1's photo of the inverter at this index.
            case inverter(Int, InverterPhoto)
        }
        public let id: String
        public let caption: String
        public let tip: String
        public let source: Source
    }

    /// One A4 page of the report.
    struct InstallPage: Equatable, Identifiable, Sendable {
        public let id: String
        /// Its line in the cover's contents: `หลังคาอาคารถังน้ำใส 1 (1/2)`, `Inverter No.2`.
        public let title: String
        /// The roof's name printed above the photos of its pages; empty elsewhere.
        public let group: String
        /// A short description for the list where the photos are taken.
        public let subtitle: String
        public let slots: [InstallSlot]
    }

    static let installStructure = "ภาพถ่ายโครงสร้างรองรับแผงเซลล์แสงอาทิตย์"

    /// The report's pages in their printed order.
    var installPages: [InstallPage] {
        var out: [InstallPage] = []
        for roof in installPhotos.effectiveRoofs {
            let r = roof.id
            out.append(InstallPage(id: r + ".a", title: roof.name + " (1/2)", group: roof.name, subtitle: "โครงสร้างรองรับ · 2 รูป", slots: [
                InstallSlot(id: r + ".a0", caption: Self.installStructure, tip: "แนวรางและขาตั้ง มุมกว้างเห็นทั้งแถว", source: .own),
                InstallSlot(id: r + ".a1", caption: Self.installStructure, tip: "ฐานและตัวยึด อีกมุมหนึ่ง", source: .own)]))
            out.append(InstallPage(id: r + ".b", title: roof.name + " (2/2)", group: roof.name, subtitle: "โครงสร้าง · แผงเซลล์", slots: [
                InstallSlot(id: r + ".b0", caption: Self.installStructure, tip: "โครงสร้างหลังวางแผง ด้านข้างหรือใต้แผง", source: .own),
                InstallSlot(id: r + ".b1", caption: "ภาพถ่ายแผงเซลล์แสงอาทิตย์", tip: "แผงทั้งแถว มุมสูงหรือโดรน", source: .own)]))
        }
        for (i, inv) in inverters.enumerated() {
            let n = i + 1
            let about = [inv.model, inv.serial.isEmpty ? nil : "S/N " + inv.serial].compactMap { $0 }.joined(separator: " · ")
            out.append(InstallPage(id: "inv\(n)", title: "Inverter No.\(n)", group: "", subtitle: about.isEmpty ? "รูปจากขั้น 1/7" : about, slots: [
                InstallSlot(id: "inv\(n).front", caption: "ภาพถ่ายเครื่องแปลงไฟฟ้า Inverter", tip: "ด้านหน้า เห็นทั้งเครื่องและหน้าจอ",
                            source: .inverter(i, .front)),
                InstallSlot(id: "inv\(n).sn", caption: "ภาพถ่ายเครื่องแปลงไฟฟ้า Inverter (Serial No.\(n))", tip: "ป้ายข้างเครื่อง อ่าน S/N ได้ชัด",
                            source: .inverter(i, .nameplate))]))
        }
        func page(_ id: String, _ title: String, _ subtitle: String, _ slots: [(String, String)]) {
            out.append(InstallPage(id: id, title: title, group: "", subtitle: subtitle,
                                   slots: slots.enumerated().map { k, s in InstallSlot(id: "\(id)\(k)", caption: s.0, tip: s.1, source: .own) }))
        }
        page("ac", "ตู้ AC", "ตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ", [
            ("ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านใน)", "เปิดฝา เห็นเบรกเกอร์และป้ายวงจร"),
            ("ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านนอก)", "ปิดฝา เห็นป้ายเตือนและการติดตั้ง")])
        page("dc", "ตู้ DC", "ตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสตรง", [
            ("ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสตรง (ด้านนอก)", "ปิดฝา เห็นป้ายเตือนไฟฟ้ากระแสตรง"),
            ("ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสตรง (ด้านใน)", "เปิดฝา เห็นฟิวส์ สวิตช์ และ SPD")])
        page("se", "Smart energy", "ตู้อุปกรณ์ไหลย้อนกลับ", [
            ("ภาพถ่ายตู้อุปกรณ์ไหลย้อนกลับ Smart energy (ด้านนอก)", "ปิดฝา เห็นทั้งตู้"),
            ("ภาพถ่ายตู้อุปกรณ์ไหลย้อนกลับ Smart energy (ด้านใน)", "เปิดฝา เห็น Zero Export Controller และ CT")])
        page("gdc", "กราวน์ DC", "สายดินด้านกระแสตรง · 1 รูป", [
            ("ภาพถ่ายกราวน์กระแสตรง", "สายดินโครงสร้างและแผง เห็นจุดต่อ")])
        page("gac", "กราวน์ AC / Inverter Station", "บาร์กราวด์ · อาคารอินเวอร์เตอร์", [
            ("ภาพถ่ายกราวน์กระแสสลับ", "บาร์กราวด์ในตู้ เห็นสายและป้าย"),
            ("ภาพถ่าย Inverter Station", "ภายนอกอาคาร มุมกว้างเห็นทั้งหลัง")])
        page("pqm", "PQM", "เครื่องวัดคุณภาพไฟฟ้า · 2 รูป", [
            ("ภาพถ่าย PQM", "เปิดฝา เห็นหน้าจอและการเดินสาย CT"),
            ("ภาพถ่าย PQM", "ตู้ PQM ภายนอก ปิดฝา")])
        return out
    }

    /// The photo id a slot shows, wherever it is kept.
    func installPhoto(_ slot: InstallSlot) -> String? {
        switch slot.source {
        case .own: installPhotos.photos[slot.id]
        case let .inverter(i, kind): inverters.indices.contains(i) ? inverters[i].photos[kind.rawValue] : nil
        }
    }

    /// Puts a photo id in a slot (nil clears it); an inverter's slot writes step 1's photo of it.
    mutating func setInstallPhoto(_ id: String?, for slot: InstallSlot) {
        switch slot.source {
        case .own: installPhotos.photos[slot.id] = id
        case let .inverter(i, kind): if inverters.indices.contains(i) { inverters[i].photos[kind.rawValue] = id }
        }
    }

    /// Photos taken of the report's slots.
    var installTally: Tally {
        let slots = installPages.flatMap(\.slots)
        return Tally(slots.filter { installPhoto($0) != nil }.count, slots.count)
    }

    /// Drive file names of the photos this report keeps itself (the inverters' are named by `photoFileNames`):
    /// `9.3 หลังคาอาคารถังน้ำใส 2 (1/2) 1.jpg`.
    func installPhotoFileNames() -> [String: String] {
        var out: [String: String] = [:]
        for (n, page) in installPages.enumerated() {
            for (k, slot) in page.slots.enumerated() where slot.source == .own {
                if let id = installPhotos.photos[slot.id] {
                    out[id] = "9.\(n + 1) \(page.title.replacingOccurrences(of: "/", with: "-")) \(k + 1).jpg"
                }
            }
        }
        return out
    }
}
