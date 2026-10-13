#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// A2's picture toolbar, scale bar, tool hint and caption row.
extension SitePageWide {
    // MARK: toolbar (v2 §2)

    func toolbar(full: Bool, narrow: Bool = false) -> some View {
        HStack(alignment: .top, spacing: narrow ? 4 : 8) {
            toolGroup {
                toolItem("เลือก", icon: "tool-select", symbol: "cursorarrow", nil, narrow: narrow)
                toolItem("พื้นที่แผง", icon: "tool-panelArea", symbol: "pentagon", .shape(.panelArea), narrow: narrow)
                toolItem("แนวสาย", icon: "tool-cableRoute", symbol: "point.topleft.down.to.point.bottomright.curvepath", .shape(.cableRoute), narrow: narrow)
                toolItem("วัดระยะ", icon: "tool-measure", symbol: "ruler", .shape(.measure), narrow: narrow)
            }
            toolGroup {
                iconItem("ย้อนกลับ", icon: "action-undo", symbol: "arrow.uturn.backward", enabled: canUndo) { undo() }
                iconItem("ทำซ้ำ", icon: "action-redo", symbol: "arrow.uturn.forward", enabled: history.canRedo && draft.isEmpty) { redo() }
            }
            toolGroup {
                Button {
                    SiteModels.setAllLocked(!allLocked, in: &job.values)
                    showLayers = false
                } label: {
                    itemLabel(allLocked ? "ล็อกอยู่" : "ล็อก", icon: allLocked ? "action-lock" : "action-unlock", symbol: allLocked ? "lock" : "lock.open",
                              fill: allLocked ? Theme.warning : .clear, on: allLocked, narrow: narrow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล็อกโมเดลอาคาร").accessibilityAddTraits(allLocked ? .isSelected : [])
            }
            Spacer(minLength: 0)
            toolGroup {
                Button { showLayers.toggle() } label: {
                    itemLabel("ชั้น \(layers.count)/\(Layer.allCases.count)", icon: "action-layers", symbol: "square.3.layers.3d",
                              fill: showLayers ? Theme.primarySoft : .clear, on: false, narrow: narrow)
                }
                .buttonStyle(.plain).accessibilityLabel("ชั้นที่แสดง \(layers.count) จาก \(Layer.allCases.count)")
                iconItem(full ? "ออกจากเต็มจอ" : "ดูภาพเต็มจอ", icon: full ? "action-fullscreenExit" : "action-fullscreen",
                         symbol: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", enabled: true) {
                    showLayers = false
                    fullScreen = !full
                }
            }
        }
    }

    /// A floating white group of toolbar buttons.
    func toolGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) { content() }
            .padding(2)
            .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: Theme.navySolid.opacity(0.28), radius: 2.5, y: 1)
    }

    /// `narrow` drops the title (VoiceOver keeps it) so the toolbar fits an iPhone.
    func itemLabel(_ title: String, icon: String, symbol: String, fill: Color, on: Bool, narrow: Bool = false) -> some View {
        HStack(spacing: 5) {
            A2Icon(name: icon, fallback: symbol, size: 16)
            if !narrow { Text(title).font(.sarabunFixed(11.5, .semibold)).lineLimit(1).fixedSize() }
        }
        .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
        .padding(.horizontal, narrow ? 0 : 10).frame(minWidth: narrow ? 36 : nil).frame(height: 36)
        .background(fill, in: RoundedRectangle(cornerRadius: 7))
        // 36 pt button + the group's padding: a 44 pt target
        .contentShape(Rectangle().inset(by: -4))
        .accessibilityLabel(title)
    }

    /// One tool of the segmented group; nil is Select.
    func toolItem(_ title: String, icon: String, symbol: String, _ t: Tool?, narrow: Bool = false) -> some View {
        let on = tool == t
        return Button { arm(t) } label: { itemLabel(title, icon: icon, symbol: symbol, fill: on ? Theme.navy : .clear, on: on, narrow: narrow) }
            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    func iconItem(_ label: String, icon: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            A2Icon(name: icon, fallback: symbol, size: 16).foregroundStyle(Theme.navy)
                .frame(width: 36, height: 36).contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// Where north is on the picture; each tap turns it a quarter and saves to `north`.
    var northButton: some View {
        let n = job.values.choice("north")
        let i = n.flatMap { Self.norths.firstIndex(of: $0) }
        return Button {
            let next = Self.norths[((i ?? -1) + 1) % 4]
            job.values["north"] = .choice(next, other: "")
        } label: {
            A2Icon(name: "ui-north", fallback: "location.north.circle.fill", size: 38)
                .foregroundStyle(i == nil ? Theme.inkMuted : Theme.danger)
                .rotationEffect(.degrees(Double(i ?? 0) * 90))
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(i == nil ? Theme.pending : .clear, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ทิศเหนือของภาพ")
        .accessibilityValue(n ?? "ยังไม่ระบุ")
        .accessibilityHint("แตะเพื่อหมุนทีละ 90 องศา")
    }

    /// v2 §3: the layers dropdown under "ชั้น n/5".
    var layersMenu: some View {
        VStack(spacing: 2) {
            ForEach(Layer.allCases, id: \.self) { l in
                let on = layers.contains(l)
                Button { if on { layers.remove(l) } else { layers.insert(l) } } label: {
                    HStack(spacing: 10) {
                        Text(on ? "✓" : "○").font(.sarabunFixed(13, .bold)).frame(width: 16)
                        Text(l.title).font(.sarabunFixed(13, .semibold)).strikethrough(!on)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                    .padding(.horizontal, 10).frame(height: 36)
                    .background(on ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle().inset(by: -1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ชั้น " + l.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 180)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.navySolid.opacity(0.3), radius: 10, y: 6)
    }

    @ViewBuilder func scaleBar(_ size: CGSize, zoom z: CGFloat) -> some View {
        if let m = metersAcross, let r = currentRect(size), r.width > 0 {
            let seen = m / Double(z)
            let length = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1000].last { $0 <= seen * 0.22 } ?? 1
            let w = CGFloat(length / m) * r.width * z
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.navy).frame(width: w / 2, height: 5)
                    Rectangle().fill(Theme.onMedia).frame(width: w / 2, height: 5).overlay(Rectangle().stroke(Theme.navy, lineWidth: 1))
                }
                HStack(spacing: 0) {
                    Text("0").frame(width: w / 2, alignment: .leading)
                    Text(fmt(length / 2)).frame(width: w / 2, alignment: .leading)
                    Text(fmt(length) + " ม.")
                }
                .font(.sarabunFixed(11, .semibold)).monospacedDigit().fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        } else if photo != nil {
            Button { arm(.shape(.measure)) } label: {
                Label("ตั้งมาตราส่วน", systemImage: "ruler").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.pending)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("วัดระยะที่รู้ความยาวจริงบนภาพ แล้วใส่ระยะจริง")
        }
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    // MARK: hint

    /// Bold tool name and what to do (the design's `TL` hints for the toolbar tools).
    var toolHint: (name: String, hint: String) {
        switch tool {
        case nil: return ("เลือก", "แตะสัญลักษณ์หรือโมเดลอาคารเพื่อแก้ไข ลากเพื่อย้าย")
        case .shape(.panelArea)?: return ("พื้นที่แผง", "แตะมุมพื้นที่ทีละจุด แตะจุดแรกอีกครั้งเพื่อปิดรูป")
        case .shape(.cableRoute)?: return ("แนวสาย", "แตะจุดเริ่มจากแผง ลากผ่านแนวที่เดินสาย จบที่ห้องอินเวอร์เตอร์")
        case .shape(.measure)?: return ("วัดระยะ", "แตะจุดเริ่มและจุดสิ้นสุด ระยะอ้างอิงจากสเกลภาพ")
        case .shape(.shade)?: return ("ร่มเงา", "แตะรอบสิ่งที่บังแดด · แตะจุดแรกเพื่อปิด")
        case .shape(.craneEntry)?: return ("ทางเข้าเครน", "ลากจากถนนเข้าหาจุดติดตั้ง")
        case .mark(let k)?: return (k.paletteTitle, "แตะบนภาพเพื่อวาง")
        case .shape(.boundary)?, .shape(.pvPoint)?: return ("", "")
        }
    }

    /// The hint banner (no hit-testing) and, while drawing a line or placing a palette item, the v1 count / done / cancel control.
    var hintStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            drawControl
            (Text(toolHint.name).bold() + Text("  " + toolHint.hint))
                .font(.sarabunFixed(13)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.navySolid.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder var drawControl: some View {
        let polyline: ShapeKind? = { if case .shape(let k)? = tool, k.fixedPoints == nil { return k }; return nil }()
        let palette: Bool = { switch tool { case .mark?, .shape(.craneEntry)?, .shape(.shade)?: return true; default: return false } }()
        if palette || (polyline != nil && !draft.isEmpty) {
            HStack(spacing: 10) {
                if let k = polyline {
                    Text("\(draft.count) จุด").font(.sarabunFixed(14, .semibold)).foregroundStyle(.white).monospacedDigit()
                    Button("เสร็จ") { finishDraft() }.font(.sarabunFixed(14, .bold))
                        .disabled(draft.count < k.minPoints)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Theme.surface.opacity(draft.count < k.minPoints ? 0.4 : 1), in: Capsule())
                        .foregroundStyle(Theme.navy)
                        .contentShape(Capsule().inset(by: -4))
                }
                Button("ยกเลิก") { arm(nil) }.font(.sarabunFixed(14, .bold))
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .overlay(Capsule().stroke(.white.opacity(0.7)))
                    .foregroundStyle(.white)
                    .contentShape(Capsule().inset(by: -4))
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
            .background(Theme.navy.opacity(0.92), in: Capsule())
        }
    }

    // MARK: caption

    /// On an iPhone the C1 chip moves to its own line under the title.
    var captionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                captionTitle.fixedSize()
                Spacer(minLength: 6)
                panelChip
                pictureMenu
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    captionTitle
                    Spacer(minLength: 6)
                    pictureMenu
                }
                panelChip
            }
        }
    }

    var captionTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ภาพสถานที่ติดตั้ง").font(.sarabunFixed(14, .bold)).underline()
            Text(photoLine).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        .lineLimit(1)
    }

    var pictureMenu: some View {
        Menu {
            Button { fetchGoogle() } label: { Label("แผนที่ดาวเทียมตามพิกัด A1", systemImage: "map") }
            Button { pickDrone = true } label: { Label("อัปโหลดภาพจากโดรน", systemImage: "photo") }
            if photo != nil {
                Button(action: exportDXF) { Label("ส่งออก DXF", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { job.values["siteMap"] = nil; job.values[SiteShapes.sourceKey] = nil; job.values[SiteShapes.scaleKey] = nil } label: {
                    Label("ลบภาพ", systemImage: "trash")
                }
            }
        } label: {
            Text(photo == nil ? "เลือกภาพ" : "เปลี่ยนภาพ").font(.sarabunFixed(15, .semibold))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.5)))
        }
    }

    /// The site plan over the picture's frame as a CAD file (docs/specs/cad-export-dxf), at real scale once it is known.
    func exportDXF() {
        do { dxfFile = try model.exportSiteDXF(job) } catch { failure = error.localizedDescription }
    }

    /// "ภาพโดรน 29/9/2569 10:12"
    var photoLine: String {
        guard let p = photo else { return "ยังไม่มีภาพ" }
        let kind = source == "google" ? "ภาพดาวเทียม" : source == "drone" ? "ภาพโดรน" : "ภาพ"
        return kind + " " + ISODate.thai(ISODate.string(p.takenAt)) + " " + p.takenAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// Panels from the C / D sections (before − cut) × W/panel of the module chosen in settings = kWp.
    var panelChip: some View {
        let n = job.modules.filter { $0.type == .roof || $0.type == .tank }.reduce(0.0) { sum, m in
            sum + max(0, (m.values.number("panelsBefore") ?? 0) - (m.values.number("panelsCut") ?? 0))
        }
        return HStack(spacing: 4) {
            Text("C1").foregroundStyle(Theme.inkMuted)
            Text(n > 0 ? "\(Int(n)) แผง" : "— แผง").bold()
            if let w = PVModuleCatalog.variant(model.settings.pvModule)?.variant.pmaxW {
                Text("× \(Int(w)) W =").foregroundStyle(Theme.inkMuted)
                Text(n > 0 ? String(format: "%.1f kWp", n * w / 1000) : "— kWp").bold()
            } else {
                Text("× [W/แผง] = [kWp]").foregroundStyle(Theme.inkMuted)
            }
        }
        .font(.sarabunFixed(13)).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(minHeight: 36)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("หน้า C จำนวนแผง \(Int(n))")
    }
}
#endif
