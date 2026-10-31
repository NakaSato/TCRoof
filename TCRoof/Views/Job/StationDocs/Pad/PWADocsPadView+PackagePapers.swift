import SwiftUI
import TCRoofUI
import TCRoofCore

/// One package's papers in the panel (`states/02`): back to every package, the title with its count and bar, then a
/// row per paper; for พค.2, the 23 check list items and the line to `ลำดับ กกพ.`.
struct PWADocsPackagePapers: View {
    let page: PWADocsPadView
    let data: PWADocsPadView.PageData
    let station: PWAPlan.Station
    let package: StationDocs.Package

    private var ctx: StationDocs.Context { station.docsContext }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { page.package = nil } } label: {
                Label("ทุกชุดเอกสาร", systemImage: "chevron.left").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                    .frame(minHeight: touchMin).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pwaDocs.allPackages")
            titleBlock
            if package == .pk2 {
                // the ERC flow is the team's to record (`erc.flow_record`)
                if !page.readOnly { ercLink }
                list(StationDocs.pk2Checklist.map { AnyView(checkRow($0)) })
            } else {
                list(StationDocs.papers(in: package, ctx).map { AnyView(PWADocsPaperRow(kind: $0, state: state($0), package: package) {
                    page.paper = .init(stationID: station.id, kindID: $0.id)
                }) })
            }
        }
    }

    private func state(_ k: StationDocs.Kind) -> StationDocs.DocState { StationDocs.state(k, station: station.docs, library: data.library) }

    /// `a/b` and its note: for พค.2, the check list items done (or not applying) of 23.
    private var count: (done: Int, total: Int) {
        if package == .pk2 {
            let states = StationDocs.pk2Checklist.map { StationDocs.check($0, station: station.docs, library: data.library, ctx) }
            return (states.filter { $0 == .done || $0 == .notApplicable }.count, states.count)
        }
        let pr = StationDocs.progress(package, station: station.docs, library: data.library, ctx)
        return (pr.ready, pr.total)
    }

    private var titleBlock: some View {
        let c = count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(package.padTitle).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("\(c.done)/\(c.total)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
            }
            ProgressBar(value: c.total == 0 ? 1 : Double(c.done) / Double(c.total), color: c.done == c.total ? Theme.success : Theme.primary)
            Text(package == .pk2 ? "Check list ของ กกพ. 23 ข้อ | ข้อที่ไม่เข้าเงื่อนไขนับว่าครบ" : package.padNote)
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var ercLink: some View {
        Button { page.ercJob = page.job(station.id) } label: {
            HStack {
                Text("ลำดับ กกพ. | ยื่น พค.1 → ตรวจสถานที่ → พค.2").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.outside)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.outside)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(Theme.outsideSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.outside.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(page.job(station.id) == nil)
    }

    private func list(_ rows: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                r.overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
        }
        .padCard(12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One check list item: numbered, the paper's origin and who under it, greyed `ไม่เข้าเงื่อนไข` when the station
    /// doesn't meet its condition. A tap opens its first paper not ready yet.
    private func checkRow(_ item: StationDocs.CheckItem) -> some View {
        let check = StationDocs.check(item, station: station.docs, library: data.library, ctx)
        let kinds = item.docs.compactMap(StationDocs.kind).filter { StationDocs.applies($0, ctx) }
        let target = kinds.first { !state($0).status.isReady } ?? kinds.first
        let na = check == .notApplicable
        return Button {
            if let target { page.paper = .init(stationID: station.id, kindID: target.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                checkMark(check).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(item.number). " + item.text).font(.sarabunFixed(14, .bold)).foregroundStyle(na ? Theme.inkFaint : Theme.navy)
                        .multilineTextAlignment(.leading)
                    Text(na ? "ไม่เข้าเงื่อนไขของสถานีนี้" : target.map(PWADocsPaperRow.origin) ?? "ทีมติ๊กบนแบบฟอร์มเอง")
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 4)
                checkPill(check, kinds: kinds)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
    }

    @ViewBuilder private func checkMark(_ c: StationDocs.CheckState) -> some View {
        switch c {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 22, height: 22).background(Theme.success, in: Circle())
        case .notApplicable:
            Text("–").font(.sarabunFixed(12, .heavy)).foregroundStyle(Theme.inkFaint).frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
        default:
            Circle().strokeBorder(Theme.inkFaint, lineWidth: 2).frame(width: 22, height: 22)
        }
    }

    @ViewBuilder private func checkPill(_ c: StationDocs.CheckState, kinds: [StationDocs.Kind]) -> some View {
        switch c {
        case .notApplicable: PWADocsPill(text: "ไม่เข้าเงื่อนไข", ink: Theme.inkFaint, fill: Theme.background)
        case .manual: PWADocsPill(text: "ทีมติ๊กเอง", ink: Theme.inkMuted, fill: Theme.segmentTrack)
        case .done, .missing:
            let worst = kinds.map { state($0).status }.filter { $0 != .notNeeded }.min { $0.rank < $1.rank } ?? .approved
            PWADocsPill(status: worst, origin: kinds.first?.origin ?? .internalDoc)
        }
    }
}

/// A paper in a drilled package: status mark, name, origin and who, the other packages sharing it, and its pill.
struct PWADocsPaperRow: View {
    let kind: StationDocs.Kind
    let state: StationDocs.DocState
    let package: StationDocs.Package
    let open: (StationDocs.Kind) -> Void

    var body: some View {
        Button { open(kind) } label: {
            HStack(alignment: .top, spacing: 10) {
                PWADocsStatusMark(status: state.status, origin: kind.origin).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).multilineTextAlignment(.leading)
                    Text(Self.origin(kind) + (PWADocs.isIDCard(kind) ? " | ต้องปิดข้อมูลบนบัตร" : ""))
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    let others = kind.packages.filter { $0 != package }
                    if !others.isEmpty {
                        Text("⇄ " + others.map { PWADocs.stepTitle($0) }.joined(separator: " | "))
                            .font(.sarabunFixed(12, .semibold)).foregroundStyle(Theme.dockTeal)
                    }
                }
                Spacer(minLength: 4)
                PWADocsPill(status: state.status, origin: kind.origin)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pwaDocs.paper.\(kind.id)")
    }

    /// `เราร่าง → กปภ. ลงนาม | ผจก. กปภ.สาขา`, `ขอจาก กปภ.สาขา`, `ทีมเราทำ | วิศวกรไฟฟ้า`.
    static func origin(_ kind: StationDocs.Kind) -> String {
        switch kind.origin {
        case .internalDoc: (["ทีมเราทำ"] + [kind.signBy].compactMap { $0 }).joined(separator: " | ")
        case .signoff: (["เราร่าง → กปภ. ลงนาม"] + [kind.signBy].compactMap { $0 }).joined(separator: " | ")
        case .external: "ขอจาก " + (kind.obtainFrom ?? "หน่วยงานนอก")
        }
    }
}

/// A status ring, ✓ when approved, a purple dot when submitted, dashed `–` when not needed.
struct PWADocsStatusMark: View {
    let status: StationDocs.Status
    let origin: StationDocs.Origin

    var body: some View {
        switch status {
        case .approved:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 22, height: 22).background(Theme.success, in: Circle())
        case .submitted, .signed:
            Circle().fill(Theme.outside).frame(width: 10, height: 10).frame(width: 22, height: 22)
        case .notNeeded:
            Text("–").font(.sarabunFixed(12, .heavy)).foregroundStyle(Theme.inkFaint).frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
        default:
            Circle().strokeBorder(status.ring(origin), lineWidth: 2).frame(width: 20, height: 20).frame(width: 22, height: 22)
        }
    }
}

/// A status pill in the page's words: `ยังไม่มี`, `ร่าง`, `รอลงนาม`, `ขอแล้ว`, `ยื่นแล้ว`, `อนุมัติแล้ว`.
struct PWADocsPill: View {
    let text: String
    let ink: Color
    let fill: Color

    init(text: String, ink: Color, fill: Color) { self.text = text; self.ink = ink; self.fill = fill }

    init(status: StationDocs.Status, origin: StationDocs.Origin) {
        self.init(text: status.padWord(origin), ink: status.padInk(origin), fill: status.padFill(origin))
    }

    var body: some View {
        Text(text).font(.sarabunFixed(11.5, .bold)).foregroundStyle(ink).lineLimit(1).fixedSize()
            .padding(.horizontal, 8).frame(height: 22).background(fill, in: Capsule())
    }
}

/// A plain progress bar, 6 pt.
struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Theme.track)
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1)) }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - words and colours

