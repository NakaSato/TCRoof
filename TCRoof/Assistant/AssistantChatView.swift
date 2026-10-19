import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// ผู้ช่วยโครงการ (docs/specs/project-assistant-qwen.md §4): a chat about the PWA stations' MP plans. The model reads
/// the plans through `Assistant.Toolbox` on this device and proposes changes as cards; a card's `ยืนยัน` saves it the way
/// บันทึกความก้าวหน้า does. Shown only with `assistant.use`.
struct AssistantChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @State private var session: Assistant.Session
    @State private var source = Source()
    @State private var draft = ""
    @State private var sending = false
    @State private var failure: String?
    @FocusState private var typing: Bool
    private let focus: Job?
    private let transport: Assistant.Transport

    /// Reads the stations for each tool call; filled once the view has its model context.
    @MainActor final class Source { var read: @MainActor () -> [Assistant.Job] = { [] } }

    init(focus: Job? = nil) {
        self.focus = focus
        #if DEBUG
        let t: Assistant.Transport = UserDefaults.standard.bool(forKey: "assistantDemo") ? AssistantDemoTransport() : AssistantClient()
        #else
        let t: Assistant.Transport = AssistantClient()
        #endif
        transport = t
        let source = Source()
        _source = State(initialValue: source)
        _session = State(initialValue: Self.makeSession(t, focus: focus, source: source))
    }

    private static func makeSession(_ t: Assistant.Transport, focus: Job?, source: Source) -> Assistant.Session {
        Assistant.Session(transport: t, focus: focus?.assistantJob(.team), jobs: { source.read() })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            intro
                            ForEach(lines) { line in row(line) }
                            // confirmed only once the answer is done, so the note follows the model's words
                            ForEach(session.proposals) { p in AssistantProposalCard(action: p, confirm: { resolve(p, true) },
                                                                                   dismiss: { resolve(p, false) }).disabled(sending) }
                            if sending { thinking }
                            if let failure { failureLine(failure) }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(16)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                    .onChange(of: sending) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                composer
            }
            .background(Theme.pageGradient.ignoresSafeArea())
            .navigationTitle("ผู้ช่วยโครงการ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { restart() } label: { Label("เริ่มใหม่", systemImage: "arrow.counterclockwise") }
                        .disabled(sending || lines.isEmpty)
                }
            }
        }
        .onAppear {
            let context = self.context, permissions = self.permissions
            source.read = { context.assistantStations().map { $0.assistantJob(permissions) } }
        }
    }

    // MARK: lines

    private struct Line: Identifiable {
        enum Kind { case person, assistant, note(confirmed: Bool) }
        let id: Int
        let kind: Kind
        let text: String
    }

    /// The person's messages, the model's answers in words, and the confirmations; tool calls and results stay hidden.
    private var lines: [Line] {
        session.messages.enumerated().compactMap { i, m in
            guard let text = m.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            switch m.role {
            case .user:
                guard text.hasPrefix("[ระบบ]") else { return Line(id: i, kind: .person, text: text) }
                let body = text.dropFirst("[ระบบ]".count).trimmingCharacters(in: .whitespaces)
                let ok = body.hasSuffix("ผู้ใช้ยืนยันและบันทึกแล้ว")
                return Line(id: i, kind: .note(confirmed: ok), text: body.components(separatedBy: " — ").first ?? body)
            case .assistant: return Line(id: i, kind: .assistant, text: text)
            default: return nil
            }
        }
    }

    @ViewBuilder private func row(_ line: Line) -> some View {
        switch line.kind {
        case .person:
            Text(line.text)
                .font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .assistant:
            AssistantAnswer(text: line.text)
        case .note(let confirmed):
            Label(line.text, systemImage: confirmed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.sarabun(14, relativeTo: .subheadline))
                .foregroundStyle(confirmed ? Theme.successText : Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier(confirmed ? "assistantSaved" : "assistantDismissed")
        }
    }

    @ViewBuilder private var intro: some View {
        if lines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("ถามเรื่องแผนงาน MP ของสถานี", systemImage: "sparkles")
                    .font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text(focus.map { "ผู้ช่วยดูแผนของ \($0.assistantStation) และทุกสถานีที่มีแผน MP ตัวเลขทั้งหมดมาจากแผนในแอป การบันทึกต้องกดยืนยันในการ์ดก่อนเสมอ" }
                     ?? "ผู้ช่วยดูแผนของทุกสถานีที่มีแผน MP ตัวเลขทั้งหมดมาจากแผนในแอป การบันทึกต้องกดยืนยันในการ์ดก่อนเสมอ")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                AssistantPrompts(items: prompts) { send($0) }
                    .disabled(sending)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tcCard()
        }
    }

    private var prompts: [String] {
        var p = ["สถานีไหนช้ากว่าแผน", "ต้องเร่งงานอะไรสัปดาห์นี้", "ร่างสรุปประชุมประจำสัปดาห์"]
        if permissions.can(.mpProgress, on: focus?.access) { p.append("อัปเดตความก้าวหน้าจากรายงานประจำวัน") }
        return p
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("กำลังดูแผนงาน…").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityIdentifier("assistantThinking")
    }

    private func failureLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("assistantError")
    }

    // MARK: composer

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("ถามผู้ช่วย เช่น MP 189 ต้องเร่งงานอะไร", text: $draft, axis: .vertical)
                    .font(.sarabun(16, relativeTo: .body))
                    .lineLimit(1...5)
                    .focused($typing)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
                    .accessibilityIdentifier("assistantInput")
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.onPrimary)
                        .background(canSend ? Theme.primary : Theme.inkFaint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("ส่ง")
            }
            if let n = session.remainingToday {
                Text("วันนี้ใช้ได้อีก \(n) ครั้ง").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(Theme.surface.opacity(0.92).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: actions

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        draft = ""; failure = nil; sending = true
        Task {
            defer { sending = false }
            do { try await session.send(t) } catch { failure = error.localizedDescription }
        }
    }

    private func resolve(_ action: Assistant.PendingAction, _ confirmed: Bool) {
        if confirmed, !context.applyAssistant(action) {
            failure = "บันทึกไม่ได้ ไม่พบแผนของ \(action.station)"
            session.resolve(action.id, confirmed: false)
            return
        }
        session.resolve(action.id, confirmed: confirmed)
    }

    private func restart() {
        failure = nil; draft = ""
        session = Self.makeSession(transport, focus: focus, source: source)
    }
}

