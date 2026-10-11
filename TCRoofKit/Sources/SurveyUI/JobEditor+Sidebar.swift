#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import TCRoofUI
import PDFReport
import DriveSync

/// Section list: job header, sections by category, add-section footer.
extension JobEditorView {
    /// One entry in the sidebar: code badge, short title, and how much of it is filled.
    struct SidebarItem: Identifiable {
        let page: Page
        let code: String
        let title: String
        let completion: Completion
        var module: SurveyModule? = nil
        var id: Page { page }
    }
    struct SidebarGroup: Identifiable {
        let category: SectionCategory
        let items: [SidebarItem]
        var id: SectionCategory { category }
    }

    /// Sections in workbook order, grouped by category (A general, B–D added sections, E sign-off).
    var sidebarGroups: [SidebarGroup] {
        let steps = job.steps
        return SectionCategory.allCases.compactMap { cat in
            let items = steps.filter { $0.category == cat }.map { s in
                SidebarItem(page: Self.page(for: s.page), code: s.code, title: s.title, completion: s.completion,
                            module: s.page.moduleID.flatMap { id in job.modules.first { $0.id == id } })
            }
            return items.isEmpty ? nil : SidebarGroup(category: cat, items: items)
        }
    }

    /// First section with required fields still empty — the header's "continue" shortcut.
    var nextIncomplete: SidebarItem? {
        guard let next = job.nextStep else { return nil }
        return sidebarGroups.flatMap(\.items).first { $0.page == Self.page(for: next.page) }
    }

    func category(of p: Page) -> SectionCategory? {
        switch p {
        case .summary: return nil
        case .info, .site, .electrical, .flood: return .general
        case .final, .photos, .revisions: return .summary
        case .module(let id): return job.modules.first { $0.id == id }?.spec.category
        }
    }

