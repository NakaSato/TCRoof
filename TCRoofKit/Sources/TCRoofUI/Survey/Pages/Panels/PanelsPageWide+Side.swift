#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// B1's right column: the A3 breaker feeding the panel, the load and when it was read, the daytime load note and details.
extension PanelsPageWide {
    var sideColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            a3Picker
            loadCard
            if let note = BuildingPanels.daytimeNote(job) { daytimeNote(note) }
            spareSlotsRow
            detailCard
        }
    }

    // MARK: A3 link

    var a3Picker: some View {
        let options = BuildingPanels.options(job), link = module.flatMap { BuildingPanels.linked($0, in: job) }
        return VStack(alignment: .leading, spacing: 8) {
            label("ตู้นี้ในผัง A3", aside: options.isEmpty ? "ยังไม่มีเบรกเกอร์ย่อยใน A3" : nil)
            Menu {
                Button("ไม่ผูกกับ A3") { BuildingPanels.link(&job, panel: moduleID, to: nil) }
                ForEach(boardGroups(options), id: \.0) { board, items in
                    Section(board) {
                        ForEach(items) { o in
                            Button { BuildingPanels.link(&job, panel: moduleID, to: o.ref) } label: {
                                Text(o.cbText + takenBy(o))
                                if o.id == link?.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(link?.label ?? "ยังไม่ได้เลือก").font(.sarabunFixed(18, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(link == nil ? Theme.inkMuted : Theme.navy)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(link == nil ? Theme.surface : Theme.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(link == nil ? Theme.navy.opacity(0.45) : Theme.teal))
                .contentShape(Rectangle())
            }
            .disabled(options.isEmpty)
            .accessibilityLabel("ตู้นี้ในผัง A3 " + (link?.label ?? "ยังไม่ได้เลือก"))
            // AT comes from A3 once linked; until then it is typed here
            if link == nil { breakerATField }
        }
    }

    /// Breakers grouped by board, in diagram order.
    func boardGroups(_ options: [BuildingPanels.Option]) -> [(String, [BuildingPanels.Option])] {
        var out: [(String, [BuildingPanels.Option])] = []
        for o in options {
            let key = "\(o.ref.trafo)/\(o.ref.board)"
            if let i = out.firstIndex(where: { $0.1.first.map { "\($0.ref.trafo)/\($0.ref.board)" } == key }) { out[i].1.append(o) }
            else { out.append((o.boardName + (job.values.transformers("trafos").count > 1 ? " (TR\(o.ref.trafo + 1))" : ""), [o])) }
        }
        return out
    }

    /// " · โรงกรอง" when another building is linked to the breaker.
    func takenBy(_ o: BuildingPanels.Option) -> String {
        guard let id = o.linkedTo, id != moduleID, let m = job.modules.first(where: { $0.id == id }) else { return "" }
        return " · " + BuildingPanels.name(m, in: job)
    }

    var breakerATField: some View {
        HStack(spacing: 10) {
            Text("ขนาดเบรกเกอร์เมน").font(.sarabunFixed(15, .semibold))
            Spacer(minLength: 6)
            SourceChip(source: values.source(BuildingPanels.Key.breakerAT))
            TextField("–", text: text(BuildingPanels.Key.breakerAT)).keyboardType(.decimalPad)
                .font(.sarabunFixed(17, .bold)).multilineTextAlignment(.trailing).frame(width: 90)
            Text("AT").foregroundStyle(Theme.inkMuted)
            NameplateScanButton(target: .breakerAT, apply: { v in
                if let i = index { job.modules[i].values.set(BuildingPanels.Key.breakerAT, .text(v), source: .nameplate) }
            }, compact: true)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.3)))
    }

    // MARK: load

    var loadCard: some View {
        let stored = values.text(BuildingPanels.Key.loadTime).trimmingCharacters(in: .whitespaces)
        let time = BuildingPanels.clockTime(stored)
        let now = time.flatMap { BuildingPanels.timeChips.contains($0) ? nil : $0 }
        return VStack(alignment: .leading, spacing: 8) {
            label("ปริมาณการใช้ไฟ", required: true, aside: time == nil && !stored.isEmpty ? "เวลาที่บันทึกไว้: \(stored)" : nil)
            HStack {
                TextField("เช่น 85", text: text(BuildingPanels.Key.loadKW)).keyboardType(.decimalPad).font(.sarabunFixed(20, .bold))
                Text("kW").font(.sarabunFixed(16, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, lineWidth: 1.5))
            HStack(spacing: 8) {
                timeChip(now.map { "ตอนนี้ \($0)" } ?? "ตอนนี้", on: now != nil) {
                    set(BuildingPanels.Key.loadTime, .text(BuildingPanels.nowTime()))
                }
                ForEach(BuildingPanels.timeChips, id: \.self) { c in
                    timeChip(c, on: time == c) { set(BuildingPanels.Key.loadTime, .text(c)) }
                }
            }
        }
    }

    func timeChip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.teal : Theme.navy.opacity(0.45), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เวลาที่อ่านโหลด " + title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func daytimeNote(_ n: BuildingPanels.DaytimeNote) -> some View {
        (Text(n.lead + " → ") + Text(n.conclusion).bold().foregroundColor(n.needsZeroExport ? Theme.pending : Theme.navy))
            .font(.sarabunFixed(14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    var spareSlotsRow: some View {
        HStack(spacing: 10) {
            Text("ช่องว่างในตู้").font(.sarabunFixed(15, .semibold))
            if !narrow { Text("แสดงที่จุดเชื่อมต่อ").font(.footnote).foregroundStyle(Theme.inkMuted) }
            Spacer(minLength: 6)
            TextField("–", text: text(BuildingPanels.Key.spareSlots)).keyboardType(.numberPad)
                .font(.sarabunFixed(17, .bold)).multilineTextAlignment(.trailing).frame(width: 60)
            Text("ช่อง").foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.3)))
    }

    var detailCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("รายละเอียดเพิ่มเติม")
            TextEditor(text: text("detail"))
                .font(.sarabunFixed(17)).scrollContentBackground(.hidden).padding(8)
                .frame(minHeight: 180)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
        }
    }
}
#endif
