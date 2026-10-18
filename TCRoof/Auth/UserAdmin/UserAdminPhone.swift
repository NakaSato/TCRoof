import SwiftUI
import TCRoofCore
import TCRoofUI

/// จัดการผู้ใช้และสิทธิ์ in compact width (docs/ui/user-admin-iphone, `PhoneUsers.dc.html` states 00–09): one column,
/// the member's detail pushed over the list, the roles table one role at a time. The store, the sheets and every rule
/// are the iPad page's.
extension UserAdminView {
    var phonePage: some View {
        ZStack {
            Theme.phonePage.ignoresSafeArea()
            VStack(spacing: 0) {
                phoneHeader
                if phoneDetail == nil { phoneTabs }
                phoneContent
            }
            if store.pendingCount > 0 { phonePendingBar }
            // above the pending bar, as the board's toast
            Color.clear.allowsHitTesting(false)
                .padding(.bottom, store.pendingCount > 0 ? 150 : 16)
                .tcToast($toast)
            if !store.isUnlocked {
                DevKeyLockScreen(store: store, onBack: leave, compact: true)
                    .transition(.opacity)
            }
            if let keyAsk { keySheet(keyAsk) }
            if inviting { InviteSheet(store: store, compact: true, done: { inviting = false; if let e = $0 { added(e) } }) }
            if !sent.isEmpty { sentSheet }
        }
        .animation(.easeOut(duration: 0.22), value: phoneDetail)
        .animation(.easeOut(duration: 0.22), value: keyAsk)
        .animation(.easeOut(duration: 0.22), value: inviting)
        .confirmationDialog("มีการแก้ไขที่ยังไม่บันทึก", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("ทิ้งการแก้ไข \(store.pendingCount) รายการ", role: .destructive) { store.discard(); close() }
            Button("กลับไปบันทึก", role: .cancel) {}
        } message: {
            Text("ออกจากหน้านี้แล้วการแก้ไขที่ยังไม่บันทึกจะหายไป")
        }
    }

    // MARK: header and tabs