extension StationDocs.Package {
    /// The section number of the hand-over folders (`4.1`, `4.2`, `4.3`); the test and the hand-over have none.
    var section: String? {
        switch self {
        case .building: "4.1"
        case .gridConnection: "4.2"
        case .pk2: "4.3"
        case .commissioning, .handover: nil
        }
    }

    /// The iPad panel's package titles, numbered by `section`.
    var padTitle: String {
        let name = switch self {
        case .building: "ใบอนุญาต อ.1 / แจ้งเทศบาล"
        case .gridConnection: "ขออนุญาตขนานไฟ (กฟภ.)"
        case .pk2: "พค.2 | ยกเว้นใบอนุญาต กกพ."
        case .commissioning: "ทดสอบระบบ"
        case .handover: "ส่งมอบงาน"
        }
        return [section, name].compactMap { $0 }.joined(separator: " ")
    }

    /// What goes in, short.
    var padNote: String {
        switch self {
        case .building: "แบบแปลน | ใบ กว. | หนังสือแจ้งเทศบาล | สำเนาโฉนด"
        case .gridConnection: "คำขอ | SLD | Datasheet | ผลทดสอบ | หนังสือมอบอำนาจ"
        case .pk2: "แบบตรวจสอบ 23 ข้อ | ภาพถ่าย | IEC Test (อินเวอร์เตอร์ ≥ 200 kVA)"
        case .commissioning: "IEC 62446 | ภาพถ่ายความร้อน"
        case .handover: "As-Built | IEC 62446 | คู่มือ O&M | ใบรับประกัน"
        }
    }
}

