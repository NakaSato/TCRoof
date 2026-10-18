import SwiftUI
import TCRoofUI
import TCRoofCore

// `ตามสถานี` on iPad (docs/ui/pwa-docs-ipad §3): the station list and the selected station's panel.

extension PWADocsPadView {

    /// The rows after the status filter, the contractor chip and the sort.
    func shownRows(_ data: PageData) -> [PWADocs.StationRow] {
        let rows = data.rows.filter { filter.holds($0.state) && (contractor == nil || $0.station.contractor == contractor) }
        return PWADocs.sorted(rows, by: sort, library: data.library)
    }

    /// The rows of the chosen contractor, before the status filter: the filter's counts.
    private func contractorRows(_ data: PageData) -> [PWADocs.StationRow] {
        data.rows.filter { contractor == nil || $0.station.contractor == contractor }
    }

    func stationsPane(_ data: PageData) -> some View {
        let rows = shownRows(data)
        let selected = data.row(selectedID) ?? rows.first ?? data.rows.first
        return HStack(alignment: .top, spacing: 18) {
            listCard(data, rows: rows, selected: selected?.id)
            Group {
                if let selected { AnyView(PWADocsStationPanel(page: self, data: data, row: selected, drilled: package)) } else { AnyView(Color.clear) }
            }
            .frame(width: 440)
        }
    }

    // MARK: list

    private func listCard(_ data: PageData, rows: [PWADocs.StationRow], selected: String?) -> some View {
        VStack(spacing: 0) {
            listHeader(data)
            toolbar(data)
            columnHeads
            if rows.isEmpty {
                AnyView(emptyList)
            } else {
                AnyView(ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in AnyView(stationRow(r, data: data, selected: r.id == selected)) }
                    }
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padCard()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func listHeader(_ data: PageData) -> some View {
        let base = contractorRows(data)
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ตามสถานี").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text("ชุด " + PWADocs.steps.map(\.title).joined(separator: " · ")).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            TCCountSegments(PWADocs.StationFilter.allCases.map { f in .init(f.title, count: base.filter { f.holds($0.state) }.count) },
                            selection: Binding(get: { PWADocs.StationFilter.allCases.firstIndex(of: filter) ?? 0 },
                                               set: { i in withAnimation(reduceMotion ? nil : .snappy) { filter = PWADocs.StationFilter.allCases[i] } }),
                            fontSize: 14)
                .frame(width: 306)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    }

    private func toolbar(_ data: PageData) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("ทุกผู้รับเหมา", on: contractor == nil) { contractor = nil }
                    ForEach(PWADocs.contractors(data.stations), id: \.self) { c in
                        chip(PWAPlan.contractorTitle(c), on: contractor == c) { contractor = c }
                    }
                }
            }
            Button { sort = sort == .handover ? .missing : .handover } label: {
                Label(sort == .handover ? "เรียง: วันส่งมอบ" : "เรียง: ขาดมากสุด", systemImage: "arrow.up.arrow.down")
                    .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .overlay(Capsule().strokeBorder(Theme.borderSubtle))
                    .frame(minHeight: touchMin).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pwaDocs.sort")
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, -2) }
    }

    func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(14, on ? .bold : .semibold)).foregroundStyle(on ? Theme.onPrimary : Theme.navy).lineLimit(1)
                .padding(.horizontal, 14).frame(height: 36)
                .background(on ? Theme.navySolid : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.borderSubtle))
                .frame(minHeight: touchMin).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var columnHeads: some View {
        HStack(spacing: 12) {
            Text("สถานี").frame(width: 200, alignment: .leading)
            Text("ถัดไป").frame(maxWidth: .infinity, alignment: .leading)
            Text("ชุดเอกสาร").frame(width: 300)
        }
        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func stationRow(_ r: PWADocs.StationRow, data: PageData, selected: Bool) -> some View {
        let missing = PWADocs.open(r.station, library: data.library).count
        return Button {
            selectedID = r.id
            package = nil
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.station.ref + " " + r.station.shortName).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    stationFacts(r, missing: missing)
                }
                .frame(width: 200, alignment: .leading)
                nextCell(r)
                PWADocsStepper(steps: r.steps, showsValues: false).frame(width: 300)
            }
            .padding(.horizontal, 16).frame(minHeight: 66)
            .background(selected ? Theme.rowSelected : Theme.surface)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.primary).frame(width: 3) } }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("pwaDocs.station.\(r.station.mpNumber.map(String.init) ?? r.id)")
    }

    /// `ส่งมอบ 6/10 · ผู้รับเหมา A · ขาด 3`, `ขาด n` in amber.
    private func stationFacts(_ r: PWADocs.StationRow, missing: Int) -> some View {
        let parts = [r.handover.map { "ส่งมอบ " + PWAPlanFormat.numeric.string(from: $0) },
                     r.station.contractor.isEmpty ? nil : PWAPlan.contractorTitle(r.station.contractor)].compactMap { $0 }
        var text = Text(parts.joined(separator: " · ")).foregroundColor(Theme.inkMuted)
        if missing > 0 { text = text + Text((parts.isEmpty ? "" : " · ") + "ขาด \(missing)").bold().foregroundColor(Theme.warningText) }
        return text.font(.sarabunFixed(12)).lineLimit(1)
    }

    /// The tag pill, except for `ทีมเรา` (the default, iPad only), then the next paper.
    private func nextCell(_ r: PWADocs.StationRow) -> some View {
        HStack(spacing: 8) {
            if r.state != .ours, r.next != nil || r.state != .ready {
                Text(r.tag).font(.sarabunFixed(11, .bold)).foregroundStyle(r.state.ink).lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).frame(height: 20).background(r.state.fill, in: Capsule())
            }
            Text(nextText(r)).font(.sarabunFixed(14)).foregroundStyle(r.next == nil ? Theme.successText : Theme.navy).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func nextText(_ r: PWADocs.StationRow) -> String {
        guard let next = r.next else {
            return r.steps.contains { $0.state == .current } ? "เอกสารครบ พร้อมยื่นชุดนี้" : "ยื่นครบทุกชุดแล้ว"
        }
        var parts = [next.name]
        if let due = r.due {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                                       to: Calendar.current.startOfDay(for: due)).day ?? 0
            parts.append(days < 0 ? "เลยกำหนด \(-days) วัน" : days == 0 ? "วันนี้" : "กำหนด " + PWAPlanFormat.numeric.string(from: due))
        }
        return parts.joined(separator: " · ")
    }

    private var emptyList: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.successText)
                .frame(width: 56, height: 56).background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(emptyTitle).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).multilineTextAlignment(.center)
            Text(search.isEmpty ? "เอกสารของสถานีกลุ่มนี้ไม่มีอะไรค้าง" : "ลองล้างคำค้นหรือดูทุกสถานี")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            Button("ดูทุกสถานี") {
                withAnimation(reduceMotion ? nil : .snappy) { contractor = nil; filter = .all }
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            .accessibilityIdentifier("pwaDocs.showAll")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        "ไม่มีสถานีที่" + filter.title + (contractor.map { " ของ" + PWAPlan.contractorTitle($0) } ?? "")
    }
}

