import SwiftUI
import TCRoofCore
import TCRoofUI

/// The 6 dots and the 3 × 4 pad of the developer key, on the dark lock gradient (`states/01`, `02`, `04`).
struct DevKeyPad: View {
    @Binding var pin: String
    var error: String?
    /// Bumped on a wrong key to shake the dots.
    var shake: Int
    var disabled: Bool
    var keySize: CGFloat
    var dotSize: CGFloat
    var onComplete: (String) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "ล้าง", "0", "⌫"]

    var body: some View {
        VStack(spacing: 12) {
            dots
            Text(error ?? " ")
                .font(.sarabun(keySize > 80 ? 14 : 13, .bold)).foregroundStyle(Theme.keyError)
                .frame(minHeight: 20)
                .accessibilityIdentifier("devKey.error")
            grid
        }
    }

    private var dots: some View {
        HStack(spacing: keySize > 80 ? 16 : 14) {
            ForEach(0..<DevKey.length, id: \.self) { i in
                Circle()
                    .fill(i < pin.count ? Theme.onPrimary : Color.clear)
                    .overlay(Circle().strokeBorder(Theme.onPrimary.opacity(i < pin.count ? 0 : 0.55), lineWidth: 2))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .modifier(ShakeEffect(shakes: CGFloat(shake)))
        .animation(.linear(duration: 0.4), value: shake)
        .padding(.top, 10)
        .accessibilityElement()
        .accessibilityLabel("ใส่แล้ว \(pin.count) จาก 6 หลัก")
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(keySize), spacing: keySize > 80 ? 26 : 22), count: 3)
        return LazyVGrid(columns: columns, spacing: keySize > 80 ? 14 : 10) {
            ForEach(keys, id: \.self) { key in
                Button { press(key) } label: { keyLabel(key) }
                    .buttonStyle(.plain)
                    .disabled(disabled && key.first?.isNumber == true)
                    .accessibilityLabel(key == "⌫" ? "ลบ" : key)
                    .accessibilityIdentifier("devKey.\(key)")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func keyLabel(_ key: String) -> some View {
        let digit = key.first?.isNumber == true
        Group {
            if key == "⌫" {
                Image(systemName: "delete.left").font(.system(size: 20, weight: .semibold))
            } else {
                Text(key).font(.sarabun(digit ? (keySize > 80 ? 30 : 26) : (keySize > 80 ? 16 : 15), digit ? .semibold : .bold))
            }
        }
        .foregroundStyle(Theme.onPrimary.opacity(disabled && digit ? 0.4 : 1))
        .frame(width: keySize, height: keySize)
        .background(digit ? Theme.onPrimary.opacity(0.14) : Color.clear, in: Circle())
        .contentShape(Circle())
    }

    private func press(_ key: String) {
        switch key {
        case "ล้าง": pin = ""
        case "⌫": if !pin.isEmpty { pin.removeLast() }
        default:
            guard !disabled, pin.count < DevKey.length else { return }
            pin += key
            if pin.count == DevKey.length {
                let entered = pin
                pin = ""
                onComplete(entered)
            }
        }
    }
}

/// Side to side, as the board's `@keyframes shake`.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 4), y: 0))
    }
}

/// The lock screen over the whole page (`states/01`, `02`): the key opens it for 15 minutes.
struct DevKeyLockScreen: View {
    let store: UserAdminStore
    var onBack: () -> Void
    /// iPhone: 76 pt keys and 16 pt margins (docs/ui/user-admin-iphone state 00).
    var compact = false
    @State private var pin = ""
    @State private var error: String?
    @State private var shake = 0

    var body: some View {
        ZStack {
            Theme.devLockGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                center
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: initialError)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.onPrimary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับไปตั้งค่า")
            Text("ตั้งค่า › นักพัฒนา").font(.sarabun(15)).foregroundStyle(Theme.onPrimary.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, compact ? 16 : 40).padding(.top, compact ? 8 : 24)
    }

    private var center: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock").font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.onPrimary)
                .frame(width: 76, height: 76)
                .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.onPrimary.opacity(0.25)))
            Text("จัดการผู้ใช้และสิทธิ์").font(.sarabun(26, .bold)).foregroundStyle(Theme.onPrimary)
            Text("เฉพาะนักพัฒนา | ใส่คีย์นักพัฒนา 6 หลักเพื่อเปิดหน้านี้").font(.sarabun(15)).foregroundStyle(Theme.onPrimary.opacity(0.78))
            keyBody
            footer
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var keyBody: some View {
        switch store.keyState {
        case .loading:
            ProgressView().tint(Theme.onPrimary).padding(40)
        case .ready:
            DevKeyPad(pin: $pin, error: error, shake: shake, disabled: store.padLocked, keySize: compact ? 76 : 84, dotSize: 16, onComplete: submit)
        case .missing, .expired, .unreadable:
            VStack(spacing: 12) {
                Text(unavailableText).font(.sarabun(15, .bold)).foregroundStyle(Theme.keyError)
                    .accessibilityIdentifier("devKey.unavailable")
                if store.keyState == .unreadable {
                    Button("ลองอีกครั้ง") { store.loadKey() }.buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            }
            .padding(.vertical, 30)
        }
    }

    private var unavailableText: String {
        switch store.keyState {
        case .expired: "คีย์หมดอายุ | ตั้งคีย์ใหม่ใน Firebase console"
        case .missing: "ยังไม่มีคีย์นักพัฒนา | ตั้งคีย์ใน Firebase console (config/devKey)"
        default: "อ่านคีย์ไม่ได้ | ต่ออินเทอร์เน็ตแล้วลองอีกครั้ง"
        }
    }

    private var footer: some View {
        var lines = ["คีย์ออกให้โดยผู้ดูแลระบบ | เปลี่ยนทุก 30 วัน | ปลดล็อกได้ครั้งละ 15 นาที"]
        lines.append(store.demo ? "ใส่ผิด 5 ครั้งจะล็อก 10 นาที | คีย์ตัวอย่างในบอร์ด 246810" : "ใส่ผิด 5 ครั้งจะล็อก 10 นาที")
        return Text(lines.joined(separator: "\n")).font(.sarabun(12)).foregroundStyle(Theme.onPrimary.opacity(0.6))
            .padding(.top, 8)
    }

    private func initialError() {
        if store.padLocked { error = "ล็อก 10 นาที | ติดต่อผู้ดูแลระบบ" }
        else if store.attempts.failures > 0 { error = "คีย์ไม่ถูกต้อง | เหลือ \(store.attempts.left) ครั้ง" }
    }

    private func submit(_ digits: String) {
        switch store.check(digits, unlock: true) {
        case .ok: error = nil
        case .wrong(let left): error = "คีย์ไม่ถูกต้อง | เหลือ \(left) ครั้ง"; shake += 1
        case .locked: error = "ล็อก 10 นาที | ติดต่อผู้ดูแลระบบ"; shake += 1
        case .unavailable: error = unavailableText
        }
    }
}

