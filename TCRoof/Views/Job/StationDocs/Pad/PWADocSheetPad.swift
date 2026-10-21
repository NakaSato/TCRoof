import SwiftUI
import PDFKit
import QuickLookThumbnailing
import TCRoofUI
import TCRoofCore

/// One paper on iPad (docs/ui/pwa-docs-ipad §4, `states/03`): its status steps, the file's first page, the facts,
/// the ID card warning, its history, and the actions its status allows. It edits the same `DocState` as
/// `StationDocSheet`, which `แก้รายละเอียด` still opens for the note and the expiry.
struct PWADocSheetPad: View {
    let page: PWADocsPadView
    /// The page's data, passed in so the sheet redraws after its own changes.
    let data: PWADocsPadView.PageData
    let kind: StationDocs.Kind
    let stationID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var uploading = false
    @State private var drafting = false
    @State private var editing = false
    @State private var shareText: SharedText?
    @State private var shareFile: SharedLink?
    @State private var thumbnail: UIImage?
    @State private var detailsLibrary = StationDocsStore.loadLibrary()

    private struct SharedText: Identifiable {
        let text: String
        var id: String { text }
    }

    private var station: PWAPlan.Station? { data.station(stationID) }
    private var state: StationDocs.DocState { page.state(kind, stationID: stationID, data) }
    private var job: Job? { page.job(stationID) }
    private var url: URL? { page.fileURL(kind, stationID: stationID, name: state.fileName) }

    var body: some View {
        VStack(spacing: 0) {
            head
            steps
            HStack(alignment: .top, spacing: 0) {
                preview.frame(width: 380).frame(maxHeight: .infinity).background(Theme.background)
                ScrollView { facts.padding(20) }.frame(maxWidth: .infinity)
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            footer
        }
        .frame(width: 920, height: 760)
        .background(Theme.surface)
        .sheet(isPresented: $uploading) {
            PWADocsUploadSheet(page: page, data: data, stationID: stationID, package: nil, preselected: kind.id).presentationSizing(.fitted)
        }
        .sheet(isPresented: $drafting) {
            if let job { OutageLetterSheet(job: job) { page.keepDraft($0, kind: kind, stationID: stationID) } }
        }
        .sheet(isPresented: $editing) {
            if let j = detailsJob { StationDocSheet(job: j, kind: kind, library: $detailsLibrary) }
        }
        .sheet(item: $shareText) { ActivitySheet(items: [$0.text]).presentationDetents([.medium, .large]) }
        .sheet(item: $shareFile) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .task(id: state.fileName) { await loadThumbnail() }
        .onChange(of: editing) { _, open in if !open { page.library = StationDocsStore.loadLibrary() } }
    }

    // MARK: head and steps

    private var head: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.name).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                Text(place).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(kind.origin.groupTitle).font(.sarabunFixed(12, .bold)).foregroundStyle(kind.origin.dot)
                .padding(.horizontal, 10).frame(height: 26)
                .background(kind.origin.dot.opacity(0.12), in: Capsule())
                .padding(.top, 6)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
            .accessibilityIdentifier("pwaDocs.sheet.close")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    /// `MP 189 ทุ่งน้อย | 4.1 ใบอนุญาต อ.1 / แจ้งเทศบาล`, or `คลังกลาง`.
    private var place: String {
        guard let st = station else { return "คลังกลาง | " + kind.scope.title }
        let packages = StationDocs.packages(st.docsContext)
        let p = kind.packages.first(where: packages.contains)
        return [st.ref + " " + st.shortName, p?.padTitle].compactMap { $0 }.joined(separator: " | ")
    }

