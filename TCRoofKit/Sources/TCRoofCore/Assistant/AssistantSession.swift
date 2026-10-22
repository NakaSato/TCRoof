import Foundation
import Observation

public extension Assistant {

    /// One conversation: sends the person's message, runs the tools the model calls (at most `maxRounds` rounds), and
    /// collects the changes it proposes. Kept on the device only; observable, so the chat screen follows it.
    @MainActor
    @Observable
    final class Session {
        public private(set) var messages: [Message]
        /// Proposed changes not yet confirmed or dismissed, oldest first.
        public private(set) var proposals: [PendingAction] = []
        public private(set) var remainingToday: Int?

        @ObservationIgnored private let transport: Transport
        @ObservationIgnored private let jobs: @MainActor () -> [Job]
        @ObservationIgnored private let now: () -> Date
        /// Builds `get_project`'s facts of one station, on demand (the app reads them from its models).
        @ObservationIgnored private let project: @MainActor (Job) -> ProjectFacts?
        @ObservationIgnored public var maxRounds = 5
        /// Messages kept after the system prompt; older turns are dropped whole.
        @ObservationIgnored public var historyLimit = 30
        /// Characters of the messages sent (the function refuses more than 80,000 with the tools); older turns go first.
        @ObservationIgnored public var charLimit = 60_000

        /// - Parameters:
        ///   - focus: the job the chat was opened from, if any.
        ///   - jobs: the stations the person may see, read fresh for every tool call.
        ///   - project: the rest of a station's project for `get_project`; by default the job's own `project`.
        public init(transport: Transport, focus: Job? = nil, jobs: @escaping @MainActor () -> [Job],
                    project: @escaping @MainActor (Job) -> ProjectFacts? = { $0.project },
                    now: @escaping () -> Date = Date.init) {
            self.transport = transport
            self.jobs = jobs
            self.project = project
            self.now = now
            messages = [.system(Self.systemPrompt(today: now(), focus: focus))]
        }

        /// Sends `text` and returns once the model answers in words.
        @discardableResult
        public func send(_ text: String) async throws -> Message {
            messages.append(.user(text))
            for _ in 0..<maxRounds {
                let reply = try await transport.complete(Request(messages: trimmed(), tools: Toolbox.definitions))
                remainingToday = reply.remainingToday ?? remainingToday
                let m = reply.message
                messages.append(m)
                guard let calls = m.toolCalls, !calls.isEmpty else {
                    guard m.content?.isEmpty == false else { throw Failure.emptyReply }
                    return m
                }
                let box = Toolbox(jobs: jobs(), today: now())
                for call in calls {
                    let outcome = call.function.name == "get_project"
                        ? projectFacts(box, arguments: call.function.arguments)
                        : box.run(call.function.name, arguments: call.function.arguments)
                    if case .proposal(let a, _) = outcome {
                        proposals.removeAll { $0.jobID == a.jobID && ($0.task == a.task || a.isReplan) && Self.sameKind($0.change, a.change) }
                        proposals.append(a)
                    }
                    messages.append(.tool(call.id, outcome.text))
                }
            }
            throw Failure.tooManyRounds
        }

        /// `get_project`, with the facts built here only for the station asked.
        private func projectFacts(_ box: Toolbox, arguments: String) -> Toolbox.Outcome {
            let args = JSONValue.parse(arguments.isEmpty ? "{}" : arguments) ?? .object([:])
            switch box.single(args["job"]?.string ?? "") {
            case .failure(let e): return e
            case .found(let job):
                guard let f = project(job) else { return box.error("ไม่มีข้อมูลโครงการของ \(job.station)") }
                return .result(f.json(ProjectFacts.Section.parse(args["sections"])))
            }
        }

        /// Takes a proposal off the list (confirmed and saved by the app, or dismissed) and tells the model.
        public func resolve(_ id: String, confirmed: Bool) {
            guard let a = proposals.first(where: { $0.id == id }) else { return }
            proposals.removeAll { $0.id == id }
            let what = confirmed ? "ผู้ใช้ยืนยันและบันทึกแล้ว" : "ผู้ใช้ยกเลิก ไม่ได้บันทึก"
            messages.append(.user("[ระบบ] \(a.station) | \(a.title): \(a.after) — \(what)"))
        }

