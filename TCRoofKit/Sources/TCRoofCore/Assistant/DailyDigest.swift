import Foundation

public extension Assistant {

    /// `สรุปโดย AI` on the feed's daily summary (`FeedBuilder.summaries`): the day's numbers of every station, as one
    /// request with no tools, for the model to put into a few plain lines. Every number comes from `facts`; the model
    /// only words it. The app asks once a day per device (`FeedDigestStore`) and keeps the answer there.
    enum DailyDigest {

        public struct Facts: Codable, Equatable, Sendable {
            public struct Station: Codable, Equatable, Sendable {
                public var station: String
                public var reportSent: Bool
                /// The station's whole progress through the day, from its daily reports over the MP plan's weights.
                public var overallPercent: Double
                /// What the MP plan expects through the day's week; nil without a plan.
                public var plannedPercent: Double?
                /// Points gained that day.
                public var changeToday: Double
                public var crew: Int?
                public var rainHours: Int?
                public var stopReason: String?
                /// The day's work lines with their cumulative %, at most four.
                public var work: [String]
                /// Problems raised that day.
                public var newProblems: [String]
            }

            public var day: String
            public var reportsSent: Int
            public var reportsDue: Int
            /// The mean change of the stations due a report, in points.
            public var changeToday: Double
            public var openIssues: Int
            /// Stations due a report or that sent one, furthest behind their plan first.
            public var stations: [Station]
            /// `station: issue`, at most ten, oldest first.
            public var issues: [String]
        }

        static let workLines = 4, issueLines = 10

        /// The day's facts, nil when the feed has no summary that day (no station due a report or sending one, and no
        /// open issue). `stations` are the feed's own (`FeedBuilder.Station`), named without customer names.
        public static func facts(_ stations: [FeedBuilder.Station], day: Date, now: Date) -> Facts? {
            guard let s = FeedBuilder.summary(stations, day: day, now: now) else { return nil }
            let cal = FeedBuilder.calendar
            let key = RoutineReport.dayKey(day)
            func round(_ x: Double) -> Double { (x * 10).rounded() / 10 }
            let rows: [Facts.Station] = stations.compactMap { st in
                let report = st.signed.last { RoutineReport.dayKey($0.daily.date) == key }
                let due = st.installDay(on: day) != nil && RoutineReport.isWorkingDay(day, settings: st.settings)
                guard st.project == .pwa, report != nil || due else { return nil }
                let planned = st.plan.contains { $0.weight > 0 }
                    ? MasterSchedule.status(plan: st.plan, actual: .init(), through: day, calendar: cal).planned : nil
                let d = report?.daily
                let today = st.overall(through: day), before = st.overall(through: RoutineReport.add(day, -1))
                let rain: Int? = d.flatMap { $0.rainHours > 0 ? $0.rainHours : nil }
                let stop: String? = d.flatMap { $0.stopReason.isEmpty ? nil : $0.stopReason }
                let work: [String] = (d?.progress ?? []).prefix(workLines).map { "\($0.title) \(Int($0.percent.rounded()))%" }
                let raised: [String] = (d?.problems ?? []).filter { !$0.description.isEmpty && RoutineReport.dayKey($0.since) == key }
                    .map(\.description)
                return Facts.Station(
                    station: st.label, reportSent: report != nil,
                    overallPercent: round(today), plannedPercent: planned.map(round), changeToday: round(today - before),
                    crew: d.map(\.crewTotal), rainHours: rain, stopReason: stop, work: work, newProblems: raised)
            }
            .sorted { Self.gap($0) < Self.gap($1) }
            var open: [(date: Date, line: String)] = []
            for st in stations {
                let name = (st.project == .home ? "งานบ้าน " : "") + st.label
                for p in FeedBuilder.problemPosts(st) + FeedBuilder.punchPosts(st)
                where p.issue?.fixed == false && RoutineReport.day(p.date) <= RoutineReport.day(day) {
                    open.append((p.date, name + ": " + String(p.text.prefix(120))))
                }
            }
            let issues = open.sorted { $0.date < $1.date }.prefix(issueLines).map(\.line)
            return Facts(day: key, reportsSent: s.sent, reportsDue: s.due, changeToday: round(s.delta), openIssues: s.open,
                         stations: rows, issues: issues)
        }

        /// Points ahead of the plan (negative: behind); 0 without a plan.
        static func gap(_ s: Facts.Station) -> Double {
            guard let planned = s.plannedPercent else { return 0 }
            return s.overallPercent - planned
        }

        /// The request: an English instruction (fewer tokens) asking for plain Thai, and the facts as JSON.
        public static func request(_ f: Facts) -> Request {
            Request(messages: [.system(prompt), .user(json(f))], tools: [])
        }

        /// What the facts were when a digest was written: a different one means the day has news since.
        public static func json(_ f: Facts) -> String {
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? String(data: e.encode(f), encoding: .utf8)) ?? "{}"
        }

        static let prompt = """
            You write TCRoof's daily summary for the team's home feed: construction of PWA (กปภ.) solar stations. The user message is the day's facts as JSON.
            Write plain everyday Thai like an experienced site engineer telling the team, 3 to 5 short lines, under 600 characters:
            1. The day overall: reports sent of those due, and the progress.
            2. The stations that need attention and why: furthest behind plan (plannedPercent minus overallPercent), no report sent, rain or work stopped, new problems.
            3. Open issues, if any.
            4. What to focus on tomorrow.
            Every number must come from the facts; never compute new ones except the gap between plannedPercent and overallPercent. Never show field names, JSON or markdown headings. Never trade safety or quality for speed.
            """
    }
}
