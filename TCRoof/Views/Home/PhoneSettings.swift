import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPhone settings (docs/ui/tcroof-home-iphone states/06, v2 colours via `homeInk`): grouped white cards on the page colour.
struct PhoneSettingsList: View {
    @Binding var confirmLogout: Bool
    /// Opened from the `กปภ.` tab: show `ตั้งค่าโครงการ PWA`.
    var pwa = false
    @Environment(GoogleSession.self) private var session
    @Environment(\.permissions) private var permissions
    @AppStorage("userName") private var userName = ""
    @AppStorage("userTeam") private var userTeam = ""
    @AppStorage(CameraRoll.defaultsKey) private var saveToLibrary = true
    @State private var sync = CloudSync.shared
    @State private var instruments = InstrumentStore.shared
    @State private var notifications = NotificationService.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.homeInk) private var ink
    #if DEBUG
    @State private var showGallery = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                accountCard.padding(.top, 12)
                section("ผู้ใช้งาน") {
                    HStack(spacing: 12) {
                        Text("ชื่อที่แสดง").foregroundStyle(ink.muted)
                        TextField("ชื่อที่แสดง", text: $userName)
                            .multilineTextAlignment(.trailing).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                            // typed by hand — stop replacing it with the account name
                            .onChange(of: userName) { GoogleSession.userNameEdited() }
                    }
                    .rowFrame()
                    divider
                    // `ทีมของฉัน` of the home's project feed; with none, the teams on today's appointments
                    HStack(spacing: 12) {
                        Text("ทีมของฉัน").foregroundStyle(ink.muted)
                        Spacer(minLength: 8)
                        Picker("ทีมของฉัน", selection: $userTeam) {
                            Text("ตามนัดวันนี้").tag("")
                            ForEach(Team.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .labelsHidden().tint(Theme.navy)
                    }
                    .rowFrame()
                }
                if pwa {
                    // the PWA module's own dock had this as a tab; here until the owner decides where it lives
                    // (docs/ui/pwa-solar-survey-iphone-v3, open question 1)
                    section("โครงการ PWA") {
                        NavigationLink { PWASettingsPage() } label: { row("ตั้งค่าโครงการ PWA", "›") }
                            .buttonStyle(.plain)
                    }
                }
                if permissions.can(.usersManage) {
                    // only these accounts sign in (firestore.rules members/)
                    section("ทีม") {
                        NavigationLink { MembersView() } label: { row("สมาชิกทีม", "เชิญ · บทบาท ›") }
                            .buttonStyle(.plain)
                    }
                }
                notificationsSection
                section("เครื่องมือ") {
                    // the tools tab's screens, kept reachable until the owner decides where they live
                    // (docs/ui/tcroof-home-iphone-v4, open question 1)
                    NavigationLink { ToolsView(modules: [.plan, .scan, .install]) } label: {
                        row("เครื่องมือวัด", toolsValue)
                    }
                    .buttonStyle(.plain)
                    divider
                    // the dock's เอกสาร is the PWA papers now (docs/ui/pwa-docs-iphone-v2); the residential library is here
                    NavigationLink { HomeLibraryView() } label: { row("เอกสารงานบ้าน", "›") }
                        .buttonStyle(.plain)
                }
                section("รูปถ่าย") {
                    Toggle(isOn: $saveToLibrary) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("บันทึกลงคลังภาพของเครื่อง").foregroundStyle(Theme.navy)
                            Text("รูปจากกล้องในแอป ขนาดเต็ม พร้อมพิกัดและทิศที่ถ่าย").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(ink.muted)
                        }
                    }
                    .tint(Theme.primary)
                    .rowFrame()
                }
                section("GOOGLE DRIVE") {
                    row("บัญชี Google", session.email.flatMap { $0.isEmpty ? nil : $0 } ?? "เชื่อมต่อแล้ว")
                    divider
                    // from members/<email>.role; set by a manager in สมาชิกทีม or in the Firebase console
                    row("บทบาท", permissions.role.label)
                    divider
                    Button {
                        let q = DriveFolders.root.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://drive.google.com/drive/search?q=\(q)") { openURL(url) }
                    } label: { row("โฟลเดอร์หลัก", DriveFolders.root + " ›") }
                    .buttonStyle(.plain)
                    divider
                    Button { confirmLogout = true } label: {
                        Text("ออกจากระบบ").font(.sarabun(16, .bold)).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity).rowFrame()
                    }
                    .buttonStyle(.plain)
                }
                section("ซิงค์ข้อมูลทีม") {
                    row("สถานะ", (sync.state == .synced ? "✓ " : "") + sync.state.title)
                    if let last = sync.lastSync {
                        divider
                        row("ซิงค์ล่าสุด", ThaiFormat.short.string(from: last) + " " + ThaiFormat.time.string(from: last))
                    }
                    if case .failed(let message) = sync.state {
                        divider
                        Text(message).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.danger).rowFrame()
                        divider
                        Button { sync.retry() } label: {
                            Text("ลองอีกครั้ง").font(.sarabun(16, .bold)).foregroundStyle(Theme.primary).frame(maxWidth: .infinity).rowFrame()
                        }
                        .buttonStyle(.plain)
                    }
                }
                section("เกี่ยวกับ") {
                    row("แอป", "TCRoof Internal")
                    divider
                    row("เวอร์ชัน", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                #if DEBUG
                section("นักพัฒนา") {
                    Button { showGallery = true } label: { row("คอมโพเนนต์", "ดูทุกสถานะ ›") }
                        .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .font(.sarabun(16))
        .background(Theme.phonePage)
        #if DEBUG
        .fullScreenCover(isPresented: $showGallery) {
            NavigationStack {
                ComponentGallery()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { showGallery = false } } }
            }
        }
        #endif
    }

    /// One switch per notification group, and a way back in when iOS has them turned off.
    private var notificationsSection: some View {
        section("การแจ้งเตือน") {
            switch notifications.authorization {
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("การแจ้งเตือนถูกปิดอยู่").foregroundStyle(Theme.danger)
                        Text("แตะเพื่อเปิดในการตั้งค่าของ iPhone ›").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(ink.muted)
                    }
                    .rowFrame()
                }
                .buttonStyle(.plain)
                divider
            case .notDetermined:
                Button { Task { await notifications.requestAuthorization() } } label: {
                    Text("อนุญาตการแจ้งเตือน").font(.sarabun(16, .bold)).foregroundStyle(Theme.primary).rowFrame()
                }
                .buttonStyle(.plain)
                divider
            default: EmptyView()
            }
            ForEach(Array(NotificationGroup.allCases.enumerated()), id: \.element) { i, group in
                if i > 0 { divider }
                NotificationGroupToggle(group: group).rowFrame()
            }
        }
        .task { await notifications.refreshAuthorization() }
    }

    private var accountCard: some View {
        HStack(spacing: 12) {
            Text(userInitials(userName, email: session.email)).font(.sarabun(17, .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 48, height: 48).background(Theme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(userName.isEmpty ? (session.email ?? "—") : userName).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text("วิศวกรสำรวจ").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(ink.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if sync.state == .synced {
                Text("✓ ซิงค์แล้ว").font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.successInk)
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Theme.paperBand, in: Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(ink.border)
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabun(12.5, .bold, relativeTo: .caption)).foregroundStyle(ink.muted)
                .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }.card(ink.border)
        }
        .padding(.top, 18)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(ink.muted)
            Spacer(minLength: 8)
            Text(value).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1).truncationMode(.middle)
        }
        .rowFrame()
        .accessibilityElement(children: .combine)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    /// `ต้องสอบเทียบ 2 ›`: the tools due for calibration within 30 days or past it, else a bare chevron.
    private var toolsValue: String {
        let due = instruments.dueCount()
        return due > 0 ? "ต้องสอบเทียบ \(due) ›" : "›"
    }
}

private struct NotificationGroupToggle: View {
    let group: NotificationGroup
    @AppStorage private var on: Bool

    init(group: NotificationGroup) {
        self.group = group
        _on = AppStorage(wrappedValue: true, group.defaultsKey)
    }

    var body: some View {
        Toggle(isOn: $on) { Text(group.title).foregroundStyle(Theme.navy) }
            .tint(Theme.primary)
            .onChange(of: on) { Task { await NotificationService.shared.groupChanged(group) } }
    }
}

private extension View {
    func rowFrame() -> some View {
        padding(.horizontal, 14).padding(.vertical, 4).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    func card(_ border: Color) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border))
    }
}