/// Why the key is asked again (`states/04`).
enum DevKeyPurpose: Equatable {
    case role(String)
    case invite
    case matrix
}

/// The smaller key sheet before a role edit, an invite or the matrix.
struct DevKeySheet: View {
    let store: UserAdminStore
    let purpose: DevKeyPurpose
    let subject: String
    /// iPhone: a bottom sheet the width of the screen (docs/ui/user-admin-iphone state 05).
    var compact = false
    var onDone: (Bool) -> Void
    @State private var pin = ""
    @State private var error: String?
    @State private var shake = 0

    var body: some View {
        ZStack(alignment: compact ? .bottom : .center) {
            Theme.navySolid.opacity(0.55).ignoresSafeArea().onTapGesture { onDone(false) }
            if compact { phoneSheet } else { padSheet }
        }
        .onAppear { if store.padLocked { error = "ล็อก 10 นาที | ติดต่อผู้ดูแลระบบ" } }
    }

    private var phoneSheet: some View {
        VStack(spacing: 12) {
            Capsule().fill(Theme.onPrimary.opacity(0.35)).frame(width: 40, height: 5).padding(.bottom, 4)
            sheetContent
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.devLockGradient).ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ยืนยันคีย์")
        .transition(.move(edge: .bottom))
    }

    @ViewBuilder
    private var sheetContent: some View {
        Image(systemName: "lock").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.onPrimary)
            .frame(width: 52, height: 52)
            .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.onPrimary.opacity(0.25)))
        Text(title).font(.sarabun(20, .bold)).foregroundStyle(Theme.onPrimary)
        Text(subtitle).font(.sarabun(13)).foregroundStyle(Theme.onPrimary.opacity(0.78))
        DevKeyPad(pin: $pin, error: error, shake: shake, disabled: store.padLocked, keySize: 72, dotSize: 14, onComplete: submit)
        Button { onDone(false) } label: {
            Text("ยกเลิก").font(.sarabun(15, .bold)).foregroundStyle(Theme.onPrimary.opacity(0.85))
                .frame(minWidth: 88, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var padSheet: some View {
            VStack(spacing: 12) {
                Image(systemName: "lock").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 56, height: 56)
                    .background(Theme.onPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.onPrimary.opacity(0.25)))
                Text(title).font(.sarabun(20, .bold)).foregroundStyle(Theme.onPrimary)
                Text(subtitle).font(.sarabun(13)).foregroundStyle(Theme.onPrimary.opacity(0.78))
                DevKeyPad(pin: $pin, error: error, shake: shake, disabled: store.padLocked, keySize: 72, dotSize: 14, onComplete: submit)
                Button { onDone(false) } label: {
                    Text("ยกเลิก").font(.sarabun(15, .bold)).foregroundStyle(Theme.onPrimary.opacity(0.85))
                        .frame(minWidth: 88, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            .frame(width: 400)
            .background(Theme.devLockGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.45), radius: 30, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("ยืนยันคีย์")
    }

    private var title: String {
        switch purpose {
        case .invite: "ยืนยันคีย์เพื่อเพิ่มผู้ใช้"
        case .matrix: "ยืนยันคีย์เพื่อแก้สิทธิ์และกฎ"
        case .role: "ยืนยันคีย์เพื่อแก้บทบาท"
        }
    }

    private var subtitle: String {
        switch purpose {
        case .invite: "การเพิ่มอีเมลให้สิทธิ์เข้าแอปทันทีหลังซิงก์ | ใส่คีย์นักพัฒนาอีกครั้ง"
        case .matrix: "ตารางสิทธิ์และกฎการใช้งานมีผลกับทุกคน | ใส่คีย์นักพัฒนาอีกครั้ง"
        case .role: "ใส่คีย์นักพัฒนาอีกครั้งเพื่อเปลี่ยนบทบาทของ \(subject)"
        }
    }

    private func submit(_ digits: String) {
        switch store.check(digits, unlock: false) {
        case .ok: onDone(true)
        case .wrong(let left): error = "คีย์ไม่ถูกต้อง | เหลือ \(left) ครั้ง"; shake += 1
        case .locked: error = "ล็อก 10 นาที | ติดต่อผู้ดูแลระบบ"; shake += 1
        case .unavailable: error = "คีย์ใช้ไม่ได้ | ตั้งคีย์ใหม่ใน Firebase console"
        }
    }
}
