import Foundation

public extension Assistant {

    /// Everything about one station besides its MP plan, as the `get_project` tool answers it: the job's basics, the
    /// NO.224 survey, the station's papers and ERC flow, the IEC 62446 test, the weekly requests, the ICL check list,
    /// scanned devices and install logs. Customer names, phones and addresses are never in it. Each part is nil when
    /// the station has none of it; lists are capped so one answer stays small.
    struct ProjectFacts: Codable, Equatable, Sendable {

        // MARK: Parts

        public struct Basics: Codable, Equatable, Sendable {
            public var code: String
            public var status: String
            public var province: String
            public var capacityKW: Double?
            public var inverterKW: Double?
            public var crew: String
            public var surveyDate: String?
            public var installStart: String
            public var installEnd: String
            public var hasMPPlan: Bool

            public init(code: String, status: String, province: String, capacityKW: Double?, inverterKW: Double?,
                        crew: String, surveyDate: String?, installStart: String, installEnd: String, hasMPPlan: Bool) {
                self.code = code; self.status = status; self.province = province; self.capacityKW = capacityKW
                self.inverterKW = inverterKW; self.crew = crew; self.surveyDate = surveyDate
                self.installStart = installStart; self.installEnd = installEnd; self.hasMPPlan = hasMPPlan
            }
        }

        /// One NO.224 survey report linked to the station.
        public struct Survey: Codable, Equatable, Sendable {
            public struct Section: Codable, Equatable, Sendable {
                public var code: String
                public var title: String
                public var percent: Int
                public var facts: String?
            }
            public var docNo: String
            public var date: String?
            public var percent: Int
            public var sections: [Section]
            /// "page: item" lines still to fill, at most `ProjectFacts.listLimit`.
            public var missing: [String]
            public var missingCount: Int
        }

        public struct Papers: Codable, Equatable, Sendable {
            public struct Package: Codable, Equatable, Sendable {
                public var title: String
                public var ready: Int
                public var total: Int
                public var due: String?
            }
            public struct Paper: Codable, Equatable, Sendable {
                public var package: String
                public var name: String
                public var status: String
                public var note: String?
                public var expires: String?
            }
            public var packages: [Package]
            /// Papers not ready yet (not signed, submitted or approved), at most `listLimit`.
            public var open: [Paper]
            public var openCount: Int
            /// Papers expired or expiring within 30 days.
            public var expiring: [Paper]
        }

        public struct ERC: Codable, Equatable, Sendable {
            public struct Wait: Codable, Equatable, Sendable {
                public var title: String
                public var since: String
                public var due: String
                public var left: String
            }
            public var flow: String
            public var headline: String
            public var waits: [Wait]
        }

        public struct IEC: Codable, Equatable, Sendable {
            public struct Step: Codable, Equatable, Sendable {
                public var number: Int
                public var title: String
                public var done: Bool
                public var confirmed: Bool
                public var missing: [String]
            }
            public struct Inverter: Codable, Equatable, Sendable {
                public var number: Int
                public var model: String?
                public var ratedKW: Double
                public var strings: Int
                public var installedKWp: Double
                public var pr: Double?
                public var passesBefore: Bool?
                public var passesAfter: Bool?
                /// Slots whose Voc is off the inverter's median.
                public var vocOutlierSlots: [Int]
            }
            /// `open`, `sent` (the contractor handed it over) or `closed` (the team closed it).
            public var state: String
            public var testDate: String?
            public var gridOn: String?
            public var stringCount: Int
            public var installedKWp: Double
            public var steps: [Step]
            public var inverters: [Inverter]
            public var passed: Bool?
            public var sentBackNote: String?
            /// `9 ภาพถ่ายติดตั้งระบบ`: photos taken and slots in all.
            public var installPhotosTaken: Int
            public var installPhotosTotal: Int
        }

        /// One week's request R1 (crew, work and risks the contractor plans).
        public struct Week: Codable, Equatable, Sendable {
            public var week: String
            public var state: String
            public var crew: Int
            public var work: [String]
            public var risks: [String]
        }

        /// The ICL acceptance check list.
        public struct ICL: Codable, Equatable, Sendable {
            public var stepsDone: Int
            public var steps: Int
            public var allPassed: Bool
            public var submitted: String?

            public init(stepsDone: Int, steps: Int, allPassed: Bool, submitted: String?) {
                self.stepsDone = stepsDone; self.steps = steps; self.allPassed = allPassed; self.submitted = submitted
            }
        }

