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

        if let plan = Self.strategy(question, results, focus: Self.mpNumber(question) ?? Self.focusID(r.messages.first?.content),
                                    call: call, say: say) { return plan }

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

    /// The strategy chips: priorities, a recovery what-if, the look-ahead and a re-plan, answered from their tools.
    private static func strategy(_ q: String, _ results: [String], focus: String?,
                                 call: (String, String) -> Assistant.Reply, say: (String) -> Assistant.Reply) -> Assistant.Reply? {
        typealias S = Assistant.Strategy
        func decode<T: Decodable>(_ t: T.Type, _ i: Int) -> T? { try? JSONDecoder().decode(t, from: Data(results[i].utf8)) }
        func err(_ i: Int) -> Assistant.Reply { say(JSONValue.parse(results[i])?["error"]?.string ?? "อ่านผลไม่ได้") }

        if q.contains("จัดลำดับ") {
            guard results.count == 1 else { return call("station_priorities", "{}") }
            guard let p = decode(S.Priorities.self, 0) else { return err(0) }
            var out = ["**ลำดับความเสี่ยง**"] + p.stations.prefix(4).enumerated().map { i, s in
                "\(i + 1). \(s.station) · ช้า \(s.projectedSlipDays ?? 0) วัน · คะแนนเสี่ยง \(num(s.riskScore))"
                    + (s.crewNeeded.map { " · ต้องใช้ \($0) คน (มี \(num(s.crewAverage ?? 0)))" } ?? "")
            }
            let over = p.loads.filter(\.overloaded)
            if !over.isEmpty { out += ["", "**สัปดาห์ที่คนไม่พอ**"] + over.prefix(3).map { "- \($0.week) \($0.crewGroup): ต้องใช้ \($0.crewNeeded) คน มี \(num($0.crewNow))" } }
            if !p.moves.isEmpty { out += ["", "**ย้ายคนได้**"] + p.moves.map { "- \($0.crewGroup): \($0.from) → \($0.to) \($0.crew) คน" } }
            return say(out.joined(separator: "\n"))
        }
        let kind = q.contains("เร่งงานให้ทัน") ? "what_if" : q.contains("ล่วงหน้า") ? "look_ahead" : q.contains("แผนใหม่") ? "suggest_replan" : nil
        guard let kind else { return nil }
        if results.isEmpty { return call("list_stations", #"{"filter":"all","limit":10}"#) }
        if results.count == 1 {
            let stations = array(JSONValue.parse(results[0])?["stations"])
            guard let id = focus ?? stations.first?["jobID"]?.string else { return say("ยังไม่มีสถานีที่มีแผน MP") }
            return call(kind, kind == "what_if" ? #"{"job":"\#(id)","crew_change":4,"extra_days":1}"# : #"{"job":"\#(id)"}"#)
        }
        switch kind {
        case "what_if":
            guard let w = decode(S.WhatIf.self, 1) else { return err(1) }
            var out = ["**\(w.station)** ส่งมอบตามแผน \(w.installEnd) · คาดส่งมอบ \(w.handoverForecast) (ช้า \(w.handoverSlipDays) วัน ตามหน้าติดตามงาน)",
                       "", "ประมาณรายงาน:",
                       "- อัตราเดิม: เสร็จ \(w.base.stationFinish ?? "–") (ช้า \(w.base.slipDays ?? 0) วัน)"]
            if let s = w.scenario, let a = w.base.slipDays, let b = s.slipDays {
                out.append("- \(s.name): เสร็จ \(s.stationFinish ?? "–") (ช้า \(b) วัน · ได้คืน \(a - b) วัน)")
            }
            if let t = w.toFinishOnTime {
                out.append("- ให้ทันแผน: เร็วขึ้น \(num(t.paceFactor)) เท่า คอขวด \(t.bottleneck)"
                           + (t.crew.map { " · ใช้ \($0) คน" } ?? "") + (t.workingDaysPerWeek.map { " หรือทำงาน \($0) วัน/สัปดาห์" } ?? ""))
            }
            return say(out.joined(separator: "\n") + "\n\n_\(w.note)_")
        case "look_ahead":
            guard let l = decode(S.LookAhead.self, 1) else { return err(1) }
            var out = ["**แผนล่วงหน้า · \(l.station)**"]
            for w in l.weeks {
                out.append("สัปดาห์ \(w.week): " + (w.tasks.isEmpty ? "ไม่มีงานตามแผน" : w.tasks.map { t in
                    t.code + (t.waitingFor.isEmpty ? "" : " (รอ " + t.waitingFor.map { "\($0.code) \(num($0.actualPercent))%" }.joined(separator: ", ") + ")")
                }.joined(separator: ", ")) + (w.inspections.isEmpty ? "" : " · ตรวจ " + w.inspections.joined(separator: ", "))
                    + (w.deadlines.isEmpty ? "" : " · ส่ง " + w.deadlines.joined(separator: ", ")))
            }
            out.append("ฝน 14 วัน: \(l.weather.rainDays) วัน \(l.weather.rainHours) ชม.")
            return say(out.joined(separator: "\n"))
        default:
            if results.count == 2 {
                guard let r = decode(S.Replan.self, 1) else { return err(1) }
                guard !r.tasks.isEmpty else { return say("\(r.station) ไม่ต้องเลื่อนแผน") }
                let tasks = r.tasks.map { #"{"task":"\#($0.code)","start":"\#($0.newStart)","end":"\#($0.newEnd)"}"# }.joined(separator: ",")
                return call("propose_replan", #"{"job":"\#(r.jobID)","reason":"ตามอัตราที่ทำได้จริง","tasks":[\#(tasks)]}"#)
            }
            let p = JSONValue.parse(results[2])
            if let e = p?["error"]?.string { return say(e) }
            return say("เสนอ\(p?["task"]?.string ?? "แผนใหม่"): \(p?["after"]?.string ?? "") ยังไม่ได้บันทึก ผู้มีสิทธิ์ตั้งค่าแผนกดยืนยันในการ์ด")
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
