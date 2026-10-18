import SwiftUI
import TCRoofCore
import TCRoofUI

/// `ผู้ใช้` (`states/03`, `05`–`09`): the list on the left, the selected member on the right.
extension UserAdminView {
    var filtered: [UserAdminStore.Member] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.shown.filter { m in
            (roleFilter == nil || m.role == roleFilter)
                && (q.isEmpty || m.label.lowercased().contains(q) || m.email.contains(q)
                    || (store.jobsByEmail[m.email] ?? []).contains { $0.lowercased().contains(q) })
        }
    }

    var selectedMember: UserAdminStore.Member? {
        let list = filtered
        if let selected, let m = list.first(where: { $0.email == selected }) { return m }
        return list.first { $0.email != me && $0.role != .maintainer } ?? list.first
    }

    func avatarColor(_ m: UserAdminStore.Member) -> Color {
        let i = store.shown.firstIndex { $0.email == m.email } ?? 0
        return UserAdminStyle.avatars[i % UserAdminStyle.avatars.count]
    }

    func status(_ m: UserAdminStore.Member) -> (String, Color) {
        if m.unsaved { return ("ยังไม่บันทึก", Theme.warning) }
        if m.suspended { return ("ระงับ", Theme.dangerText) }
        if m.pending { return ("รอส่งขึ้นระบบ", Theme.warning) }
        return ("ใช้งาน", Theme.success)
    }

    /// The status's second line: when it was suspended or invited (the documents' own dates).
    func since(_ m: UserAdminStore.Member) -> String {
        if m.suspended, let at = m.suspendedAt { return "ระงับ " + ThaiFormat.numericDate.string(from: at) }
        if let at = m.invitedAt { return "เชิญ " + ThaiFormat.numericDate.string(from: at) }
        return m.unsaved ? "รอบันทึก" : "—"
    }

    func jobs(_ m: UserAdminStore.Member) -> [String] { store.jobsByEmail[m.email] ?? [] }

    var usersTab: some View {
        HStack(alignment: .top, spacing: 16) {
            AdminCard {
                VStack(spacing: 0) {
                    listToolbar
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    userList
                }
            }
            .frame(maxHeight: .infinity)
            if let m = selectedMember {
                UserDetail(view: self, member: m).frame(width: 440).frame(maxHeight: .infinity)
            }
        }
    }

    /// One row at the board's width; narrower (iPad portrait), the role filter gets its own scrolling row.
    private var listToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { roleSegments; searchField; inviteButton }
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) { roleSegments }
                HStack(spacing: 10) { searchField; inviteButton }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var roleSegments: some View {
        AdminSegments(items: [AdminSegments<UserRole?>.Item(id: nil, title: "ทั้งหมด", count: store.shown.count)]
            + UserRole.every.sorted { order($0) < order($1) }.map { r in
                AdminSegments<UserRole?>.Item(id: r, title: r == .external ? "ภายนอก" : r.label,
                                              count: store.shown.filter { $0.role == r }.count)
            }, selected: roleFilter, stretch: false) { roleFilter = $0 }
            .fixedSize()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("ค้นหาชื่อ อีเมล งาน", text: $search)
                .font(.sarabun(14)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(Theme.stripFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.track))
        .frame(minWidth: 200)
    }

    private var inviteButton: some View {
        Button { ask(.invite) } label: { Label("เพิ่มผู้ใช้", systemImage: "plus") }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .accessibilityLabel("เพิ่มผู้ใช้ด้วยอีเมล")
            .accessibilityIdentifier("userAdmin.invite")
            .fixedSize()
    }

    private func order(_ r: UserRole) -> Int { [.maintainer: 0, .manager: 1, .internalTeam: 2, .external: 3][r] ?? 4 }

    private var userList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { m in userRow(m).id(m.email) }
                    if filtered.isEmpty {
                        Text(store.loaded ? "ไม่มีผู้ใช้ในตัวกรองนี้" : "กำลังโหลดรายชื่อ…")
                            .font(.sarabun(14)).foregroundStyle(Theme.muted).padding(40)
                    }
                }
            }
            // a row selected from elsewhere (an invite just added) comes into view
            .onChange(of: selected) { _, e in if let e { withAnimation { proxy.scrollTo(e) } } }
            .task { if let e = selected { try? await Task.sleep(for: .milliseconds(300)); proxy.scrollTo(e) } }
        }
    }

    private func userRow(_ m: UserAdminStore.Member) -> some View {
        let on = m.email == selectedMember?.email
        let (st, color) = status(m)
        return Button { selected = m.email; if roleEditing != m.email { roleEditing = nil } } label: {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    UserAvatar(name: m.name ?? m.email, color: avatarColor(m), dot: color)
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(m.label).font(.sarabun(14.5, .bold))
                         + Text(m.email == me ? " (คุณ)" : "").font(.sarabun(11, .semibold)).foregroundColor(Theme.primary))
                            .foregroundStyle(Theme.navy)
                        Text(m.email).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    RolePill(role: m.role)
                    Text(scopeLine(m)).font(.sarabun(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(st).font(.sarabun(12, .bold)).foregroundStyle(color)
                    Text(since(m)).font(.sarabun(11.5)).foregroundStyle(Theme.muted)
                }
                .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(minHeight: 62)
            .background(on ? Theme.unreadRow : Theme.surface)
            .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("userAdmin.row.\(m.email)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The team sees every job; an external member, their own.
    func scopeLine(_ m: UserAdminStore.Member) -> String {
        let n = jobs(m).count
        switch m.role {
        case .external: return n == 0 ? "ไม่มีงาน" : "\(n) งาน"
        case .maintainer, .manager: return "ทุกโครงการ"
        case .internalTeam: return n == 0 ? "ทุกโครงการ" : "ทุกโครงการ · ชื่ออยู่ใน \(n) งาน"
        }
    }
}

/// The detail panel of the selected member: beside the list on iPad, a pushed page on iPhone (`compact`,
/// docs/ui/user-admin-iphone states 02, 03, 09).
struct UserDetail: View {
    let view: UserAdminView
    let member: UserAdminStore.Member
    var compact = false

    private var store: UserAdminStore { view.store }
    private var editing: Bool { view.roleEditing == member.email }
    private var isMaintainer: Bool { member.role == .maintainer }
    private var cells: [(Capability, RoleAccess)] { Capability.allCases.map { ($0, $0.access(member.role, overrides: store.overrides)) } }

    var body: some View {
        if compact { phoneBody } else { padBody }
    }

    private var padBody: some View {
        AdminCard {
            VStack(spacing: 0) {
                head
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isMaintainer { maintainerCard } else { roleSection }
                        scope
                        duties
                        summary
                        groups
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                footer
            }
        }
    }

    @ViewBuilder
    private var duties: some View {
        if member.role == .external { DutyCard(jobs: view.jobs(member).count, overrides: store.overrides) }
    }

    private var phoneBody: some View {
        ScrollView {
            VStack(spacing: 14) {
                AdminCard {
                    VStack(alignment: .leading, spacing: 14) {
                        phoneHead
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        if isMaintainer { maintainerCard } else { roleSection }
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        scope
                    }
                    .padding(16)
                }
                duties
                AdminCard {
                    VStack(alignment: .leading, spacing: 12) {
                        summary
                        groups
                    }
                    .padding(16)
                }
                footerButton
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, store.pendingCount > 0 ? 160 : 28)
        }
        .accessibilityIdentifier("userAdmin.detail")
    }

    private var phoneHead: some View {
        let (st, color) = view.status(member)
        return HStack(spacing: 14) {
            UserAvatar(name: member.name ?? member.email, color: view.avatarColor(member), size: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.label).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                if member.name?.isEmpty == false {
                    Text(member.email).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
                Text(st + " · " + view.since(member)).font(.sarabun(12.5, .bold)).foregroundStyle(color)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var head: some View {
        let (st, color) = view.status(member)
        return HStack(spacing: 12) {
            UserAvatar(name: member.name ?? member.email, color: view.avatarColor(member), size: 52)
            VStack(alignment: .leading, spacing: 0) {
                Text(member.label).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                if member.name?.isEmpty == false {
                    Text(member.email).font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
                }
                Text(st + " · " + view.since(member)).font(.sarabun(12, .bold)).foregroundStyle(color)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if !isMaintainer { editButton }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    @ViewBuilder
    private var editButton: some View {
        if editing {
            Button("เสร็จ") { view.roleEditing = nil }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
                .accessibilityIdentifier("userAdmin.roleDone")
        } else {
            Button {
                if member.email == view.me { view.toast = "เปลี่ยนบทบาทของตัวเองไม่ได้" } else { view.ask(.role(member.email)) }
            } label: { Label("แก้ไขบทบาท", systemImage: "lock") }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .accessibilityIdentifier("userAdmin.editRole")
        }
    }

    private var maintainerCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Maintainer · ทำได้ทุกอย่าง").font(.sarabun(15, .bold))
            Text("ทุกสิทธิ์ของ 3 บทบาท + ปิดบัญชี คีย์นักพัฒนา ตั้งค่าระบบ · เปลี่ยนหรือปิดบัญชีจากหน้านี้ไม่ได้").font(.sarabun(12)).opacity(0.9)
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.maintainerGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 6) {
            if compact {
                HStack {
                    Text("บทบาท").font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    editButton
                }
            } else {
                Text("บทบาท").font(.sarabun(13, .bold)).foregroundStyle(Theme.navy)
            }
            if editing {
                AdminSegments(items: UserRole.allCases.map {
                    .init(id: $0, title: $0 == .external ? "ภายนอก" : $0.label, detail: $0.english, tint: UserAdminStyle.ink($0))
                }, selected: member.role, height: 52, radius: 11) { role in
                    if member.email == view.me { view.toast = "เปลี่ยนบทบาทของตัวเองไม่ได้" } else { store.setRole(role, of: member.email) }
                }
                .accessibilityIdentifier("userAdmin.roleControl")
            } else {
                let line = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                line {
                    RolePill(role: member.role, size: 13)
                    Text("\(member.role.english) · แก้ได้หลังยืนยันคีย์").font(.sarabun(12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, compact ? 12 : 0)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Theme.stripFill, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.track))
            }
            if let to = store.roleChanges[member.email], let from = store.members.first(where: { $0.email == member.email })?.role {
                diffBox(RoleChange(from: from, to: to, overrides: store.overrides))
            }
        }
    }

    private func diffBox(_ c: RoleChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(c.from.label) → \(c.to.label) · ได้เพิ่ม \(c.gained.count) · เสีย \(c.lost.count)")
                .font(.sarabun(13, .bold)).foregroundStyle(Theme.slotColumnInk)
                .accessibilityIdentifier("userAdmin.diff")
            FlowChips(items: c.gained.prefix(4).map { ("+ " + $0.label, true) } + c.lost.prefix(4).map { ("− " + $0.label, false) })
            Button("ยกเลิกการเปลี่ยนบทบาท") { store.undoRole(of: member.email) }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.slotColumnFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.slotColumnLine))
        .padding(.top, 2)
    }

    private var scope: some View {
        let jobs = view.jobs(member)
        let external = member.role == .external
        let chips: [(String, Bool)] = external
            ? (jobs.isEmpty ? [("ยังไม่มีงาน · มอบหมายจากหน้างาน", true)] : jobs.map { ($0, true) })
            : [("ทุกโครงการ", true)] + jobs.map { ($0, false) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(external ? "งานที่ได้รับมอบหมาย" : "ขอบเขต").font(.sarabun(13, .bold)).foregroundStyle(Theme.navy)
            FlowLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                    Text(c.0).font(.sarabun(12, .bold)).foregroundStyle(c.1 ? Theme.primary : Theme.inkMuted)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(c.1 ? Theme.primarySoft : Theme.stripeLight, in: Capsule())
                }
            }
        }
    }

    private func count(_ a: RoleAccess) -> Int { cells.filter { $0.1 == a }.count }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("สิทธิ์").font(.sarabun(13, .bold)).foregroundStyle(Theme.navy)
                Text("ทำได้ \(count(.allow)) · มีเงื่อนไข \(count(.conditional)) · ดู \(count(.view)) · ไม่ได้ \(count(.deny))")
                    .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
            }
            GeometryReader { geo in
                let parts: [(RoleAccess, Color)] = [(.allow, Theme.success), (.conditional, Theme.warning), (.view, Theme.primary), (.deny, Theme.borderSubtle)]
                let total = max(1, parts.reduce(0) { $0 + count($1.0) })
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { p in
                        if count(p.0) > 0 { p.1.frame(width: max(0, (geo.size.width - 6) * CGFloat(count(p.0)) / CGFloat(total))) }
                    }
                }
            }
            .frame(height: 6).clipShape(Capsule())
        }
    }

    private var groups: some View {
        VStack(spacing: 6) {
            ForEach(Capability.groups) { g in group(g) }
        }
    }

    private static let order: [RoleAccess: Int] = [.allow: 0, .conditional: 1, .view: 2, .deny: 3, .disabled: 4]

    private func group(_ g: CapabilityGroup) -> some View {
        let items = g.capabilities.map { ($0, $0.access(member.role, overrides: store.overrides)) }
            .filter { $0.1 != .disabled }
            .sorted { Self.order[$0.1]! < Self.order[$1.1]! }
        let open = view.openGroups.contains(g.id)
        let n = { (a: RoleAccess) in items.filter { $0.1 == a }.count }
        return VStack(spacing: 0) {
            Button {
                if open { view.openGroups.remove(g.id) } else { view.openGroups.insert(g.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0))
                    Text(g.label).font(.sarabun(13, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                    countChip(n(.allow), Theme.successText, Theme.successSoft)
                    countChip(n(.conditional), Theme.warningText, Theme.warningSoft)
                    countChip(n(.deny) + n(.view), Theme.inkFaint, Theme.stripeLight)
                }
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Theme.stripFill)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            if open {
                VStack(spacing: 0) {
                    ForEach(items, id: \.0) { item in permRow(item.0, item.1) }
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.track))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func countChip(_ n: Int, _ ink: Color, _ fill: Color) -> some View {
        if n > 0 {
            Text("\(n)").font(.sarabun(11, .heavy)).foregroundStyle(ink)
                .frame(minWidth: 22, minHeight: 20).padding(.horizontal, 2)
                .background(fill, in: Capsule())
        }
    }

    private func permRow(_ c: Capability, _ a: RoleAccess) -> some View {
        let (icon, ink, fill): (String, Color, Color) = switch a {
        case .allow: ("✓", Theme.successText, Theme.successSoft)
        case .view: ("ดู", Theme.primary, Theme.primarySoft)
        case .deny, .disabled: ("✕", Theme.inkFaint, Theme.stripeLight)
        case .conditional: ("!", Theme.warningText, Theme.warningSoft)
        }
        let note = a == .conditional ? c.note(member.role) : a == .view ? "ดูได้อย่างเดียว" : nil
        return HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.sarabun(10.5, .heavy)).foregroundStyle(ink)
                .frame(minWidth: 22, minHeight: 20).padding(.horizontal, 2)
                .background(fill, in: Capsule())
            VStack(alignment: .leading, spacing: 0) {
                Text(c.label).font(.sarabun(13)).foregroundStyle(a == .deny ? Theme.inkFaint : Theme.navy)
                if let note { Text(note).font(.sarabun(11)).foregroundStyle(Theme.warningInk) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stripeLight).frame(height: 1) }
    }

    private var footer: some View {
        footerButton.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var footerButton: some View {
        // `ออกจากระบบทุกเครื่อง` is left out: the app has no remote sign-out (docs/ui/user-admin-ipad "No source")
        let suspended = member.suspended
        let title = isMaintainer ? "ปิดบัญชีไม่ได้"
            : member.unsaved ? "เอาออกจากรายชื่อ"
            : suspended ? "เปิดใช้งานอีกครั้ง · Maintainer" : "ปิดบัญชี · Maintainer"
        return Button(title) {
            if member.email == view.me || isMaintainer { view.toast = "ปิดบัญชีของตัวเองไม่ได้"; return }
            store.toggleSuspension(of: member.email)
        }
        .buttonStyle(TCButtonStyle(isMaintainer ? .secondary : .destructive, size: .card, fullWidth: true))
        .opacity(isMaintainer ? 0.5 : 1)
        .accessibilityIdentifier("userAdmin.suspend")
    }
}

/// Wrapping chips of the diff box.
struct FlowChips: View {
    let items: [(String, Bool)]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                // FlowLayout measures each chip unconstrained, so a long label is shortened here
                Text(c.0.count > 46 ? c.0.prefix(45) + "…" : c.0).font(.sarabun(11.5, .bold))
                    .foregroundStyle(c.1 ? Theme.successText : Theme.dangerText)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(c.1 ? Theme.successSoft : Theme.dangerSoft, in: Capsule())
            }
        }
    }
}