    private var steps: some View {
        let flow = PWADocs.flow(kind.origin, state.status)
        return HStack(spacing: 0) {
            ForEach(Array(flow.labels.enumerated()), id: \.offset) { i, label in
                step(i, label, flow: flow)
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("สถานะ " + state.status.padWord(kind.origin))
    }

    private func step(_ i: Int, _ label: String, flow: PWADocs.Flow) -> some View {
        let done = i < flow.done && flow.current != i
        let current = flow.current == i
        let last = flow.labels.count - 1
        return VStack(spacing: 4) {
            ZStack {
                HStack(spacing: 0) {
                    // a line is green up to a step that is done or current
                    Rectangle().fill(i < flow.done || flow.current == i ? Theme.success : Theme.borderSubtle)
                        .frame(height: 3).opacity(i == 0 ? 0 : 1)
                    Rectangle().fill(i + 1 < flow.done || flow.current == i + 1 ? Theme.success : Theme.borderSubtle)
                        .frame(height: 3).opacity(i == last ? 0 : 1)
                }
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 22, height: 22).background(Theme.success, in: Circle())
                } else if current {
                    Text("\(i + 1)").font(.sarabunFixed(11.5, .heavy)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 24, height: 24).background(Theme.primary, in: Circle())
                        .background(Circle().fill(Theme.primary.opacity(0.18)).padding(-4))
                } else {
                    Text("\(i + 1)").font(.sarabunFixed(11.5, .heavy)).foregroundStyle(Theme.muted)
                        .frame(width: 22, height: 22).background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.inkFaint, lineWidth: 1.5))
                }
            }
            .frame(height: 28)
            Text(label).font(.sarabunFixed(12, current ? .heavy : .semibold))
                .foregroundStyle(current ? Theme.primary : done ? Theme.navy : Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: preview

    @ViewBuilder private var preview: some View {
        VStack(spacing: 10) {
            if state.fileName != nil, let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit()
                    .background(Theme.paper)
                    .shadow(color: Theme.navy.opacity(0.15), radius: 6, y: 2)
                    .frame(maxHeight: 420)
                    .accessibilityLabel("หน้าแรกของไฟล์")
                Text(fileLine).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            } else if let name = state.fileName {
                Image(systemName: "doc.text").font(.system(size: 40)).foregroundStyle(Theme.inkFaint)
                Text(name).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 30)).foregroundStyle(Theme.inkFaint)
                    Text("ยังไม่มีไฟล์").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.inkMuted)
                }
                .frame(width: 300, height: 400)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
        }
        .padding(24)
    }

    /// `ฉบับล่าสุด | PDF | 5 หน้า`.
    private var fileLine: String {
        guard let url else { return "ฉบับล่าสุด" }
        let ext = url.pathExtension.uppercased()
        let pages = PDFDocument(url: url).map { " | \($0.pageCount) หน้า" } ?? ""
        return "ฉบับล่าสุด | " + ext + pages
    }

    private func loadThumbnail() async {
        thumbnail = nil
        guard let url else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 300, height: 420), scale: 2, representationTypes: .thumbnail)
        thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
    }

    // MARK: facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            fact("ผู้รับผิดชอบ", responsible)
            if let st = station, let due = page.due(kind, st) { dueFact(due) }
            if let number = PWADocs.letterNumber(state.note) { fact("เลขที่หนังสือ", number) }
            if kind.packages.count > 1 { fact("ใช้ร่วมกัน", kind.packages.map { PWADocs.stepTitle($0) }.joined(separator: " | ")) }
            if let st = station, !st.contractor.isEmpty { fact("ผู้รับเหมา", st.contractor) }
            if let end = state.expiresAt { fact("หมดอายุ", ThaiFormat.numericDate.string(from: end)) }
            if !state.note.isEmpty { fact("หมายเหตุ", state.note) }
            if PWADocs.isIDCard(kind) {
                Text("🔒 ก่อนแนบ ปิดศาสนา กรุ๊ปเลือด และวันเกิดบนบัตรทุกใบ | แอปไม่เก็บเลขบัตรเป็นข้อความ")
                    .font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.dangerText)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            history
        }
    }

    private var responsible: String {
        switch kind.origin {
        case .internalDoc: kind.signBy ?? "ทีมเรา"
        case .signoff: kind.signBy ?? "กปภ."
        case .external: kind.obtainFrom ?? "หน่วยงานนอก"
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(width: 120, alignment: .leading)
            Text(value).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func dueFact(_ due: Date) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: due)).day ?? 0
        let ready = state.status.isReady || state.status == .notNeeded
        let text = ready || days > 0 ? PWAPlanFormat.numeric.string(from: due) : days == 0 ? "วันนี้" : "เลย \(-days) วัน"
        return HStack(alignment: .top, spacing: 12) {
            Text("ครบกำหนด").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(width: 120, alignment: .leading)
            Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(!ready && days < 0 ? Theme.dangerText : Theme.navy)
        }
        .accessibilityElement(children: .combine)
    }

    /// The last change and every reminder, newest first: all the paper keeps.
    @ViewBuilder private var history: some View {
        let lines = historyLines
        if !lines.isEmpty {
            Text("ประวัติ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).padding(.top, 8)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .top, spacing: 12) {
                    Text(Self.when(l.date)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(width: 120, alignment: .leading)
                    Text(l.text).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var historyLines: [(date: Date, text: String)] {
        var out = state.reminders.enumerated().map { (date: $0.element, text: "ทวงครั้งที่ \($0.offset + 1)") }
        // the last change, unless it was only the latest reminder
        if let at = state.updatedAt, state.reminders.last != at { out.append((at, "อัปเดตเป็น " + state.status.padWord(kind.origin))) }
        return out.sorted { $0.date > $1.date }
    }

    /// `21:12` today, `เมื่อวาน`, else `5/10`.
    static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return ThaiFormat.time.string(from: date) }
        if cal.isDateInYesterday(date) { return "เมื่อวาน" }
        return PWAPlanFormat.numeric.string(from: date)
    }

    // MARK: footer

    private struct Action {
        let title: String
        let id: String
        let run: () -> Void
    }

    private var actions: [Action] {
        // a contractor views the paper; only its approved file can be opened
        if page.readOnly {
            guard state.status == .approved else { return [] }
            return [Action(title: "ดาวน์โหลด", id: "download") { if let url { shareFile = SharedLink(url: url) } }]
        }
        let s = state.status
        let draftable = StationDocs.draft(for: kind) != nil && job != nil
        var out: [Action] = []
        switch s {
        case .missing:
            if draftable { out.append(Action(title: "สร้างร่างจากข้อมูลหน้างาน", id: "draft") { drafting = true }) }
            if kind.scope.isShared, station != nil {
                out.append(Action(title: "แนบจากคลังกลาง", id: "library") {
                    dismiss()
                    page.libraryPaper = .init(stationID: nil, kindID: kind.id)
                })
            }
            if kind.origin == .external { out.append(Action(title: "ส่งคำขอเอกสาร", id: "request") { set(.requested) }) }
            out.append(Action(title: "อัปโหลดไฟล์", id: "upload") { uploading = true })
        case .draft:
            if draftable { out.append(Action(title: "แก้ร่าง", id: "draft") { drafting = true }) }
            if kind.origin == .signoff {
                out.append(Action(title: "ส่งให้ \(kind.signBy ?? "กปภ.") ลงนาม", id: "send") { set(.requested) })
            } else {
                out.append(Action(title: "ยื่นแล้ว", id: "submitted") { set(.submitted) })
            }
        case .requested:
            let n = state.reminders.count
            out.append(Action(title: n == 0 ? "ทวง" : "ทวง (ครั้งที่ \(n + 1))", id: "remind") {
                shareText = SharedText(text: page.remind(kind, stationID: stationID))
            })
            out.append(Action(title: kind.origin == .external ? "ได้รับแล้ว | อัปโหลด" : "อัปโหลดฉบับลงนาม", id: "upload") { uploading = true })
        case .signed, .submitted:
            out.append(Action(title: "บันทึกผลอนุมัติ", id: "approve") { set(.approved) })
        case .approved:
            out.append(Action(title: "ดาวน์โหลด", id: "download") { if let url { shareFile = SharedLink(url: url) } })
            out.append(Action(title: "เปลี่ยนไฟล์", id: "upload") { uploading = true })
        case .notNeeded:
            out.append(Action(title: "ใช้กับสถานีนี้", id: "use") { set(.missing) })
        }
        return out
    }

    private func set(_ status: StationDocs.Status) {
        page.update(kind, stationID: stationID) { $0.status = status }
    }

    private var footer: some View {
        let actions = self.actions
        return HStack(spacing: 10) {
            if !page.readOnly { moreMenu }
            Spacer(minLength: 8)
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                Button(a.title, action: a.run)
                    .buttonStyle(TCButtonStyle(i == actions.count - 1 ? .primary : .secondary, size: .bar))
                    .disabled(a.id == "download" && url == nil)
                    .accessibilityIdentifier("pwaDocs.sheet.\(a.id)")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// The rest of the old sheet: the note and the expiry (`StationDocSheet`), and setting the paper not needed.
    private var moreMenu: some View {
        Menu {
            // a library paper is kept in the library whichever job opens the old sheet; the example has no job
            if !page.isDemo, let editJob = job ?? (kind.scope.isShared ? page.stationJobs.first : nil) {
                Button { detailsJob = editJob; detailsLibrary = StationDocsStore.loadLibrary(); editing = true } label: {
                    Label("แก้รายละเอียด", systemImage: "square.and.pencil")
                }
            }
            if state.status != .notNeeded, station != nil {
                Button { set(.notNeeded) } label: { Label("ไม่ใช้กับสถานีนี้", systemImage: "minus.circle") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(width: 53, height: 53)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
        .accessibilityLabel("เพิ่มเติม")
    }

    @State private var detailsJob: Job?
}
