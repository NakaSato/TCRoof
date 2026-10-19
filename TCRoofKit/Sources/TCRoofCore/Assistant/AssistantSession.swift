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
        @ObservationIgnored public var maxRounds = 5
        /// Messages kept after the system prompt; older turns are dropped whole.
        @ObservationIgnored public var historyLimit = 30
        /// Characters of the messages sent (the function refuses more than 80,000 with the tools); older turns go first.
        @ObservationIgnored public var charLimit = 60_000

        /// - Parameters:
        ///   - focus: the job the chat was opened from, if any.
        ///   - jobs: the stations the person may see, read fresh for every tool call.
        public init(transport: Transport, focus: Job? = nil, jobs: @escaping @MainActor () -> [Job],
                    now: @escaping () -> Date = Date.init) {
            self.transport = transport
            self.jobs = jobs
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
                    let outcome = box.run(call.function.name, arguments: call.function.arguments)
                    if case .proposal(let a, _) = outcome {
                        proposals.removeAll { $0.jobID == a.jobID && ($0.task == a.task || a.isReplan) && Self.sameKind($0.change, a.change) }
                        proposals.append(a)
                    }
                    messages.append(.tool(call.id, outcome.text))
                }
            }
            throw Failure.tooManyRounds
        }

        /// Takes a proposal off the list (confirmed and saved by the app, or dismissed) and tells the model.
        public func resolve(_ id: String, confirmed: Bool) {
            guard let a = proposals.first(where: { $0.id == id }) else { return }
            proposals.removeAll { $0.id == id }
            let what = confirmed ? "ผู้ใช้ยืนยันและบันทึกแล้ว" : "ผู้ใช้ยกเลิก ไม่ได้บันทึก"
            messages.append(.user("[ระบบ] \(a.station) · \(a.title): \(a.after) — \(what)"))
        }

        /// The system prompt and the latest `historyLimit` messages, starting at a person's message so a tool answer
        /// never loses the call it answers.
        func trimmed() -> [Message] {
            let rest = messages.dropFirst()
            var start = max(rest.startIndex, rest.endIndex - historyLimit)
            func nextTurn(from i: Int) -> Int {
                var i = i
                while i < rest.endIndex, rest[i].role != .user { i += 1 }
                return i
            }
            start = nextTurn(from: start)
            func size(_ m: Message) -> Int { (m.content?.count ?? 0) + (m.toolCalls ?? []).reduce(0) { $0 + $1.function.arguments.count + 64 } + 32 }
            var total = size(messages[0]) + rest[start...].reduce(0) { $0 + size($1) }
            // keep at least the latest turn, even when it alone is long
            let last = rest.lastIndex { $0.role == .user } ?? start
            while total > charLimit, start < last {
                let next = nextTurn(from: start + 1)
                total -= rest[start..<next].reduce(0) { $0 + size($1) }
                start = next
            }
            return [messages[0]] + rest[start...]
        }

        private static func sameKind(_ a: PendingAction.Change, _ b: PendingAction.Change) -> Bool {
            switch (a, b) {
            case (.progress, .progress), (.dates, .dates), (.lateCause, .lateCause), (.replan, .replan): true
            default: false
            }
        }

        static func systemPrompt(today: Date, focus: Job?) -> String {
            let day = ScheduleBrief.day(today, calendar: MasterSchedule.calendar)
            var s = """
            คุณคือผู้ช่วยโครงการก่อสร้างของ TC Renewable Energy ช่วยทีมรักษาแผนงาน MP ของสถานีโซลาร์ กปภ. ให้ตรงเวลา
            วันนี้คือ \(day) (เวลาไทย สัปดาห์เริ่มวันอาทิตย์)

            กติกา:
            - ตอบเป็นภาษาไทย สั้น ตรงประเด็น ใช้รายการเมื่อมีหลายข้อ
            - ตัวเลขทุกตัว (%, คะแนน, วันที่, จำนวนวันที่ช้า) ต้องมาจากผลของเครื่องมือเท่านั้น ห้ามคำนวณหรือเดาเอง
            - ข้อมูลที่ไม่มีในเครื่องมือ ให้บอกว่าไม่มีข้อมูล
            - งานแต่ละงานมีน้ำหนักเป็นคะแนน (รวมทั้งสถานี 100) neededPointsPerWeek คือคะแนนต่อสัปดาห์ที่ต้องทำเพื่อให้เสร็จตามแผน (งานที่เลยกำหนดแล้วคือคะแนนที่เหลือทั้งหมด)
              pacePointsPerWeek คืออัตราที่ทำได้จริง slipDays คือจำนวนวันที่คาดว่าจะเสร็จช้ากว่าแผน
            - วันส่งมอบที่คาดของสถานี ให้อ้าง handoverForecast และ handoverSlipDays (ตรงกับ "คาดส่งมอบ" ในหน้าติดตามงาน คิดจาก SPI)
              ส่วน projectedFinish และผลของ what_if คิดรายงานตามอัตราของแต่ละงาน ใช้เทียบทางเลือกและบอกว่าได้คืนกี่วัน
              ถ้าสองค่าต่างกัน ให้บอกว่าแบบรายงานละเอียดกว่า และระบุทั้งสองค่า
            - เมื่อแนะนำการเร่งงาน ให้เรียงตามงานที่กระทบวันจบมากที่สุด และอ้างรายงานประจำวัน (คน ฝน ปัญหา) ถ้ามี
            - การบันทึกทุกอย่างทำผ่านเครื่องมือ propose_* เท่านั้น ซึ่งยังไม่บันทึกจนกว่าผู้ใช้จะกดยืนยันในการ์ด
              ห้ามบอกว่าบันทึกแล้วจนกว่าจะได้ข้อความ [ระบบ] ว่าผู้ใช้ยืนยัน
            - เสนอบันทึกเฉพาะเมื่อผู้ใช้ขอ หรือเมื่อรายงานประจำวันระบุ % ชัดเจน และบอกที่มาของตัวเลข

            การวางกลยุทธ์ (ตัวเลขมาจากเครื่องมือเสมอ คุณเป็นผู้อธิบายและแนะนำ):
            - สถานีช้า ให้ใช้ what_if เทียบทางเลือก (เพิ่มคน เพิ่มวันทำงาน เริ่มงานคู่ขนาน) แล้วแนะนำทางที่ได้วันคืนมากที่สุดต่อแรงที่เพิ่ม
              บอก toFinishOnTime (คน/วันทำงานที่ต้องใช้ และงานคอขวด) และบอกข้อสมมติใน note
            - ภาพรวมหลายสถานี ให้ใช้ station_priorities เรียงตาม riskScore ชี้สัปดาห์ที่ overloaded และเสนอย้ายคนตาม moves
            - แผนล่วงหน้าหรือเตรียมประชุม ให้ใช้ look_ahead ระบุงานที่รองานก่อนหน้า (waitingFor) นัดตรวจ กำหนดส่งเอกสาร และความเสี่ยงฝน
            - ถ้าเร่งแล้วยังไม่ทัน ให้ใช้ suggest_replan แล้วเสนอ propose_replan ด้วยวันที่จากผลนั้นเท่านั้น
              และบอกว่าแผนเดิมจะถูกแทนที่ ต้องให้ผู้มีสิทธิ์ตั้งค่าแผนยืนยัน
            - คำแนะนำแต่ละข้อให้ระบุ ทำอะไร ที่สถานีไหน ภายในวันไหน และได้ผลกี่วัน
            """
            if let focus {
                s += "\n\nผู้ใช้เปิดผู้ช่วยจากสถานี \(focus.station) (job: \(focus.id)"
                    + (focus.mpNumber.map { ", MP \($0)" } ?? "") + ") ถ้าไม่ระบุสถานี ให้หมายถึงสถานีนี้"
            }
            return s
        }
    }
}
