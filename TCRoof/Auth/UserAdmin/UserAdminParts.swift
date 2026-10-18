import SwiftUI
import TCRoofCore
import TCRoofUI

/// Small pieces of จัดการผู้ใช้และสิทธิ์.
enum UserAdminStyle {
    /// The avatars' colours, by the row's index (the board's `AV`).
    static let avatars: [Color] = [Theme.primary, Theme.success, Theme.planInspect, Theme.warning, Theme.navySolid,
                                   Theme.dangerText, Theme.sheetSource5Line]

    /// Two letters of the name (Thai leading vowels skipped), else of the email.
    static func initials(_ name: String) -> String {
        // the first letter of each of two words: Thai leading vowels and marks (ั ิ ่ …) skipped, as the board's `ini`
        let leading: Set<Unicode.Scalar> = ["เ", "แ", "โ", "ใ", "ไ"]
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { w in
            w.unicodeScalars.first { $0.properties.isAlphabetic && $0.properties.generalCategory != .nonspacingMark && !leading.contains($0) }
        }
        var out = String(String.UnicodeScalarView(letters)).uppercased()
        if out.isEmpty { out = name.first.map { String($0).uppercased() } ?? "?" }
        return out
    }

    static func ink(_ role: UserRole) -> Color {
        switch role {
        case .manager: Theme.navy
        case .internalTeam: Theme.primary
        case .external: Theme.warningText
        case .maintainer: Theme.onPrimary
        }
    }

    static func fill(_ role: UserRole) -> AnyShapeStyle {
        switch role {
        case .manager: AnyShapeStyle(Theme.ganttTrack)
        case .internalTeam: AnyShapeStyle(Theme.primarySoft)
        case .external: AnyShapeStyle(Theme.warningTint)
        case .maintainer: AnyShapeStyle(Theme.maintainerGradient)
        }
    }

    /// An audit entry's kind pill: ink and fill.
    static func kind(_ k: AuditKind) -> (Color, Color) {
        switch k {
        case .role: (Theme.primary, Theme.primarySoft)
        case .perm: (Theme.warningText, Theme.warningSoft)
        case .user: (Theme.successText, Theme.successSoft)
        case .key: (Theme.planInspect, Theme.planInspectSoft)
        case .sus: (Theme.dangerText, Theme.dangerSoft)
        }
    }

    static func cellInk(_ a: RoleAccess) -> Color {
        switch a {
        case .allow: Theme.onPrimary
        case .view: Theme.primary
        case .deny, .disabled: Theme.inkFaint
        case .conditional: Theme.warningText
        }
    }

    static func cellFill(_ a: RoleAccess) -> AnyShapeStyle {
        switch a {
        case .allow: AnyShapeStyle(Theme.success)
        case .view: AnyShapeStyle(Theme.primarySoft)
        case .deny: AnyShapeStyle(Theme.stripeLight)
        case .conditional: AnyShapeStyle(Theme.warningSoft)
        case .disabled: AnyShapeStyle(Theme.stripeDark)
        }
    }
}

struct RolePill: View {
    let role: UserRole
    var size: CGFloat = 12
    var body: some View {
        Text(role.label).font(.sarabun(size, .bold)).foregroundStyle(UserAdminStyle.ink(role))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(UserAdminStyle.fill(role), in: Capsule())
    }
}

struct UserAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 40
    /// The status dot (nil: none).
    var dot: Color?
    var body: some View {
        Text(UserAdminStyle.initials(name)).font(.sarabun(size * 0.33, .bold)).foregroundStyle(Theme.onPrimary)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if let dot {
                    Circle().fill(dot).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A rounded segment track with its chips (the tabs, the role filter, the role control).
struct AdminSegments<ID: Hashable>: View {
    struct Item: Identifiable {
        var id: ID
        var title: String
        var detail: String? = nil
        var count: Int? = nil
        var tint: Color = Theme.navy
    }
    let items: [Item]
    let selected: ID?
    var height: CGFloat = 38
    var radius: CGFloat = 19
    var stretch = true
    var pick: (ID) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item.id == selected
                Button { pick(item.id) } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 5) {
                            Text(item.title).font(.sarabun(item.detail == nil ? 14 : 13.5, on ? .bold : .semibold))
                            if let n = item.count { Text("\(n)").font(.sarabun(12, .bold)).foregroundStyle(Theme.inkMuted) }
                        }
                        if let d = item.detail { Text(d).font(.sarabun(10.5, .semibold)).opacity(0.75) }
                    }
                    .lineLimit(1)
                    .foregroundStyle(on ? item.tint : Theme.inkMuted)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: stretch ? .infinity : nil, minHeight: max(height, 38))
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: radius - 3, style: .continuous).fill(Theme.surface)
                                .shadow(color: Theme.navySolid.opacity(0.16), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: radius + 3, style: .continuous))
    }
}

/// White card with the board's border.
struct AdminCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
