#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// B5 (docs/ui/survey-b5): the Emergency button's photo, place, what it cuts and its height on the
/// left; its point on the A2 picture and the FTS part of the single line diagram on the right. The height is A4's
/// `emgMountCm`; the pin is A2's `.emergency` mark for this module. The FTS cabinet is no longer located, so
/// `photoFTS` isn't shown here (owner's decision). iPad portrait and iPhone stack the three cards in one scrolling column.
struct FtsPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    var openSite: () -> Void = {}
    var openDiagram: () -> Void = {}
    /// Portrait and iPhone: the button card, the A2 picture and the SLD crop one under another, the page scrolling.
    var stacked = false
    @Environment(SurveyModel.self) var model
    @State var editingPlace = false
    @State var placeText = ""

    var leftWidth: CGFloat { min(520, max(400, width * 0.4)) }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func set(_ id: String, _ v: FieldValue?) { if let i = index { job.modules[i].values[id] = v } }

    static let red = Color(red: 0.851, green: 0.271, blue: 0.231)
    static let orange = Color(red: 0.941, green: 0.549, blue: 0.0)
    static let warnRed = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let slotFill = Color(red: 0.969, green: 0.976, blue: 0.988)

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: width < 600 ? "ปุ่ม Emergency" : "ตำแหน่งติดตั้งปุ่ม FTS switch (Emergency)")
            if stacked { stackedColumn } else { sideBySide }
        }
        .foregroundStyle(Theme.navy)
        .alert("ตำแหน่งปุ่ม Emergency", isPresented: $editingPlace) {
            TextField("เช่น ผนังข้างประตู Site Office", text: $placeText)
            Button("ตกลง") {
                let t = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
                set(EmergencyButton.placeKey, t.isEmpty ? nil : .text(t))
            }
            Button("ยกเลิก", role: .cancel) {}
        }
    }

    var sideBySide: some View {
        HStack(alignment: .top, spacing: 20) {
            buttonCard.frame(width: leftWidth).frame(maxHeight: .infinity)
            VStack(spacing: 14) {
                siteCard.frame(maxHeight: .infinity)
                sldCard.frame(height: 248)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    var stackedColumn: some View {
        ScrollView {
            VStack(spacing: 14) {
                buttonCard
                siteCard.frame(height: stackedPictureHeight + 60)
                sldCard.frame(height: 248)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// The A2 picture at the column's width and its own proportions, within 240–560 pt (as B3).
    var stackedPictureHeight: CGFloat {
        let p = job.values.photo("siteMap")
        let ratio = p.map { $0.width > 0 ? CGFloat($0.height) / CGFloat($0.width) : 0.625 } ?? 0.625
        return min(560, max(240, (width - 32) * ratio))
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.navy.opacity(0.16)))
            .shadow(color: Theme.navy.opacity(0.06), radius: 3, y: 2)
    }

    func title(_ t: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(t).font(.system(size: 17, weight: .bold)).lineLimit(1)
            Text(sub).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: 1 the button

    var buttonCard: some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Text("1").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.primary)
                    .frame(width: 28, height: 28).background(WaterPageWide.chipFill, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("ภาพพื้นที่ติดตั้งปุ่ม Emergency") + Text(" *").foregroundColor(Theme.danger)).font(.system(size: 17, weight: .bold))
                    Text("จุดที่เข้าถึงได้ทันที").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                }
            }
            photo.frame(height: stacked ? (width < 600 ? 260 : 380) : nil).frame(maxHeight: stacked ? nil : .infinity)
            VStack(spacing: 0) {
                infoRow("ตำแหน่ง") { placeButton }
                infoRow("สั่งตัด") { Text(EmergencyButton.cuts(job)).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7) }
                infoRow("ความสูงปุ่ม") { heightStepper }
            }
        }
    }

    var photo: some View {
        let p = values.photo(EmergencyButton.photoKey)
        return PhotoSlot(photo: p, jobID: job.id, hint: "ถ่ายภาพจุดติดตั้งปุ่ม Emergency ให้เห็นความสูง", required: true, title: "ปุ่ม Emergency",
                         onPick: { img in if let ph = model.addPhoto(img, to: job.id) { set(EmergencyButton.photoKey, .photo(ph)) } },
                         onClear: { set(EmergencyButton.photoKey, nil) })
            .overlay(alignment: .bottomLeading) {
                if p != nil {
                    Text("วงจุดติดตั้งปุ่ม · ระบุความสูง").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                        .padding(8).allowsHitTesting(false)
                }
            }
    }

    func infoRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 44)
    }

    var placeButton: some View {
        let place = values.text(EmergencyButton.placeKey)
        return Button { placeText = place; editingPlace = true } label: {
            HStack(spacing: 6) {
                Text(place.isEmpty ? "แตะเพื่อระบุ" : place).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(place.isEmpty ? Theme.primary : Theme.navy)
                Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ตำแหน่ง " + (place.isEmpty ? "ยังไม่ระบุ" : place))
        .accessibilityHint("แตะเพื่อแก้ไข")
    }

    var heightStepper: some View {
        let cm = EmergencyButton.heightCm(job), ok = EmergencyButton.isRecommended(cm)
        return HStack(spacing: 12) {
            stepButton("minus", enabled: cm > EmergencyButton.rangeCm.lowerBound) { EmergencyButton.step(&job, by: -1) }
            Text(EmergencyButton.meters(cm) + (ok ? " ✓" : " ⚠")).font(.system(size: 16, weight: .bold)).monospacedDigit()
                .foregroundStyle(ok ? Theme.navy : Self.warnRed).frame(minWidth: 88)
            stepButton("plus", enabled: cm < EmergencyButton.rangeCm.upperBound) { EmergencyButton.step(&job, by: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ความสูงปุ่ม " + EmergencyButton.meters(cm) + (ok ? "" : " นอกช่วงแนะนำ 1.10 ถึง 1.50 เมตร"))
    }

    func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Theme.navy.opacity(0.3) : Theme.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "เพิ่มความสูง 5 ซม." : "ลดความสูง 5 ซม.")
    }

    // MARK: A2 picture

    var siteCard: some View {
        card {
            title("ตำแหน่งบนภาพ A2", sub: "แตะบนภาพเพื่อวางตำแหน่งปุ่ม FTS switch")
            SitePinStage(job: $job, moduleID: moduleID, kind: .emergency, type: .fts, legendAlignment: .topTrailing,
                         pinName: "ปุ่ม FTS switch", scrolls: stacked, openSite: openSite) {
                SitePin(ring: Self.red, halo: Self.orange, haloStroke: Self.orange, label: "FTS switch")
            } legend: {
                HStack(spacing: 6) {
                    Circle().fill(Self.red).frame(width: 11, height: 11)
                    Text("ปุ่ม FTS switch (Emergency)").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: SLD crop

    var sldCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                title("ใน SLD", sub: "FTS ตัดวงจร DC · ปุ่ม Emergency สั่งตัด")
                Spacer(minLength: 8)
                Button(action: openDiagram) {
                    Text("ดู SLD ทั้งหมด →").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -10)
            let drawing = SingleLineLayout.draw(SingleLine.build(job))
            Group {
                if drawing.ftsBox != nil {
                    SLDCrop(drawing: drawing)
                } else {
                    Text("ยังไม่มีแผนภาพ · กรอกหม้อแปลงและ MDB ในหน้า A3 ก่อน").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center).padding()
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.1)))
                .accessibilityLabel("แผนภาพเส้นเดียวส่วน FTS และปุ่ม Emergency")
        }
    }
}

/// A part of the single line diagram, fitted and clipped; read-only. The FTS / Emergency part (`ftsBox`) unless `box`
/// names another (B4's `zeroExportBox`).
struct SLDCrop: View {
    let drawing: SingleLineDrawing
    var box: Box? = nil
    /// Widens (or deepens) the box to the view's shape, within the drawing, so the lines run to the edges.
    var fill = false

    var body: some View {
        Canvas { ctx, size in
            guard var b = box ?? drawing.ftsBox, b.w > 0, b.h > 0, size.width > 0, size.height > 0 else { return }
            if fill { b = Self.widened(b, to: Double(size.width / size.height), within: drawing) }
            let pad = fill ? 0.0 : 8.0
            let k = min((size.width - 2 * pad) / b.w, (size.height - 2 * pad) / b.h)
            let ox = (size.width - b.w * k) / 2, oy = (size.height - b.h * k) / 2
            ctx.clip(to: Path(CGRect(x: ox, y: oy, width: b.w * k, height: b.h * k)))
            ctx.translateBy(x: ox - b.x * k, y: oy - b.y * k)
            ctx.scaleBy(x: k, y: k)
            ctx.withCGContext { cg in PDFRenderer.draw(drawing.sketch.ops, in: cg, photo: { _ in nil }) }
        }
        .background(Theme.paper)
        .clipped()
    }

    static func widened(_ b: Box, to aspect: Double, within d: SingleLineDrawing) -> Box {
        if b.w / b.h < aspect {
            let w = min(b.h * aspect, d.width)
            return Box(min(max(b.x + b.w / 2 - w / 2, 0), d.width - w), b.y, w, b.h)
        }
        let h = min(b.w / aspect, d.height)
        return Box(b.x, min(max(b.y + b.h / 2 - h / 2, 0), d.height - h), b.w, h)
    }
}
#endif
