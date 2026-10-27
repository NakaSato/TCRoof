import SwiftUI
import SwiftData
import TCRoofCore
import TCRoofUI

/// ICL ตรวจหน้างาน of a PWA station (`SiteICL`, the Master Plan's `ICL ตรวจหน้างาน` sheet): the 10 groups of the
/// checklist, group 2.1 one sheet per installation point. The contractor fills a sheet and sends it (`icl.site_fill`),
/// the team's engineer signs it or sends it back (`icl.site_sign`); everyone else assigned to the job sees the sheets.
struct SiteICLScreen: View {
    let job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @State private var addingPoint = false

    private var catalog: SiteICL.Catalog { SiteICL.catalog }
    private var canFill: Bool { permissions.can(.iclSiteFill, on: job.access) }

    var body: some View {
        VStack(spacing: 0) {
            SiteICLHeader(title: "ICL ตรวจหน้างาน", subtitle: "\(job.code) · \(job.projectName)") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    ForEach(catalog.groups) { group in groupCard(group) }
                    legend
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .tcPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $addingPoint) {
            SiteICLAddPoint(mounts: catalog.mounts, taken: Set(job.iclSheets.compactMap { $0.sheet.point })) { code, name, mount in
                open(SiteICL.Sheet(group: "2.1", point: code, pointName: name, mount: mount))
            }
        }
    }

    private var summary: some View {
        let tally = job.siteICLTally
        return HStack(spacing: 12) {
            Image(systemName: "checklist.checked").font(.sarabun(22, relativeTo: .title2)).foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("ลงนามแล้ว \(tally.signed) / \(tally.total) ใบ").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text("ผรม. ตรวจ กรอกผล ถ่ายรูป แล้วส่งให้ วศ. ลงนาม · ข้อไม่ผ่าน แก้แล้วตรวจซ้ำในใบเดิม")
                    .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .cardStyle()
    }

    @ViewBuilder private func groupCard(_ group: SiteICL.Group) -> some View {
        let sheets = job.siteICL.filter { $0.sheet.group == group.id }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(group.id) \(group.title)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                Text("WBS \(group.wbs)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            if group.perPoint {
                ForEach(sheets) { sheet in row(sheet) }
                if sheets.isEmpty {
                    Text("ยังไม่มีจุดติดตั้ง · เพิ่มทีละจุด (หลังคา / ถัง / Carport) ตามแบบสำรวจ")
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
                if canFill {
                    Button { addingPoint = true } label: {
                        Label("เพิ่มจุดติดตั้ง", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            } else if let sheet = sheets.first {
                row(sheet)
            } else if canFill {
                Button { open(SiteICL.Sheet(group: group.id)) } label: {
                    Label("เริ่มตรวจ", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
            } else {
                Text("ยังไม่เริ่มตรวจ").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
    }

    private func row(_ model: ICLSheet) -> some View {
        NavigationLink { SiteICLSheetView(job: job, model: model) } label: {
            SiteICLRow(model: model)
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SiteICL.Hold.allCases, id: \.self) { h in
                HStack(spacing: 8) { SiteICLHoldBadge(hold: h); Text(h.title) }
            }
        }
        .font(.sarabun(13, relativeTo: .footnote))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 4)
    }

    /// Makes the sheet (the same document id on every device) or finds the one already made.
    private func open(_ sheet: SiteICL.Sheet) {
        guard job.iclSheet(sheet.id) == nil else { return }
        let model = ICLSheet(sheet)
        model.syncID = ICLSheet.syncID(job: job, sheet: sheet)
        context.insert(model)
        model.job = job
        try? context.save()
    }
}

// MARK: - Pieces

struct SiteICLHeader: View {
    let title: String
    let subtitle: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.sarabun(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("กลับ")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(20, .bold, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.sarabun(15, relativeTo: .subheadline)).lineLimit(1)
            }
            .foregroundStyle(Theme.onPrimary)
            Spacer()
        }
        .padding(.horizontal, isPhone ? 16 : 24)
        .padding(.vertical, 14)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
            .fill(Theme.headerGradient).ignoresSafeArea(edges: .top))
    }
}

struct SiteICLHoldBadge: View {
    let hold: SiteICL.Hold

    var body: some View {
        Text(hold.rawValue)
            .font(.sarabun(12, .bold, relativeTo: .caption))
            .foregroundStyle(ink)
            .frame(width: 24, height: 22)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(hold.title)
    }

    private var fill: Color {
        switch hold {
        case .hold: Theme.dangerSoft
        case .witness: Theme.warningSoft
        case .review: Theme.successSoft
        }
    }

    private var ink: Color {
        switch hold {
        case .hold: Theme.dangerText
        case .witness: Theme.warningText
        case .review: Theme.successInk
        }
    }
}

/// A sheet's line: its title, progress and where the hand-over stands.
struct SiteICLRow: View {
    let model: ICLSheet

    var body: some View {
        let sheet = model.sheet
        let progress = model.progress
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label(sheet))
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                if let mount = sheet.mount {
                    Text(mount).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                SiteICLStatus(sheet: sheet, items: model.items, progress: progress)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.12)))
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }

