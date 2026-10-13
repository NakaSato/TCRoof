import Foundation

/// Papers of a กปภ. station that the app writes itself, from the station's facts and a few answers. This file holds
/// the content only; the app draws it (`StationPaperRenderer`) and keeps the PDF as the paper's file.
extension StationDocs {

    /// A paper the app can draft.
    public enum Draft: String, Sendable {
        case outageLetter
    }

    public static func draft(for kind: Kind) -> Draft? {
        kind.id == "outage_letter" ? .outageLetter : nil
    }

    /// What a drafted paper says about the station; the app fills it from the job.
    public struct Facts: Equatable, Sendable {
        public var station: String
        public var address: String
        public var capacityKW: Double
        public var company: String

        public init(station: String, address: String, capacityKW: Double, company: String) {
            self.station = station; self.address = address; self.capacityKW = capacityKW; self.company = company
        }
    }

    /// A one-page letter in the company's letterhead.
    public struct Letter: Equatable, Sendable {
        public var number: String
        public var date: String
        public var subject: String
        public var to: String
        public var paragraphs: [String]
        public var closing: String
        public var signer: String
        public var position: String
    }

    /// หนังสือแจ้งดับไฟ: the answers the letter needs. Kept on the station.
    public struct OutageLetter: Codable, Equatable, Sendable {
        public static let numberPrefix = "TC-PML-"
        public static let subject = "ขอแจ้งดับกระแสไฟฟ้าเพื่อเชื่อมต่อระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา"

        public var number: String
        /// The day the letter is dated.
        public var date: Date?
        public var to: String
        public var outageDay: Date?
        /// The outage, as minutes after midnight.
        public var start: Int
        public var end: Int
        /// The letter's own text, when the team rewrote it; empty prints the standard text.
        public var body: String
        public var signer: String
        public var position: String

        public init(number: String = OutageLetter.numberPrefix, date: Date? = nil, to: String = "", outageDay: Date? = nil,
                    start: Int = 9 * 60, end: Int = 12 * 60, body: String = "", signer: String = "", position: String = "") {
            self.number = number; self.date = date; self.to = to; self.outageDay = outageDay
            self.start = start; self.end = end; self.body = body; self.signer = signer; self.position = position
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decodeIfPresent(String.self, forKey: .number) ?? OutageLetter.numberPrefix
            date = try c.decodeIfPresent(Date.self, forKey: .date)
            to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
            outageDay = try c.decodeIfPresent(Date.self, forKey: .outageDay)
            start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 9 * 60
            end = try c.decodeIfPresent(Int.self, forKey: .end) ?? 12 * 60
            body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            signer = try c.decodeIfPresent(String.self, forKey: .signer) ?? ""
            position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        }

        /// What is still missing before the letter can go out.
        public var issues: [String] {
            var out: [String] = []
            let n = number.trimmingCharacters(in: .whitespaces)
            if n.isEmpty || n == OutageLetter.numberPrefix { out.append("เลขที่หนังสือ") }
            if to.trimmingCharacters(in: .whitespaces).isEmpty { out.append("เรียน (ผู้รับหนังสือ)") }
            if outageDay == nil { out.append("วันที่ดับไฟ") }
            if end <= start { out.append("เวลาดับไฟ") }
            if signer.trimmingCharacters(in: .whitespaces).isEmpty { out.append("ผู้ลงนาม") }
            return out
        }

        /// `09:00–12:00 น.`
        public var hours: String { "\(OutageLetter.clock(start))–\(OutageLetter.clock(end)) น." }

        /// `3 ชั่วโมง`, `2 ชั่วโมง 30 นาที`; empty when the end isn't after the start.
        public var duration: String {
            let m = end - start
            guard m > 0 else { return "" }
            return [m / 60 > 0 ? "\(m / 60) ชั่วโมง" : nil, m % 60 > 0 ? "\(m % 60) นาที" : nil].compactMap { $0 }.joined(separator: " ")
        }

        static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

        /// The standard text, one paragraph per line; the team can rewrite it in `body`.
        public func standardBody(_ facts: Facts) -> String {
            let kwp = facts.capacityKW.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            let place = [facts.station, facts.address].filter { !$0.isEmpty }.joined(separator: " ")
            let day = outageDay.map(PermitDate.long) ?? "........................"
            let span = duration.isEmpty ? "" : " (ประมาณ \(duration))"
            return [
                "ด้วย \(facts.company) เป็นผู้รับจ้างติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา (Solar Rooftop) "
                    + "ขนาด \(kwp) kWp ณ \(place) ซึ่งติดตั้งแล้วเสร็จและพร้อมเชื่อมต่อเข้ากับระบบไฟฟ้าของสถานี",
                "ในการเชื่อมต่อระบบดังกล่าวจำเป็นต้องดับกระแสไฟฟ้าของสถานีเป็นการชั่วคราว บริษัทฯ จึงขอแจ้งดับกระแสไฟฟ้า"
                    + "ในวันที่ \(day) เวลา \(hours)\(span)",
                "จึงเรียนมาเพื่อโปรดทราบและพิจารณาอนุญาต",
            ].joined(separator: "\n")
        }

        public func letter(_ facts: Facts, today: Date = .now) -> Letter {
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? standardBody(facts) : body
            return Letter(number: number, date: PermitDate.long(date ?? today), subject: OutageLetter.subject, to: to,
                          paragraphs: text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                              .filter { !$0.isEmpty },
                          closing: "ขอแสดงความนับถือ", signer: signer, position: position)
        }
    }
}
