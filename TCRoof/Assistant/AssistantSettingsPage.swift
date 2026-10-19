import SwiftUI
import TCRoofUI
import TCRoofCore

/// ตั้งค่า › ผู้ช่วยโครงการ (AI): the Qwen key on this device. A manager enters, tests and removes it; the team sees
/// whether this device has one and today's use.
struct AssistantSettingsPage: View {
    @Environment(\.permissions) private var permissions
    @State private var hasKey = AssistantKey.hasKey
    @State private var keyText = ""
    @State private var model = AssistantKey.model
    @State private var baseURL = AssistantKey.baseURL
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmRemove = false
    @State private var used = AssistantKey.used()

    private var manages: Bool { permissions.can(.usersManage) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                status
                if manages { form } else {
                    Text("ผู้จัดการเป็นผู้ใส่คีย์ในแต่ละเครื่อง").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                }
                if let result { resultLine(result) }
                Text("คีย์เก็บในพวงกุญแจของเครื่องนี้เท่านั้น ไม่ซิงก์และไม่อยู่ในข้อมูลสำรอง แอปส่งเฉพาะแผน MP ความก้าวหน้า และรายงานประจำวันของสถานีไปยัง Qwen ไม่ส่งชื่อ เบอร์ หรือที่อยู่ลูกค้า แต่ละเครื่องใช้ได้ \(Assistant.OpenAI.dailyLimit) ครั้งต่อวัน")
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("ผู้ช่วยโครงการ (AI)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("ลบคีย์ Qwen ออกจากเครื่องนี้?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("ลบคีย์", role: .destructive) { AssistantKey.remove(); hasKey = false; result = nil }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("ผู้ช่วยในเครื่องนี้จะใช้ไม่ได้จนกว่าจะใส่คีย์ใหม่") }
    }

    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: hasKey ? "checkmark.seal.fill" : "key.slash")
                .font(.system(size: 24)).foregroundStyle(hasKey ? Theme.success : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasKey ? "ใช้คีย์ในเครื่องนี้ · \(AssistantKey.model)" : "ยังไม่ได้ใส่คีย์ Qwen ในเครื่องนี้")
                    .font(.sarabun(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("assistantKeyStatus")
                Text("วันนี้ใช้ไป \(used)/\(Assistant.OpenAI.dailyLimit) ครั้ง").font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .tcCard()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            TCFieldLabel(hasKey ? "เปลี่ยนคีย์ API (เว้นว่างไว้ = ใช้คีย์เดิม)" : "คีย์ API", required: !hasKey)
            SecureField("sk-…", text: $keyText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.sarabun(16, relativeTo: .body))
                .padding(.horizontal, 14).frame(minHeight: 50)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
                .accessibilityIdentifier("assistantKeyField")
            TCFieldLabel("รุ่นโมเดล")
            TCTextField(Assistant.OpenAI.defaultModel, text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TCFieldLabel("ที่อยู่ API")
            TCTextField(Assistant.OpenAI.defaultBaseURL, text: $baseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            HStack(spacing: 10) {
                TCButton("ทดสอบ", systemImage: "bolt.horizontal", kind: .secondary, size: .card, working: testing) { test() }
                    .disabled(testing || (keyText.isEmpty && !hasKey))
                TCButton("บันทึก", systemImage: "checkmark", size: .card) { save() }
                    .disabled(keyText.isEmpty && model == AssistantKey.model && baseURL == AssistantKey.baseURL)
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

    private func save() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Assistant.OpenAI.url(base: baseURL) != nil else { result = (false, "ที่อยู่ API ต้องขึ้นต้นด้วย https://"); return }
        if !key.isEmpty {
            guard AssistantKey.save(key) else { result = (false, "บันทึกคีย์ในเครื่องไม่ได้"); return }
            keyText = ""
        }
        AssistantKey.model = model.isEmpty ? Assistant.OpenAI.defaultModel : model
        AssistantKey.baseURL = baseURL.isEmpty ? Assistant.OpenAI.defaultBaseURL : baseURL
        model = AssistantKey.model; baseURL = AssistantKey.baseURL
        hasKey = AssistantKey.hasKey
        result = (true, "บันทึกแล้ว")
    }

    /// One short request without tools, with the key typed (else the saved one).
    private func test() {
        let typed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = typed.isEmpty ? AssistantKey.key : typed else { return }
        testing = true; result = nil
        let client = QwenDirectClient(key: key, model: model.isEmpty ? Assistant.OpenAI.defaultModel : model,
                                      baseURL: baseURL.isEmpty ? Assistant.OpenAI.defaultBaseURL : baseURL)
        Task {
            defer { testing = false; used = AssistantKey.used() }
            do {
                let r = try await client.complete(.init(messages: [.user("ตอบคำเดียวว่า พร้อม")], tools: []))
                result = (true, "เชื่อมต่อได้ · \(client.model) ตอบว่า \"\(String((r.message.content ?? "").prefix(40)))\"")
            } catch {
                result = (false, error.localizedDescription)
            }
        }
    }
}
