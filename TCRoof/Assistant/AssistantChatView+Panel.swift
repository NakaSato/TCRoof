import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPad install tracking page's ผู้ช่วยโครงการ panel (CHA-68, board "iPad · ติดตามงานติดตั้ง"): the blue header
/// with the station's line and ✕, the conversation as bubbles (the intro first, the person's in blue on the right, the
/// answers in white on the left with their dot points, `ที่มา:` and the proposal inside), and the white composer with the
/// station's prompt chips, the field and the footnote. The session, tools, permissions and confirming are the sheet's.
extension AssistantChatView {

    var panelBody: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        panelIntro
                        ForEach(lines) { panelRow($0) }
                        // a proposal waiting for the answer's words (or left by a failure) stands alone
                        if proposalHost == nil {
                            ForEach(session.proposals) { p in proposalBox(p).padding(.trailing, 48) }
                        }
                        if sending { AssistantThinkingBubble() }
                        if let failure { failureLine(failure) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: sending) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .background(Theme.background)
            .overlay(alignment: .bottom) { if let toast { savedToast(toast) } }
            panelComposer
        }
        .accessibilityAction(.escape) { onClose() }
    }

    // MARK: header

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("ผู้ช่วยโครงการ").font(.sarabun(17, .bold, relativeTo: .headline))
                    .accessibilityAddTraits(.isHeader)
                if !stationLine.isEmpty {
                    Text(stationLine).font(.sarabun(13, relativeTo: .caption)).opacity(0.9)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Button { restart() } label: {
                Label("เริ่มใหม่", systemImage: "arrow.counterclockwise")
                    .font(.sarabun(14, .semibold, relativeTo: .subheadline))
                    .padding(.horizontal, 12).frame(minHeight: touchMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sending || lines.isEmpty)
            .opacity(sending || lines.isEmpty ? 0.5 : 1)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.onPrimary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
            .accessibilityIdentifier("assistantClose")
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.headerGradient)
    }

    /// `<station> · แผน MP · รายงานประจำวันถึง 30/9`.
    static func stationLine(_ job: Job?) -> String {
        guard let job else { return "" }
        var parts = [job.assistantStation]
        if job.scheduleInput != nil { parts.append("แผน MP") }
        if let last = job.dailyReports.map(\.date).max() {
            parts.append("รายงานประจำวันถึง " + ThaiFormat.dayMonth.string(from: last))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: conversation

    /// The assistant's first bubble: what it answers and what it reads.
    private var panelIntro: some View {
        let station = focus?.assistantStation
        let text = "สวัสดีครับ ถามเรื่อง" + (station.map { "งาน \($0) " } ?? "งานนี้") + "ได้เลย เช่น งานไหนเสี่ยงช้า "
            + "สรุปสัปดาห์นี้ หรือต้องเตรียมอะไรสัปดาห์หน้า ผมอ่านจากแผน MP รายงานประจำวัน และเอกสารของสถานีนี้"
        return Text(text)
            .font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .assistantBubble()
            .padding(.trailing, 48)
            .accessibilityIdentifier("assistantIntro")
    }

    /// The last answer carries the open proposals inside its bubble.
    private var proposalHost: Int? {
        guard !session.proposals.isEmpty, let last = lines.last, case .assistant = last.kind else { return nil }
        return last.id
    }

    @ViewBuilder private func panelRow(_ line: Line) -> some View {
        switch line.kind {
        case .person:
            Text(line.text)
                .font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 96)
        case .assistant:
            AssistantAnswerBubble(text: line.text, sources: sources(answeredAt: line.id)) {
                if line.id == proposalHost {
                    ForEach(session.proposals) { p in proposalBox(p) }
                }
            }
            .padding(.trailing, 48)
        case .note(let confirmed):
            Label(line.text, systemImage: confirmed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.sarabun(14, relativeTo: .subheadline))
                .foregroundStyle(confirmed ? Theme.successText : Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier(confirmed ? "assistantSaved" : "assistantDismissed")
        }
    }

    private func proposalBox(_ p: Assistant.PendingAction) -> some View {
        AssistantProposalBox(action: p, confirm: { confirm(p) }, dismiss: { resolve(p, false) })
            .disabled(sending)
    }

    /// `ที่มา`: what the tools called for this answer read, in the order first called; none when it called none.
    private func sources(answeredAt index: Int) -> [String] {
        let messages = session.messages
        guard messages.indices.contains(index) else { return [] }
        var names: [String] = []
        var i = index - 1
        while i > 0, messages[i].role != .user {
            for call in (messages[i].toolCalls ?? []).reversed() {
                names.insert(contentsOf: Self.sourceNames(call.function.name, arguments: call.function.arguments), at: 0)
            }
            i -= 1
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    static func sourceNames(_ tool: String, arguments: String) -> [String] {
        switch tool {
        case "list_stations": return ["รายชื่อสถานี"]
        case "get_schedule", "propose_progress", "propose_dates", "propose_late_cause", "suggest_replan", "propose_replan":
            return ["แผน MP"]
        case "get_week_tasks": return ["แผน MP", "รายงานประจำวัน"]
        case "what_if": return ["แผน MP", "รายงานประจำวัน"]
        case "station_priorities": return ["แผน MP ทุกสถานี"]
        case "look_ahead": return ["แผน MP", "รายงานประจำวัน"]
        case "get_project":
            let named: [String: String] = ["survey": "รายงานสำรวจ", "papers": "เอกสารสถานี", "erc": "ลำดับ กกพ.",
                                           "iec": "ทดสอบ IEC", "weekly": "คำขอรายสัปดาห์", "icl": "ICL",
                                           "devices": "อุปกรณ์", "logs": "บันทึกติดตั้ง", "inspections": "การตรวจ"]
            var asked: [String] = []
            if case .array(let a)? = JSONValue.parse(arguments)?["sections"] { asked = a.compactMap(\.string) }
            let list = asked.compactMap { named[$0] }
            return list.isEmpty ? ["ข้อมูลสถานี"] : list
        default: return []
        }
    }

    // MARK: toast

    static func savedToast(_ a: Assistant.PendingAction) -> String {
        let what: String
        switch a.change {
        case .progress: what = "บันทึกความก้าวหน้าแล้ว"
        case .lateCause: what = "บันทึกสาเหตุล่าช้าแล้ว"
        case .dates, .replan: what = "ปรับแผนแล้ว"
        }
        return what + " · " + a.title
    }

    private func savedToast(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ringDone)
            Text(message).lineLimit(2)
            if let openPlan {
                Button { toast = nil; openPlan() } label: {
                    Text("ดูในแผนก่อสร้าง").font(.sarabun(14, .bold, relativeTo: .subheadline)).underline()
                        .frame(minHeight: touchMin).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.onMedia)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .frame(minHeight: touchMin)
        .background(Theme.toast, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistantToast")
        .task(id: message) {
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: composer

    /// This station's questions first, then the plan tools the person may use.
    var panelPrompts: [String] {
        var p = ["งานไหนเสี่ยงช้า?", "สรุปสัปดาห์นี้", "ต้องเตรียมอะไรสัปดาห์หน้า?", "วางแผนเร่งงานให้ทันกำหนด",
                 "เอกสารและการทดสอบที่ค้าง"]
        if permissions.can(.mpProgress, on: focus?.access) { p.append("อัปเดตความก้าวหน้าจากรายงานประจำวัน") }
        if permissions.can(.mpSetup, on: focus?.access) { p.append("เสนอแผนใหม่ที่ทำได้จริง") }
        return p
    }

    private var panelComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(panelPrompts, id: \.self) { s in
                        Button { send(s) } label: {
                            Text(s).font(.sarabun(15, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(Theme.navy)
                                .padding(.horizontal, 16).frame(minHeight: touchMin)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.borderSubtle, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(sending)
            .opacity(sending ? 0.5 : 1)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("ถามเรื่องงานนี้…", text: $draft, axis: .vertical)
                    .font(.sarabun(16, relativeTo: .body))
                    .lineLimit(1...4)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl.opacity(0.6)))
                    .accessibilityIdentifier("assistantInput")
                Button { send(draft) } label: {
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Theme.onPrimary)
                        .background(canSend ? Theme.primary : Theme.inkFaint,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("ส่ง")
            }
            HStack(spacing: 8) {
                Text("คำตอบอ้างอิงข้อมูลในแอป · การปรับแผนต้องกดยืนยันก่อนเสมอ")
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if let n = session.remainingToday {
                    Text("วันนี้ใช้ได้อีก \(n) คำถาม" + (session.servedBy.map { " | ตอบโดย " + $0 } ?? ""))
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityIdentifier("assistantServedBy")
                }
            }
            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

private extension View {
    /// A white bubble with a thin border, as the assistant speaks.
    func assistantBubble() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

/// An answer as the panel draws it: a bold first line, Markdown bullets as lines with a dot (coloured only when the line
/// starts with a known marker), other lines as text, then `ที่มา:` and `คัดลอก`, and the open proposals under them.
struct AssistantAnswerBubble<Proposals: View>: View {
    let text: String
    let sources: [String]
    @ViewBuilder let proposals: () -> Proposals
    @State private var copied = false

    struct Part: Identifiable, Equatable {
        enum Kind: Equatable { case head, text, point(Mark?), gap }
        enum Mark: Equatable { case good, watch, risk, todo }
        let id: Int
        let kind: Kind
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.parts(text)) { part($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // one element for VoiceOver and the UI tests, as the sheet's answer
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.replacingOccurrences(of: "**", with: ""))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("assistantAnswer")
            HStack(spacing: 8) {
                if !sources.isEmpty {
                    Text("ที่มา: " + sources.joined(separator: " · "))
                        .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                } label: {
                    Label(copied ? "คัดลอกแล้ว" : "คัดลอก", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.sarabun(12, .semibold, relativeTo: .caption))
                        .frame(minHeight: touchMin).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
            }
            proposals()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .assistantBubble()
    }

    @ViewBuilder private func part(_ p: Part) -> some View {
        switch p.kind {
        case .head:
            Text(AssistantAnswer.styled(p.text))
                .font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                .textSelection(.enabled)
        case .text:
            Text(AssistantAnswer.styled(p.text))
                .font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
                .textSelection(.enabled)
        case .point(let mark):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Self.color(mark)).frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(AssistantAnswer.styled(p.text))
                    .font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .textSelection(.enabled)
            }
        case .gap:
            Color.clear.frame(height: 2)
        }
    }

    static func color(_ mark: Part.Mark?) -> Color {
        switch mark {
        case .good: Theme.success
        case .watch: Theme.warning
        case .risk: Theme.danger
        case .todo: Theme.primary
        case nil: Theme.inkFaint
        }
    }

    /// The answer's lines: the first is the head, `**…**` or `#` lines are heads too, `-`, `*` and `•` lines are points.
    static func parts(_ text: String) -> [Part] {
        var out: [Part] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let id = out.count
            if line.isEmpty {
                if let last = out.last, last.kind != .gap { out.append(Part(id: id, kind: .gap, text: "")) }
                continue
            }
            if let body = bullet(line) {
                let (mark, rest) = marker(body)
                out.append(Part(id: id, kind: .point(mark), text: rest))
            } else if line.hasPrefix("#") {
                out.append(Part(id: id, kind: .head, text: line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if out.isEmpty || (line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4) {
                out.append(Part(id: id, kind: .head, text: line))
            } else {
                out.append(Part(id: id, kind: .text, text: line))
            }
        }
        if out.last?.kind == .gap { out.removeLast() }
        return out
    }

    private static func bullet(_ line: String) -> String? {
        for p in ["- ", "* ", "• ", "· "] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// A known marker at the start of a point: 🟢 ✅ good, 🟠 🟡 ⚠️ watch, 🔴 ❗ ⛔ risk, 🔵 📌 to do.
    private static func marker(_ s: String) -> (Part.Mark?, String) {
        let marks: [(String, Part.Mark)] = [("🟢", .good), ("✅", .good), ("🟠", .watch), ("🟡", .watch), ("⚠️", .watch),
                                            ("⚠", .watch), ("🔴", .risk), ("❗", .risk), ("⛔", .risk), ("🔵", .todo), ("📌", .todo)]
        for (m, kind) in marks where s.hasPrefix(m) {
            return (kind, String(s.dropFirst(m.count)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, s)
    }
}

/// A proposal inside the answer's bubble: `ข้อเสนอ:` and the change, `ยืนยันปรับแผน` and `ไม่ใช่ตอนนี้`. Nothing is
/// saved until `ยืนยันปรับแผน`.
struct AssistantProposalBox: View {
    let action: Assistant.PendingAction
    let confirm: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("ข้อเสนอ: ").bold() + Text("\(action.station) · \(action.title)"))
                .font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.warningText)
            let layout = action.isReplan ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text(action.before).foregroundStyle(Theme.inkMuted).strikethrough(action.before != action.after)
                Image(systemName: action.isReplan ? "arrow.down" : "arrow.right").foregroundStyle(Theme.inkMuted)
                Text(action.after).fontWeight(.semibold).foregroundStyle(Theme.navy).monospacedDigit()
            }
            .font(.sarabun(15, relativeTo: .body))
            .accessibilityElement(children: .combine)
            if action.isReplan {
                Label("ยืนยันแล้ววันตามแผนเดิมของงานเหล่านี้จะถูกแทนที่ เปอร์เซ็นต์ตามแผนจะคิดจากแผนใหม่", systemImage: "exclamationmark.triangle")
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.warningText)
            }
            Text("ยังไม่ได้บันทึก").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                TCButton("ยืนยันปรับแผน", size: .card, action: confirm)
                    .accessibilityIdentifier("assistantConfirm")
                TCButton("ไม่ใช่ตอนนี้", kind: .secondary, size: .card, action: dismiss)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warning.opacity(0.35)))
    }
}

/// While the model works: a pulsing badge and what it is reading, one line after another (text swaps only with
/// Reduce Motion).
struct AssistantThinkingBubble: View {
    static let steps = ["กำลังอ่านแผน MP…", "ดูรายงานประจำวันและสภาพอากาศ…", "เทียบกับแผนก่อสร้าง…"]
    @State private var step = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 28, height: 28)
                .background(Theme.primarySoft, in: Circle())
                .scaleEffect(pulse ? 1.12 : 0.9)
                .opacity(pulse ? 1 : 0.7)
            Text(Self.steps[step % Self.steps.count])
                .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                .id(step)
                .transition(.opacity)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistantThinking")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                if Task.isCancelled { break }
                if reduceMotion { step += 1 } else { withAnimation(.easeInOut(duration: 0.25)) { step += 1 } }
            }
        }
    }
}
