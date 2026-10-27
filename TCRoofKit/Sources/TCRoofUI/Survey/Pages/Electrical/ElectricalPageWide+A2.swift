#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Small `A2` tag on a field whose value came from, or matches, a symbol on the A2 picture (docs/ui/a2-a3-autofill).
struct A2Badge: View {
    var body: some View {
        Text("A2").font(.sarabunFixed(10.5, .bold)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 5).frame(height: 18)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
            .accessibilityLabel("กรอกจากภาพ A2")
    }
}

/// Keeps A3's `SiteSync.Summary` until the symbols, transformers, board names or B4 levels change: the badges and the
/// button read it from several cards on every render, and A3 renders on every keystroke.
final class A2SyncCache {
    private var inputs: SiteSync.Inputs?
    private var value = SiteSync.Summary()
    func summary(_ job: Job) -> SiteSync.Summary {
        let now = SiteSync.Inputs(job)
        if now != inputs { inputs = now; value = SiteSync.summary(job) }
        return value
    }
}

// MARK: ดึงจากภาพ A2

extension ElectricalPageWide {
    var a2Sync: SiteSync.Summary { a2Cache.summary(job) }
    var a2Badges: Set<SiteSync.Field> { a2Sync.badges }

    /// `ดึงจากภาพ A2 | N รายการ`, orange `| ต่างกัน n` with conflicts; opens the panel (a sheet on iPhone).
    @ViewBuilder var a2Button: some View {
        let items = a2Sync.items
        if !items.isEmpty {
            let conflicts = items.filter(\.status.isConflict).count
            let linked = items.filter(\.status.isLinked).count
            let tint = conflicts > 0 ? Theme.pending : Theme.primary
            Button { showA2.toggle() } label: {
                if narrow {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 15, weight: .semibold))
                        Text(conflicts > 0 ? "ดึงจากภาพ A2 | ต่างกัน \(conflicts)" : "ดึงจากภาพ A2 | \(linked) รายการ")
                            .font(.sarabunFixed(14, .bold)).lineLimit(1)
                        Text("▾").font(.sarabunFixed(12))
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(conflicts > 0 ? Theme.pendingSoft : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(conflicts > 0 ? Theme.warning : Theme.primary.opacity(0.3)))
                } else {
                    compactA2Label(conflicts: conflicts)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(narrow ? "ข้อมูลที่ดึงจากภาพ A2"
                                : conflicts > 0 ? "ดึงจากภาพ A2 | ต่างกัน \(conflicts) รายการ" : "ดึงจากภาพ A2 | \(linked) รายการ")
            .popover(isPresented: narrow ? .constant(false) : $showA2, arrowEdge: .top) { a2Panel.frame(width: 440) }
            .sheet(isPresented: narrow ? $showA2 : .constant(false)) { a2Panel.presentationDetents([.medium, .large]) }
        }
    }

    /// iPad (docs/ui/survey-a3-ipad-v3 §1.1): `A2 ใส่จากภาพ A2`, orange with `ต่างกัน n` while values differ.
    func compactA2Label(conflicts: Int) -> some View {
        HStack(spacing: 8) {
            A2Badge()
            Text("ใส่จากภาพ A2").font(.sarabunFixed(16, .bold)).lineLimit(1)
            if conflicts > 0 { Text("ต่างกัน \(conflicts)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.pending).lineLimit(1) }
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(conflicts > 0 ? Theme.pendingSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(conflicts > 0 ? Theme.warning : Theme.primary.opacity(0.35)))
    }

    var a2Panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ใส่ให้อัตโนมัติจากภาพ A2").font(.sarabunFixed(20, .bold))
                    Spacer()
                    Button { showA2 = false } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("ปิด")
                }
                ForEach(a2Sync.items) { a2Row($0) }
                Divider().padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    (Text("ช่องที่มีป้าย ") + Text("A2").bold().foregroundColor(Theme.primary)
                        + Text(" กรอกให้อัตโนมัติจากสัญลักษณ์บนภาพ A2 | วางหม้อแปลง / MDB ใหม่บน A2 จะสร้างการ์ดในผังนี้ให้ | แก้ที่หน้านี้แล้วป้ายบนภาพ A2 เปลี่ยนตาม | ช่องที่กรอกเองไว้แล้วจะไม่ถูกทับ ให้เลือกเอง"))
                    Text(SiteSync.notSent)
                }
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .foregroundStyle(Theme.navy)
    }

    func a2Row(_ it: SiteSync.Item) -> some View {
        let conflict: (a3: String, a2: String)? = { if case .conflict(let x, let y) = it.status { return (x, y) }; return nil }()
        let skipped = { if case .skipped = it.status { return true }; return false }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(it.symbol).font(.sarabunFixed(14, .bold)).lineLimit(1)
                    .padding(.horizontal, 10).frame(minWidth: 64, minHeight: 30)
                    .overlay(Capsule().stroke(Theme.navy, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.title).font(.sarabunFixed(17, .bold)).lineLimit(1)
                    if !it.target.isEmpty { Text("→ " + it.target).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(2) }
                }
                Spacer(minLength: 4)
                if conflict != nil {
                    Text("ต่างกัน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.pending)
                        .padding(.horizontal, 10).frame(minHeight: 26).background(Theme.warning.opacity(0.15), in: Capsule())
                } else if !skipped {
                    Text("✓ ใส่แล้ว").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.success).fixedSize()
                }
            }
            if let c = conflict {
                HStack(spacing: 8) {
                    Text("หน้านี้ \(c.a3) | A2 \(c.a2)" + (it.unit.map { " " + $0 } ?? ""))
                        .font(.sarabunFixed(14)).foregroundStyle(Theme.pending).lineLimit(2)
                    Spacer(minLength: 4)
                    Button { SiteSync.useA2(&job, mark: it.id) } label: {
                        Text("ใช้ค่า A2").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    Button { SiteSync.keepA3(&job, mark: it.id) } label: {
                        Text("คงค่านี้").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(conflict != nil ? Theme.pendingSoft : skipped ? Theme.disabledFill : Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(conflict != nil ? Theme.warning : Color.clear, lineWidth: 1.5))
        .opacity(skipped ? 0.75 : 1)
        .accessibilityElement(children: .contain)
    }
}
#endif