        // MARK: Fields

        public var jobID: String
        public var station: String
        public var mpNumber: Int?
        public var today: String
        public var basics: Basics
        public var surveys: [Survey]
        public var papers: Papers?
        public var erc: ERC?
        public var iec: IEC?
        /// The latest weeks' requests, newest first.
        public var weeklyRequests: [Week]
        public var icl: ICL?
        /// Scanned serials by device kind (`แผง`: 120).
        public var devices: [String: Int]
        public var installLogs: Int
        public var lastInstallLog: String?
        /// Upcoming inspections by the PWA representative (`yyyy-MM-dd HH:mm subject`).
        public var inspections: [String]

        static let listLimit = 25

        /// The parts `get_project` can be asked for; the station's name and `basics` always come.
        public enum Section: String, CaseIterable, Sendable {
            case survey, papers, erc, iec, weekly, icl, devices, logs, inspections

            var keys: [String] {
                switch self {
                case .survey: ["surveys"]
                case .weekly: ["weeklyRequests"]
                case .logs: ["installLogs", "lastInstallLog"]
                default: [rawValue]
                }
            }

            /// The sections named in a tool call's `sections`; all of them when it names none it knows.
            static func parse(_ v: JSONValue?) -> Set<Section> {
                guard case .array(let items) = v ?? .null else { return Set(allCases) }
                let picked = Set(items.compactMap { $0.string.flatMap(Section.init(rawValue:)) })
                return picked.isEmpty ? Set(allCases) : picked
            }
        }

        /// Compact JSON for the model: keys sorted, only `sections`, and no empty lists or objects (the system prompt
        /// tells the model a part left out means there is none).
        public func json(_ sections: Set<Section> = Set(Section.allCases)) -> String {
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? e.encode(self), let full = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(var o) = full else { return "{}" }
            for s in Section.allCases where !sections.contains(s) { for k in s.keys { o.removeValue(forKey: k) } }
            return Toolbox.encode(Self.pruned(.object(o)) ?? .object([:]))
        }

        /// Drops empty arrays and objects, at any depth.
        static func pruned(_ v: JSONValue) -> JSONValue? {
            switch v {
            case .array(let a):
                let kept = a.compactMap(pruned)
                return kept.isEmpty ? nil : .array(kept)
            case .object(let o):
                let kept = o.compactMapValues(pruned)
                return kept.isEmpty ? nil : .object(kept)
            default: return v
            }
        }

        // MARK: Building

