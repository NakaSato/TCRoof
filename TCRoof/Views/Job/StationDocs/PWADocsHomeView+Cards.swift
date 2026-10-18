import SwiftUI
import TCRoofUI
import TCRoofCore

// The page's cards (docs/ui/pwa-docs-iphone-v2 §3–7). No shadows, as the PWA home.

extension PWADocsHomeView {

    // MARK: summary

    func summaryCard(_ s: PWADocs.Summary) -> AnyView {
        AnyView(summaryContent(s))
    }

    private func summaryContent(_ s: PWADocs.Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("อนุมัติแล้ว").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(s.approved)").font(.sarabunFixed(28, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                        Text("/ \(s.total) ฉบับ").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                Text("\(s.percent)%").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successText)
                    .padding(.horizontal, 10).padding(.vertical, 2).background(Theme.successSoft, in: Capsule())
            }
            .accessibilityElement(children: .combine)
            bandBar(s)
            HStack(spacing: 0) {
                tile("ทีมเราทำ", s.open[.internalDoc] ?? 0, Theme.primary)
                tile("รอ กปภ. ลงนาม", s.open[.signoff] ?? 0, Theme.warning)
                tile("รอหน่วยงานนอก", s.open[.external] ?? 0, Theme.outside)
            }
            .padding(.horizontal, -6)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
        .docsCard()
    }

    private func bandBar(_ s: PWADocs.Summary) -> some View {
        let bands = PWADocs.Band.allCases.filter { (s.bands[$0] ?? 0) > 0 }
        return GeometryReader { geo in
            let gaps = CGFloat(max(bands.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(bands, id: \.self) { b in
                    Rectangle().fill(b.color)
                        .frame(width: max(0, (geo.size.width - gaps) * CGFloat(s.bands[b] ?? 0) / CGFloat(max(s.total, 1))))
                }
            }
        }
        .frame(height: 8)
        .background(Theme.borderOutdoor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(PWADocs.Band.allCases.map { "\($0.title) \(s.bands[$0] ?? 0)" }.joined(separator: " · "))
    }

    /// One of the three counts; a tap opens `ต้องทำ`.
    private func tile(_ title: String, _ count: Int, _ dot: Color) -> some View {
        Button { select(.todo) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(title).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text("\(count)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).monospacedDigit().padding(.leading, 12)
            }
            .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(count)")
    }

    // MARK: expiry

    func expiryBanner(_ row: PWADocs.LibraryRow) -> AnyView {
        AnyView(Button { open(row.kind, station: nil) } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock").font(.system(size: 17, weight: .semibold))
                // the name gives way; the days stay
                HStack(spacing: 4) {
                    Text(row.kind.name).lineLimit(1)
                    Group {
                        if case .soon(let days) = row.pill {
                            Text("หมดอายุอีก ") + Text("\(days) วัน").bold()
                        } else {
                            Text("หมดอายุแล้ว").bold()
                        }
                    }
                    .fixedSize()
                }
                .font(.sarabunFixed(13)).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.warningText)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain))
    }

    // MARK: stations

    @ViewBuilder func stations(_ rows: [PWADocs.StationRow]) -> some View {
        TCCountSegments(PWADocs.StationFilter.allCases.map { f in .init(f.title, count: rows.filter { f.holds($0.state) }.count) },
                        selection: Binding(get: { PWADocs.StationFilter.allCases.firstIndex(of: filter) ?? 0 },
                                           set: { i in withAnimation(reduceMotion ? nil : .snappy) { filter = PWADocs.StationFilter.allCases[i] } }))
        let shown = rows.filter { filter.holds($0.state) }
        if shown.isEmpty {
            empty(search.isEmpty ? "ไม่มีสถานีในกลุ่มนี้" : "ไม่พบสถานีที่ค้นหา")
        }
        ForEach(shown) { AnyView(stationCard($0)) }
    }

    private func stationCard(_ r: PWADocs.StationRow) -> some View {
        Button { station = job(r.station) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.station.shortName).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        Text(stationLine(r.station)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(r.tag).font(.sarabunFixed(11, .bold)).foregroundStyle(r.state.ink).lineLimit(1)
                        .padding(.horizontal, 9).frame(height: 20).background(r.state.fill, in: Capsule()).padding(.top, 1)
                }
                PWADocsStepper(steps: r.steps).padding(.horizontal, 4)
                nextRow(r)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .docsCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `MP 189 · 92.34 kWp · ผู้รับเหมา A`, leaving out what the station has none of.
    private func stationLine(_ s: PWAPlan.Station) -> String {
        let who = s.contractor.isEmpty ? s.team : PWAPlan.contractorTitle(s.contractor)
        return [s.ref, s.kWp > 0 ? "\(Self.kWp(s.kWp)) kWp" : "", who].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func kWp(_ x: Double) -> String {
        x.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func nextRow(_ r: PWADocs.StationRow) -> some View {
        HStack(spacing: 8) {
            if let next = r.next {
                Text("ถัดไป").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                Text(next.name).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            } else {
                Text(r.state == .ready && r.steps.contains { $0.state == .current } ? "เอกสารครบ พร้อมยื่นชุดนี้" : "ยื่นครบทุกชุดแล้ว")
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successText).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let handover = r.handover {
                Text("ส่งมอบ " + PWAPlanFormat.numeric.string(from: handover)).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1).fixedSize()
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, 10).frame(minHeight: 40)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: to do

    @ViewBuilder func todo(_ groups: [PWADocs.Group]) -> some View {
        let shown = groups.filter { !$0.items.isEmpty }
        if shown.isEmpty { empty(search.isEmpty ? "ไม่มีเอกสารค้าง" : "ไม่พบเอกสารที่ค้นหา") }
        ForEach(shown) { g in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(g.origin.dot).frame(width: 8, height: 8)
                    Text(g.origin.groupTitle).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    Spacer(minLength: 8)
                    Text(groupSub(g)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .padding(.horizontal, 12).frame(minHeight: 40)
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                ForEach(g.items) { AnyView(todoRow($0)) }
            }
            .docsCard()
        }
    }

    private func groupSub(_ g: PWADocs.Group) -> String {
        switch g.origin {
        case .internalDoc: "\(g.items.count) รายการ" + (g.draftable > 0 ? " · แอปสร้างได้ \(g.draftable)" : "")
        case .signoff: "\(g.items.count) รายการ"
        case .external: "\(g.items.count) รายการ · ติดตามอย่างเดียว"
        }
    }

    private func todoRow(_ item: PWADocs.Item) -> some View {
        Button { open(item.kind, station: item.station) } label: {
            HStack(spacing: 10) {
                Circle().strokeBorder(item.ring, lineWidth: 2).frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.kind.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    (Text([item.place, item.who].filter { !$0.isEmpty }.joined(separator: " · ") + " · ").foregroundColor(Theme.inkMuted)
                     + Text(item.statusWord).bold().foregroundColor(item.statusInk))
                        .font(.sarabunFixed(12)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let due = dueText(item) {
                    Text(due.text).font(.sarabunFixed(12, .bold)).foregroundStyle(due.late ? Theme.dangerText : Theme.inkMuted)
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 56)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `เลย 4 วัน`, `วันนี้` (both red), or `20/10`.
    private func dueText(_ item: PWADocs.Item) -> (text: String, late: Bool)? {
        guard let due = item.due, let days = item.days(today: today) else { return nil }
        if days < 0 { return ("เลย \(-days) วัน", true) }
        if days == 0 { return ("วันนี้", true) }
        return (PWAPlanFormat.numeric.string(from: due), false)
    }

    // MARK: library

    @ViewBuilder func libraryList(_ rows: [PWADocs.LibraryRow]) -> some View {
        Text("อัปโหลดครั้งเดียว ใช้ได้ทุกสถานี · แอปเช็กวันหมดอายุให้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 2)
        if rows.isEmpty {
            empty("ไม่พบเอกสารที่ค้นหา")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in AnyView(libraryRow(r, divider: i > 0)) }
            }
            .docsCard()
        }
    }

    private func libraryRow(_ r: PWADocs.LibraryRow, divider: Bool) -> some View {
        Button { open(r.kind, station: nil) } label: {
            HStack(spacing: 10) {
                Text(r.kind.scope.badge).font(.sarabunFixed(10, .heavy)).foregroundStyle(r.kind.scope.badgeInk).lineLimit(1)
                    .frame(width: 46, height: 34).background(r.kind.scope.badgeFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.kind.name).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(librarySub(r)).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(r.pill.title).font(.sarabunFixed(11, .bold)).foregroundStyle(r.pill.ink).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 1).background(r.pill.fill, in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 54)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `ผู้รับจ้าง · หมดอายุ 30/11/2569`, or the packages it goes into.
    private func librarySub(_ r: PWADocs.LibraryRow) -> String {
        let detail = r.state.expiresAt.map { "หมดอายุ " + ThaiFormat.numericDate.string(from: $0) }
            ?? "ใช้ในชุด" + r.kind.packages.map { PWADocs.stepTitle($0) }.joined(separator: " · ")
        return r.kind.scope.owner + " · " + detail
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 80).docsCard()
    }
}

/// The station card's four steps (`อ.1 · ขนานไฟ · พค.2 · ส่งมอบ`): done a green tick, current a blue ringed number,
/// later a grey outline, not required a dashed `–` over `ไม่ต้องยื่น`. The line is green up to the current step.
struct PWADocsStepper: View {
    let steps: [PWADocs.Step]
    /// The count line under each label (`8/9`, `ครบ`); the iPad table leaves it out (docs/ui/pwa-docs-ipad).
    var showsValues = true

    private var current: Int? { steps.firstIndex { $0.state == .current } }

    private func isDone(_ i: Int) -> Bool { steps[i].state == .done || steps[i].state == .skip }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in step(i, s) }
        }
    }

    private func step(_ i: Int, _ s: PWADocs.Step) -> some View {
        let leftOn = i > 0 && isDone(i - 1) && (current.map { i <= $0 } ?? true)
        let rightOn = isDone(i) && (current.map { i < $0 } ?? true)
        return VStack(spacing: 3) {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle().fill(leftOn ? Theme.success : Theme.borderSubtle).frame(height: 3).opacity(i == 0 ? 0 : 1)
                    Rectangle().fill(rightOn ? Theme.success : Theme.borderSubtle).frame(height: 3).opacity(i == steps.count - 1 ? 0 : 1)
                }
                dot(i, s)
            }
            .frame(height: 29)
            Text(s.title).font(.sarabunFixed(12, s.state == .current ? .heavy : .semibold)).lineLimit(1)
                .foregroundStyle(s.state == .current ? Theme.primary : s.state == .done ? Theme.navy : Theme.muted)
            if showsValues {
                Text(value(s)).font(.sarabunFixed(10.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: showsValues ? 48 : 0, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.title + " · " + (s.state == .skip ? "ไม่ต้องยื่น" : s.state == .done ? "ครบ"
                                               : "เอกสาร \(s.progress.ready) จาก \(s.progress.total)"))
    }

    private func value(_ s: PWADocs.Step) -> String {
        switch s.state {
        case .skip: "ไม่ต้องยื่น"
        case .done: "ครบ"
        default: "\(s.progress.ready)/\(s.progress.total)"
        }
    }

    @ViewBuilder private func dot(_ i: Int, _ s: PWADocs.Step) -> some View {
        switch s.state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 22, height: 22).background(Theme.success, in: Circle())
        case .current:
            Text("\(i + 1)").font(.sarabunFixed(11.5, .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 26, height: 26).background(Theme.primary, in: Circle())
                .background(Circle().fill(Theme.primary.opacity(0.18)).padding(-4))
        case .later:
            Text("\(i + 1)").font(.sarabunFixed(11.5, .heavy)).foregroundStyle(Theme.muted)
                .frame(width: 22, height: 22).background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.inkFaint, lineWidth: 1.5))
        case .skip:
            Text("–").font(.sarabunFixed(11.5, .heavy)).foregroundStyle(Theme.inkFaint)
                .frame(width: 22, height: 22).background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
        }
    }
}

// MARK: - colours and words

extension PWADocs.Band {
    var title: String {
        switch self {
        case .approved: "อนุมัติแล้ว"
        case .submitted: "ยื่นแล้ว"
        case .waiting: "รอลงนาม"
        case .draft: "ร่าง"
        case .missing: "ยังไม่มี"
        }
    }

    var color: Color {
        switch self {
        case .approved: Theme.success
        case .submitted: Theme.outside
        case .waiting: Theme.warning
        case .draft: Theme.primary
        case .missing: Theme.borderOutdoor
        }
    }
}

extension PWADocs.StationFilter {
    var title: String {
        switch self {
        case .todo: "ต้องทำ"
        case .waiting: "รอผู้อื่น"
        case .all: "ทั้งหมด"
        }
    }
}

extension PWADocs.StationState {
    var ink: Color {
        switch self {
        case .late: Theme.dangerText
        case .ours: Theme.navy
        case .waitingPWA: Theme.warningText
        case .waitingOutside: Theme.outside
        case .ready: Theme.successText
        }
    }

    var fill: Color {
        switch self {
        case .late: Theme.dangerSoft
        case .ours: Theme.primarySoft
        case .waitingPWA: Theme.warningTint
        case .waitingOutside: Theme.outsideSoft
        case .ready: Theme.successSoft
        }
    }
}

extension StationDocs.Origin {
    var groupTitle: String {
        switch self {
        case .internalDoc: "ทีมเราจัดทำ"
        case .signoff: "เราร่าง → กปภ. ลงนาม"
        case .external: "ขอจากหน่วยงานนอก"
        }
    }

    var dot: Color {
        switch self {
        case .internalDoc: Theme.primary
        case .signoff: Theme.warning
        case .external: Theme.outside
        }
    }
}

extension PWADocs.Item {
    /// The status ring: grey missing, blue draft, orange waiting for PWA's signature, purple asked of an outside office.
    var ring: Color {
        switch status {
        case .draft: Theme.primary
        case .requested: kind.origin == .signoff ? Theme.warning : Theme.outside
        default: Theme.inkFaint
        }
    }

    var statusInk: Color {
        switch status {
        case .draft: Theme.primary
        case .requested: kind.origin == .signoff ? Theme.warningText : Theme.outside
        default: Theme.inkMuted
        }
    }
}

extension StationDocs.Scope {
    /// The library row's badge.
    var badge: String {
        switch self {
        case .org, .branch: "กปภ."
        case .contractor: "บริษัท"
        case .project, .site: "โครงการ"
        }
    }

    var badgeInk: Color {
        switch self {
        case .org, .branch: Theme.primary
        case .contractor: Theme.outside
        case .project, .site: Theme.successText
        }
    }

    var badgeFill: Color {
        switch self {
        case .org, .branch: Theme.primarySoft
        case .contractor: Theme.outsideSoft
        case .project, .site: Theme.successSoft
        }
    }

    /// Whose paper it is, short: `ทั้ง กปภ.`, `ผู้รับจ้าง`.
    var owner: String {
        switch self {
        case .org: "ทั้ง กปภ."
        case .branch: "กปภ.สาขา"
        case .contractor: "ผู้รับจ้าง"
        case .project: "ทั้งโครงการ"
        case .site: "สถานี"
        }
    }
}

extension PWADocs.Pill {
    var title: String {
        switch self {
        case .latest: "ล่าสุด"
        case .missing: "ยังไม่มี"
        case .soon(let days): "\(days) วัน"
        case .expired: "หมดอายุ"
        case .notNeeded: "ไม่ใช้"
        }
    }

    var ink: Color {
        switch self {
        case .latest: Theme.successText
        case .missing, .notNeeded: Theme.inkMuted
        case .soon, .expired: Theme.dangerText
        }
    }

    var fill: Color {
        switch self {
        case .latest: Theme.successSoft
        case .missing, .notNeeded: Theme.segmentTrack
        case .soon, .expired: Theme.dangerSoft
        }
    }
}

private extension View {
    /// The page's white card: r16 with a hairline border.
    func docsCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
