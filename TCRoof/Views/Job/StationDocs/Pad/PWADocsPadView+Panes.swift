import SwiftUI
import TCRoofUI
import TCRoofCore

// `ต้องทำ` (§7), `คลังกลาง` (§8) and the search panel (§9) of the iPad page.

extension PWADocsPadView {

    // MARK: to do

    func todoPane(_ data: PageData) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(data.groups) { g in AnyView(todoColumn(g, data: data)) }
        }
    }

    private func todoColumn(_ g: PWADocs.Group, data: PageData) -> some View {
        let late = PWADocs.dueNow(g, today: today)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(g.origin.dot).frame(width: 8, height: 8)
                Text(g.origin.groupTitle).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                if late > 0 {
                    Text("เลย \(late)").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.dangerText)
                        .padding(.horizontal, 7).frame(height: 18).background(Theme.dangerSoft, in: Capsule())
                }
                Spacer(minLength: 4)
                Text("\(g.items.count) รายการ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Text(subBar(g)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(Theme.background)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            if g.items.isEmpty {
                Text("ไม่มีรายการค้าง").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(g.items) { item in AnyView(todoCard(item, data: data)) }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padCard()
        .overlay(alignment: .top) { Rectangle().fill(g.origin.dot).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func subBar(_ g: PWADocs.Group) -> String {
        switch g.origin {
        case .internalDoc: "แอปสร้างได้ \(g.draftable) · เรียงตามกำหนด"
        case .signoff: "ทวงได้จากแอป · เรียงตามกำหนด"
        case .external: "ติดตามอย่างเดียว · เรียงตามกำหนด"
        }
    }

    private func todoCard(_ item: PWADocs.Item, data: PageData) -> some View {
        let state = item.station.map { StationDocs.state(item.kind, station: $0.docs, library: data.library) }
            ?? StationDocs.state(item.kind, station: .init(), library: data.library)
        let draftable = StationDocs.draft(for: item.kind) != nil && item.status == .missing
        // a library paper on the list has no station: it opens the library's sheet
        let open = {
            if let st = item.station { paper = .init(stationID: st.id, kindID: item.kind.id) }
            else { libraryPaper = .init(stationID: nil, kindID: item.kind.id) }
        }
        return Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Circle().strokeBorder(item.status.ring(item.kind.origin), lineWidth: 2).frame(width: 18, height: 18).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PWADocs.title(item)).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Text(cardPlace(item, state: state)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    PWADocsPill(status: item.status, origin: item.kind.origin)
                    if draftable { PWADocsPill(text: "แอปสร้างได้", ink: Theme.successText, fill: Theme.successSoft) }
                    if let due = dueText(item) {
                        Text(due.text).font(.sarabunFixed(12, .bold)).foregroundStyle(due.ink).lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 4)
                    Text(action(item)).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
                }
                .padding(.leading, 28)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padCard(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pwaDocs.todo.\(item.station?.mpNumber.map(String.init) ?? "lib").\(item.kind.id)")
    }

    /// `MP 189 ทุ่งน้อย · อ.1 · ทวงแล้ว 2 ครั้ง`.
    private func cardPlace(_ item: PWADocs.Item, state: StationDocs.DocState) -> String {
        var parts = [item.place]
        if let p = item.package { parts.append(PWADocs.stepTitle(p)) }
        if !state.reminders.isEmpty { parts.append("ทวงแล้ว \(state.reminders.count) ครั้ง") }
        return parts.joined(separator: " · ")
    }

    /// `เลย n วัน` red, `วันนี้` amber, else `d/M`.
    private func dueText(_ item: PWADocs.Item) -> (text: String, ink: Color)? {
        guard let due = item.due, let days = item.days(today: today) else { return nil }
        if days < 0 { return ("เลย \(-days) วัน", Theme.dangerText) }
        if days == 0 { return ("วันนี้", Theme.warningText) }
        return (PWAPlanFormat.numeric.string(from: due), Theme.inkMuted)
    }

    /// The card's button: what the paper's sheet would do first.
    private func action(_ item: PWADocs.Item) -> String {
        if item.kind.scope.isShared && item.station == nil { return item.status == .missing ? "อัปโหลด" : "เปิด" }
        switch item.status {
        case .missing:
            if StationDocs.draft(for: item.kind) != nil { return "สร้างร่าง" }
            if item.kind.scope.isShared { return "แนบจากคลัง" }
            return item.kind.origin == .external ? "ขอเอกสาร" : "อัปโหลด"
        case .draft: return "แก้ร่าง"
        case .requested: return "ทวง"
        default: return "เปิด"
        }
    }

    // MARK: library

    func libraryPane(_ data: PageData) -> some View {
        let marks = PWADocs.expiryMarks(data.libraryRows, today: today)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !marks.isEmpty { AnyView(expiryCard(marks)) }
                ForEach(PWADocs.libraryScopes, id: \.self) { scope in
                    let rows = data.libraryRows.filter { $0.kind.scope == scope }
                    if !rows.isEmpty { AnyView(libraryGroup(scope, rows: rows, data: data)) }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func expiryCard(_ marks: [PWADocs.ExpiryMark]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("หมดอายุใน 12 เดือน").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text("แอปเตือนก่อน 60 วัน · ใช้แทนในทุกสถานีเมื่ออัปโหลดฉบับใหม่").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            PWADocsExpiryTrack(marks: marks) { libraryPaper = .init(stationID: nil, kindID: $0.id) }
        }
        .padding(16)
        .padCard()
    }

    private func libraryGroup(_ scope: StationDocs.Scope, rows: [PWADocs.LibraryRow], data: PageData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scope.groupTitle).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(scope.groupSub).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(rows) { r in AnyView(libraryCard(r, used: PWADocs.usedIn(r.kind, data.stations).count)) }
            }
        }
    }

    private func libraryCard(_ r: PWADocs.LibraryRow, used: Int) -> some View {
        Button { libraryPaper = .init(stationID: nil, kindID: r.kind.id) } label: {
            HStack(spacing: 12) {
                Text(r.kind.scope.padBadge).font(.sarabunFixed(12, .heavy)).foregroundStyle(r.kind.scope.padBadgeInk).lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 46, height: 46).background(r.kind.scope.padBadgeFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.kind.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(librarySub(r)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    Text("ใช้ใน \(used) สถานี").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(r.pill.padTitle).font(.sarabunFixed(11.5, .bold)).foregroundStyle(r.pill.ink).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).frame(height: 22).background(r.pill.fill, in: Capsule())
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padCard(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pwaDocs.lib.\(r.kind.id)")
    }

    /// `ผู้รับจ้าง · หมดอายุ 30/11/2569`, or its packages.
    func librarySub(_ r: PWADocs.LibraryRow) -> String {
        let detail = r.state.expiresAt.map { "หมดอายุ " + ThaiFormat.numericDate.string(from: $0) }
            ?? "ใช้ในชุด" + r.kind.packages.map { PWADocs.stepTitle($0) }.joined(separator: " · ")
        return r.kind.scope.owner + " · " + detail
    }

    // MARK: search

    func searchPanel(_ data: PageData) -> some View {
        let hits = PWADocs.search(search, stations: data.stations, library: data.library)
        return VStack(alignment: .leading, spacing: 0) {
            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                searchHint(data)
            } else if hits.isEmpty {
                Text("ไม่พบ \"\(search)\" · ลองเลข MP หรือชื่อสถานี").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    .padding(16)
            } else {
                Text("\(hits.count) ผลลัพธ์").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 16).frame(height: 36)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(hits) { h in AnyView(hitRow(h)) }
                    }
                }
                .frame(maxHeight: 560)
            }
        }
        .frame(width: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.navy.opacity(0.22), radius: 20, y: 12)
        .padding(.top, 10).padding(.trailing, 63)
    }

    private func searchHint(_ data: PageData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ค้นได้ทั้งสถานี ชื่อเอกสาร และเลขที่หนังสือ").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 8) {
                ForEach(suggestions(data), id: \.self) { s in
                    Button { search = s } label: {
                        Text(s).font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.navy).lineLimit(1)
                            .padding(.horizontal, 12).frame(height: 34).background(Theme.segmentTrack, in: Capsule())
                            .frame(minHeight: touchMin).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    /// Four chips: the first station's MP number and the next papers of the first rows, then a generic one.
    private func suggestions(_ data: PageData) -> [String] {
        var out: [String] = data.rows.first.map { [$0.station.ref] } ?? []
        for r in data.rows { if let n = r.next?.name.components(separatedBy: " (").first, !out.contains(n) { out.append(n) } }
        if !out.contains("มอบอำนาจ") { out.append("มอบอำนาจ") }
        return Array(out.prefix(4))
    }

    private func hitRow(_ h: PWADocs.Hit) -> some View {
        Button { openHit(h) } label: {
            HStack(spacing: 12) {
                Text(h.tag).font(.sarabunFixed(11, .bold)).foregroundStyle(h.tagInk).lineLimit(1)
                    .frame(width: 58, height: 22).background(h.tagFill, in: Capsule())
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(hitContext(h)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 16).frame(minHeight: 58)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pwaDocs.hit.\(h.kind?.id ?? h.station?.id ?? "")")
    }

    /// `MP 189 ทุ่งน้อย · ขนานไฟ · ร่าง`, `คลังกลาง · ทั้ง กปภ. · ล่าสุด`, or the station's next paper.
    private func hitContext(_ h: PWADocs.Hit) -> String {
        switch h.type {
        case .station:
            return [h.station?.name, h.station.map { PWAPlan.contractorTitle($0.contractor) }].compactMap { $0 }.joined(separator: " · ")
        case .paper:
            guard let st = h.station, let k = h.kind else { return "" }
            return [st.ref + " " + st.shortName, h.package.map { PWADocs.stepTitle($0) }, h.state.map { $0.status.padWord(k.origin) }]
                .compactMap { $0 }.joined(separator: " · ")
        case .library:
            guard let k = h.kind else { return "" }
            return ["คลังกลาง", k.scope.owner, h.state.map { PWADocs.pill(k, $0, today: today, warnDays: 60).padTitle }]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }

    private func openHit(_ h: PWADocs.Hit) {
        searchOpen = false
        switch h.type {
        case .station:
            pane = .st
            selectedID = h.station?.id
            package = nil
            if let st = h.station, !(shownRows(data).contains { $0.id == st.id }) { filter = .all; contractor = nil }
        case .paper:
            if let k = h.kind { paper = .init(stationID: h.station?.id, kindID: k.id) }
        case .library:
            if let k = h.kind { libraryPaper = .init(stationID: nil, kindID: k.id) }
        }
    }
}

/// The library's 12-month track: today at the left, the first 60 days tinted red, a marker per paper (red under
/// 60 days, amber under 180, green after) with its name and days above it. A marker opens its paper.
struct PWADocsExpiryTrack: View {
    let marks: [PWADocs.ExpiryMark]
    let open: (StationDocs.Kind) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.track).frame(height: 4).offset(y: 44)
                Capsule().fill(Theme.dangerSoft).frame(width: w * 60 / 365, height: 4).offset(y: 44)
                ForEach(marks) { m in
                    let x = w * CGFloat(m.days) / 365
                    // the label runs right of a marker in the first half, left of one in the second, so it stays on the card
                    let left = x < w / 2
                    Button { open(m.kind) } label: {
                        VStack(alignment: left ? .leading : .trailing, spacing: 4) {
                            Text(m.kind.name + " · " + (m.expired ? "หมดอายุ" : "\(m.days) วัน"))
                                .font(.sarabunFixed(12, .bold)).foregroundStyle(m.ink).lineLimit(1).fixedSize()
                            ZStack {
                                Circle().fill(Theme.surface).frame(width: 18, height: 18)
                                Circle().strokeBorder(m.ink, lineWidth: 2).frame(width: 18, height: 18)
                                Circle().fill(m.ink).frame(width: 8, height: 8)
                            }
                        }
                        .frame(minHeight: touchMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .alignmentGuide(.leading) { d in left ? 9 - x : d.width - 9 - x }
                    .offset(y: 6)
                    .accessibilityLabel(m.kind.name + " หมดอายุ" + (m.expired ? "แล้ว" : "ในอีก \(m.days) วัน"))
                }
                Text("วันนี้").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).offset(y: 56)
                Text("60 วัน").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.dangerText)
                    .alignmentGuide(.leading) { d in d.width / 2 - w * 60 / 365 }.offset(y: 56)
                Text("12 เดือน").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                    .alignmentGuide(.leading) { d in d.width - w }.offset(y: 56)
            }
        }
        .frame(height: 74)
    }
}

