import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ตั้งค่า Monitoring` (issue #259 §7): a dialog over the page in two columns. Left: the data servers (name, URL, a
/// token kept in this iPad's Keychain with only its last four characters shown, a connection test), the poll interval,
/// the nightly archive and the pairings' count with `ดูรายการ ›`, which turns the dialog to `จับคู่สถานีกับ Plant`
/// (`MonitoringPairingPane`, `‹` brings the settings back). Right: the alert thresholds, who is told, and the
/// electricity rate. Only a manager edits; others see the values. Changes wait for `บันทึก`, the pairings too.
/// `-monitoringPairing YES` opens it on the pairing page with example plants in place of the server's.
struct MonitoringSettingsDialog: View {
    enum Page { case settings, pairing }

    let store: MonitoringStore
    let stations: [Monitoring.Station]
    let canEdit: Bool
    let close: () -> Void

    @State private var draft: Monitoring.Settings
    @State private var page: Page
    @State private var adding = false
    @State private var newName = ""
    @State private var newURL = GrowattAPI.openAPIURL.absoluteString
    @State private var newToken = ""
    /// Tokens typed for new servers, saved to the Keychain on `บันทึก`; servers removed, their tokens removed then.
    @State private var pendingTokens: [UUID: String] = [:]
    @State private var testing: Set<UUID> = []
    @State private var testNote: [UUID: String] = [:]

    init(store: MonitoringStore, stations: [Monitoring.Station], canEdit: Bool, startOnPairing: Bool = false, close: @escaping () -> Void) {
        self.store = store; self.stations = stations; self.canEdit = canEdit; self.close = close
        _draft = State(initialValue: store.settings)
        _page = State(initialValue: startOnPairing ? .pairing : .settings)
    }

    /// `-monitoringPairing YES`: the picker lists example plants, with no network.
    static var stubPlants: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "monitoringPairing")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            Theme.popoverDim.ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 0) {
                titleBar
                Divider()
                if page == .pairing {
                    MonitoringPairingPane(stations: stations, draft: $draft, canEdit: canEdit, stub: Self.stubPlants)
                } else {
                    ScrollView {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { serversCard.disabled(!canEdit); pollingCard }.frame(maxWidth: .infinity)
                            VStack(spacing: 16) { thresholdsCard; recipientsCard; rateCard }.frame(maxWidth: .infinity).disabled(!canEdit)
                        }
                        .padding(24)
                    }
                }
                Divider()
                footer
            }
            .frame(maxWidth: 1040, maxHeight: 776)
            .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
            .padding(40)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var titleBar: some View {
        HStack(alignment: .top, spacing: 12) {
            if page == .pairing {
                Button { withAnimation(.easeInOut(duration: 0.2)) { page = .settings } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 44).background(Theme.track, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("กลับไปตั้งค่า").accessibilityIdentifier("monitoring.pairing.back")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(page == .pairing ? "จับคู่สถานีกับ Plant" : "ตั้งค่า Monitoring")
                    .font(.sarabun(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text(page == .pairing ? pairedLine : canEdit ? "ใช้กับ Monitoring เท่านั้น · แก้ได้เฉพาะผู้จัดการ" : "ดูได้อย่างเดียว · แก้ได้เฉพาะผู้จัดการ")
                    .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.track, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Theme.surface)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("ค่าที่เปลี่ยนมีผลกับทุกสถานี").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Button(action: close) { Text(verbatim: "ยกเลิก") }.buttonStyle(TCButtonStyle(.secondary, fullWidth: false))
            if canEdit {
                Button(action: save) { Text(verbatim: "บันทึก") }.buttonStyle(TCButtonStyle(.primary, fullWidth: false))
                    .disabled(draft == store.settings && pendingTokens.isEmpty)
                    .accessibilityIdentifier("monitoring.settings.save")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.surface)
    }

    private func save() {
        for (id, token) in pendingTokens { MonitoringToken.save(token, for: id) }
        // servers taken out lose their token too
        for old in store.settings.servers where !draft.servers.contains(where: { $0.id == old.id }) { MonitoringToken.remove(old.id) }
        store.save(draft)
        close()
    }

    // MARK: left column

    private var serversCard: some View {
        section("เซิร์ฟเวอร์ข้อมูล", note: "เพิ่มได้หลาย URL · อ่านอย่างเดียว") {
            ForEach(draft.servers) { s in
                serverRow(s)
                Divider()
            }
            if adding { addServerForm; Divider() }
            Button { adding = true } label: {
                HStack {
                    Label("เพิ่มเซิร์ฟเวอร์", systemImage: "plus").font(.sarabun(15, .bold)).foregroundStyle(Theme.primary)
                    Spacer()
                    Text("เช่น บัญชี Growatt แยกตามเฟส").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(adding)
            Divider()
            settingRow("Token", "เก็บในพวงกุญแจของ iPad เครื่องนี้ · ใช้ร่วมกันทุกบัญชี · แสดงแค่ 4 ตัวท้าย") {
                Text("ซ่อนไว้").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
            }
            Divider()
            settingRow("สิทธิ์", "แอปไม่ส่งคำสั่งเปิดปิดหรือตั้งค่าอินเวอร์เตอร์") {
                Text("อ่านอย่างเดียว").font(.sarabun(14, .bold)).foregroundStyle(Theme.successInk)
            }
            Divider()
            settingRow("สถานะ", lastTested) {
                Button { Task { for s in draft.servers { await test(s) } } } label: { Text(verbatim: "ทดสอบทั้งหมด") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                    .disabled(draft.servers.isEmpty || !testing.isEmpty)
            }
        }
    }

    private var lastTested: String {
        guard let d = draft.servers.compactMap(\.testedAt).max() else { return "ยังไม่ได้ทดสอบ" }
        return "ทดสอบล่าสุด " + d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "th_TH")))
    }

    private func serverRow(_ s: Monitoring.Settings.Server) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack").font(.system(size: 16)).foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text([s.host, s.tokenSuffix.isEmpty ? "ไม่มี Token" : "Token •••• " + s.tokenSuffix, s.plants.map { "\($0) Plant" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                if let note = testNote[s.id] { Text(note).font(.sarabun(12)).foregroundStyle(Theme.dangerText) }
            }
            Spacer(minLength: 8)
            if testing.contains(s.id) {
                ProgressView()
            } else if let ok = s.testOK, let at = s.testedAt {
                MonChip((ok ? "ทดสอบล่าสุด " : "ล้มเหลว ") + MonFormat.time(at), ok ? .ok : .bad)
            }
            Button {
                draft.servers.removeAll { $0.id == s.id }
                pendingTokens[s.id] = nil
            } label: { Text(verbatim: "ลบ") }
            .font(.sarabun(14, .bold)).foregroundStyle(Theme.dangerText).frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var addServerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TCTextField("ชื่อ เช่น Growatt · บัญชีเฟส 3", text: $newName)
            TCTextField("URL", text: $newURL)
            SecureField("Token จาก Growatt", text: $newToken)
                .font(.sarabun(15)).padding(.horizontal, 12).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderControl))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            HStack {
                Button { adding = false; newName = ""; newToken = "" } label: { Text(verbatim: "ยกเลิก") }.buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                Button { addServer() } label: { Text(verbatim: "เพิ่ม") }.buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: false))
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || URL(string: newURL)?.host == nil
                              || newToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private func addServer() {
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = Monitoring.Settings.Server(name: newName.trimmingCharacters(in: .whitespaces), url: newURL.trimmingCharacters(in: .whitespaces),
                                           tokenSuffix: Monitoring.Settings.Server.suffix(of: token))
        draft.servers.append(s)
        pendingTokens[s.id] = token
        adding = false; newName = ""; newToken = ""; newURL = GrowattAPI.openAPIURL.absoluteString
    }

    /// The connection test needs the token in the Keychain: a server just added is saved first.
    private func test(_ s: Monitoring.Settings.Server) async {
        if let t = pendingTokens[s.id] { MonitoringToken.save(t, for: s.id); pendingTokens[s.id] = nil }
        if !store.settings.servers.contains(where: { $0.id == s.id }) {
            var saved = store.settings
            saved.servers.append(s)
            store.save(saved)
        }
        testing.insert(s.id)
        let result = await store.test(s)
        testing.remove(s.id)
        if let updated = store.settings.servers.first(where: { $0.id == s.id }),
           let i = draft.servers.firstIndex(where: { $0.id == s.id }) {
            draft.servers[i].testedAt = updated.testedAt
            draft.servers[i].testOK = updated.testOK
            draft.servers[i].plants = updated.plants
        }
        if case .failure(let f) = result { testNote[s.id] = f.message } else { testNote[s.id] = nil }
    }

    private var pollingCard: some View {
        section("การดึงข้อมูล", note: nil) {
            settingRow("รอบดึงข้อมูล", "Growatt ให้ถี่สุดทุก 5 นาที") {
                MonSwitch(options: Monitoring.Settings.pollChoices.map { ($0, "\($0) นาที") }, selection: $draft.pollMinutes)
            }
            .disabled(!canEdit)
            Divider()
            settingRow("เก็บข้อมูลถาวรทุกคืน", "Growatt เก็บค่า 5 นาทีไว้ราว 95 วัน · TCRoof เก็บต่อเวลา 00:30") {
                Toggle("เก็บข้อมูลถาวรทุกคืน", isOn: $draft.archiveNightly).labelsHidden().tint(Theme.success)
            }
            .disabled(!canEdit)
            Divider()
            settingRow("จับคู่สถานี", pairedLine) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { page = .pairing } } label: { Text(verbatim: "ดูรายการ ›") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                    .accessibilityIdentifier("monitoring.pairing.open")
            }
        }
    }

    /// `6/6 สถานีจับคู่กับ Plant ใน Growatt แล้ว`, from the draft.
    private var pairedLine: String { "\(draft.paired(of: stations.map(\.id)))/\(stations.count) สถานีจับคู่กับ Plant ใน Growatt แล้ว" }

    // MARK: right column

    private var thresholdsCard: some View {
        section("เกณฑ์แจ้งเตือน", note: "ใช้กับทุกสถานี") {
            settingRow("ดาต้าล็อกเกอร์ขาดการติดต่อ", "นานกว่า") {
                MonSwitch(options: Monitoring.Settings.loggerChoices.map { ($0, $0 >= 60 ? "\($0 / 60) ชม." : "\($0) น.") }, selection: $draft.loggerOfflineMinutes)
            }
            Divider()
            settingRow("สตริงกระแสต่ำ", "ต่ำกว่าค่ากลางของอินเวอร์เตอร์ นาน 30 นาที") {
                MonSwitch(options: Monitoring.Settings.stringChoices.map { ($0, "\($0)%") }, selection: $draft.stringLowPercent)
            }
            Divider()
            settingRow("ผลิตต่ำกว่าที่คาด", "ทั้งวัน ต่ำกว่า") {
                MonSwitch(options: Monitoring.Settings.belowExpectedChoices.map { ($0, "\($0)%") }, selection: $draft.belowExpectedPercent)
            }
            Divider()
            settingRow("PR ต่ำ", "เฉพาะสถานีที่มีเซนเซอร์แสง") {
                MonSwitch(options: Monitoring.Settings.prChoices.map { ($0, "\($0)%") }, selection: $draft.prLowPercent)
            }
        }
    }

    private var recipientsCard: some View {
        section("ส่งแจ้งเตือนถึง", note: "แจ้งในแอปและมือถือ") {
            settingRow("ทีมบำรุงรักษา", "ทุกสถานี") { Toggle("ทีมบำรุงรักษา", isOn: $draft.notifyMaintenance).labelsHidden().tint(Theme.success) }
            Divider()
            settingRow("ผู้ควบคุมงานของสถานี", "เฉพาะสถานีที่รับผิดชอบ") { Toggle("ผู้ควบคุมงานของสถานี", isOn: $draft.notifySupervisor).labelsHidden().tint(Theme.success) }
            Divider()
            settingRow("ผู้รับเหมาของสถานี", "เฉพาะสถานีที่ได้รับมอบหมาย") { Toggle("ผู้รับเหมาของสถานี", isOn: $draft.notifyContractor).labelsHidden().tint(Theme.success) }
        }
    }

    /// The rate: unset until a manager picks one (`มูลค่าไฟที่ผลิตได้` reads `—` until then).
    private var rateCard: some View {
        section("มูลค่าไฟ", note: "ใช้คำนวณ \"มูลค่าไฟที่ผลิตได้\"") {
            settingRow("อัตราค่าไฟ", draft.rate == nil ? "ยังไม่ได้ตั้ง · บาทต่อ kWh" : "บาทต่อ kWh") {
                HStack(spacing: 8) {
                    TextField("เช่น 4.20", value: $draft.rate, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.sarabun(16, .bold)).frame(width: 96, height: 44)
                        .padding(.horizontal, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderControl))
                        .accessibilityLabel("อัตราค่าไฟ บาทต่อ kWh")
                    Text("฿/kWh").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    // MARK: parts

    private func section<Content: View>(_ title: String, note: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted)
                if let note { Text(note).font(.sarabun(12)).foregroundStyle(Theme.inkMuted.opacity(0.75)) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            content()
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func settingRow<Trailing: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text(detail).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 52)
    }
}
