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
                Text("ชุด " + PWADocs.steps.map(\.title).joined(separator: " | ")).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
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

    /// `ส่งมอบ 6/10 | ผู้รับเหมา A | ขาด 3`, `ขาด n` in amber.
    private func stationFacts(_ r: PWADocs.StationRow, missing: Int) -> some View {
        let parts = [r.handover.map { "ส่งมอบ " + PWAPlanFormat.numeric.string(from: $0) },
                     r.station.contractor.isEmpty ? nil : PWAPlan.contractorTitle(r.station.contractor)].compactMap { $0 }
        var text = Text(parts.joined(separator: " | ")).foregroundColor(Theme.inkMuted)
        if missing > 0 { text = text + Text((parts.isEmpty ? "" : " | ") + "ขาด \(missing)").bold().foregroundColor(Theme.warningText) }
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
        return parts.joined(separator: " | ")
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

    /// `90 kWp | ผู้รับเหมา A | ส่งมอบ 6/10`.
    private var facts: String {
        [st.kWp > 0 ? PWADocsHomeView.kWp(st.kWp) + " kWp" : nil,
         st.contractor.isEmpty ? nil : PWAPlan.contractorTitle(st.contractor),
         row.handover.map { "ส่งมอบ " + PWAPlanFormat.numeric.string(from: $0) }].compactMap { $0 }.joined(separator: " | ")
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
                Text(row.state == .ours ? "ถัดไป" : "ถัดไป | " + row.tag).font(.sarabunFixed(12, .semibold))
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
                        Text(item.state.status.title + (item.state.updatedAt.map { " | " + Self.relative($0) } ?? ""))
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
            if !page.readOnly {
                Button("อัปโหลด") { page.upload = .init(stationID: st.id, package: drilled, kindID: nil) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .bar))
                    .fixedSize()
                    .accessibilityIdentifier("pwaDocs.upload")
            }
        }
        .padding(16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
