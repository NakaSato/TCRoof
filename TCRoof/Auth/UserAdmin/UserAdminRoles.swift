import SwiftUI
import TCRoofCore
import TCRoofUI

/// `บทบาทและสิทธิ์` (`states/10`, `11`) and `ประวัติการแก้ไข` (`states/12`).
extension UserAdminView {
    /// The matrix with the rules beside it; narrower than the board (iPad portrait), the rules follow the matrix.
    var rolesTab: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                matrixCard(rulesBelow: false).frame(minWidth: 900)
                ScrollView {
                    VStack(spacing: 12) {
                        rulesCard
                        decisionsCard
                    }
                }
                .frame(width: 300)
            }
            matrixCard(rulesBelow: true)
        }
    }

    private func matrixCard(rulesBelow: Bool) -> some View {
        AdminCard {
            VStack(spacing: 0) {
                matrixHead
                Rectangle().fill(Theme.borderSubtle).frame(height: 1)
                matrixRows(rulesBelow: rulesBelow)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                legend
            }
        }
        .frame(maxHeight: .infinity)
    }

    private static let column: CGFloat = 190

    private var matrixHead: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("สิทธิ์ \(Capability.allCases.count) รายการ").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text("ตาม docs/reference/roles/user-roles.json | กดแก้ไขและยืนยันคีย์ก่อนเปลี่ยน").font(.sarabun(11)).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    Button { if matrixEditing { matrixEditing = false } else { ask(.matrix) } } label: {
                        Label(matrixEditing ? "กำลังแก้ไข | เสร็จ" : "แก้ไขสิทธิ์และกฎ", systemImage: "lock")
                            .font(.sarabun(12, .bold))
                            .foregroundStyle(matrixEditing ? Theme.onPrimary : Theme.primary)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(matrixEditing ? Theme.primary : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(matrixEditing ? Color.clear : Theme.borderOutdoor))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("userAdmin.matrixEdit")
                    Button { onlyChanged.toggle() } label: {
                        Text(onlyChanged ? "แสดงทั้งหมด" : "แสดงเฉพาะที่แก้ (\(store.changedCells.count))")
                            .font(.sarabun(12, .bold))
                            .foregroundStyle(onlyChanged ? Theme.onPrimary : Theme.projectTabInk)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(onlyChanged ? Theme.navySolid : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(onlyChanged ? Color.clear : Theme.borderSubtle))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(UserRole.allCases, id: \.self) { r in
                VStack(spacing: 3) {
                    RolePill(role: r)
                    Text("\(r.english) | \(store.shown.filter { $0.role == r }.count) คน").font(.sarabun(11)).foregroundStyle(Theme.inkMuted)
                }
                .frame(width: Self.column)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private func matrixRows(rulesBelow: Bool) -> some View {
        let changed = Set(store.changedCells.map { $0.1 })
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Capability.groups) { g in
                    let caps = g.capabilities.filter { !onlyChanged || changed.contains($0) }
                    if !caps.isEmpty {
                        Section {
                            ForEach(caps, id: \.self) { c in matrixRow(c) }
                        } header: {
                            Text(g.label).font(.sarabun(12, .bold)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12).padding(.bottom, 4)
                                .background(Theme.surface)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
            if rulesBelow {
                VStack(spacing: 12) { rulesCard; decisionsCard }.padding(16)
            }
        }
    }

    private func matrixRow(_ c: Capability) -> some View {
        let disabled = c.access(.manager) == .disabled
        let enforced = Capability.enforcedByRules.contains(c)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(c.label).font(.sarabun(13.5)).foregroundStyle(Theme.navy)
                Text(enforced ? "\(c.rawValue) | บังคับใน rules" : c.rawValue).font(.sarabun(11)).foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            ForEach(UserRole.allCases, id: \.self) { r in matrixCell(c, r) }
        }
        .frame(minHeight: 46)
        .opacity(disabled ? 0.7 : 1)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stripeLight).frame(height: 1) }
    }

    private func matrixCell(_ c: Capability, _ r: UserRole) -> some View {
        let a = c.access(r, overrides: store.overrides)
        let changed = store.overrides[r, c] != store.savedOverrides[r, c]
        let reason = c.lockReason(for: r)
        let note = Capability.maintainerOnly.contains(c) ? "เฉพาะ Maintainer" : a == .conditional ? c.note(r) : nil
        return Button {
            guard matrixEditing else { return ask(.matrix) }
            if let reason { toast = reason; return }
            store.cycle(r, c)
        } label: {
            VStack(spacing: 2) {
                Text(a.label).font(.sarabun(12, .bold))
                .foregroundStyle(UserAdminStyle.cellInk(a))
                .padding(.horizontal, 10).frame(minHeight: 24)
                .background(UserAdminStyle.cellFill(a), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.pendingYellow, lineWidth: changed ? 2.5 : 0).padding(-2.5))
                if let note {
                    Text(note).font(.sarabun(10.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineLimit(2)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(width: Self.column).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(r.label) | \(c.label) | \(a.label)" + (note.map { " (\($0))" } ?? ""))
        .accessibilityIdentifier("userAdmin.cell.\(r.rawValue)|\(c.rawValue)")
    }

    private var legend: some View {
        let items: [(RoleAccess, String)] = [(.allow, ""), (.conditional, "ตามงานที่ได้รับมอบหมาย"), (.view, ""), (.deny, "ไม่ได้"), (.disabled, "BOQ")]
        return HStack(spacing: 12) {
            ForEach(items, id: \.0) { a, d in
                HStack(spacing: 6) {
                    Text(a.label).font(.sarabun(11, .bold)).foregroundStyle(UserAdminStyle.cellInk(a))
                        .padding(.horizontal, 8).frame(minHeight: 20)
                        .background(UserAdminStyle.cellFill(a), in: Capsule())
                    if !d.isEmpty { Text(d) }
                }
            }
            Text("บังคับใน rules: แก้ใน firestore.rules เท่านั้น")
            Spacer(minLength: 0)
        }
        .font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// The rules that are facts of the system, shown locked on. `ปิดบัญชีเมื่อไม่ใช้งาน 30 วัน` is left out: nothing
    /// in the app does it (docs/ui/user-admin-ipad "No source").
    static let rules: [(String, String)] = [
        ("ปิด / ระงับบัญชีได้เฉพาะ Maintainer", "ผู้จัดการตั้งบทบาทและเพิ่มสมาชิกได้ แต่ปิดบัญชีไม่ได้ | ล็อกไว้"),
        ("เข้าได้เฉพาะอีเมลในรายชื่อสมาชิก", "members/<email> | บัญชีอื่นถูกล้างข้อมูลในเครื่อง"),
        ("คนภายนอกเห็นเฉพาะงานที่ได้รับมอบหมาย", "บังคับใน firestore.rules | ข้อมูลติดต่อลูกค้าแยกใน jobContacts"),
        ("iPad ใช้ร่วมกันต้องล็อกอินแยกคน", "บทบาทมีผลตามบัญชีที่ล็อกอิน"),
    ]

    var rulesCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("กฎการใช้งาน").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy).padding(.bottom, 8)
                ForEach(Self.rules, id: \.0) { t, d in
                    Button {
                        if !matrixEditing { ask(.matrix) } else { toast = "กฎนี้ล็อกไว้ | เป็นข้อเท็จจริงของระบบ" }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t).font(.sarabun(13)).foregroundStyle(Theme.navy)
                                Text(d).font(.sarabun(11)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            lockedSwitch
                        }
                        .frame(minHeight: 44)
                        .padding(.vertical, 4)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.stripeLight).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t)
                    .accessibilityValue("เปิด | ล็อกไว้")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    /// An iOS switch drawn on and dimmed: these can't be turned off.
    private var lockedSwitch: some View {
        Capsule().fill(Theme.success).frame(width: 51, height: 31)
            .overlay(alignment: .trailing) {
                Circle().fill(Theme.surface).frame(width: 27, height: 27).padding(2)
                    .shadow(color: Theme.navySolid.opacity(0.15), radius: 4, y: 3)
            }
            .opacity(0.55)
    }

    /// The board's `ข้อตกลง` (`v.dec`), static.
    static let decisions = [
        "รายงานประจำวัน: หัวหน้างานผู้รับเหมากรอก วิศวกรของเราเซ็นรับทราบ | แผน MP นับเฉพาะที่เซ็นแล้ว",
        "IEC 62446: ผู้รับเหมาทดสอบและส่งผล ทีมภายในปิด | นับ 3.1 เข้าแผน MP เมื่อทีมภายในปิด",
        "วิศวกรภายนอกกับผู้รับเหมาใช้บทบาทเดียวกัน (external)",
        "ผู้รับเหมาต้องส่ง: รายงานประจำวันทุกวันที่เข้างาน | คำขอรายสัปดาห์ทุกสัปดาห์ | ผล IEC 62446 ก่อนและหลังขนาน (เฉพาะงานที่ได้รับมอบหมาย)",
        "เซ็นตรวจรับขั้นสุดท้าย: ผู้จัดการ หรือวิศวกรภายในผู้ควบคุมงานของงานนั้น",
        "Drive: ทีมอัปโหลดเข้า Drive กลาง | ผู้รับเหมาเข้า Drive ของตัวเอง แชร์ให้ทีมอ่าน",
        "BOQ ปิดใช้งานทุกบทบาท",
        "ปิด / ระงับบัญชีผู้ใช้: เฉพาะ Maintainer (ผู้จัดการตั้งบทบาทได้ แต่ปิดบัญชีไม่ได้)",
    ]

    var decisionsCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("ข้อตกลง").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                ForEach(Self.decisions, id: \.self) { d in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.primary).frame(width: 5, height: 5).padding(.top, 7)
                        Text(d).font(.sarabun(12)).foregroundStyle(Theme.projectTabInk)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: log

    var logTab: some View {
        AdminCard {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.log) { e in logRow(e) }
                    if store.log.isEmpty {
                        Text("ยังไม่มีประวัติการแก้ไข").font(.sarabun(14)).foregroundStyle(Theme.muted).padding(40)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func logRow(_ e: UserAdminStore.AuditEntry) -> some View {
        let who = store.shown.first { $0.email == e.by }
        let (ink, fill) = UserAdminStyle.kind(e.kind)
        return HStack(spacing: 12) {
            Text(e.at.map { ThaiFormat.dayMonthTime.string(from: $0) } ?? "รอเวลาจากเซิร์ฟเวอร์")
                .font(.sarabun(13)).foregroundStyle(Theme.inkMuted).frame(width: 140, alignment: .leading)
            UserAvatar(name: who?.name ?? e.by, color: who.map(avatarColor) ?? Theme.primary, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                Text(e.detail.isEmpty ? e.by : e.detail).font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.kind.label).font(.sarabun(12, .bold)).foregroundStyle(ink)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(fill, in: Capsule())
                .frame(width: 140, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