extension StationDocs.Status {
    /// Lower is further from done, for the worst paper of a check list item.
    var rank: Int {
        switch self {
        case .missing: 0
        case .requested: 1
        case .draft: 2
        case .signed: 3
        case .submitted: 4
        case .approved: 5
        case .notNeeded: 6
        }
    }

    func padWord(_ origin: StationDocs.Origin) -> String {
        switch self {
        case .missing: "ยังไม่มี"
        case .draft: "ร่าง"
        case .requested: origin == .external ? "ขอแล้ว" : "รอลงนาม"
        case .signed: origin == .external ? "ได้รับแล้ว" : "ลงนามแล้ว"
        case .submitted: "ยื่นแล้ว"
        case .approved: "อนุมัติแล้ว"
        case .notNeeded: "ไม่ใช้"
        }
    }

    func padInk(_ origin: StationDocs.Origin) -> Color {
        switch self {
        case .missing, .notNeeded: Theme.inkMuted
        case .draft: Theme.primary
        case .requested: origin == .external ? Theme.outside : Theme.warningText
        case .signed, .submitted: Theme.outside
        case .approved: Theme.successText
        }
    }

    func padFill(_ origin: StationDocs.Origin) -> Color {
        switch self {
        case .missing, .notNeeded: Theme.segmentTrack
        case .draft: Theme.primarySoft
        case .requested: origin == .external ? Theme.outsideSoft : Theme.warningTint
        case .signed, .submitted: Theme.outsideSoft
        case .approved: Theme.successSoft
        }
    }

    /// The ring of an open paper: grey missing, blue draft, orange waiting for PWA, purple asked outside.
    func ring(_ origin: StationDocs.Origin) -> Color {
        switch self {
        case .draft: Theme.primary
        case .requested: origin == .signoff ? Theme.warning : Theme.outside
        default: Theme.inkFaint
        }
    }
}