    private var phoneHeader: some View {
        HStack(spacing: 12) {
            Button { if phoneDetail != nil { popDetail() } else { leave() } } label: {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(phoneDetail != nil ? "กลับไปรายชื่อ" : "กลับไปตั้งค่า")
            .accessibilityIdentifier("userAdmin.back")
            VStack(alignment: .leading, spacing: 0) {
                Text(phoneDetail != nil ? "รายละเอียดผู้ใช้" : "จัดการผู้ใช้และสิทธิ์").font(.sarabun(22, .bold))
                Label("นักพัฒนา · ปลดล็อกเหลือ \(remainingText) นาที", systemImage: "clock")
                    .font(.sarabun(13)).opacity(0.9).monospacedDigit()
            }
            .foregroundStyle(Theme.onPrimary)
            .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button(action: lock) {
                Image(systemName: "lock").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ล็อกหน้านี้")
            .accessibilityIdentifier("userAdmin.lock")
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    private var remainingText: String {
        let left = Int(store.remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    private var phoneTabs: some View {
        AdminSegments(items: [
            .init(id: Tab.users, title: "ผู้ใช้", count: store.shown.count),
            .init(id: Tab.roles, title: "สิทธิ์", count: UserRole.allCases.count),
            .init(id: Tab.log, title: "ประวัติ", count: store.log.count),
        ], selected: tab) { t in
            tab = t
            roleEditing = nil
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    @ViewBuilder
    private var phoneContent: some View {
        if let email = phoneDetail, let m = store.shown.first(where: { $0.email == email }) {
            UserDetail(view: self, member: m, compact: true)
                .transition(.move(edge: .trailing))
        } else {
            Group {
                switch tab {
                case .users: phoneUsers
                case .roles: phoneRoles
                case .log: phoneLog
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.move(edge: .leading))
        }
    }

    private var phoneBottom: CGFloat { store.pendingCount > 0 ? 160 : 28 }

    func popDetail() {
        phoneDetail = nil
        roleEditing = nil
    }

    // MARK: ผู้ใช้ (01)

    private var phoneUsers: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("ค้นหาชื่อ อีเมล งาน", text: $search)
                            .font(.sarabun(15)).foregroundStyle(Theme.navy)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderSubtle))
                    Button { ask(.invite) } label: {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 44, height: 44)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("เพิ่มผู้ใช้ด้วยอีเมล")
                    .accessibilityIdentifier("userAdmin.invite")
                }
                .padding(.horizontal, 16)
                phoneRoleChips
                AdminCard {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { m in phoneRow(m) }
                        if filtered.isEmpty {
                            Text(store.loaded ? "ไม่มีผู้ใช้ในตัวกรองนี้" : "กำลังโหลดรายชื่อ…")
                                .font(.sarabun(14)).foregroundStyle(Theme.muted).padding(32)
                        }
                    }
                }
                .padding(.horizontal, 16)
                HStack(spacing: 6) {
                    Circle().fill(store.offline ? Theme.warning : Theme.success).frame(width: 8, height: 8)
                    Text(syncLine).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 14).padding(.bottom, phoneBottom)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var phoneRoleChips: some View {
        let roles: [UserRole?] = [nil, .maintainer, .manager, .internalTeam, .external]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(roles, id: \.self) { r in
                    let on = r == roleFilter
                    let n = r.map { r in store.shown.filter { $0.role == r }.count } ?? store.shown.count
                    Button { roleFilter = r } label: {
                        HStack(spacing: 5) {
                            Text(r.map { $0 == .external ? "ภายนอก" : $0.label } ?? "ทั้งหมด").font(.sarabun(14, on ? .bold : .semibold))
                            Text("\(n)").font(.sarabun(12.5, .bold)).opacity(0.7)
                        }
                        .foregroundStyle(on ? Theme.onPrimary : Theme.projectTabInk)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(on ? Theme.navySolid : Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func phoneRow(_ m: UserAdminStore.Member) -> some View {
        let (st, color) = status(m)
        return Button {
            selected = m.email
            if roleEditing != m.email { roleEditing = nil }
            phoneDetail = m.email
        } label: {
            HStack(spacing: 12) {
                UserAvatar(name: m.name ?? m.email, color: avatarColor(m), dot: color)
                VStack(alignment: .leading, spacing: 2) {
                    (Text(m.label).font(.sarabun(15, .bold))
                     + Text(m.email == me ? " (คุณ)" : "").font(.sarabun(11, .semibold)).foregroundColor(Theme.primary))
                        .foregroundStyle(Theme.navy)
                    if m.name?.isEmpty == false {
                        Text(m.email).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    }
                    HStack(spacing: 6) {
                        RolePill(role: m.role, size: 11.5)
                        Text(scopeLine(m)).font(.sarabun(12)).foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                // the board's last activity under the status has no source (docs/ui/user-admin-iphone data rules)
                Text(st).font(.sarabun(13, .bold)).foregroundStyle(color)
                    .fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 72)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("userAdmin.row.\(m.email)")
    }

    // MARK: สิทธิ์ (06, 07)

    private var phoneRoles: some View {
        VStack(spacing: 12) {
            AdminSegments(items: UserRole.allCases.map { r in
                .init(id: r, title: r == .external ? "ภายนอก" : r.label,
                      detail: "\(r.english) · \(store.shown.filter { $0.role == r }.count) คน", tint: UserAdminStyle.ink(r))
            }, selected: phoneRole, height: 52, radius: 13) { phoneRole = $0 }
            .accessibilityIdentifier("userAdmin.roleSegment")
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Button { if matrixEditing { matrixEditing = false } else { ask(.matrix) } } label: {
                    Label(matrixEditing ? "เสร็จ" : "แก้ไขสิทธิ์และกฎ", systemImage: "lock")
                        .font(.sarabun(14, .bold))
                        .foregroundStyle(matrixEditing ? Theme.onPrimary : Theme.primary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(matrixEditing ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(matrixEditing ? Color.clear : Theme.borderOutdoor))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("userAdmin.matrixEdit")
                Button { onlyChanged.toggle() } label: {
                    Text(onlyChanged ? "แสดงทั้งหมด" : "เฉพาะที่แก้ (\(phoneChanged.count))")
                        .font(.sarabun(14, .bold))
                        .foregroundStyle(onlyChanged ? Theme.onPrimary : Theme.projectTabInk)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(onlyChanged ? Theme.navySolid : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(onlyChanged ? Color.clear : Theme.borderSubtle))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(onlyChanged ? .isSelected : [])
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 12) {
                    phoneMatrixCard
                    phoneLegend
                    rulesCard
                    decisionsCard
                }
                .padding(.horizontal, 16).padding(.bottom, phoneBottom)
            }
        }
        .padding(.top, 12)
    }

    /// This role's changed cells.
    private var phoneChanged: Set<Capability> { Set(store.changedCells.filter { $0.0 == phoneRole }.map(\.1)) }

    private var phoneMatrixCard: some View {
        let changed = phoneChanged
        let groups = Capability.groups.map { g in (g, g.capabilities.filter { !onlyChanged || changed.contains($0) }) }.filter { !$0.1.isEmpty }
        return AdminCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("สิทธิ์ของ\(phoneRole.label)").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                    Text(matrixEditing ? "แตะเพื่อเปลี่ยน" : "แก้ได้หลังยืนยันคีย์").font(.sarabun(12)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 4)
                if groups.isEmpty {
                    Text("ยังไม่มีสิทธิ์ที่แก้ของบทบาทนี้").font(.sarabun(14)).foregroundStyle(Theme.muted).padding(.vertical, 24)
                }
                ForEach(groups, id: \.0.id) { g, caps in
                    Text(g.label).font(.sarabun(12.5, .bold)).foregroundStyle(Theme.muted)
                        .padding(.top, 12).padding(.bottom, 2)
                    ForEach(caps, id: \.self) { c in phoneMatrixRow(c) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private func phoneMatrixRow(_ c: Capability) -> some View {
        let r = phoneRole
        let a = c.access(r, overrides: store.overrides)
        let changed = store.overrides[r, c] != store.savedOverrides[r, c]
        let enforced = Capability.enforcedByRules.contains(c)
        let note = Capability.maintainerOnly.contains(c) ? "เฉพาะ Maintainer" : a == .conditional ? c.note(r) : nil
        return Button {
            guard matrixEditing else { return ask(.matrix) }
            if let reason = c.lockReason(for: r) { toast = reason; return }
            store.cycle(r, c)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.label).font(.sarabun(14.5)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                    Text(enforced ? "\(c.rawValue) · บังคับใน rules" : c.rawValue).font(.sarabun(12)).foregroundStyle(Theme.inkFaint)
                    if let note { Text(note).font(.sarabun(12)).foregroundStyle(Theme.warningInk) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(a == .deny ? "✕" : a.label).font(.sarabun(12.5, .bold))
                    .foregroundStyle(UserAdminStyle.cellInk(a))
                    .padding(.horizontal, 12).frame(minWidth: 40, minHeight: 28)
                    .background(UserAdminStyle.cellFill(a), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.pendingYellow, lineWidth: changed ? 2.5 : 0).padding(-3))
                    .fixedSize()
            }
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .overlay(alignment: .top) { Rectangle().fill(Theme.stripeLight).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(c.access(.manager) == .disabled ? 0.7 : 1)
        .accessibilityLabel("\(r.label) · \(c.label) · \(a.label)" + (note.map { " (\($0))" } ?? ""))
        .accessibilityIdentifier("userAdmin.cell.\(r.rawValue)|\(c.rawValue)")
    }

    private var phoneLegend: some View {
        let items: [(RoleAccess, String)] = [(.allow, ""), (.conditional, "ตามงานที่ได้รับมอบหมาย"), (.view, ""), (.deny, "ไม่ได้"), (.disabled, "BOQ")]
        return FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { a, d in
                HStack(spacing: 6) {
                    Text(a.label).font(.sarabun(11, .bold)).foregroundStyle(UserAdminStyle.cellInk(a))
                        .padding(.horizontal, 8).frame(minHeight: 20)
                        .background(UserAdminStyle.cellFill(a), in: Capsule())
                    if !d.isEmpty { Text(d).font(.sarabun(12)).foregroundStyle(Theme.inkMuted) }
                }
            }
            Text("บังคับใน rules: แก้ใน firestore.rules เท่านั้น").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: ประวัติ (08)

    private var phoneLog: some View {
        ScrollView {
            AdminCard {
                LazyVStack(spacing: 0) {
                    ForEach(store.log) { e in phoneLogRow(e) }
                    if store.log.isEmpty {
                        Text("ยังไม่มีประวัติการแก้ไข").font(.sarabun(14)).foregroundStyle(Theme.muted).padding(32)
                    }
                    Text("auditLog · เพิ่มได้อย่างเดียว ลบไม่ได้").font(.sarabun(12)).foregroundStyle(Theme.muted)
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 14)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, phoneBottom)
        }
    }

    private func phoneLogRow(_ e: UserAdminStore.AuditEntry) -> some View {
        let who = store.shown.first { $0.email == e.by }
        let (ink, fill) = UserAdminStyle.kind(e.kind)
        return HStack(alignment: .top, spacing: 12) {
            UserAvatar(name: who?.name ?? e.by, color: who.map(avatarColor) ?? Theme.primary, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                Text(e.detail.isEmpty ? e.by : e.detail).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(e.kind.label).font(.sarabun(12, .bold)).foregroundStyle(ink)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .background(fill, in: Capsule())
                    Text(e.at.map { ThaiFormat.dayMonthTime.string(from: $0) } ?? "รอเวลาจากเซิร์ฟเวอร์")
                        .font(.sarabun(13)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: pending bar

    private var phonePendingBar: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(Theme.pendingYellow).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("แก้ไข \(store.pendingCount) รายการ · ยังไม่บันทึก").font(.sarabun(15, .bold))
                            .accessibilityIdentifier("userAdmin.pending")
                        Text("บันทึกแล้วจะซิงก์ members/<email>.role ให้ทุกเครื่อง").font(.sarabun(12)).opacity(0.8)
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                }
                HStack(spacing: 10) {
                    Button { store.discard(); roleEditing = nil } label: {
                        Text("ยกเลิกทั้งหมด").font(.sarabun(15, .bold)).foregroundStyle(Theme.onPrimary).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    Button(action: save) {
                        Text("บันทึกและซิงก์").font(.sarabun(15, .heavy)).foregroundStyle(Theme.onSun).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.pendingYellow, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Theme.navySolid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.35), radius: 16, y: 12)
            .padding(.horizontal, 12).padding(.bottom, 24)
        }
        .ignoresSafeArea(.keyboard)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("การเปลี่ยนแปลงที่ยังไม่บันทึก")
    }
}
