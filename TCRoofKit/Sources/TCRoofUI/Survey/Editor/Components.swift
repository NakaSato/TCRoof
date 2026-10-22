#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Colours of the paper form (green bands of the NO.224 workbook).
enum Paper {
    static let band = Theme.paperBand
    static let tick = Theme.paperTick
    static let ink = Theme.paperInk
    static let value = Theme.paperValue
    static let rule = Theme.paperRule
    static let page = Theme.paperPage
}

/// Lays children left to right and wraps to new lines.
public struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing; self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

/// A form box with the green title band.
struct PaperBox<Content: View>: View {
    let title: String
    var number: String? = nil
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let number { Text(number).font(.sarabun(15, .heavy, relativeTo: .subheadline)).monospacedDigit() }
                Text(title).font(.sarabun(15, .bold, relativeTo: .subheadline))
                Spacer()
                if let trailing { Text(trailing).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
            }
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.band)
            Rectangle().fill(Paper.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: 0) { content }
        }
        .background(Theme.surface)
        .overlay(Rectangle().stroke(Paper.rule, lineWidth: 1))
    }
}

/// Renders a vector sketch (plan, truss, compass) with the same code as the PDF.
struct SketchView: View {
    let sketch: Sketch
    var body: some View {
        SketchViewDrawing(ops: sketch.ops, width: sketch.width, height: sketch.height).equatable()
            .aspectRatio(CGFloat(sketch.width / max(sketch.height, 1)), contentMode: .fit)
            .background(Theme.paper)
    }
}

/// The drawing itself, drawn again only when its ops or size change, not on every edit of the page around it.
private struct SketchViewDrawing: View, Equatable {
    let ops: [DrawOp]
    let width: Double
    let height: Double
    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / CGFloat(width), size.height / CGFloat(height))
            let dx = (size.width - CGFloat(width) * k) / 2
            ctx.withCGContext { cg in
                cg.translateBy(x: dx, y: 0)
                cg.scaleBy(x: k, y: k)
                PDFRenderer.draw(ops, in: cg, photo: { _ in nil })
            }
        }
    }
}

/// UIActivityViewController for sharing exported files (AirDrop, Files, Mail, LINE…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension View {
    /// Shows a short error alert bound to an optional message.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("เกิดข้อผิดพลาด", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }
}
#endif
