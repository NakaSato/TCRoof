import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ตั้งค่า Monitoring` (issue #259 §7, redesigned in CHA-72 / #323): one column over the page. From the top: the
/// Growatt accounts as cards (a token kept in this iPad's Keychain, only its last four in the settings; a dashed
/// `+ เพิ่มบัญชี` card opens an inline form that tests the account before adding it), polling with the nightly archive
/// and the pairings' count (`ดูรายการ ›` turns the dialog to `จับคู่สถานีกับ Plant`, `MonitoringPairingPane`), the
/// alert thresholds as four tiles, who is told as three cards, and the electricity rate. Only a manager edits; the
/// team sees the values. Changes wait for `บันทึก` in the footer, which says how many are unsaved;
/// `ยกเลิกการแก้` puts the saved values back. `-monitoringPairing YES` opens it on the pairing page with example plants.
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
    /// The add form's connection test: running, and why it failed.
    @State private var addTesting = false
    @State private var addError: String?
    /// The account whose token is being replaced, and the new one typed.
    @State private var changingToken: UUID?
    @State private var changedToken = ""
    /// Accounts whose token is in this iPad's Keychain, read once when the dialog opens, not on every redraw.
    @State private var savedTokens: Set<UUID> = []
    /// Plants already read for each server during this dialog session (`testAndAdd`, `test`, or the pairing pane),
    /// kept so opening `จับคู่สถานีกับ Plant` doesn't call `plant/list` a second time.
    @State private var plants: [UUID: [Monitoring.Pairing.Plant]] = [:]
    @State private var testing: Set<UUID> = []
    @State private var testNote: [UUID: String] = [:]

    init(store: MonitoringStore, stations: [Monitoring.Station], canEdit: Bool, startOnPairing: Bool = false, close: @escaping () -> Void) {
        self.store = store; self.stations = stations; self.canEdit = canEdit; self.close = close
        _draft = State(initialValue: store.settings)
        _page = State(initialValue: startOnPairing ? .pairing : .settings)
        _savedTokens = State(initialValue: Set(store.settings.servers.map(\.id).filter { MonitoringToken.token($0) != nil }))
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
                if page == .pairing {
                    Divider()
                    MonitoringPairingPane(stations: stations, draft: $draft, canEdit: canEdit, stub: Self.stubPlants,
                                          plants: $plants)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            sourcesSection.disabled(!canEdit)
                            pollingSection
                            thresholdsSection.disabled(!canEdit)
                            recipientsSection.disabled(!canEdit)
                            rateSection.disabled(!canEdit)
                        }
                        .padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 24)
                    }
                }
                Divider()
                footer
            }
            .frame(maxWidth: 940, maxHeight: 900)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
            .padding(40)
        }
        // the keyboard covers the dialog's lower part rather than squeezing all of it above the keys: the account
        // fields are near the top, so they stay in view while typed
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: title and footer

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if page == .pairing {
                Button { withAnimation(.easeInOut(duration: 0.2)) { page = .settings } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 44).background(Theme.track, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("กลับไปตั้งค่า").accessibilityIdentifier("monitoring.pairing.back")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(page == .pairing ? "จับคู่สถานีกับ Plant" : "ตั้งค่า Monitoring")
                    .font(.sarabun(24, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                if page == .pairing {
                    Text(pairedLine).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            Button(action: close) { Label("ปิด", systemImage: "xmark") }
                .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                .accessibilityIdentifier("monitoring.settings.close")
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
    }

    private var footer: some View {
        let n = changeCount
        return HStack(spacing: 12) {
            Circle().fill(!canEdit || n == 0 ? Theme.muted : Theme.warning).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(footerLine(n)).font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                .accessibilityIdentifier("monitoring.settings.status")
            Spacer()
            if canEdit {
                if n > 0 {
                    Button(action: undo) { Text(verbatim: "ยกเลิกการแก้") }
                        .buttonStyle(TCButtonStyle(.secondary, fullWidth: false))
                        .accessibilityIdentifier("monitoring.settings.undo")
                }
                Button(action: save) { Text(verbatim: "บันทึก") }.buttonStyle(TCButtonStyle(.primary, fullWidth: false))
                    .disabled(n == 0)
                    .accessibilityIdentifier("monitoring.settings.save")
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
    }

    private func footerLine(_ n: Int) -> String {
        if !canEdit { return "ดูได้อย่างเดียว · แก้ได้เฉพาะผู้จัดการ" }
        return n == 0 ? "ไม่มีการเปลี่ยนแปลง" : "ยังไม่ได้บันทึก \(n) รายการ · มีผลกับทุกสถานี"
    }

    /// Settings that differ from the saved ones: each account added, removed or changed (a new token counts), each
    /// field, and the pairings as one.
    private var changeCount: Int {
        let saved = store.settings
        let ids = Set(saved.servers.map(\.id)).union(draft.servers.map(\.id))
        var n = ids.filter { id in
            let a = saved.servers.first { $0.id == id }, b = draft.servers.first { $0.id == id }
            return a?.name != b?.name || a?.url != b?.url || a?.tokenSuffix != b?.tokenSuffix
        }.count
        let fields: [Bool] = [
            saved.pollMinutes != draft.pollMinutes,
            saved.loggerOfflineMinutes != draft.loggerOfflineMinutes, saved.stringLowPercent != draft.stringLowPercent,
            saved.belowExpectedPercent != draft.belowExpectedPercent, saved.prLowPercent != draft.prLowPercent,
            saved.notifyMaintenance != draft.notifyMaintenance, saved.rate != draft.rate,
            saved.pairings != draft.pairings || saved.pairingServers != draft.pairingServers,
        ]
        n += fields.filter { $0 }.count
        return n
    }

    private func save() {
        // tokens are saved when they are added or changed; accounts taken out lose theirs here
        var tokensChanged = false
        for old in store.settings.servers where !draft.servers.contains(where: { $0.id == old.id }) {
            if savedTokens.contains(old.id) { tokensChanged = true }
            MonitoringToken.remove(old.id)
        }
        store.save(draft)
        if tokensChanged { store.noteTokenChange() }
        close()
    }

    /// A token saved: in this iPad's Keychain for its own poll, and nowhere else.
    private func keep(_ token: String, for server: UUID) {
        MonitoringToken.save(token, for: server)
    }

    /// `ยกเลิกการแก้`: the saved values back and forms dropped. Accounts added and tokens changed were saved at once,
    /// so they stay.
    private func undo() {
        draft = store.settings
        plants = [:]
        adding = false; changingToken = nil; changedToken = ""
        newName = ""; newToken = ""; newURL = GrowattAPI.openAPIURL.absoluteString; addError = nil
        testNote = [:]
    }

    // MARK: data sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("แหล่งข้อมูล", note: "บัญชี Growatt ที่ดึงข้อมูลมาแสดง")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(draft.servers) { s in accountCard(s) }
                if canEdit { addCard }
            }
            if let id = changingToken, let s = draft.servers.first(where: { $0.id == id }) { changeTokenForm(s) }
            if adding { addForm }
        }
    }

    private func accountCard(_ s: Monitoring.Settings.Server) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "server.rack").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 48, height: 48)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.name).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(accountLine(s)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                accountStatus(s)
                if let note = testNote[s.id] {
                    Text(note).font(.sarabun(12)).foregroundStyle(Theme.dangerText).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            roundButton("key", label: "เปลี่ยน Token ของ \(s.name)", tint: Theme.primary, fill: Theme.primarySoft) {
                changingToken = changingToken == s.id ? nil : s.id
                changedToken = ""
            }
            .accessibilityIdentifier("monitoring.server.changeToken")
            roundButton("trash", label: "ลบบัญชี \(s.name)", tint: Theme.dangerText, fill: Theme.dangerSoft) {
                draft.servers.removeAll { $0.id == s.id }
                plants[s.id] = nil
                if changingToken == s.id { changingToken = nil }
            }
            .accessibilityIdentifier("monitoring.server.delete")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    /// `openapi.growatt.com · 4 สถานี · 43 Plant`: the stations whose plant is read from this account, and how many
    /// plants the last test saw.
    private func accountLine(_ s: Monitoring.Settings.Server) -> String {
        let n = stations.filter { draft.pairing(of: $0.id)?.server.id == s.id }.count
        let total = s.plants.map { " · \($0) Plant" } ?? ""
        return s.host + " · \(n) สถานี" + total
    }

    /// The account's connection: a tap tests it again. No token on this iPad says so first, since nothing can be read.
    @ViewBuilder
    private func accountStatus(_ s: Monitoring.Settings.Server) -> some View {
        let hasToken = savedTokens.contains(s.id)
        Button { Task { await test(s) } } label: {
            Group {
                if testing.contains(s.id) {
                    MonChip("กำลังทดสอบ…", .info)
                } else if !hasToken {
                    MonChip("ไม่มี Token ใน iPad เครื่องนี้", .warn)
                } else if let ok = s.testOK, let at = s.testedAt {
                    MonChip((ok ? "เชื่อมต่อได้ · " : "เชื่อมต่อไม่ได้ · ") + MonFormat.time(at), ok ? .ok : .bad)
                } else {
                    MonChip("ยังไม่ได้ทดสอบ · แตะเพื่อทดสอบ", .muted)
                }
            }
            .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasToken || testing.contains(s.id))
        .accessibilityHint("แตะเพื่อทดสอบการเชื่อมต่ออีกครั้ง")
        .accessibilityIdentifier("monitoring.server.test")
    }

    private var addCard: some View {
        Button { adding = true; addError = nil } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "เพิ่มบัญชี").font(.sarabun(16, .bold)).foregroundStyle(Theme.primary)
                    Text(verbatim: "URL + Token ของบัญชี Growatt").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding)
        .opacity(adding ? 0.45 : 1)
        .accessibilityIdentifier("monitoring.server.add")
    }

    private var defaultAccountName: String {
        draft.servers.isEmpty ? "Growatt" : "Growatt \(draft.servers.count + 1)"
    }

    private var resolvedNewURL: String {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? GrowattAPI.openAPIURL.absoluteString : trimmed
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "บัญชีใหม่").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
            HStack(alignment: .top, spacing: 12) {
                labelledField("ชื่อบัญชี") { TCTextField(defaultAccountName, text: $newName) }
                labelledField("URL") { TCTextField(GrowattAPI.openAPIURL.absoluteString, text: $newURL) }
                labelledField("Token") { secureField("วาง Token", text: $newToken, id: "monitoring.server.token") }
            }
            if let addError {
                Text(addError).font(.sarabun(13)).foregroundStyle(Theme.dangerText)
                    .accessibilityIdentifier("monitoring.server.addError")
            }
            HStack(spacing: 10) {
                Spacer()
                Button {
                    adding = false; newName = ""; newToken = ""; newURL = GrowattAPI.openAPIURL.absoluteString; addError = nil
                } label: { Text(verbatim: "ยกเลิก") }
                .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                Button { Task { await testAndAdd() } } label: {
                    HStack(spacing: 8) {
                        if addTesting { ProgressView().tint(Theme.onPrimary) }
                        Text(verbatim: addTesting ? "กำลังทดสอบ…" : "ทดสอบและเพิ่ม")
                    }
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: false))
                .disabled(addTesting || URL(string: resolvedNewURL)?.host == nil
                          || newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("monitoring.server.testAndAdd")
            }
        }
        .padding(16)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Lists the account's plants (read only, `plant/list`) before it is added, so a wrong URL or token is caught in
    /// the form; once verified, the account and its token are saved at once so closing the dialog doesn't lose them.
    private func testAndAdd() async {
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = resolvedNewURL
        let typedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typedName.isEmpty ? defaultAccountName : typedName
        guard let base = URL(string: url) else { return }
        addTesting = true; addError = nil
        defer { addTesting = false }
        do {
            let rows = try await GrowattAPI(baseURL: base, token: token).allPlants(maxPages: 10)
            var s = Monitoring.Settings.Server(name: name, url: url,
                                               tokenSuffix: Monitoring.Settings.Server.suffix(of: token))
            s.testedAt = Date(); s.testOK = true; s.plants = rows.count
            keep(token, for: s.id)
            savedTokens.insert(s.id)
            draft.servers.append(s)
            plants[s.id] = rows.map(Monitoring.Pairing.Plant.init)
            var saved = store.settings
            saved.servers.append(s)
            store.save(saved)
            store.noteTokenChange()
            adding = false; newName = ""; newToken = ""; newURL = GrowattAPI.openAPIURL.absoluteString
        } catch let f as GrowattAPI.Failure {
            addError = f.message
        } catch {
            addError = GrowattAPI.Failure.badResponse.message
        }
    }

    /// A new token for an account already added: saved to the Keychain at once, its last four updated and the last
    /// test cleared, since it was the old one's.
    private func changeTokenForm(_ s: Monitoring.Settings.Server) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token ใหม่ของ \(s.name)").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 10) {
                secureField("วาง Token ใหม่จาก Growatt", text: $changedToken, id: "monitoring.server.newToken")
                Button { changingToken = nil; changedToken = "" } label: { Text(verbatim: "ยกเลิก") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                Button {
                    let token = changedToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = Monitoring.Settings.Server.suffix(of: token)
                    keep(token, for: s.id)
                    savedTokens.insert(s.id)
                    plants[s.id] = nil
                    if let i = draft.servers.firstIndex(where: { $0.id == s.id }) {
                        draft.servers[i].tokenSuffix = suffix
                        draft.servers[i].testOK = nil
                        draft.servers[i].testedAt = nil
                        draft.servers[i].plants = nil
                    }
                    var saved = store.settings
                    if let i = saved.servers.firstIndex(where: { $0.id == s.id }) {
                        saved.servers[i].tokenSuffix = suffix
                        saved.servers[i].testOK = nil
                        saved.servers[i].testedAt = nil
                        saved.servers[i].plants = nil
                        store.save(saved)
                    }
                    store.noteTokenChange()
                    testNote[s.id] = nil
                    changingToken = nil; changedToken = ""
                } label: { Text(verbatim: "ใช้ Token นี้") }
                    .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: false))
                    .disabled(changedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Tests the account's connection with the token in this iPad's Keychain (`MonitoringStore.test` records the
    /// result on the saved row), and shows the result and the plants read in the draft.
    private func test(_ s: Monitoring.Settings.Server) async {
        let current = draft.servers.first { $0.id == s.id } ?? s
        testing.insert(s.id)
        let result = await store.test(current)
        testing.remove(s.id)
        if let i = draft.servers.firstIndex(where: { $0.id == s.id }) {
            draft.servers[i].testedAt = store.settings.servers.first(where: { $0.id == s.id })?.testedAt ?? Date()
            switch result {
            case .success(let list):
                draft.servers[i].testOK = true
                draft.servers[i].plants = list.count
                plants[s.id] = list.map(Monitoring.Pairing.Plant.init)
                testNote[s.id] = nil
            case .failure(let f):
                draft.servers[i].testOK = false
                testNote[s.id] = f.message
            }
        }
    }

    // MARK: polling

    private var pollingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("การดึงข้อมูล", note: "Growatt ให้ถี่สุดทุก 5 นาที")
            VStack(spacing: 0) {
                settingRow("รอบดึงข้อมูล", "ยิ่งถี่ ข้อมูลยิ่งใหม่ · ใช้โควตา API มากขึ้น") {
                    Segments(options: Monitoring.Settings.pollChoices.map { ($0, "\($0) นาที") }, selection: $draft.pollMinutes)
                        .frame(width: 280)
                }
                .disabled(!canEdit)
                Divider()
                // viewing the pairings is open to everyone; the pane itself is read only for the team
                settingRow("จับคู่สถานี", pairedLine) {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { page = .pairing } } label: { Text(verbatim: "ดูรายการ ›") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
                        .accessibilityIdentifier("monitoring.pairing.open")
                }
            }
            .modifier(SectionCard())
        }
    }

    /// `6/6 สถานีจับคู่กับ Plant ใน Growatt แล้ว`, from the draft.
    private var pairedLine: String { "\(draft.paired(of: stations.map(\.id)))/\(stations.count) สถานีจับคู่กับ Plant ใน Growatt แล้ว" }

    // MARK: thresholds

    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("แจ้งเตือนเมื่อ", note: "ใช้กับทุกสถานี")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                thresholdTile("wifi", Theme.primary, Theme.primarySoft, "ดาต้าล็อกเกอร์ขาดการติดต่อ", "นานกว่า",
                              Segments(options: Monitoring.Settings.loggerChoices.map { ($0, $0 >= 60 ? "\($0 / 60) ชม." : "\($0) น.") },
                                       selection: $draft.loggerOfflineMinutes))
                thresholdTile("bolt", Theme.warningText, Theme.warningSoft, "สตริงกระแสต่ำ", "ต่ำกว่าค่ากลางของอินเวอร์เตอร์ นาน 30 นาที",
                              Segments(options: Monitoring.Settings.stringChoices.map { ($0, "\($0)%") }, selection: $draft.stringLowPercent))
                thresholdTile("chart.line.downtrend.xyaxis", Theme.dangerText, Theme.dangerSoft, "ผลิตต่ำกว่าที่คาด", "ต่ำกว่าค่ากลางของสถานีปกติ",
                              Segments(options: Monitoring.Settings.belowExpectedChoices.map { ($0, "\($0)%") }, selection: $draft.belowExpectedPercent))
                thresholdTile("sun.max", Theme.successInk, Theme.successSoft, "PR ต่ำ", "เฉพาะสถานีที่มีเซนเซอร์แสง",
                              Segments(options: Monitoring.Settings.prChoices.map { ($0, "\($0)%") }, selection: $draft.prLowPercent))
            }
        }
    }

    private func thresholdTile(_ icon: String, _ tint: Color, _ fill: Color, _ title: String, _ detail: String,
                               _ control: Segments<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36).background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                    Text(detail).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            control
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SectionCard())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    // MARK: recipients

    /// Only the maintenance team: alerts come from the iPad that reads Growatt, and with no server poll nothing can
    /// reach a station's supervisor or contractor (CHA-94), so their switches are left out.
    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ส่งแจ้งเตือนถึง", note: "แจ้งบน iPad ที่เปิด Monitoring")
            recipientCard("ทีมบำรุงรักษา", "ทุกสถานี", on: $draft.notifyMaintenance)
        }
    }

    private func recipientCard(_ title: String, _ detail: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                    Text(detail).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(on.wrappedValue ? Theme.primary : Theme.surface)
                    Circle().strokeBorder(on.wrappedValue ? Theme.primary : Theme.borderControl, lineWidth: 1.5)
                    if on.wrappedValue {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(on.wrappedValue ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(on.wrappedValue ? Theme.primary : Theme.borderSubtle, lineWidth: on.wrappedValue ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " · " + detail)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    // MARK: rate

    /// The rate: 4.18 until a manager sets the company's; cleared, the page reads `—`. The field takes numbers only.
    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("มูลค่าไฟ", note: "ใช้คำนวณ \"มูลค่าไฟที่ผลิตได้\" ของทุกสถานี")
            settingRow("อัตราค่าไฟ", draft.rate == nil ? "ยังไม่ได้ตั้ง · มูลค่าไฟจะแสดง —" : "ค่าเฉลี่ยต่อหน่วย") {
                HStack(spacing: 10) {
                    TextField("4.18", value: $draft.rate, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                        .font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
                        .frame(width: 96, height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("อัตราค่าไฟ บาทต่อ kWh")
                        .accessibilityIdentifier("monitoring.settings.rate")
                    Text(verbatim: "บาท / kWh").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                }
                .padding(4).padding(.trailing, 8)
                .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .modifier(SectionCard())
        }
    }

    // MARK: parts

    private func sectionHeader(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabun(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted) }
        }
    }

    private func settingRow<Trailing: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                Text(detail).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 64)
    }

    private func labelledField<F: View>(_ label: String, @ViewBuilder _ field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted)
            field()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secureField(_ prompt: String, text: Binding<String>, id: String) -> some View {
        HStack(spacing: 8) {
            SecureField(prompt, text: text)
                .font(.sarabun(15))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(id)
            if text.wrappedValue.isEmpty {
                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
                        text.wrappedValue = pasted
                    }
                } label: {
                    Text(verbatim: "วาง").font(.sarabun(13, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.primarySoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("วาง Token จากคลิปบอร์ด")
                .accessibilityIdentifier(id + ".paste")
            } else {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้าง Token")
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderControl))
    }

    private func roundButton(_ icon: String, label: String, tint: Color, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A section's white card: radius 16, a hairline border.
private struct SectionCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

/// The dialog's iOS-style segmented control: the segments share the width given, the selected one raised.
private struct Segments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { selection = value } label: {
                    Text(verbatim: title).font(.sarabun(15, on ? .bold : .regular))
                        .foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface)
                                    .shadow(color: Theme.navy.opacity(0.18), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