    var sidebar: some View {
        let groups = sidebarGroups
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sidebarHeader
                    row(SidebarItem(page: .summary, code: "", title: "สรุปภาพรวม 1 หน้า", completion: Completion()), symbol: "doc.text.magnifyingglass")
                    if !readOnly { cardImportRow }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            groupHeader(g)
                            if !collapsed.contains(g.category) {
                                ForEach(g.items) { item in
                                    if let m = item.module, !readOnly {
                                        row(item).contextMenu {
                                            Button { duplicate(m) } label: { Label("ทำสำเนาหัวข้อ", systemImage: "plus.square.on.square") }
                                            Button(role: .destructive) { confirmDelete = m } label: { Label("ลบหัวข้อ", systemImage: "trash") }
                                        }
                                    } else {
                                        row(item)
                                    }
                                }
                            }
                        }
                    }
                    reviewRows
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .trailing) { if !compact { Rectangle().fill(Theme.borderSubtle).frame(width: 1) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { if !readOnly { sidebarFooter } }
            // keep the open section visible when "next" or "continue" jumps into a collapsed group
            .onChange(of: page) { _, p in
                if let c = category(of: p) { collapsed.remove(c) }
                withAnimation { proxy.scrollTo(p) }
            }
        }
    }

    /// Project card: number, name, overall ring, one bar per step and the "continue" shortcut.
    var sidebarHeader: some View {
        let c = job.completion
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NO.\(job.docNo.isEmpty ? " —" : job.docNo)").font(.sarabun(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    Text(job.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : job.projectName)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(job.projectName.isEmpty ? Theme.inkMuted : Theme.navy)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PercentRing(percent: c.percent, size: 48)
            }
            HStack(spacing: 3) {
                ForEach(job.stepStatuses, id: \.step.id) { s in Capsule().fill(stepColor(s.status)).frame(height: 5) }
            }
            HStack(spacing: 10) {
                Text("กรอกแล้ว \(c.filled)/\(c.total) ช่อง")
                Spacer()
                Label("\(job.photoCount)", systemImage: "photo")
            }
            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            photoStatus
            if job.isLocked && job.stage == .survey {
                Label("REV \(job.rev) ล็อก · \(FormHash.short(job.lock?.hash ?? ""))", systemImage: "lock.fill").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.borderSubtle, in: Capsule())
            } else if readOnly {
                Label("ล็อก · อยู่ในงานติดตั้ง", systemImage: "lock").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.borderSubtle, in: Capsule())
            } else if let next = nextIncomplete, next.page != page {
                Button { select(next.page) } label: {
                    HStack(spacing: 6) {
                        Text("ทำต่อ").font(.sarabun(12, relativeTo: .caption)).opacity(0.85)
                        Text(next.code).font(.sarabun(15, .heavy, relativeTo: .subheadline))
                        Text(next.title).font(.sarabun(15, .bold, relativeTo: .subheadline)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.sarabun(12, .bold, relativeTo: .caption))
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }

    func stepColor(_ s: SurveyStep.Status) -> Color {
        switch s {
        case .complete: return Theme.mint
        case .current: return Theme.primary
        case .missing: return Theme.dangerLine
        case .notStarted: return Theme.track
        }
    }

    /// Download progress, or how many photos are still only on another device.
    @ViewBuilder var photoStatus: some View {
        let gap = PhotoGap(model: model, job: job)
        if let f = model.photoFetch[job.id], f.running {
            HStack(spacing: 6) {
                ProgressView(value: Double(f.done + f.failed), total: Double(f.total)).tint(Theme.primary).frame(width: 60)
                Text("กำลังดึงรูปจาก Drive \(f.done)/\(f.total)")
            }
            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        } else if let u = model.photoUpload[job.id], u.running {
            HStack(spacing: 6) {
                ProgressView(value: Double(u.done), total: Double(max(u.total, 1))).tint(Theme.primary).frame(width: 60)
                Text("กำลังอัปรูปขึ้น Drive \(u.done)/\(u.total)")
            }
            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        } else if let e = model.photoUpload[job.id]?.error, model.photosToUpload(job) > 0 {
            Label("อัปรูปขึ้น Drive ไม่สำเร็จ: \(e)", systemImage: "exclamationmark.icloud")
                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.pending).lineLimit(3)
        } else if gap.missing > 0 {
            Label("รูป \(gap.missing) รูปยังไม่อยู่ในเครื่องนี้", systemImage: "icloud.slash")
                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.pending)
        }
    }

    /// Category letter and name, sections done, and a chevron to fold the group.
    func groupHeader(_ g: SidebarGroup) -> some View {
        let done = g.items.filter(\.completion.isComplete).count
        let all = done == g.items.count
        let open = !collapsed.contains(g.category)
        return Button { withAnimation(.snappy) { if open { collapsed.insert(g.category) } else { collapsed.remove(g.category) } } } label: {
            HStack(spacing: 8) {
                Text(g.category.rawValue).font(.sarabun(12, .heavy, relativeTo: .caption)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Theme.navySolid, in: RoundedRectangle(cornerRadius: 6))
                Text(g.category.title).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(done)/\(g.items.count)").font(.sarabun(12, .bold, relativeTo: .caption)).monospacedDigit()
                    .foregroundStyle(all ? Theme.navy : Theme.inkMuted)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(all ? Theme.mint.opacity(0.6) : Theme.segmentTrack, in: Capsule())
                Image(systemName: "chevron.down").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .rotationEffect(.degrees(open ? 0 : -90))
            }
            .padding(.horizontal, 6).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(g.category.heading) ครบ \(done) จาก \(g.items.count)")
        .accessibilityHint(open ? "ซ่อนหัวข้อ" : "แสดงหัวข้อ")
    }

    var sidebarFooter: some View {
        VStack(spacing: 8) {
            if !job.stationOverflow.isEmpty {
                Label("หัวข้อระบบไฟฟ้าเกินช่องในแผ่นงาน — Excel จะเพิ่มแผ่น \"ระบบไฟฟ้า (2)\" ให้อัตโนมัติ", systemImage: "info.circle")
                    .font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                ForEach([SectionCategory.electrical, .roof, .water]) { cat in
                    Section(cat.heading) {
                        ForEach(ModuleType.byCode.filter { $0.category == cat }) { t in
                            Button { add(t) } label: { Label(t.code + " " + Schema.spec(t).label + "  (แผ่น " + Schema.spec(t).sheet + ")", systemImage: icon(t)) }
                        }
                    }
                }
            } label: {
                // same dashed add button as A3's "เพิ่มหม้อแปลง" and "+ เพิ่มตู้"
                Label("เพิ่มหัวข้อสำรวจ", systemImage: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground).shadow(.drop(color: Theme.navy.opacity(0.08), radius: 6, y: -2)))
    }

    func select(_ p: Page) {
        page = p
        if compact { withAnimation { sidebarVisible = false } }
    }

    /// นำเข้ารูปจากการ์ด / USB (hardware assist §H6), styled as a row.
    var cardImportRow: some View {
        Button { showCardImport = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "sdcard").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.navy)
                    .frame(width: 38, height: 26)
                    .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 7))
                Text("นำเข้ารูปจากการ์ด / USB").font(.system(size: 16, weight: .medium)).lineLimit(1).foregroundStyle(Theme.navy)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10).frame(minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// Code badge tinted by status, one-line title, status mark; the open section gets a blue bar and tint.
    func row(_ item: SidebarItem, symbol: String? = nil) -> some View {
        let c = item.completion
        let selected = !compact && page == item.page
        let (badgeFill, badgeText): (Color, Color) = selected ? (Theme.primary, .white)
            : c.total > 0 && c.isComplete ? (Theme.mint.opacity(0.6), Theme.navy)
            : c.filled > 0 ? (Theme.dangerLine.opacity(0.35), Theme.dangerText)
            : (Theme.segmentTrack, Theme.navy)
        return Button { select(item.page) } label: {
            HStack(spacing: 10) {
                Group {
                    if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                    else { Text(item.code).font(.sarabun(12, .heavy, relativeTo: .caption)).monospacedDigit() }
                }
                .foregroundStyle(badgeText)
                .frame(width: 38, height: 26)
                .background(badgeFill, in: RoundedRectangle(cornerRadius: 7))
                Text(item.title).font(.system(size: 16, weight: selected ? .bold : .medium)).lineLimit(1)
                    .foregroundStyle(selected ? Theme.primary : c.total > 0 && c.isComplete ? Theme.inkMuted : Theme.navy)
                Spacer(minLength: 4)
                if let n = changedPages[item.page] {
                    Text("แก้ \(n)").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.pending)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.pendingSoft, in: Capsule())
                        .accessibilityLabel("แก้จาก REV ก่อน \(n) รายการ")
                }
                StatusMark(completion: c)
            }
            .padding(.leading, 10).padding(.trailing, 10).frame(minHeight: 48)
            .background(selected ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(Theme.primary).frame(width: 4).padding(.vertical, 10) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .id(item.page)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(c.total > 0 ? "กรอกแล้ว \(c.filled) จาก \(c.total)" : "")
        .help(item.code + " " + item.title)
    }

    func icon(_ t: ModuleType) -> String {
        switch t {
        case .panel: return "rectangle.split.3x1"
        case .inverter: return "bolt.batteryblock"
        case .water: return "drop"
        case .backfeed: return "arrow.uturn.backward.circle"
        case .fts: return "exclamationmark.octagon"
        case .roof: return "house"
        case .tank: return "cylinder"
        case .sed: return "square.split.bottomrightquarter"
        case .house: return "house.lodge"
        case .roofForm: return "building.2"
        }
    }
}
#endif
