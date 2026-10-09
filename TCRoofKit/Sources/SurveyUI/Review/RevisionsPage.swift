#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// REV และรายการแก้ไข (docs/specs/review-lock-revisions-swift.md §3.3): the issued REVs with their PDFs, and what changed
/// between any two of them or the current draft.
struct RevisionsPage: View {
    enum Filter: String, CaseIterable { case all = "ทั้งหมด", text = "ข้อความ", photos = "รูป" }
    static let current = "ฉบับปัจจุบัน"

    let job: Job
    var openPDF: (URL, String) -> Void
    @Environment(SurveyModel.self) private var model
    @State var from: String?
    @State var to: String?
    @State private var filter = Filter.all
    @State private var photoPair: FieldChange?

    var body: some View {
        let revs = job.revisions ?? []
        // default: the last issued REV against the current draft, or the two last REVs while locked
        let a = from ?? (job.isLocked ? job.previousRevision?.rev : revs.last?.rev) ?? revs.first?.rev ?? "00"
        let b = to ?? (job.isLocked ? job.rev : Self.current)
        let changes = compare(a, b)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                history(revs)
                picker(revs, a, b)
                list(changes)
            }
            .padding(16)
        }
        .sheet(item: $photoPair) { c in photoSheet(c) }
    }

    func snapshot(_ rev: String) -> FormSnapshot? { rev == Self.current ? job.snapshot : model.snapshot(job, rev: rev) }

    func compare(_ a: String, _ b: String) -> [FieldChange]? {
        guard let sa = snapshot(a), let sb = snapshot(b) else { return nil }
        return FormDiff.changes(from: sa, to: sb)
    }

    // MARK: history

    func history(_ revs: [Revision]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ประวัติ REV").font(.headline).foregroundStyle(Theme.navy)
            ForEach(revs.reversed()) { r in
                HStack(alignment: .top, spacing: 12) {
                    Text("REV \(r.rev)").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.navy, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ISODate.thai(ISODate.string(r.issuedAt))) · \(r.issuedBy.isEmpty ? "—" : r.issuedBy)").font(.subheadline.weight(.semibold))
                        Text(r.reason.isEmpty ? "ออกครั้งแรก" : r.reason).font(.subheadline).foregroundStyle(Theme.inkMuted)
                        Label(r.shortCode, systemImage: "lock.fill").font(.caption.monospaced()).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 8)
                    let url = model.store.revisionPDF(rev: r.rev, job: job.id)
                    if r.pdfFile != nil, FileManager.default.fileExists(atPath: url.path) {
                        TCButton("เปิด PDF", systemImage: "doc.richtext", kind: .secondary, size: .card) { openPDF(url, "REV \(r.rev) " + job.projectName) }
                            .fixedSize()
                    } else {
                        Text("ไม่มี PDF ในเครื่องนี้").font(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
            }
            if !job.isLocked {
                Label("REV \(job.rev) กำลังแก้ไข" + ((job.pendingReason ?? "").isEmpty ? "" : " · " + job.pendingReason!), systemImage: "pencil")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.pending)
            }
        }
    }

    // MARK: compare

    func picker(_ revs: [Revision], _ a: String, _ b: String) -> some View {
        let options = revs.map(\.rev) + (job.isLocked ? [] : [Self.current])
        func name(_ r: String) -> String { r == Self.current ? "ฉบับปัจจุบัน (ยังไม่ออก)" : "REV \(r)" }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { menus(options, a, b, name); Spacer(minLength: 8); filters }
            VStack(alignment: .leading, spacing: 10) { menus(options, a, b, name); filters }
        }
    }

    func menus(_ options: [String], _ a: String, _ b: String, _ name: @escaping (String) -> String) -> some View {
        HStack(spacing: 10) {
            Text("จาก").foregroundStyle(Theme.inkMuted)
            Menu(name(a)) { ForEach(options.filter { $0 != Self.current }, id: \.self) { r in Button(name(r)) { from = r } } }
                .frame(minHeight: 44)
            Image(systemName: "arrow.right").foregroundStyle(Theme.inkMuted)
            Text("ถึง").foregroundStyle(Theme.inkMuted)
            Menu(name(b)) { ForEach(options, id: \.self) { r in Button(name(r)) { to = r } } }
                .frame(minHeight: 44)
        }
        .font(.headline)
    }

    var filters: some View {
        Picker("แสดง", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(width: 240)
    }

    @ViewBuilder func list(_ changes: [FieldChange]?) -> some View {
        if let changes {
            let shown = changes.filter { filter == .all || (filter == .photos) == $0.isPhoto }
            if shown.isEmpty {
                ContentUnavailableView("ไม่มีรายการแก้ไข", systemImage: "checkmark.circle").frame(maxWidth: .infinity).padding(.top, 24)
            } else {
                let groups = Dictionary(grouping: shown, by: \.group)
                let order = shown.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                Text("\(shown.count) รายการ").font(.subheadline).foregroundStyle(Theme.inkMuted)
                ForEach(order, id: \.self) { g in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g).font(.subheadline.weight(.bold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading).background(Theme.paperBand)
                        ForEach(groups[g] ?? []) { c in row(c); Divider() }
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
                }
            }
        } else {
            Label("ไม่พบข้อมูล REV ที่เลือกในเครื่องนี้", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.pending)
        }
    }

    func row(_ c: FieldChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.field).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.navy)
            if c.isPhoto {
                Button { photoPair = c } label: {
                    HStack(spacing: 10) {
                        thumb(c.oldPhoto)
                        Image(systemName: "arrow.right").foregroundStyle(Theme.inkMuted)
                        thumb(c.newPhoto)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { old(c); Image(systemName: "arrow.right").foregroundStyle(Theme.inkMuted); new(c) }
                    VStack(alignment: .leading, spacing: 4) { old(c); new(c) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func old(_ c: FieldChange) -> some View {
        Text(c.old).strikethrough(c.old != "—").foregroundStyle(Theme.dangerText)
    }
    func new(_ c: FieldChange) -> some View {
        Text(c.new).fontWeight(.semibold).foregroundStyle(Theme.okText)
    }
    @ViewBuilder func thumb(_ p: Photo?) -> some View {
        if let p {
            Thumbnail(photo: p, jobID: job.id).frame(width: 120, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text("—").frame(width: 120, height: 90).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))
        }
    }

    /// Old and new photo side by side.
    func photoSheet(_ c: FieldChange) -> some View {
        NavigationStack {
            HStack(spacing: 12) {
                ForEach([(c.oldPhoto, "เดิม"), (c.newPhoto, "ใหม่")], id: \.1) { p, title in
                    VStack(spacing: 8) {
                        Text(title).font(.headline).foregroundStyle(.white)
                        if let p, let img = model.image(p, in: job.id) { Image(uiImage: img).resizable().scaledToFit() }
                        else { Text("—").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .background(Color.black)
            .navigationTitle(c.field).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { photoPair = nil } } }
        }
    }
}
#endif