    private func label(_ sheet: SiteICL.Sheet) -> String {
        guard let point = sheet.point else { return sheet.title }
        guard let name = sheet.pointName else { return point }
        return "\(point) · \(name)"
    }
}

struct SiteICLStatus: View {
    let sheet: SiteICL.Sheet
    let items: [SiteICL.Item]
    let progress: (done: Int, total: Int)

    var body: some View {
        Text(text).font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(color)
    }

    private var text: String {
        switch sheet.lockState {
        case .closed: sheet.failed(items).isEmpty ? "ลงนามแล้ว · ผ่านทุกข้อ" : "ลงนามแล้ว · มีข้อไม่ผ่าน \(sheet.failed(items).count)"
        case .sent: "ส่งแล้ว · รอ วศ. ลงนาม"
        case .open: sheet.sendBack != nil ? "ส่งกลับให้แก้ · \(progress.done)/\(progress.total)" : "กำลังตรวจ \(progress.done)/\(progress.total)"
        }
    }

    private var color: Color {
        switch sheet.lockState {
        case .closed: sheet.failed(items).isEmpty ? Theme.success : Theme.danger
        case .sent: Theme.primary
        case .open: sheet.sendBack != nil ? Theme.danger : Theme.warningText
        }
    }
}

/// `เพิ่มจุดติดตั้ง`: a code (R1, T1), a name and the mounting type, which picks the point's items.
struct SiteICLAddPoint: View {
    let mounts: [String]
    let taken: Set<String>
    let add: (String, String?, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var mount = ""

    private var trimmed: String { code.trimmingCharacters(in: .whitespaces).uppercased() }
    private var ok: Bool { !trimmed.isEmpty && !taken.contains(trimmed) && !mount.isEmpty && !trimmed.contains("/") }

    var body: some View {
        NavigationStack {
            Form {
                Section("จุดติดตั้ง") {
                    TextField("รหัส เช่น R1, T1", text: $code).textInputAutocapitalization(.characters)
                    TextField("ชื่อ เช่น หลังคาอาคารสูบน้ำ (ไม่บังคับ)", text: $name)
                    if taken.contains(trimmed) { Text("มีจุด \(trimmed) แล้ว").foregroundStyle(Theme.danger) }
                }
                Section("ประเภทหน้างาน") {
                    ForEach(mounts, id: \.self) { m in
                        Button { mount = m } label: {
                            HStack { Text(m).foregroundStyle(Theme.navy); Spacer(); if mount == m { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }
            .font(.sarabun(16, relativeTo: .body))
            .navigationTitle("เพิ่มจุดติดตั้ง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        add(trimmed, n.isEmpty ? nil : n, mount)
                        dismiss()
                    }
                    .disabled(!ok)
                }
            }
        }
    }
}