        /// - Parameters:
        ///   - surveys: the NO.224 reports linked to the station.
        ///   - stationDocs: the station's papers, with the shared library and the facts its size gives; nil for a job
        ///     that isn't a PWA station.
        ///   - devices: scanned serials by device kind's title.
        public init(jobID: String, station: String, mpNumber: Int?, basics: Basics, surveys: [TCRoofCore.Job] = [],
                    stationDocs: StationDocs.Station? = nil, library: StationDocs.Library = .init(),
                    docsContext: StationDocs.Context? = nil, ercContext: ERCFlow.Context = .init(),
                    iec: IECReport? = nil, weeklyRequests: [RoutineReport.WeeklyRequest] = [], icl: ICL? = nil,
                    devices: [String: Int] = [:], installLogs: [Date] = [], inspections: [RoutineReport.Inspection] = [],
                    today: Date, calendar cal: Calendar = MasterSchedule.calendar) {
            let day = { (d: Date) in ScheduleBrief.day(d, calendar: cal) }
            self.jobID = jobID
            self.station = station
            self.mpNumber = mpNumber
            self.today = day(today)
            self.basics = basics
            self.surveys = surveys.map { Self.survey($0) }
            if let stationDocs, let docsContext {
                papers = Self.papers(stationDocs, library: library, docsContext, today: today, calendar: cal)
                erc = stationDocs.erc.map { Self.erc($0, ercContext, today: today) }
            }
            self.iec = iec.map { Self.iec($0, calendar: cal) }
            self.weeklyRequests = weeklyRequests.sorted { $0.weekStart > $1.weekStart }.prefix(4).map { w in
                let state = w.approvedAt != nil ? "approved" : w.sentAt != nil ? "sent" : "draft"
                return Week(week: day(w.weekStart), state: state, crew: w.crew.reduce(0) { $0 + $1.count },
                            work: w.work.prefix(Self.listLimit).map { l in
                                [l.task?.code, l.description, l.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                            },
                            risks: w.risks.filter { !$0.description.isEmpty }.map { "\($0.level.title): \($0.description)" })
            }
            self.icl = icl
            self.devices = devices
            self.installLogs = installLogs.count
            lastInstallLog = installLogs.max().map(day)
            let start = cal.startOfDay(for: today)
            let time = DateFormatter()
            time.calendar = cal; time.timeZone = cal.timeZone; time.locale = Locale(identifier: "en_US_POSIX")
            time.dateFormat = "yyyy-MM-dd HH:mm"
            self.inspections = inspections.filter { $0.at >= start }.sorted { $0.at < $1.at }.prefix(10).map {
                [time.string(from: $0.at), $0.subject].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }

        static func survey(_ r: TCRoofCore.Job) -> Survey {
            let sections = r.sectionsByCategory.flatMap(\.sections).map { s in
                let facts = r.facts(s.module)
                return Survey.Section(code: s.number, title: s.module.title, percent: s.module.completion.percent,
                                      facts: facts.isEmpty ? nil : facts)
            }
            let missing = r.missingItems
            let date = r.values.text("date")
            return Survey(docNo: r.docNo, date: date.isEmpty ? nil : date, percent: r.completion.percent,
                          sections: sections, missing: Array(missing.prefix(listLimit)), missingCount: missing.count)
        }

        static func papers(_ s: StationDocs.Station, library: StationDocs.Library, _ ctx: StationDocs.Context,
                           today: Date, calendar cal: Calendar) -> Papers {
            let day = { (d: Date) in ScheduleBrief.day(d, calendar: cal) }
            var open: [Papers.Paper] = [], expiring: [Papers.Paper] = []
            var seen = Set<String>()
            let packages = StationDocs.packages(ctx).map { pkg in
                for kind in StationDocs.papers(in: pkg, ctx) where seen.insert(kind.id).inserted {
                    let state = StationDocs.state(kind, station: s, library: library)
                    let paper = Papers.Paper(package: pkg.title, name: kind.name, status: state.status.title,
                                             note: state.note.isEmpty ? nil : state.note, expires: state.expiresAt.map(day))
                    if state.status != .notNeeded, !state.status.isReady { open.append(paper) }
                    if StationDocs.expiry(kind, state, on: today, calendar: cal) != nil { expiring.append(paper) }
                }
                let p = StationDocs.progress(pkg, station: s, library: library, ctx)
                return Papers.Package(title: pkg.title, ready: p.ready, total: p.total, due: s.due(pkg).map(day))
            }
            return Papers(packages: packages, open: Array(open.prefix(listLimit)), openCount: open.count, expiring: expiring)
        }

        static func erc(_ r: ERCFlow.Record, _ ctx: ERCFlow.Context, today: Date) -> ERC {
            ERC(flow: r.variant(ctx).title, headline: ERCFlow.headline(r, ctx),
                waits: ERCFlow.waits(r, ctx, today: today).map { .init(title: $0.title, since: $0.since, due: $0.due, left: $0.text) })
        }

        static func iec(_ r: IECReport, calendar cal: Calendar) -> IEC {
            let day = { (d: Date) in ScheduleBrief.day(d, calendar: cal) }
            let steps = IECReport.Stage.allCases.map { s in
                IEC.Step(number: s.rawValue, title: s.title, done: r.isDone(s), confirmed: r.isConfirmed(s),
                         missing: Array(r.missing(s).prefix(10)))
            }
            let inverters = r.inverters.enumerated().map { i, inv in
                IEC.Inverter(number: i + 1, model: inv.model, ratedKW: inv.ratedKW, strings: inv.strings.count,
                             installedKWp: IECReport.round2(r.installedKWp(inv)), pr: r.pr(inv).map(IECReport.round2),
                             passesBefore: r.passes(inv, .before), passesAfter: r.passes(inv, .after),
                             vocOutlierSlots: r.vocOutliers(inv))
            }
            let slots = r.installPages.flatMap(\.slots)
            return IEC(state: r.lockState.rawValue, testDate: r.testDate.map(day), gridOn: r.gridOnAt.map(day),
                       stringCount: r.stringCount, installedKWp: IECReport.round2(r.installedKWp), steps: steps,
                       inverters: inverters, passed: r.result?.passed,
                       sentBackNote: r.sentBack.flatMap { $0.note.isEmpty ? nil : $0.note },
                       installPhotosTaken: slots.filter { r.installPhoto($0) != nil }.count, installPhotosTotal: slots.count)
        }
    }
}
