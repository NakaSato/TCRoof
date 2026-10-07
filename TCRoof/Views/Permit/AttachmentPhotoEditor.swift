import SwiftUI
import UIKit
import TCRoofUI
import TCRoofCore

extension UIImage {
    /// The image turned clockwise by `quarterTurns` × 90°.
    func turned(_ quarterTurns: Int) -> UIImage {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 else { return self }
        let out = q % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: out, format: format).image { r in
            let ctx = r.cgContext
            ctx.translateBy(x: out.width / 2, y: out.height / 2)
            ctx.rotate(by: CGFloat(q) * .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

/// One attachment photo: caption, whole or cropped, turn, and red boxes drawn with a finger over what PEA checks.
struct AttachmentPhotoEditor: View {
    let attachment: Int
    let index: Int
    let data: Data
    @Binding var info: AttachmentPhotoInfo
    let defaultFit: AttachmentPhotoInfo.Fit
    @Environment(\.dismiss) private var dismiss

    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?

    private var image: UIImage? { UIImage(data: data)?.turned(info.quarterTurns) }
    private var fit: AttachmentPhotoInfo.Fit { info.fit ?? defaultFit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    canvas
                    Text("ลากบนรูปเพื่อตีกรอบแดงจุดที่ต้องการให้ กฟภ. เห็น เช่น S/N ค่าตั้ง หรือพิกัดอุปกรณ์ · แตะกรอบเพื่อลบ")
                        .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    HStack(spacing: Space.s) {
                        TCButton("หมุน 90°", systemImage: "rotate.right", kind: .secondary, size: .card) {
                            info.quarterTurns = (info.quarterTurns + 1) % 4
                            info.highlights = []   // marks belong to the old orientation
                        }
                        TCButton("ล้างกรอบแดง", systemImage: "eraser", kind: .secondary, size: .card) { info.highlights = [] }
                            .disabled(info.highlights.isEmpty)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TCFieldLabel("การวางในกรอบ")
                        TCSegmented(AttachmentPhotoInfo.Fit.allCases.map(\.title),
                                    selection: Binding(get: { fit.title },
                                                       set: { t in info.fit = AttachmentPhotoInfo.Fit.allCases.first { $0.title == t } }))
                        Text(fit == .fill ? "ครอปให้เต็มกรอบ เหมาะกับภาพหน้างานและอุปกรณ์" : "แสดงทั้งภาพบนพื้นเทาอ่อน เหมาะกับเอกสาร")
                            .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    }
                    captionField
                }
                .padding(Space.l)
            }
            .background(Theme.background)
            .navigationTitle("รูปที่ \(attachment).\(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } }
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel("คำบรรยายใต้รูป", optional: true)
            TCTextField("เช่น ป้ายอินเวอร์เตอร์ (Nameplate)", text: $info.caption)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(SelfCertification.captionSuggestions[attachment - 1], id: \.self) { s in
                        TCChoiceChip(s, selected: info.caption == s) { info.caption = s }
                    }
                }
            }
            Text("พิมพ์เป็น “รูปที่ \(attachment).\(index + 1) \(info.caption)”")
                .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }

    /// The turned photo with its red boxes; a drag draws a new box.
    @ViewBuilder private var canvas: some View {
        if let image {
            let aspect = image.size.width / max(image.size.height, 1)
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                    ForEach(info.highlights.indices, id: \.self) { i in
                        let h = info.highlights[i]
                        Rectangle().strokeBorder(Theme.danger, lineWidth: 2.5)
                            .contentShape(Rectangle())
                            .frame(width: h[2] * size.width, height: h[3] * size.height)
                            .offset(x: h[0] * size.width, y: h[1] * size.height)
                            .onTapGesture { info.highlights.remove(at: i) }
                            .accessibilityLabel("กรอบแดงที่ \(i + 1) แตะเพื่อลบ")
                    }
                    if let dragRect {
                        Rectangle().strokeBorder(Theme.danger, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(width: dragRect.width, height: dragRect.height)
                            .offset(x: dragRect.minX, y: dragRect.minY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { g in
                            let a = g.startLocation, b = g.location
                            dragRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                                .intersection(CGRect(origin: .zero, size: size))
                        }
                        .onEnded { _ in
                            if let r = dragRect, r.width > 8, r.height > 8, size.width > 0, size.height > 0 {
                                info.highlights.append([r.minX / size.width, r.minY / size.height, r.width / size.width, r.height / size.height])
                            }
                            dragRect = nil
                        }
                )
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderSubtle))
            .accessibilityLabel("รูปที่ \(attachment).\(index + 1) ลากเพื่อตีกรอบแดง")
        }
    }
}
