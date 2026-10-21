import Foundation

/// A survey appointment as an iPad Calendar event (docs/specs/calendar-travel-expenses-swift.md §A2): title, times,
/// place, a link back to the job, plain-text notes Calendar makes tappable, and two alarms. Built from plain values so
/// the manual editor and a later automatic sync fill events the same way. The linked NO.224 form's coordinator, phone,
/// address and GPS win over the job's own.
public struct SurveyEvent: Equatable, Sendable {
    /// What the event is built from: the TCRoof job, and its linked survey form when there is one.
    public struct Source: Sendable {
        public var projectName: String
        public var code: String
        public var customerName: String
        public var phone: String
        public var address: String
        public var province: String
        public var team: String
        public var capacityKW: Double
        /// The appointment: date and time; 00:00 means a day with no time.
        public var start: Date
        public var syncID: String?
        /// The linked form's `coordinator`, `phone`, `address` and `gps` (empty when not filled).
        public var formCoordinator: String
        public var formPhone: String
        public var formAddress: String
        public var formGPS: String

        public init(projectName: String, code: String, customerName: String, phone: String, address: String, province: String,
                    team: String, capacityKW: Double, start: Date, syncID: String?, formCoordinator: String = "",
                    formPhone: String = "", formAddress: String = "", formGPS: String = "") {
            self.projectName = projectName; self.code = code; self.customerName = customerName; self.phone = phone
            self.address = address; self.province = province; self.team = team; self.capacityKW = capacityKW
            self.start = start; self.syncID = syncID; self.formCoordinator = formCoordinator; self.formPhone = formPhone
            self.formAddress = formAddress; self.formGPS = formGPS
        }
    }

    public enum Alarm: Equatable, Sendable {
        /// At a set time (the day before at 17:00).
        case at(Date)
        /// This long before the start.
        case before(TimeInterval)
    }

    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Address and province, for the event's place.
    public var location: String
    public var latitude: Double?
    public var longitude: Double?
    public var url: URL?
    public var notes: String
    public var alarms: [Alarm]

    /// `hours`: how long a timed survey takes (spec: 3 h).
    public init(_ s: Source, hours: Double = 3, calendar cal: Calendar = .current) {
        let name = s.projectName.trimmed.isEmpty ? s.customerName.trimmed : s.projectName.trimmed
        title = "สำรวจ | " + name + (s.code.isEmpty ? "" : " (\(s.code))")
        let t = cal.dateComponents([.hour, .minute], from: s.start)
        isAllDay = (t.hour ?? 0) == 0 && (t.minute ?? 0) == 0
        let day = cal.startOfDay(for: s.start)
        start = isAllDay ? day : s.start
        end = isAllDay ? cal.date(byAdding: .day, value: 1, to: day)! : s.start.addingTimeInterval(max(hours, 0.5) * 3600)

        let address = s.formAddress.trimmed.isEmpty ? [s.address.trimmed, s.province.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
                                                    : s.formAddress.trimmed
        location = address
        // locals: the closure below can't capture self before every property is set
        let pin = GPS.check(s.formGPS) == .ok ? GPS.parse(s.formGPS) : nil
        latitude = pin?.lat; longitude = pin?.lon
        let link = s.syncID.flatMap { Self.jobURL($0) }
        url = link

        var lines: [String] = []
        let coordinator = s.formCoordinator.trimmed.isEmpty ? s.customerName.trimmed : s.formCoordinator.trimmed
        if !coordinator.isEmpty { lines.append("ผู้ประสานงาน: " + coordinator) }
        let phone = s.formPhone.trimmed.isEmpty ? s.phone.trimmed : s.formPhone.trimmed
        if !phone.isEmpty { lines.append("โทร: " + phone) }
        let size = s.capacityKW > 0 ? "ขนาด \(Self.kw(s.capacityKW)) kW" : ""
        let team = [s.team.isEmpty ? "" : "ทีม: " + s.team, size].filter { !$0.isEmpty }.joined(separator: " | ")
        if !team.isEmpty { lines.append(team) }
        // to the pin when the form has one, else to the address
        let destination = pin.map { String(format: "%.6f,%.6f", $0.lat, $0.lon) }
            ?? (address.isEmpty ? nil : address.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed))
        if let destination {
            lines.append("นำทาง (Apple Maps): maps://?daddr=" + destination)
            lines.append("นำทาง (Google Maps): https://www.google.com/maps/dir/?api=1&destination=" + destination)
        }
        if let link { lines.append("เปิดงานใน TCRoof: " + link.absoluteString) }
        notes = lines.joined(separator: "\n")

        let dayBefore = cal.date(byAdding: .day, value: -1, to: day)!
        alarms = [.at(cal.date(bySettingHour: 17, minute: 0, second: 0, of: dayBefore)!)]
        if !isAllDay { alarms.append(.before(3600)) }
    }

    /// `tcroof://job/<syncID>`, which opens the job (`DeepLink(url:)`).
    public static func jobURL(_ syncID: String) -> URL? {
        guard let id = syncID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !id.isEmpty else { return nil }
        return URL(string: "tcroof://job/" + id)
    }

    /// "92.34", "5", "10.5".
    static func kw(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}

extension DeepLink {
    /// `tcroof://job/<syncID>` opens the job, `tcroof://job/<syncID>/survey` its survey form; nil for anything else.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "tcroof", url.host?.lowercased() == "job" else { return nil }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let id = parts.first, !id.isEmpty else { return nil }
        switch parts.dropFirst().first {
        case nil: self = .job(job: id)
        case "survey": self = .survey(job: id)
        default: return nil
        }
    }
}

private extension CharacterSet {
    /// A query value: no `&`, `=`, `+`, `?` or `#`.
    static let urlQueryValueAllowed: CharacterSet = {
        var c = CharacterSet.urlQueryAllowed
        c.remove(charactersIn: "&=+?#")
        return c
    }()
}
