#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import SurveyCore
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
        case .final: return .summary
        case .module(let id): return job.modules.first { $0.id == id }?.spec.category
        }
    }

    var sidebar: some View {
        let groups = sidebarGroups
        return List(selection: Binding(get: { compact ? nil : Optional(page) }, set: { if let p = $0 { select(p) } })) {
            Section { sidebarHeader }.listRowBackground(Color(uiColor: .systemBackground))
            Section {
                row(SidebarItem(page: .summary, code: "", title: "สรุปภาพรวม 1 หน้า", completion: Completion()), symbol: "doc.text.magnifyingglass")
            }
            ForEach(groups) { g in
                Section(isExpanded: expanded(g.category)) {
                    ForEach(g.items) { item in
                        if let m = item.module {
                            row(item)
                                .contextMenu {
                                    Button { duplicate(m) } label: { Label("ทำสำเนาหัวข้อ", systemImage: "plus.square.on.square") }
                                    Button(role: .destructive) { confirmDelete = m } label: { Label("ลบหัวข้อ", systemImage: "trash") }
                                }
                                .swipeActions { Button(role: .destructive) { confirmDelete = m } label: { Label("ลบ", systemImage: "trash") } }
                        } else {
                            row(item)
                        }
                    }
                } header: {
                    groupHeader(g)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Paper.page)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
        // keep the open section visible when "next" or "continue" jumps into a collapsed group
        .onChange(of: page) { _, p in if let c = category(of: p) { collapsed.remove(c) } }
    }

    func expanded(_ c: SectionCategory) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(c) }, set: { open in withAnimation { if open { collapsed.remove(c) } else { collapsed.insert(c) } } })
    }

    var sidebarHeader: some View {
        let c = job.completion
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(job.projectName.isEmpty ? "(ยังไม่ได้ตั้งชื่อโครงการ)" : job.projectName).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("\(c.percent)%").font(.title2.bold()).monospacedDigit().foregroundStyle(c.isComplete ? Paper.tick : .primary)
            }
            ProgressView(value: c.fraction).tint(c.isComplete ? Paper.tick : .accentColor)
            HStack {
                Text("กรอกแล้ว \(c.filled)/\(c.total)")
                Spacer()
                Label("\(job.photoCount)", systemImage: "photo")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            photoStatus
            if let next = nextIncomplete, next.page != page {
                Button { select(next.page) } label: {
                    Label("ไปต่อ: \(next.code) \(next.title)", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    /// Download progress, or how many photos are still only on another device.
    @ViewBuilder var photoStatus: some View {
        let gap = PhotoGap(model: model, job: job)
        if let f = model.photoFetch[job.id], f.running {
            HStack(spacing: 6) {
                ProgressView(value: Double(f.done + f.failed), total: Double(f.total)).frame(width: 60)
                Text("กำลังดึงรูปจาก Drive \(f.done)/\(f.total)")
            }
            .font(.caption).foregroundStyle(.secondary)
        } else if let u = model.photoUpload[job.id], u.running {
            HStack(spacing: 6) {
                ProgressView(value: Double(u.done), total: Double(max(u.total, 1))).frame(width: 60)
                Text("กำลังอัปรูปขึ้น Drive \(u.done)/\(u.total)")
            }
            .font(.caption).foregroundStyle(.secondary)
        } else if let e = model.photoUpload[job.id]?.error, model.photosToUpload(job) > 0 {
            Label("อัปรูปขึ้น Drive ไม่สำเร็จ: \(e)", systemImage: "exclamationmark.icloud")
                .font(.caption).foregroundStyle(.orange).lineLimit(3)
        } else if gap.missing > 0 {
            Label("รูป \(gap.missing) รูปยังไม่อยู่ในเครื่องนี้", systemImage: "icloud.slash")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    func groupHeader(_ g: SidebarGroup) -> some View {
        let done = g.items.filter(\.completion.isComplete).count
        return HStack {
            Text(g.category.heading)
            Spacer()
            Text("\(done)/\(g.items.count)").monospacedDigit()
                .foregroundStyle(done == g.items.count ? Paper.tick : .secondary)
        }
    }

    var sidebarFooter: some View {
        VStack(spacing: 8) {
            if !job.stationOverflow.isEmpty {
                Label("หัวข้อระบบไฟฟ้าเกินช่องในแผ่นงาน — Excel จะเพิ่มแผ่น \"ระบบไฟฟ้า (2)\" ให้อัตโนมัติ", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
                Label("เพิ่มหัวข้อสำรวจ", systemImage: "plus").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .menuStyle(.button).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(12)
        .background(.bar)
    }

    func select(_ p: Page) {
        page = p
        if compact { withAnimation { sidebarVisible = false } }
    }

    /// Code badge, one-line title, status mark; finished sections step back so open work stands out.
    func row(_ item: SidebarItem, symbol: String? = nil) -> some View {
        let c = item.completion
        let selected = !compact && page == item.page
        return HStack(spacing: 10) {
            Group {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                else { Text(item.code).font(.caption.weight(.bold)).monospacedDigit() }
            }
            .foregroundStyle(selected ? Color.white : Paper.ink)
            .frame(minWidth: 38, minHeight: 22)
            .padding(.horizontal, 2)
            .background(selected ? Color.accentColor : Paper.band, in: RoundedRectangle(cornerRadius: 6))
            Text(item.title).lineLimit(1)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.accentColor : c.isComplete ? .secondary : .primary)
            Spacer(minLength: 4)
            StatusMark(completion: c)
        }
        .tag(item.page)
        // own selection look: the system one turns solid blue while the list has focus and hides the badge and status
        .listRowBackground(selected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
        .accessibilityElement(children: .combine)
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