/// The model's answer: Markdown's inline styles and line breaks, selectable, with `คัดลอก` for drafts.
private struct AssistantAnswer: View {
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.styled(text))
                .font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.navy)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("assistantAnswer")
            Button {
                UIPasteboard.general.string = text
                copied = true
            } label: {
                Label(copied ? "คัดลอกแล้ว" : "คัดลอก", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.sarabun(13, .semibold, relativeTo: .caption)).frame(minHeight: touchMin)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, 14).padding(.top, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .padding(.trailing, 48)
    }

    static func styled(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A change the model proposed: station, task, before → after, and the two buttons. Nothing is saved until `ยืนยัน`.
struct AssistantProposalCard: View {
    let action: Assistant.PendingAction
    let confirm: () -> Void
    let dismiss: () -> Void

    private var kind: String {
        switch action.change {
        case .progress: "บันทึกความก้าวหน้า"
        case .dates: "วันที่จริง"
        case .lateCause: "สาเหตุล่าช้า"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("เสนอ\(kind)", systemImage: "square.and.pencil")
                    .font(.sarabun(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.warningText)
                Spacer()
                Text("ยังไม่ได้บันทึก").font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Text(action.station).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            Text(action.title).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            HStack(spacing: 8) {
                Text(action.before).foregroundStyle(Theme.inkMuted).strikethrough(action.before != action.after)
                Image(systemName: "arrow.right").foregroundStyle(Theme.inkMuted)
                Text(action.after).fontWeight(.semibold).foregroundStyle(Theme.navy)
            }
            .font(.sarabun(16, relativeTo: .body))
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                TCButton("ยกเลิก", kind: .secondary, size: .card, action: dismiss)
                TCButton("ยืนยัน", systemImage: "checkmark", size: .card, action: confirm)
                    .accessibilityIdentifier("assistantConfirm")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.warning.opacity(0.5)))
    }
}

/// Prompt chips that wrap onto more lines.
private struct AssistantPrompts: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { s in
                Button { pick(s) } label: {
                    Text(s).font(.sarabun(15, .semibold, relativeTo: .subheadline))
                        .padding(.horizontal, 14).frame(minHeight: touchMin)
                        .background(Theme.primarySoft, in: Capsule())
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
