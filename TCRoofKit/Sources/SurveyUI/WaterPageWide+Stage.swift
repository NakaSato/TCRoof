#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// B3's A2 picture: the site picture with A2's drawings and symbols, read-only, and this module's water pin on top.
/// A tap or a drag anywhere on the picture moves the pin (creating it the first time); it is written when the finger lifts.
struct WaterPinStage: View {
    @Binding var job: Job
    let moduleID: UUID
    let mode: WaterPoint.Mode
    var openSite: () -> Void = {}
    @Environment(SurveyModel.self) var model
    /// The pin while a finger moves it, in fractions of the picture.
    @State var dragging: ShapePoint?

    static let blue = Color(red: 0.122, green: 0.435, blue: 0.710)

    var photo: Photo? { job.values.photo("siteMap") }
    var mark: MapMark? { WaterPoint.mark(job, module: moduleID) }

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
        .overlay(alignment: .topLeading) { legend.padding(10) }
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
        return ZStack(alignment: .topLeading) {
            Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            drawing(r).allowsHitTesting(false)
            if let at { pin.position(x: r.minX + at.x * r.width, y: r.minY + at.y * r.height) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in dragging = fraction(g.location, in: r) ?? dragging }
            .onEnded { g in
                if let f = fraction(g.location, in: r) ?? dragging { WaterPoint.place(&job, module: moduleID, x: f.x, y: f.y) }
                dragging = nil
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mark == nil ? "ภาพ A2 ยังไม่มีจุดจ่ายน้ำ" : "ภาพ A2 จุดจ่ายน้ำ " + mode.pinLabel)
        .accessibilityHint("แตะบนภาพเพื่อย้ายจุด")
    }

    func fraction(_ p: CGPoint, in r: CGRect) -> ShapePoint? {
        guard r.width > 0, r.height > 0, r.insetBy(dx: -4, dy: -4).contains(p) else { return nil }
        return ShapePoint(min(max(Double((p.x - r.minX) / r.width), 0), 1), min(max(Double((p.y - r.minY) / r.height), 0), 1))
    }

    /// Building models, shapes and symbols as A2 shows them; this module's own water mark is the pin instead.
    func drawing(_ r: CGRect) -> some View {
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        let shapes = job.values.shapes(SiteShapes.key).filter { $0.kind != .boundary && $0.kind != .pvPoint }
        let own = mark?.id
        let marks = job.values.marks(WaterPoint.marksKey).filter { $0.id != own }
        let meters = job.values.number(SiteShapes.scaleKey).flatMap { $0 > 0 ? $0 : nil }
        let locked = SiteModels.allLocked(job.values)
        let models = meters.map { m in
            SiteModels.placed(job).flatMap { SiteModels.ops($0.model, $0.source, in: box, metersAcross: m, detailed: true, locked: locked || $0.model.locked) }
        } ?? []
        let ops = models + SiteShapes.ops(shapes, in: box, metersAcross: meters) + SiteMarks.ops(marks, in: box)
        return Canvas { ctx, _ in ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) } }
    }

    /// 30 pt white circle, 4 pt blue ring, 10 pt blue dot, in a 44 pt target; the mode's name in a blue pill below.
    var pin: some View {
        ZStack {
            Circle().fill(Self.blue.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(Color.white).frame(width: 30, height: 30).overlay(Circle().stroke(Self.blue, lineWidth: 4))
            Circle().fill(Self.blue).frame(width: 10, height: 10)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .bottom) {
            Text(mode.pinLabel).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Self.blue, in: Capsule())
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                .offset(y: 22)
        }
        .allowsHitTesting(false)
    }

    var legend: some View {
        HStack(spacing: 6) {
            Circle().stroke(Self.blue, lineWidth: 3).frame(width: 11, height: 11)
            Text(mode.legend).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    /// No A2 picture yet (or not downloaded to this device): say so and offer A2.
    func empty(noPicture: Bool) -> some View {
        VStack(spacing: 14) {
            if noPicture {
                Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(Home.muted)
                Text("ยังไม่มีภาพสถานที่ติดตั้งในหน้า A2").font(.headline)
                Button(action: openSite) {
                    Text("เปิด A2 เพื่อเลือกภาพ").font(.system(size: 15, weight: .bold)).padding(.horizontal, 16).frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                PhotoSlot.notDownloaded
            }
        }
    }
}
#endif
