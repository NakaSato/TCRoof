#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Colours of the paper form (green bands of the NO.224 workbook).
enum Paper {
    static let band = Color(red: 0.886, green: 0.937, blue: 0.855)
    static let tick = Color(red: 0.439, green: 0.678, blue: 0.278)
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.14)
    static let value = Color(red: 0.12, green: 0.31, blue: 0.47)
    static let rule = Color.black.opacity(0.75)
    static let page = Color(uiColor: .secondarySystemBackground)
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

/// Square checkbox with a label, like the boxes printed on the form.
struct CheckChip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(on ? Paper.tick : Color.white)
                    RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.8), lineWidth: 1)
                    if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 22, height: 22)
                Text(label).font(.body.weight(on ? .semibold : .regular)).foregroundStyle(Paper.ink)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(on ? Paper.band : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Paper.tick : Color.secondary.opacity(0.3), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                if let number { Text(number).font(.subheadline.weight(.heavy)).monospacedDigit() }
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            }
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.band)
            Rectangle().fill(Paper.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: 0) { content }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(Rectangle().stroke(Paper.rule, lineWidth: 1))
    }
}

/// Renders a vector sketch (plan, truss, compass) with the same code as the PDF.
struct SketchView: View {
    let sketch: Sketch
    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / CGFloat(sketch.width), size.height / CGFloat(sketch.height))
            let dx = (size.width - CGFloat(sketch.width) * k) / 2
            ctx.withCGContext { cg in
                cg.translateBy(x: dx, y: 0)
                cg.scaleBy(x: k, y: k)
                PDFRenderer.draw(sketch.ops, in: cg, photo: { _ in nil })
            }
        }
        .aspectRatio(CGFloat(sketch.width / max(sketch.height, 1)), contentMode: .fit)
    }
}

/// Circular progress used on job cards and in the sidebar.
struct ProgressRing: View {
    let value: Double
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle().trim(from: 0, to: value).stroke(value >= 1 ? Paper.tick : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))").font(.system(size: size * 0.3, weight: .bold)).monospacedDigit()
        }
        .frame(width: size, height: size)
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
