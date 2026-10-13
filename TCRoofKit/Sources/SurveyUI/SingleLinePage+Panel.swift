#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// Right-hand panel of the single line page: PV data, breaker check, what must be collected, flood note, lists.
extension SingleLinePage {
    static let navyCard = Theme.navySolid

    func panel(_ sl: SingleLine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            pvCard(sl)
            checkSection(sl)
            if !sl.blocking.isEmpty { blockingCard(sl) }
            if let f = sl.flood { floodCard(f) }
            VStack(spacing: 0) {
                disclosure("ข้อมูลที่ขาดอื่นๆ", "\(sl.others.count) จุด · ไม่กระทบแบบ", .others)
                disclosure("สภาพอุปกรณ์", "ชำรุด \(sl.conditionCounts.bad) · พอใช้ \(sl.conditionCounts.fair)", .conditions)
                disclosure("ค่าสมมติ", "\(sl.assumptions.count) ข้อ" + (sl.pv.totalCableM > 0 ? " · รวมระยะสาย \(sl.pv.totalCableM) ม." : ""), .assumptions)
            }
        }
        .padding(.bottom, 8)
    }

    func pvCard(_ sl: SingleLine) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ข้อมูลฝั่ง PV").font(.sarabunFixed(20, .bold))
                Spacer()
                Text("400 V 3 เฟส").font(.sarabunFixed(13)).opacity(0.75)
            }
            .padding(.bottom, 10)
            ForEach(Array(sl.pv.rows.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.label).font(.sarabunFixed(14)).opacity(0.85)
                    Spacer(minLength: 6)
                    Text(r.value.text).font(.sarabunFixed(i == 0 ? 18 : 15, .bold)).monospacedDigit().minimumScaleFactor(0.8)
                        .foregroundStyle(r.value.isMissing ? Theme.dangerOnDark : .white)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(.white.opacity(0.14)).frame(height: 1) } }
            }
        }
        .foregroundStyle(Theme.onMedia)
        .padding(16)
        .background(Self.navyCard, in: RoundedRectangle(cornerRadius: 16))
    }

    func checkSection(_ sl: SingleLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("เบรกเกอร์ทนลัดวงจร \(sl.isc.map { SingleLine.fmt($0) } ?? "?") kA ได้ไหม").font(.sarabunFixed(17, .bold))
            if sl.iscAssumedZ { Text("ใช้ %Z สมมติ \(SingleLine.fmt(SLConstants.defaultZPercent)) % ในการคำนวณ").font(.sarabunFixed(13)).foregroundStyle(Theme.pending) }
            if sl.checks.isEmpty { Text("ยังไม่มีเบรกเกอร์ในตู้ที่ต่อ PV").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
            ForEach(sl.checks) { c in
                Button { open(c.target) } label: {
                    HStack(spacing: 10) {
                        let (icon, col) = mark(c.state)
                        Image(icon, bundle: .module).resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(c.name).font(.sarabunFixed(15)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(c.value).font(.sarabunFixed(15, .bold)).foregroundStyle(col).lineLimit(1)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    func mark(_ s: SLCheckState) -> (String, Color) {
        switch s {
        case .ok: return ("ui-check-ok", Theme.success)
        case .marginal: return ("ui-check-marginal", Theme.pending)
        case .insufficient: return ("ui-check-insufficient", Theme.danger)
        case .unknown: return ("ui-check-unknown", Theme.danger)
        }
    }

    func blockingCard(_ sl: SingleLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ต้องเก็บก่อนออกแบบ").font(.sarabunFixed(16, .bold))
                Spacer()
                Text("\(sl.blocking.count) จาก \(sl.missing.count)").font(.sarabunFixed(14, .bold))
            }
            .foregroundStyle(Theme.danger)
            ForEach(sl.blocking) { b in
                HStack(spacing: 8) {
                    Text(b.label).font(.sarabunFixed(14)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { open(b.target) } label: {
                        Text(b.target.linkLabel).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(minWidth: 52, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 14))
    }

    func floodCard(_ f: SLFlood) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image("ui-flood-alert", bundle: .module).resizable().scaledToFit().frame(width: 28, height: 28)
            Text("จุดเชื่อมต่อเคยน้ำท่วม").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.pending)
                + Text("\n" + f.text).font(.sarabunFixed(14))
            Spacer(minLength: 4)
            Button { open(SLTarget(.flood)) } label: {
                Text("A4 →").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(minWidth: 48, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 14))
    }

    func disclosure(_ title: String, _ detail: String, _ kind: ListKind) -> some View {
        Button { listSheet = kind } label: {
            HStack(spacing: 8) {
                Text(title).font(.sarabunFixed(16, .bold))
                Text(detail).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: lists

    @ViewBuilder func listView(_ kind: ListKind, _ sl: SingleLine) -> some View {
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection {
                    switch kind {
                    case .others:
                        ForEach(sl.others) { m in
                            Button { listSheet = nil; open(m.target) } label: {
                                HStack { Text(m.label).foregroundStyle(Theme.navy); Spacer(); Text(m.target.linkLabel).bold().foregroundStyle(Theme.primary) }
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if sl.others.isEmpty { Text("ไม่มีข้อมูลที่ขาดเพิ่ม").foregroundStyle(Theme.inkMuted) }
                    case .conditions:
                        ForEach(conditionRows(sl), id: \.0) { r in
                            HStack { Text(r.0); Spacer(); Text(r.1).bold().foregroundStyle(r.1 == "ชำรุด" ? Theme.danger : Theme.pending) }
                        }
                        if conditionRows(sl).isEmpty { Text("ไม่มีอุปกรณ์ชำรุดหรือพอใช้").foregroundStyle(Theme.inkMuted) }
                    case .assumptions:
                        ForEach(sl.assumptions) { a in Text(a.text).font(.sarabun(16, relativeTo: .callout)) }
                        if sl.assumptions.isEmpty { Text("ไม่มีค่าสมมติ").foregroundStyle(Theme.inkMuted) }
                    }
                }
            }
            .navigationTitle(kind == .others ? "ข้อมูลที่ขาดอื่นๆ" : kind == .conditions ? "สภาพอุปกรณ์" : "ค่าสมมติ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { listSheet = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    func conditionRows(_ sl: SingleLine) -> [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ name: String, _ t: SLText?) {
            if case .condition(let c)? = t?.status, c != .good { rows.append((name + " — " + (t?.text.replacingOccurrences(of: "สภาพ: ", with: "") ?? ""), c == .bad ? "ชำรุด" : "พอใช้")) }
        }
        for tx in sl.transformers {
            if case .condition(let c)? = tx.lines.last?.status, c != .good { rows.append(("TX\(tx.index + 1)", c == .bad ? "ชำรุด" : "พอใช้")) }
            for bd in tx.boards {
                add(bd.name, bd.main.condition)
                for b in bd.breakers { add("\(bd.name) CB\(b.number)", b.condition) }
            }
        }
        return rows
    }
}
#endif
