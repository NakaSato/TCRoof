#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// A section's point on the A2 picture (B3's water point, B5's FTS switch): the site picture with A2's drawings and
/// symbols, read-only, and this module's pin on top. A tap or a drag anywhere on the picture moves the pin (creating it
/// the first time); it is written when the finger lifts. The pin is A2's `siteMarks` entry of `kind` (`ModuleMarks`).
struct SitePinStage<Pin: View, Legend: View>: View {
    @Binding var job: Job
    let moduleID: UUID
    let kind: MarkKind
    let type: ModuleType
    var legendAlignment: Alignment = .topLeading
    /// Spoken name of the pin ("จุดต่อแยก", "FTS switch").
    var pinName: String
    /// Inside a scroll view (portrait): a tap places the pin and only the pin itself drags, so the page still scrolls.
    var scrolls = false
    var openSite: () -> Void = {}
    @ViewBuilder var pin: () -> Pin
    @ViewBuilder var legend: () -> Legend
    @Environment(SurveyModel.self) var model
    /// The pin while a finger moves it, in fractions of the picture.
    @State var dragging: ShapePoint?

    var photo: Photo? { job.values.photo("siteMap") }
    var mark: MapMark? { ModuleMarks.mark(job, kind, of: type, module: moduleID) }

    var body: some View {
        GeometryReader { geo in
            if let p = photo, let img = model.image(p, in: job.id) {
                stage(img, geo.size)
            } else {
                empty(noPicture: photo == nil).frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(PhotoSlot.stageColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: legendAlignment) { legend().allowsHitTesting(false).padding(10) }
    }

    func imageRect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    func stage(_ img: UIImage, _ size: CGSize) -> some View {
        let r = imageRect(img, in: size)
        let at = dragging ?? mark.map { ShapePoint($0.x, $0.y) }
        let drag = DragGesture(minimumDistance: scrolls ? 4 : 0, coordinateSpace: .named(Self.space))
            .onChanged { g in dragging = fraction(g.location, in: r) ?? dragging }
            .onEnded { g in
                if let f = fraction(g.location, in: r) ?? dragging { ModuleMarks.place(&job, kind, of: type, module: moduleID, x: f.x, y: f.y) }
                dragging = nil
            }
        return ZStack(alignment: .topLeading) {
            Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            drawing(r).allowsHitTesting(false)
            if scrolls {
                Color.white.opacity(0.001).frame(width: size.width, height: size.height)
                    .onTapGesture(coordinateSpace: .named(Self.space)) { p in
                        if let f = fraction(p, in: r) { ModuleMarks.place(&job, kind, of: type, module: moduleID, x: f.x, y: f.y) }
                    }
            }
            if let at {
                pin().contentShape(Rectangle()).allowsHitTesting(scrolls)
                    .gesture(drag, including: scrolls ? .all : .none)
                    .position(x: r.minX + at.x * r.width, y: r.minY + at.y * r.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: Self.space)
        .contentShape(Rectangle())
        .gesture(drag, including: scrolls ? .none : .all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mark == nil ? "ภาพ A2 ยังไม่มีตำแหน่ง " + pinName : "ภาพ A2 ตำแหน่ง " + pinName)
        .accessibilityHint("แตะบนภาพเพื่อย้ายจุด")
    }

    static var space: String { "sitePinStage" }

    func fraction(_ p: CGPoint, in r: CGRect) -> ShapePoint? {
        guard r.width > 0, r.height > 0, r.insetBy(dx: -4, dy: -4).contains(p) else { return nil }
        return ShapePoint(min(max(Double((p.x - r.minX) / r.width), 0), 1), min(max(Double((p.y - r.minY) / r.height), 0), 1))
    }

    /// Building models, shapes and symbols as A2 shows them; this module's own mark is the pin instead.
    func drawing(_ r: CGRect) -> some View { siteDrawing(job, in: r, without: mark?.id) }

    /// No A2 picture yet (or not downloaded to this device): say so and offer A2.
    func empty(noPicture: Bool) -> some View {
        VStack(spacing: 14) {
            if noPicture {
                Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(Theme.inkMuted)
                Text("ยังไม่มีภาพสถานที่ติดตั้งในหน้า A2").font(.sarabun(17, .semibold, relativeTo: .headline))
                Button(action: openSite) {
                    Text("เปิด A2 เพื่อเลือกภาพ").font(.sarabunFixed(15, .bold)).padding(.horizontal, 16).frame(minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
            } else {
                PhotoSlot.notDownloaded
            }
        }
    }
}

/// A2's building models, shapes and symbols over the site picture drawn in `r`, read-only; `own` leaves out one mark.
func siteDrawing(_ job: Job, in r: CGRect, without own: UUID? = nil) -> some View {
    let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
    let shapes = job.values.shapes(SiteShapes.key).filter { $0.kind != .boundary && $0.kind != .pvPoint }
    let marks = job.values.marks(ModuleMarks.key).filter { $0.id != own }
    let meters = job.values.number(SiteShapes.scaleKey).flatMap { $0 > 0 ? $0 : nil }
    let locked = SiteModels.allLocked(job.values)
    let models = meters.map { m in
        SiteModels.placed(job).flatMap { SiteModels.ops($0.model, $0.source, in: box, metersAcross: m, detailed: true, locked: locked || $0.model.locked) }
    } ?? []
    let ops = models + SiteShapes.ops(shapes, in: box, metersAcross: meters) + SiteMarks.ops(marks, in: box)
    return Canvas { ctx, _ in ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) } }
}

/// A round pin in a 44 pt target with its name in a pill below (docs/ui/survey-b3 / survey-b5 icons).
struct SitePin: View {
    var ring: Color
    var halo: Color
    var haloStroke: Color? = nil
    let label: String

    var body: some View {
        ZStack {
            Circle().fill(halo.opacity(0.18)).frame(width: 44, height: 44)
            if let haloStroke { Circle().stroke(haloStroke, lineWidth: 3).frame(width: 41, height: 41) }
            Circle().fill(Theme.onMedia).frame(width: 26, height: 26).overlay(Circle().stroke(ring, lineWidth: 4))
            Circle().fill(ring).frame(width: 10, height: 10)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .bottom) {
            Text(label).font(.sarabunFixed(12.5, .bold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(ring, in: Capsule())
                .overlay(Capsule().stroke(Theme.onMedia, lineWidth: 1.5))
                .offset(y: 22)
        }
    }
}
#endif
