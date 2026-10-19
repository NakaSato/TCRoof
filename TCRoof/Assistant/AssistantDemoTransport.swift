#if DEBUG
import Foundation
import TCRoofCore

/// `-assistantDemo YES`: stands in for Qwen so the chat can be tried without the Cloud Function. It calls the same
/// tools the model would (stations, then one station's schedule, then a proposal when asked to update) and answers
/// from their results, so every number shown is the app's own.
struct AssistantDemoTransport: Assistant.Transport {
    var delay: Duration = .milliseconds(400)

    func complete(_ r: Assistant.Request) async throws -> Assistant.Reply {
        try? await Task.sleep(for: delay)
        let asked = r.messages.lastIndex { $0.role == .user && !($0.content ?? "").hasPrefix("[ระบบ]") } ?? 0
        let question = r.messages[asked].content ?? ""
        let results = r.messages[asked...].filter { $0.role == .tool }.compactMap(\.content)
        let left = max(0, 50 - r.messages.filter { $0.role == .assistant }.count - 1)
        func call(_ name: String, _ args: String) -> Assistant.Reply {
            Assistant.Reply(message: .init(role: .assistant, content: nil,
                                           toolCalls: [.init(id: "demo-\(results.count)", name: name, arguments: args)]),
                            remainingToday: left)
        }
        func say(_ text: String) -> Assistant.Reply {
            Assistant.Reply(message: .init(role: .assistant, content: text), remainingToday: left)
        }

        let update = question.contains("อัปเดต") || question.contains("บันทึก")
        let draft = question.contains("ร่าง") || question.contains("สรุป")
        switch results.count {
        case 0:
            return call("list_stations", #"{"filter":"all","limit":10}"#)
        case 1:
            let stations = Self.array(JSONValue.parse(results[0])?["stations"])
            // the station the chat was opened from, else the one most behind
            let focus = Self.mpNumber(question) ?? Self.focusID(r.messages.first?.content)
            guard let id = focus ?? stations.first?["jobID"]?.string else { return say("ยังไม่มีสถานีที่มีแผน MP") }
            if !update, !draft, focus == nil {
                let lines = stations.prefix(5).map { s in
                    "- **\(s["station"]?.string ?? "")** แผน \(s["plannedPercent"]?.string ?? "–")% · ทำได้ \(s["actualPercent"]?.string ?? "–")%"
                        + (s["projectedSlipDays"]?.number.map { $0 > 0 ? " · คาดว่าช้า \(Int($0)) วัน" : "" } ?? "")
                }
                return say("สถานีที่ช้ากว่าแผนมากที่สุด:\n" + lines.joined(separator: "\n"))
            }
            return call("get_schedule", #"{"job":"\#(id)"}"#)
        case 2:
            guard let brief = try? JSONDecoder().decode(ScheduleBrief.self, from: Data(results[1].utf8)) else {
                return say(JSONValue.parse(results[1])?["error"]?.string ?? "อ่านแผนไม่ได้")
            }
            let open = brief.tasks.filter { $0.weight > 0 && $0.actualPercent < 100 && $0.state != .upcoming }
            if update, let t = open.first {
                let next = min(100, (t.actualPercent / 10).rounded(.down) * 10 + 10)
                return call("propose_progress", #"{"job":"\#(brief.jobID)","task":"\#(t.code)","percent":\#(Int(next))}"#)
            }
            let behind = open.sorted { ($0.slipDays ?? 0) > ($1.slipDays ?? 0) }.prefix(3)
            let tasks = behind.map { t in
                "- \(t.code) \(t.title): ทำได้ \(Self.num(t.actualPercent))% ต้องทำ \(Self.num(t.neededPointsPerWeek ?? 0)) คะแนน/สัปดาห์"
                    + (t.slipDays.map { $0 > 0 ? " · คาดว่าช้า \($0) วัน" : "" } ?? "")
            }
            let head = draft ? "**ร่างสรุปประชุมประจำสัปดาห์ · \(brief.station)**" : "**\(brief.station)**"
            return say(head + "\nแผน \(Self.num(brief.plannedPercent))% · ทำได้ \(Self.num(brief.actualPercent))%"
                       + (brief.projectedFinish.map { " · คาดว่าเสร็จ \($0)" } ?? "")
                       + (tasks.isEmpty ? "" : "\n\nงานที่ต้องเร่ง:\n" + tasks.joined(separator: "\n")))
        default:
            let p = JSONValue.parse(results[results.count - 1])
            if let e = p?["error"]?.string { return say(e) }
            return say("เสนอบันทึก \(p?["task"]?.string ?? "") เป็น \(p?["after"]?.string ?? "") ยังไม่ได้บันทึก กดยืนยันในการ์ดด้านล่าง")
        }
    }

    private static func array(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let a) = v { return a }
        return []
    }

    /// The job id the system prompt names (`(job: <id>`).
    private static func focusID(_ prompt: String?) -> String? {
        guard let p = prompt, let r = p.range(of: "(job: ") else { return nil }
        let rest = p[r.upperBound...]
        return rest.firstIndex { $0 == "," || $0 == ")" }.map { String(rest[..<$0]) }
    }

    /// `MP 190` named in the question.
    private static func mpNumber(_ q: String) -> String? {
        guard let r = q.range(of: #"MP\s*\d+"#, options: .regularExpression) else { return nil }
        return String(q[r])
    }

    private static func num(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
#endif
