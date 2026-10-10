#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// B2's right column: the live plan with the tray / ladder steppers, the zero export choice (B4) and the inverter list.
extension InverterPageWide {
    var planTitle: String { station.site == .outdoor ? "แปลน Inverter Station" : "แปลนติดตั้งในอาคาร (Top view)" }

    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            planCard
            calcCard
        }
    }

    /// `คำนวณห้องและแบบให้เอง`: B4 in the header, the inverter list and the summary strip.
    var calcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let head = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            head {
                Text("คำนวณห้องและแบบให้เอง").font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                if !narrow { Spacer(minLength: 8) }
                zeroExport
            }
            Divider()
            inverterList
            summaryStrip
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.2)))
    }

    // MARK: plan

    var planCard: some View {
        let s = station
        return VStack(alignment: .leading, spacing: 10) {
            if narrow {
                // iPhone: title and verdict on one line, the site switch full width under them
                HStack(spacing: 10) {
                    Text(planTitle).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    planVerdict(s)
                }
                siteSwitch(s, segmentWidth: nil)
            } else {
                HStack(spacing: 10) {
                    Text(planTitle).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    siteSwitch(s, segmentWidth: 118)
                    planVerdict(s)
                }
            }
            planPicture(s)
            let trays = narrow ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
            trays {
                widthStepper("Tray อินเวอร์เตอร์ → AC-DB", value: s.trayWidth, min: s.trayMin, sizes: InverterStation.traySizes) { w in update { $0.trayPick = w } }
                widthStepper("Ladder ออกจาก AC-DB", value: s.ladderWidth, min: s.feeder.ladderMin, sizes: InverterStation.ladderSizes) { w in update { $0.ladderPick = w } }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }

    func siteSwitch(_ s: InverterStation, segmentWidth: CGFloat?) -> some View {
        HStack(spacing: 0) {
            ForEach(InverterStation.Site.allCases, id: \.self) { site in
                segment(site.label, on: s.site == site) { update { $0.site = site } }.frame(width: segmentWidth)
            }
        }
        .padding(3).background(Theme.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    func planVerdict(_ s: InverterStation) -> some View {
            Text(!s.measured ? "ยังไม่ได้วัด" : s.isOK ? "พื้นที่พอ ✓" : "พื้นที่ไม่พอ ✗").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .foregroundStyle(!s.measured ? Theme.pending : s.isOK ? Theme.success : Theme.danger)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((!s.measured ? Theme.pending : s.isOK ? Theme.success : Theme.danger).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    func planPicture(_ s: InverterStation) -> some View {
        Button { showPlan = true } label: {
            // capped so the inverter list and summary stay on screen in landscape; tap opens it full screen
            SketchView(sketch: InverterStationDrawing.sketch(s))
                .frame(maxWidth: .infinity, maxHeight: 270)
                .padding(6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.12)))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(width: 30, height: 30).background(Theme.surface.opacity(0.9), in: Circle()).padding(6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(planTitle) \(String(format: "%.1f", s.planLength)) × \(String(format: "%.1f", s.planWidth)) ม. อินเวอร์เตอร์ \(s.sizes.count) เครื่อง")
        .accessibilityHint("แตะเพื่อดูเต็มจอ")
    }

    func widthStepper(_ title: String, value: Int, min: Int, sizes: [Int], set: @escaping (Int) -> Void) -> some View {
        let down = InverterStation.step(sizes, from: value, by: -1, min: min), up = InverterStation.step(sizes, from: value, by: 1, min: min)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(title) \(value) มม.").font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(value > min ? "ขั้นต่ำ \(min) · ปรับเพิ่มเอง" : "ขั้นต่ำตามคำนวณ").font(.system(size: 12)).foregroundStyle(value > min ? Theme.pending : Theme.inkMuted)
            }
            Spacer(minLength: 4)
            boxButton("minus", enabled: down != nil) { if let down { set(down) } }
                .accessibilityLabel("ลดความกว้าง " + title)
            boxButton("plus", enabled: up != nil) { if let up { set(up) } }
                .accessibilityLabel("เพิ่มความกว้าง " + title)
        }
        .frame(maxWidth: .infinity)
    }

    /// 36-pt bordered stepper button with a 44-pt hit area.
    func boxButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 36, height: 34)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.45)))
                .opacity(enabled ? 1 : 0.35)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    // MARK: B4

    static let zeroExportLevels = ["กันย้อนที่แรงต่ำ", "กันย้อนที่แรงสูง"]
    var b4Index: Int? { job.modules.firstIndex { $0.type == .backfeed } }

    var zeroExport: some View {
        let level = b4Index.flatMap { job.modules[$0].values.choice("level") }
        return HStack(spacing: 8) {
            (Text("กันย้อน (B4)") + Text(" *").foregroundColor(Theme.danger)).font(.system(size: 14, weight: .bold)).lineLimit(1)
            ForEach(Array(zip(Self.zeroExportLevels, ["แรงต่ำ", "แรงสูง"])), id: \.0) { value, title in
                let on = level == value
                Button { if let i = b4Index { job.modules[i].values["level"] = .choice(value, other: "") } } label: {
                    Text(title).font(.system(size: 15, weight: .bold))
                        .frame(width: 84, height: 40)
                        .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.teal : Theme.navy.opacity(0.5), lineWidth: on ? 1.5 : 1))
                        .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(b4Index == nil).opacity(b4Index == nil ? 0.5 : 1)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(b4Index == nil ? "ยังไม่มีหัวข้อ B4 ในงานนี้" : "เขียนลงหัวข้อ B4")
            }
        }
    }

    // MARK: inverters

    var inverterList: some View {
        let s = station, n = s.sizes.count, full = n >= InverterStation.maxInverters
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let count = Text("\(n) / \(InverterStation.maxInverters) เครื่อง").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                if narrow {
                    VStack(alignment: .leading, spacing: 0) {
                        (Text("อินเวอร์เตอร์ Growatt") + Text(" *").foregroundColor(Theme.danger)).font(.system(size: 17, weight: .bold))
                        count
                    }
                } else {
                    (Text("อินเวอร์เตอร์ Growatt") + Text(" *").foregroundColor(Theme.danger)).font(.system(size: 17, weight: .bold))
                    count
                }
                Spacer()
                Button { update { $0.sizes.append($0.sizes.last ?? 60); $0.sizesAssumed = false } } label: {
                    Text(full ? "ครบแล้ว" : "+ เพิ่มเครื่อง").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(full ? Theme.borderControl : Theme.primary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(full ? Theme.disabledFill : Theme.primary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain).disabled(full)
            }
            if s.sizesAssumed && values.number(InverterStation.Key.count) != nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.pending)
                    Text("ขนาดยังเป็นค่าสมมติจากจำนวนเครื่องเดิม · เลือก kW ให้ตรงหน้างาน").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.pending)
                    Spacer(minLength: 4)
                    Button("ยืนยัน") { update { $0.sizesAssumed = false } }.font(.system(size: 13, weight: .bold)).frame(minHeight: 44)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: narrow ? 1 : 2), spacing: 8) {
                ForEach(Array(s.sizes.enumerated()), id: \.offset) { i, kw in inverterRow(i, kw, s) }
            }
        }
    }

    func inverterRow(_ i: Int, _ kw: Int, _ s: InverterStation) -> some View {
        let cb = s.breaker(kw: kw), inv = s.catalog.inverter(kw: kw)
        return HStack(spacing: 8) {
            Text("\(i + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Theme.navy, in: Circle())
            HStack(spacing: 0) {
                boxButton("minus", enabled: s.stepSize(kw, by: -1) != kw) { setSize(i, s.stepSize(kw, by: -1)) }
                    .accessibilityLabel("ลดขนาดเครื่อง \(i + 1)")
                Text("\(kw) kW").font(.system(size: 16, weight: .bold)).monospacedDigit().frame(width: 62)
                boxButton("plus", enabled: s.stepSize(kw, by: 1) != kw) { setSize(i, s.stepSize(kw, by: 1)) }
                    .accessibilityLabel("เพิ่มขนาดเครื่อง \(i + 1)")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(inv.model).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text("CB \(cb.at)AT · \(s.cable(kw: kw).label)").font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Button { update { $0.sizes.remove(at: i); $0.sizesAssumed = false } } label: {
                A2Icon(name: "ui-close", fallback: "xmark", size: 14).foregroundStyle(Color(red: 0.706, green: 0.137, blue: 0.094))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).opacity(s.sizes.count > 1 ? 1 : 0).disabled(s.sizes.count <= 1)
            .accessibilityLabel("ลบเครื่อง \(i + 1)")
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
    }

    func setSize(_ i: Int, _ kw: Int) {
        update { s in
            guard s.sizes.indices.contains(i) else { return }
            s.sizes[i] = kw; s.sizesAssumed = false
        }
    }

    // MARK: summary

    var summaryStrip: some View {
        let s = station, cap = s.capacityCheck(job.values.number("capacity"))
        let row = narrow ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return row {
            summaryCell("กำลังรวม", "\(s.totalKW) kW", sub: cap?.text ?? "A1 ยังไม่มี kWp", good: cap?.ok)
            summaryCell("CB อินเวอร์เตอร์", s.breakerSummary, sub: "Feeder \(s.feeder.at) AT", good: nil)
            summaryCell(s.site == .outdoor ? "ห้องขั้นต่ำ" : "ผนังยาวขั้นต่ำ",
                        s.site == .outdoor ? "\(String(format: "%.1f", s.minLength)) × \(fmt(InverterStation.roomWidth)) ม." : "\(String(format: "%.1f", s.minLength)) ม.",
                        sub: s.fits ? "ทางเดิน \(String(format: "%.2f", s.walkway)) ม. \(s.walkwayOK ? "✓" : "✗")" : "ต้องการยาวอีก \(String(format: "%.1f", s.shortfall)) ม. ✗",
                        good: s.fits && s.walkwayOK)
        }
    }

    func summaryCell(_ title: String, _ value: String, sub: String, good: Bool?) -> some View {
        let tint: Color = good == nil ? Theme.navy : good! ? Theme.success : Theme.danger
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(good == false ? Color(red: 0.706, green: 0.137, blue: 0.094) : Theme.navy)
            Text(sub).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(good == nil ? Theme.navy.opacity(0.04) : tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