        /// The system prompt and the latest `historyLimit` messages, starting at a person's message so a tool answer
        /// never loses the call it answers.
        func trimmed() -> [Message] {
            let rest = messages.dropFirst()
            // the latest turn is sent whole; tool results of earlier questions go as a short note (the model's answer
            // carries what it took from them, and it can call again)
            let last = rest.lastIndex { $0.role == .user } ?? rest.endIndex
            let sent = rest.indices.map { $0 < last ? Self.compacted(rest[$0]) : rest[$0] }
            func at(_ i: Int) -> Message { sent[i - rest.startIndex] }
            var start = max(rest.startIndex, rest.endIndex - historyLimit)
            func nextTurn(from i: Int) -> Int {
                var i = i
                while i < rest.endIndex, rest[i].role != .user { i += 1 }
                return i
            }
            start = nextTurn(from: start)
            func size(_ m: Message) -> Int { (m.content?.count ?? 0) + (m.toolCalls ?? []).reduce(0) { $0 + $1.function.arguments.count + 64 } + 32 }
            var total = size(messages[0]) + (start..<rest.endIndex).reduce(0) { $0 + size(at($1)) }
            // keep at least the latest turn, even when it alone is long
            while total > charLimit, start < last {
                let next = nextTurn(from: start + 1)
                total -= (start..<next).reduce(0) { $0 + size(at($1)) }
                start = next
            }
            return [messages[0]] + (start..<rest.endIndex).map(at)
        }

        /// What an earlier question's tool result is sent as: a short note in place of a long result.
        static let droppedResult = #"{"note":"result of an earlier question, dropped to save tokens; call the tool again if needed"}"#

        static func compacted(_ m: Message) -> Message {
            guard m.role == .tool, (m.content?.count ?? 0) > droppedResult.count else { return m }
            var c = m
            c.content = droppedResult
            return c
        }

        private static func sameKind(_ a: PendingAction.Change, _ b: PendingAction.Change) -> Bool {
            switch (a, b) {
            case (.progress, .progress), (.dates, .dates), (.lateCause, .lateCause), (.replan, .replan): true
            default: false
            }
        }

        /// In English, which takes far fewer tokens than Thai; the model is told to answer in Thai.
        static func systemPrompt(today: Date, focus: Job?) -> String {
            let day = ScheduleBrief.day(today, calendar: MasterSchedule.calendar)
            var s = """
            You are TC Renewable Energy's construction assistant for PWA (กปภ.) solar stations, keeping each station's MP plan on time.
            Today is \(day) (Thai time; weeks start Sunday).
            Rules:
            - Answer in Thai, short and to the point; use lists for several items.
            - Every number (%, points, dates, days late) must come from a tool result. Never compute or guess. If no tool has it, say there is no data.
            - Tasks carry weight in points (100 per station). neededPointsPerWeek = points per week to finish on plan (overdue: all remaining); pacePointsPerWeek = actual pace; slipDays = expected days late.
            - A station's expected handover: quote handoverForecast and handoverSlipDays (the tracking page's "คาดส่งมอบ", from SPI). projectedFinish and what_if are task by task: use them to compare options and days gained. If they differ, say the task-by-task one is more detailed and give both.
            - A re-planned station has originalInstallEnd and originalPlannedPercent (every other planned % is against the new plan); quote them when asked about the original plan.
            - When advising how to speed up, rank by impact on the finish date and cite daily reports (crew, rain, problems) when present.
            - Other project topics (survey, station papers, ERC flow, IEC test, weekly requests, ICL, devices, inspections): call get_project with only the sections needed (a part missing from its answer means there is none). When advising on the plan, check for papers or tests that would block handover.
            - Saving only goes through propose_* tools, which save nothing until the user confirms the card. Never say it is saved before a [ระบบ] message says the user confirmed.
            - Propose only when asked, or when a daily report states a clear %; say where the number came from.
            - Results of earlier questions are dropped from the history; call the tool again when you need them.
            Strategy (numbers always from tools; you explain and recommend):
            - Late station: what_if to compare options (more crew, more working days, start tasks in parallel); recommend the most days gained per extra effort; give toFinishOnTime (crew / working days needed, bottleneck task) and the assumptions in note.
            - All stations: station_priorities ranked by riskScore; point out overloaded weeks; suggest crew moves from moves.
            - Look-ahead or meeting prep: look_ahead; name tasks waiting on earlier ones (waitingFor), inspections, paper deadlines, rain risk.
            - If speeding up can't make it: suggest_replan, then propose_replan with its dates only; say the old plan is replaced and someone allowed to set up the plan must confirm.
            - Each recommendation: what, at which station, by when, and how many days it gains.
            """
            if let focus {
                s += "\nThe user opened the assistant from station \(focus.station) (job: \(focus.id)"
                    + (focus.mpNumber.map { ", MP \($0)" } ?? "") + "). When no station is named, it means this one."
            }
            return s
        }
    }
}