/// The right panel: the selected station, its next paper, its packages (or one package's papers once drilled into),
/// its latest changes, and a bar for the PDF and uploads.
struct PWADocsStationPanel: View {
    let page: PWADocsPadView
    let data: PWADocsPadView.PageData
    let row: PWADocs.StationRow
    /// The package drilled into, passed in so the panel redraws when it changes.
    let drilled: StationDocs.Package?

    private var st: PWAPlan.Station { row.station }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    head
                    if let p = drilled {
                        AnyView(PWADocsPackagePapers(page: page, data: data, station: st, package: p))
                    } else {
                        AnyView(overview)
                    }
                }
                .padding(16)
            }
            bottomBar
        }
        .frame(maxHeight: .infinity)
        .padCard()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(st.ref + " " + st.shortName).font(.sarabunFixed(19, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(st.name).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Text(facts).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if page.job(st.id) != nil {
                Button("เปิดสถานี ›") { page.openStation = page.job(st.id) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
        }
    }

    /// `90 kWp · ผู้รับเหมา A · ส่งมอบ 6/10`.
    private var facts: String {
        [st.kWp > 0 ? PWADocsHomeView.kWp(st.kWp) + " kWp" : nil,
         st.contractor.isEmpty ? nil : PWAPlan.contractorTitle(st.contractor),
         row.handover.map { "ส่งมอบ " + PWAPlanFormat.numeric.string(from: $0) }].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var overview: some View {
        nextBox
        ForEach(PWADocs.steps, id: \.package) { s in AnyView(packageCard(s.package)) }
        recentList
    }

    private var nextBox: some View {
        let late = row.state == .late
        return Button {
            if let next = row.next { page.paper = .init(stationID: st.id, kindID: next.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.state == .ours ? "ถัดไป" : "ถัดไป · " + row.tag).font(.sarabunFixed(12, .semibold))
                    .foregroundStyle(late ? Theme.dangerText : Theme.inkMuted)
                Text(page.nextText(row)).font(.sarabunFixed(15, .bold)).foregroundStyle(late ? Theme.dangerText : Theme.navy)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(late ? Theme.dangerSoft : row.state == .ours ? Theme.primarySoft : row.state.fill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.next == nil)
    }

    private func packageCard(_ p: StationDocs.Package) -> some View {
        let needed = StationDocs.packages(st.docsContext).contains(p)
        let pr = StationDocs.progress(p, station: st.docs, library: data.library, st.docsContext)
        let complete = pr.isComplete
        return Button { withAnimation(.snappy) { page.package = p } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(p.padTitle).font(.sarabunFixed(15, .bold)).foregroundStyle(needed ? Theme.navy : Theme.inkMuted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(!needed ? "ไม่ต้องยื่น" : complete ? "ครบ \(pr.total)/\(pr.total)" : "\(pr.ready)/\(pr.total) ฉบับ")
                        .font(.sarabunFixed(12, .bold)).foregroundStyle(!needed ? Theme.inkFaint : complete ? Theme.successText : Theme.navy)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(!needed ? Theme.background : complete ? Theme.successSoft : Theme.primarySoft, in: Capsule())
                    if needed { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint) }
                }
                if needed {
                    ProgressBar(value: pr.total == 0 ? 1 : Double(pr.ready) / Double(pr.total), color: complete ? Theme.success : Theme.primary)
                }
                Text(needed ? p.padNote : "อินเวอร์เตอร์รวมต่ำกว่า 200 kVA").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: needed ? [] : [5, 4])))
            .opacity(needed ? 1 : 0.75)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!needed)
        .accessibilityIdentifier("pwaDocs.package.\(p.rawValue)")
    }

    @ViewBuilder private var recentList: some View {
        let recent = PWADocs.recent(st, library: data.library)
        if !recent.isEmpty {
            Text("ความเคลื่อนไหว").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).padding(.top, 4)
            ForEach(recent, id: \.kind.id) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(item.state.status.isReady ? Theme.success : Theme.primary).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.kind.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        Text(item.state.status.title + (item.state.updatedAt.map { " · " + Self.relative($0) } ?? ""))
                            .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("รวมชุดเอกสาร PDF") { page.mergePDF(st, data: data) }
                .buttonStyle(TCButtonStyle(.primary, size: .bar, fullWidth: true))
                .accessibilityIdentifier("pwaDocs.mergePDF")
            Button("อัปโหลด") { page.upload = .init(stationID: st.id, package: drilled, kindID: nil) }
                .buttonStyle(TCButtonStyle(.secondary, size: .bar))
                .fixedSize()
                .accessibilityIdentifier("pwaDocs.upload")
        }
        .padding(16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

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
                ercLink
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
            Text(package == .pk2 ? "Check list ของ กกพ. 23 ข้อ · ข้อที่ไม่เข้าเงื่อนไขนับว่าครบ" : package.padNote)
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var ercLink: some View {
        Button { page.ercJob = page.job(station.id) } label: {
            HStack {
                Text("ลำดับ กกพ. · ยื่น พค.1 → ตรวจสถานที่ → พค.2").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.outside)
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
                    Text(Self.origin(kind) + (PWADocs.isIDCard(kind) ? " · ต้องปิดข้อมูลบนบัตร" : ""))
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    let others = kind.packages.filter { $0 != package }
                    if !others.isEmpty {
                        Text("⇄ " + others.map { PWADocs.stepTitle($0) }.joined(separator: " · "))
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

    /// `เราร่าง → กปภ. ลงนาม · ผจก. กปภ.สาขา`, `ขอจาก กปภ.สาขา`, `ทีมเราทำ · วิศวกรไฟฟ้า`.
    static func origin(_ kind: StationDocs.Kind) -> String {
        switch kind.origin {
        case .internalDoc: (["ทีมเราทำ"] + [kind.signBy].compactMap { $0 }).joined(separator: " · ")
        case .signoff: (["เราร่าง → กปภ. ลงนาม"] + [kind.signBy].compactMap { $0 }).joined(separator: " · ")
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
    /// The iPad panel's package titles, numbered as the hand-over folders (`4.1`, `4.2`, `4.3`).
    var padTitle: String {
        switch self {
        case .building: "4.1 ใบอนุญาต อ.1 / แจ้งเทศบาล"
        case .gridConnection: "4.2 ขออนุญาตขนานไฟ (กฟภ.)"
        case .pk2: "4.3 พค.2 · ยกเว้นใบอนุญาต กกพ."
        case .commissioning: "ทดสอบระบบ"
        case .handover: "ส่งมอบงาน"
        }
    }

    /// What goes in, short.
    var padNote: String {
        switch self {
        case .building: "แบบแปลน · ใบ กว. · หนังสือแจ้งเทศบาล · สำเนาโฉนด"
        case .gridConnection: "คำขอ · SLD · Datasheet · ผลทดสอบ · หนังสือมอบอำนาจ"
        case .pk2: "แบบตรวจสอบ 23 ข้อ · ภาพถ่าย · IEC Test (อินเวอร์เตอร์ ≥ 200 kVA)"
        case .commissioning: "IEC 62446 · ภาพถ่ายความร้อน"
        case .handover: "As-Built · IEC 62446 · คู่มือ O&M · ใบรับประกัน"
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
