#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

// MARK: - Breaker Sheet

/// Edit one outgoing breaker of the main board: a sheet on iPhone, and on iPad (`popover`) the board's popover
/// anchored to the row (docs/ui/survey-a3-ipad-v3 state 06): AT / AF / Icu / ยี่ห้อ menus, สภาพ and `เสร็จ` on top,
/// the other fields below.
struct BreakerSheet: View {
    @Binding var breaker: Breaker
    let isMain: Bool
    let onDelete: () -> Void
    /// The row's number, for the popover's title `CB ลูกย่อย n`.
    var number: Int? = nil
    var popover = false
    @Environment(\.dismiss) private var dismiss
    /// iPhone: delete and done in the bottom bar (docs/ui/components/iphone-bottom-bar, state 07).
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if popover { popoverBody } else { sheetBody }
    }

    // the same fields in both layouts

    var at: Binding<String> { Binding(get: { breaker.at }, set: { breaker.at = NumberInput.clean($0) }) }
    var af: Binding<String> { Binding(get: { breaker.af }, set: { breaker.af = NumberInput.clean($0) }) }
    var ic: Binding<String> { Binding(get: { breaker.ic }, set: { breaker.ic = NumberInput.clean($0) }) }
    var poles: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "จำนวนขั้ว")
            A3Segments(options: ["2", "3", "4"], titles: ["2P", "3P", "4P"], selected: breaker.poles) { breaker.poles = $0 }
        }
    }
    var condition: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "สภาพ", required: popover)
            A3Segments(options: ["ดี", "พอใช้", "ชำรุด"], selected: breaker.condition) { breaker.condition = $0 }
        }
    }
    var target: some View { A3Input(label: "ปลายทาง (ป้อนไปที่)", text: $breaker.target) }
    func deleteButton() -> some View {
        Button(role: .destructive, action: onDelete) {
            Label("ลบ CB ลูกย่อยนี้", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(TCButtonStyle(.secondary, size: .card))
    }

    var sheetBody: some View {
        let phone = sizeClass == .compact
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        A3Input(label: "AT (ตั้งตัด)", text: at, unit: "A", keyboard: .numberPad)
                        A3Input(label: "AF (เฟรม)", text: af, unit: "A", keyboard: .numberPad)
                        A3Input(label: "IC", text: ic, unit: "kA", keyboard: .decimalPad)
                    }
                    poles
                    A3Input(label: "ยี่ห้อ / รุ่น", text: $breaker.brand)
                    target
                    condition
                    BreakerSLDFields(breaker: $breaker)
                    if !phone { deleteButton().padding(.top, 8) }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if phone {
                    BottomBar(variant: .detail(destructive: .init(title: "ลบ CB ลูกย่อยนี้", action: onDelete),
                                               primary: .init(title: "เสร็จ") { dismiss() }))
                }
            }
            .navigationTitle("CB ลูกย่อย").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !phone { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } } }
        }
    }

    var popoverHeader: some View {
        HStack(spacing: 8) {
            Text("CB ลูกย่อย" + (number.map { " \($0)" } ?? "")).font(.sarabunFixed(17, .bold))
            Text("MCCB" + (breaker.poles.isEmpty ? "" : " \(breaker.poles)P")).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 4)
            Button { dismiss() } label: {
                Text("เสร็จ").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    var popoverMenus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                A3MenuField(label: "AT (ตั้งตัด)", text: at, options: A3Options.subAT, required: true, unit: "A", keyboard: .numberPad)
                A3MenuField(label: "AF (เฟรม)", text: af, options: A3Options.subAF, required: true, unit: "A", keyboard: .numberPad,
                            auto: A3Options.autoAF(at: breaker.at, frames: A3Options.subAF))
            }
            HStack(alignment: .top, spacing: 8) {
                A3MenuField(label: "Icu", text: ic, options: A3Options.subIcu, required: true, unit: "kA", keyboard: .decimalPad, flagEmpty: true)
                A3MenuField(label: "ยี่ห้อ", text: $breaker.brand, options: A3Options.breakerBrands, required: true, prompt: "เลือกยี่ห้อ",
                            flagEmpty: true, addTitle: "อื่น ๆ")
            }
        }
    }

    var popoverBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                popoverHeader
                popoverMenus
                condition
                Divider().padding(.vertical, 2)
                poles
                target
                BreakerSLDFields(breaker: $breaker)
                deleteButton().padding(.top, 4)
            }
            .padding(16)
        }
        .frame(width: 400)
        .frame(minHeight: 420, idealHeight: 640, maxHeight: 720)
        .foregroundStyle(Theme.navy)
    }
}
#endif