extension PWADocs.ExpiryMark {
    var ink: Color { days < 60 ? Theme.dangerText : days < 180 ? Theme.warningText : Theme.successText }
}

extension PWADocs.Hit {
    var tag: String {
        switch type {
        case .station: "สถานี"
        case .paper: "เอกสาร"
        case .library: "คลังกลาง"
        }
    }

    var tagInk: Color { type == .library ? Theme.successText : type == .station ? Theme.primary : Theme.navy }
    var tagFill: Color { type == .library ? Theme.successSoft : type == .station ? Theme.primarySoft : Theme.segmentTrack }

    var title: String {
        switch type {
        case .station: (station?.ref ?? "") + " " + (station?.shortName ?? "")
        default: kind?.name ?? ""
        }
    }
}

extension StationDocs.Scope {
    var groupTitle: String {
        switch self {
        case .org: "ระดับ กปภ."
        case .contractor: "ผู้รับจ้าง"
        case .project: "โครงการ"
        case .branch: "สาขา กปภ."
        case .site: "สถานี"
        }
    }

    var groupSub: String {
        switch self {
        case .org: "ใช้ได้ทุกสถานี"
        case .contractor: "ใบอนุญาตและเอกสารบริษัท · เตือนก่อนหมดอายุ 60 วัน"
        case .project: "ใช้ทั้งโครงการ"
        case .branch: "ใช้ร่วมกันเฉพาะสถานีในสาขาเดียวกัน"
        case .site: ""
        }
    }

    /// The iPad card's badge: `สาขา` apart from `กปภ.`.
    var padBadge: String { self == .branch ? "สาขา" : badge }
    var padBadgeInk: Color { self == .branch ? Theme.warningText : badgeInk }
    var padBadgeFill: Color { self == .branch ? Theme.warningTint : badgeFill }
}

extension PWADocs.Pill {
    /// On iPad an expiring paper reads `49 วัน`, a missing one `ยังไม่มี`.
    var padTitle: String { title }
}
