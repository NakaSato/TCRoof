import SwiftUI
import TCRoofUI
import TCRoofCore

/// ตั้งค่า › ผู้ช่วยโครงการ (AI): the AI keys on this device, one per provider (Qwen, OpenAI, Claude, Gemini …). A manager
/// picks a provider, enters, tests and removes its key; saving makes it the one the assistant uses. The team sees which
/// provider this device uses and today's questions.
struct AssistantSettingsPage: View {
    @Environment(\.permissions) private var permissions
    @Environment(\.openURL) private var openURL
    /// The provider the form shows; saving makes it the one in use.
    @State private var provider = AssistantKey.provider
    @State private var active = AssistantKey.provider
    @State private var activeHasKey = AssistantKey.hasActiveKey
    @State private var keyText = ""
    @State private var model = AssistantKey.model(AssistantKey.provider)
    @State private var baseURL = AssistantKey.baseURL(AssistantKey.provider)
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmRemove = false
    @State private var used = AssistantKey.used()
    /// Bumped after a key is saved or removed, so the list of keys reads the Keychain again.
    @State private var keysChanged = 0

    private var manages: Bool { permissions.can(.usersManage) }
    private var hasKey: Bool { _ = keysChanged; return AssistantKey.hasKey(provider) }
    private var withKeys: [Assistant.Provider] { _ = keysChanged; return Assistant.Provider.allCases.filter { AssistantKey.hasKey($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                status
                if manages { form } else {
                    Text("ผู้จัดการเป็นผู้ใส่คีย์ในแต่ละเครื่อง").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                }
                if let result { resultLine(result) }
                Text("คีย์เก็บในพวงกุญแจของเครื่องนี้เท่านั้น ไม่ซิงก์และไม่อยู่ในข้อมูลสำรอง แอปส่งข้อมูลงานของสถานีไปยังผู้ให้บริการ AI ที่เลือก เฉพาะที่ผู้ช่วยถาม (แผน MP ความก้าวหน้า รายงานประจำวัน แบบสำรวจ เอกสารสถานี ลำดับ กกพ. ทดสอบ IEC คำขอรายสัปดาห์ ICL อุปกรณ์) ไม่ส่งชื่อ เบอร์ หรือที่อยู่ลูกค้า ค่าใช้จ่ายคิดกับบัญชีของคีย์นั้น แต่ละเครื่องถามได้ \(Assistant.OpenAI.dailyLimit) คำถามต่อวัน")
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("ผู้ช่วยโครงการ (AI)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: provider) { _, p in
            keyText = ""; result = nil
            model = AssistantKey.model(p); baseURL = AssistantKey.baseURL(p)
        }
        .confirmationDialog("ลบคีย์ \(provider.title) ออกจากเครื่องนี้?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("ลบคีย์", role: .destructive) { remove() }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text(provider == active ? "ผู้ช่วยในเครื่องนี้จะใช้ไม่ได้จนกว่าจะใส่คีย์ใหม่" : "คีย์ของผู้ให้บริการที่ใช้อยู่ไม่เปลี่ยน") }
    }

    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: activeHasKey ? "checkmark.seal.fill" : "key.slash")
                .font(.system(size: 24)).foregroundStyle(activeHasKey ? Theme.success : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeHasKey ? "ใช้คีย์ในเครื่องนี้ | \(active.title) | \(AssistantKey.model(active))" : "ยังไม่ได้ใส่คีย์ \(active.title) ในเครื่องนี้")
                    .font(.sarabun(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("assistantKeyStatus")
                Text("วันนี้ถามไป \(used)/\(Assistant.OpenAI.dailyLimit) คำถาม").font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                if !withKeys.isEmpty {
                    Text("มีคีย์ในเครื่อง: " + withKeys.map(\.title).joined(separator: ", "))
                        .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .tcCard()
    }

    private var providerTitle: Binding<String> {
        Binding(get: { provider.title },
                set: { t in if let p = Assistant.Provider.allCases.first(where: { $0.title == t }) { provider = p } })
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            TCFieldLabel("ผู้ให้บริการ AI")
            TCDropdown(Assistant.Provider.allCases.map(\.title), selection: providerTitle, accessibilityTitle: "ผู้ให้บริการ AI")
                .accessibilityIdentifier("assistantProvider")
            HStack(spacing: 8) {
                TCFieldLabel(hasKey ? "เปลี่ยนคีย์ API (เว้นว่างไว้ = ใช้คีย์เดิม)" : "คีย์ API", required: !hasKey)
                Spacer(minLength: 0)
                if let page = provider.keyPage.flatMap(URL.init(string:)) {
                    TCLinkButton("ขอคีย์ ›") { openURL(page) }
                }
            }
            SecureField(provider.keyHint, text: $keyText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.sarabun(16, relativeTo: .body))
                .padding(.horizontal, 14).frame(minHeight: 50)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
                .accessibilityIdentifier("assistantKeyField")
            TCFieldLabel("รุ่นโมเดล", required: provider.defaultModel.isEmpty)
            TCTextField(provider.defaultModel.isEmpty ? "ชื่อโมเดล" : provider.defaultModel, text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TCFieldLabel("ที่อยู่ API", required: provider.defaultBaseURL.isEmpty)
            TCTextField(provider.defaultBaseURL.isEmpty ? "https://…/v1" : provider.defaultBaseURL, text: $baseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            HStack(spacing: 10) {
                TCButton("ทดสอบ", systemImage: "bolt.horizontal", kind: .secondary, size: .card, working: testing) { test() }
                    .disabled(testing || (keyText.isEmpty && !hasKey))
                TCButton(provider == active ? "บันทึก" : "บันทึกและใช้", systemImage: "checkmark", size: .card) { save() }
                    .disabled(keyText.isEmpty && !hasKey)
                    .accessibilityIdentifier("assistantKeySave")
                Spacer(minLength: 0)
                if hasKey {
                    TCButton("ลบคีย์ออก", kind: .secondary, size: .card) { confirmRemove = true }
                        .accessibilityIdentifier("assistantKeyRemove")
                }
            }
        }
        .padding(16)
        .tcCard()
    }

    private func resultLine(_ r: (ok: Bool, text: String)) -> some View {
        Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.sarabun(15, relativeTo: .subheadline))
            .foregroundStyle(r.ok ? Theme.successText : Theme.dangerText)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(r.ok ? Theme.successSoft : Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("assistantKeyResult")
    }

    /// The form's model and endpoint, else the provider's defaults.
    private var chosen: (model: String, baseURL: String) {
        (model.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultModel : model,
         baseURL.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultBaseURL : baseURL)
    }

    private func valid(_ c: (model: String, baseURL: String)) -> String? {
        if c.model.isEmpty { return "ใส่ชื่อรุ่นโมเดล" }
        let url = provider.api == .anthropic ? Assistant.Anthropic.url(base: c.baseURL) : Assistant.OpenAI.url(base: c.baseURL)
        return url == nil ? "ที่อยู่ API ต้องขึ้นต้นด้วย https://" : nil
    }

    /// Saves the form's key, model and endpoint for its provider and makes it the one in use.
    private func save() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = chosen
        if let problem = valid(c) { result = (false, problem); return }
        if !key.isEmpty {
            guard AssistantKey.save(key, for: provider) else { result = (false, "บันทึกคีย์ในเครื่องไม่ได้"); return }
            keyText = ""
        }
        AssistantKey.setModel(c.model, for: provider)
        AssistantKey.setBaseURL(c.baseURL, for: provider)
        AssistantKey.provider = provider
        model = AssistantKey.model(provider); baseURL = AssistantKey.baseURL(provider)
        refresh()
        result = (true, "บันทึกแล้ว | ผู้ช่วยใช้ \(provider.title)")
    }

    private func remove() {
        AssistantKey.remove(provider)
        refresh()
        result = nil
    }

    private func refresh() {
        active = AssistantKey.provider
        activeHasKey = AssistantKey.hasActiveKey
        keysChanged += 1
    }

    /// One short request without tools, with the key typed (else the saved one).
    private func test() {
        let typed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = typed.isEmpty ? AssistantKey.key(provider) : typed else { return }
        let c = chosen
        if let problem = valid(c) { result = (false, problem); return }
        testing = true; result = nil
        let client = DirectAIClient(provider: provider, key: key, model: c.model, baseURL: c.baseURL)
        Task {
            defer { testing = false; used = AssistantKey.used() }
            do {
                let r = try await client.complete(.init(messages: [.user("ตอบคำเดียวว่า พร้อม")], tools: []))
                result = (true, "เชื่อมต่อได้ | \(provider.title) \(c.model) ตอบว่า \"\(String((r.message.content ?? "").prefix(40)))\"")
            } catch {
                result = (false, error.localizedDescription)
            }
        }
    }
}
