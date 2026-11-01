import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: ทดสอบ IEC 62446

    func phoneIECTab() -> some View {
        let r = job.iecReport, stages = IECReport.Stage.allCases
        let current = r.flatMap { r in stages.first { !r.isDone($0) } }
        let (chipText, tone): (String, InstallPageData.Tone) = if let r {
            if let res = r.result { (res.passed ? "ผ่าน | ปิดแล้ว" : "ไม่ผ่าน", res.passed ? .ok : .danger) }
            else if r.isAwaitingClose { ("รอปิด", .warn) } else { ("กำลังทำ", .info) }
        } else { ("ยังไม่เริ่ม", .idle) }
        return VStack(alignment: .leading, spacing: 14) {
            phoneCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bolt").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.warningInk)
                            .frame(width: 44, height: 44).background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("ทดสอบ IEC 62446-1").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                            Text(r.map { InstallPageData.iecDetail($0, drive: ProjectDriveUpload.iecPhotoUpload(job)) } ?? "ยังไม่ได้ตั้งค่า inverter และสตริง")
                                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        toneChip(chipText, tone)
                    }
                    HStack(spacing: 4) {
                        ForEach(stages) { s in
                            Capsule().fill(r.map { $0.isDone(s) } == true ? Theme.success : s == current ? Theme.primary : Theme.track).frame(height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                    HStack(spacing: 8) {
                        factTile("อินเวอร์เตอร์", r.map { "\($0.inverters.count) เครื่อง" } ?? "–")
                        factTile("สตริง", r.map { "\($0.stringCount)" } ?? "–")
                        factTile("ผู้ทดสอบ", r.map { $0.tester.isEmpty ? "ทีม " + job.team.rawValue : $0.tester } ?? "–")
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(stages) { s in
                    Button { route = .iec } label: { iecRow(s, r, current: current) }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if s != stages.first { Rectangle().fill(Theme.hairline).frame(height: 1) } }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .cardShadow()
            Button { route = .iec } label: {
                Text(r == nil ? "เริ่มตั้งค่าการทดสอบ" : current.map { "ทำต่อ | ขั้น \($0.rawValue) " + $0.title } ?? "เปิดการทดสอบ").lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TCButtonStyle(.primary, size: .page, fullWidth: true))
            if r != nil {
                Button { route = .iec } label: { Text("ดูชีต Excel").frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .page, fullWidth: true))
            }
        }
    }

    private func iecRow(_ s: IECReport.Stage, _ r: IECReport?, current: IECReport.Stage?) -> some View {
        let done = r?.isDone(s) ?? false, isCurrent = s == current
        let note = done ? (r?.isConfirmed(s) == true ? "ยืนยันแล้ว" : "ครบแล้ว | ยังไม่ยืนยัน")
            : isCurrent ? (r?.missing(s).prefix(2).joined(separator: " | ") ?? "") : "ยังไม่เริ่ม"
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.success : isCurrent ? Theme.primary : Theme.segmentTrack)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                } else {
                    Text("\(s.rawValue)").font(.sarabunFixed(14, .bold)).foregroundStyle(isCurrent ? Theme.onPrimary : Theme.inkMuted)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(note).font(.sarabunFixed(13)).foregroundStyle(isCurrent && !done ? Theme.warningInk : Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 14).frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: เอกสาร

    /// The three submissions of the permit route, in order: the municipality, the PEA's grid connection, the ERC's พค.2.
    private static let permitRoute: [(StationDocs.Package, String, String)] = [
        (.building, "เทศบาล", "อ.1 / แจ้งเทศบาล"), (.gridConnection, "กฟภ.", "ขนานไฟ (กฟภ.)"), (.pk2, "กกพ.", "พค.2 (กกพ.)"),
    ]

    func phoneDocsTab() -> some View {
        let ctx = job.stationContext, station = job.stationDocs, library = StationDocsStore.loadLibrary()
        let applies = Set(StationDocs.packages(ctx))
        var seen = Set<String>(), papers: [StationDocs.Kind] = []
        for p in StationDocs.packages(ctx) { for k in StationDocs.papers(in: p, ctx) where seen.insert(k.id).inserted { papers.append(k) } }
        let states = papers.map { StationDocs.state($0, station: station, library: library).status }.filter { $0 != .notNeeded }
        let ready = states.filter(\.isReady).count, waiting = states.filter { $0 == .requested }.count
        let todo = states.count - ready - waiting
        let route = Self.permitRoute
        let selected = docsStage ?? route.first { applies.contains($0.0) && !StationDocs.progress($0.0, station: station, library: library, ctx).isComplete }?.0 ?? .building
        return VStack(alignment: .leading, spacing: 14) {
            phoneCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardHeading("เอกสารโครงการ", note: "ขออนุญาตของสถานีนี้")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(ready)").font(.sarabunFixed(30, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                        Text("/ \(states.count) ฉบับเรียบร้อย").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.success).frame(width: g.size.width * CGFloat(ready) / CGFloat(max(states.count, 1)))
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 12) {
                        legendDot(Theme.warning, "ต้องทำ \(todo)")
                        legendDot(Theme.aiPurple, "รอผู้อื่น \(waiting)")
                        legendDot(Theme.success, "ครบ / อนุมัติ \(ready)")
                    }
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Button("เปิดเอกสารสถานี | อัปโหลด") { phoneRoute = .docs(selected, nil) }
                        .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("เส้นทางขออนุญาต").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text("ยื่นตามลำดับ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            ForEach(Array(route.enumerated()), id: \.offset) { i, stage in
                permitStageCard(i + 1, stage, applies: applies.contains(stage.0), selected: selected == stage.0,
                                progress: StationDocs.progress(stage.0, station: station, library: library, ctx))
            }
            if applies.contains(selected) {
                paperList(selected, title: route.first { $0.0 == selected }.map { "\($0.1) | \($0.2)" } ?? selected.title,
                          ctx: ctx, station: station, library: library)
            }
        }
    }

    private func legendDot(_ c: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(title).monospacedDigit()
        }
    }

    private func permitStageCard(_ n: Int, _ stage: (StationDocs.Package, String, String), applies: Bool, selected: Bool,
                                 progress p: StationDocs.Progress) -> some View {
        let share = p.total > 0 ? Double(p.ready) / Double(p.total) : 0
        let (chipText, tone): (String, InstallPageData.Tone) = !applies ? ("ไม่ต้องยื่น", .idle)
            : p.isComplete ? ("ครบ \(p.ready)/\(p.total)", .ok) : p.ready > 0 ? ("กำลังยื่น", .info) : ("ยังไม่เริ่ม", .idle)
        let note = !applies ? "ต่ำกว่า 200 kVA" : p.isComplete ? "ยื่นครบแล้ว" : "ค้าง \(p.total - p.ready) ฉบับ"
        return Button { if applies { docsStage = stage.0 } } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.track, lineWidth: 5)
                    Circle().trim(from: 0, to: share).stroke(p.isComplete ? Theme.success : Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(applies ? "\(p.ready)/\(p.total)" : "–").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ขั้น \(n) | \(stage.1)").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    Text(stage.2).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 4)
                toneChip(chipText, tone)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Theme.primary : Theme.borderSubtle, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!applies)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func paperList(_ package: StationDocs.Package, title: String, ctx: StationDocs.Context, station: StationDocs.Station,
                           library: StationDocs.Library) -> some View {
        let kinds = StationDocs.papers(in: package, ctx)
        return VStack(spacing: 0) {
            HStack {
                Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 6)
                Text("ร่าง → ยื่น → อนุมัติ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            ForEach(kinds) { k in
                let s = StationDocs.state(k, station: station, library: library).status
                Button { phoneRoute = .docs(package, k.id) } label: { paperRow(k, s) }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
            if kinds.isEmpty {
                Text("ไม่มีเอกสารในชุดนี้").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 56)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    private func paperRow(_ k: StationDocs.Kind, _ s: StationDocs.Status) -> some View {
        let tone: InstallPageData.Tone = s == .approved ? .ok : s.isReady ? .info : s == .notNeeded ? .idle : s == .requested ? .info : .warn
        let level = switch s { case .approved: 3; case .submitted: 2; case .draft, .signed: 1; default: 0 }
        return HStack(spacing: 12) {
            Text("PDF").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 40, height: 46, alignment: .bottom).padding(.bottom, 4)
                .background(s == .missing || s == .notNeeded ? Theme.inkFaint : Self.ink(tone), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(k.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                Text(k.origin.title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in Circle().fill(i < level ? Theme.success : Theme.track).frame(width: 10, height: 10) }
                }
                .accessibilityHidden(true)
                toneChip(s.title, tone)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
