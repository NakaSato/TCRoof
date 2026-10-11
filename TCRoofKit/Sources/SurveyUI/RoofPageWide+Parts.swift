#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// The span popover: ± 0.5 m, quick values, split, delete, next, equalise and "all 4.00".
struct SpanEditor: View {
    let spans: [Double]
    let ref: RoofPageWide.SpanRef
    let set: ([Double], Int) -> Void
    let select: (RoofPageWide.SpanRef?) -> Void
    @State var typed = ""
    @FocusState var typing: Bool

    var cur: Double { spans[safe: ref.index] ?? 0 }
    func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    func with(_ v: Double) { var a = spans; if a.indices.contains(ref.index) { a[ref.index] = v; set(a, ref.index) } }
    var total: Double { spans.reduce(0, +) }
    var equal: Bool { spans.allSatisfy { abs($0 - total / Double(spans.count)) <= 0.005 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ระยะช่วงกริด " + Roof.spanName(ref.axis, ref.index)).font(.system(size: 17, weight: .bold))
                Spacer(minLength: 8)
                Text("ช่วงที่ \(ref.index + 1) จาก \(spans.count)").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                Button { select(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 44, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            valueRow
            HStack(spacing: 8) {
                ForEach([1.5, 3, 4, 4.5, 6], id: \.self) { v in
                    let on = abs(v - cur) < 0.001
                    Button { with(v) } label: {
                        Text(fmt(v)).font(.system(size: 15, weight: on ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Theme.navy.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                Button("แบ่งครึ่ง") {
                    var a = spans; let h = r2(cur / 2)
                    a.replaceSubrange(ref.index...ref.index, with: [h, r2(cur - h)]); set(a, ref.index)
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
                Button("ลบช่วง") {
                    var a = spans; a.remove(at: ref.index); set(a, min(ref.index, a.count - 1))
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(spans.count > 1 ? RoofPageWide.red : Theme.disabledText).frame(minHeight: 44)
                .disabled(spans.count <= 1)
                Spacer()
                Button {
                    if ref.index < spans.count - 1 { select(.init(axis: ref.axis, index: ref.index + 1)) }
                    else { select(.init(axis: ref.axis == .x ? .y : .x, index: 0)) }
                } label: {
                    Text("ถัดไป ›").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 16).frame(minHeight: 44).background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                outline("EQ เท่ากันทั้งแนว", enabled: !equal) {
                    let m = spans.count; set(Array(repeating: (total / Double(m) * 1000).rounded() / 1000, count: m), ref.index)
                }
                outline("ทุกช่วง 4.00 ม.", enabled: spans.contains { abs($0 - 4) > 0.001 }) { set(Array(repeating: 4, count: spans.count), ref.index) }
            }
            Divider()
            (Text("ทั้งแนว: ") + Text(spans.map { fmt($0) }.joined(separator: ", ")).bold() + Text(" · รวม " + String(format: "%.2f", total) + " ม."))
                .font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        .foregroundStyle(Theme.navy)
        .padding(16)
        .frame(width: 340)
        .onAppear { typed = String(format: "%.2f", cur) }
        .onChange(of: ref) { _, _ in typed = String(format: "%.2f", cur) }
        .onChange(of: cur) { _, v in if !typing { typed = String(format: "%.2f", v) } }
    }

    var valueRow: some View {
        HStack(spacing: 10) {
            square("minus") { with(max(0.5, r2(cur - 0.5))) }
            HStack {
                TextField("", text: $typed).keyboardType(.decimalPad).focused($typing)
                    .font(.system(size: 24, weight: .bold)).monospacedDigit()
                    .onSubmit(commit)
                    .onChange(of: typing) { _, on in if !on { commit() } }
                Text("ม.").font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary, lineWidth: 2))
            square("plus") { with(r2(cur + 0.5)) }
        }
    }

    func commit() {
        if let v = NumberInput.value(typed), v > 0 { with(r2(v)) } else { typed = String(format: "%.2f", cur) }
    }

    func square(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 48, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "เพิ่ม 0.5 เมตร" : "ลด 0.5 เมตร")
    }

    func outline(_ t: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Theme.primary : Theme.disabledText).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Theme.primary.opacity(0.6) : Theme.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}
/// The plan legend's north arrow (icons/north-arrow.svg): navy half pointing north, white half south.
struct NorthArrow: View {
    let degrees: Double
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 48, c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42)), with: .color(Theme.navy), lineWidth: 1.2)
            ctx.rotate(by: .degrees(degrees))
            var n = Path(); n.move(to: CGPoint(x: 0, y: -18)); n.addLine(to: CGPoint(x: 6, y: 4)); n.addLine(to: .zero); n.addLine(to: CGPoint(x: -6, y: 4)); n.closeSubpath()
            ctx.fill(n, with: .color(Theme.navy))
            var so = Path(); so.move(to: CGPoint(x: 0, y: 18)); so.addLine(to: CGPoint(x: 6, y: 4)); so.addLine(to: .zero); so.addLine(to: CGPoint(x: -6, y: 4)); so.closeSubpath()
            ctx.fill(so, with: .color(.white)); ctx.stroke(so, with: .color(Theme.navy), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A 24 × 14 legend symbol (icons/legend).
struct LegendGlyph: View {
    enum Kind { case post, double, heavy, thin, dashedHeavy, purlin, skyOK, skyNo, ridge, section, pv, table, gap, blocked, keepOut }
    let kind: Kind
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 14
            func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy) }
            func h(_ y: Double, _ x0: Double = 1, _ x1: Double = 23) -> Path { var p = Path(); p.move(to: CGPoint(x: x0 * sx, y: y * sy)); p.addLine(to: CGPoint(x: x1 * sx, y: y * sy)); return p }
            let chain = StrokeStyle(lineWidth: 1.4, dash: [6, 2, 1.5, 2])
            switch kind {
            case .post: ctx.fill(Path(r(7, 2, 10, 10)), with: .color(Color(red: 0.067, green: 0.094, blue: 0.153)))
            case .double: ctx.stroke(h(5), with: .color(Self.ink), lineWidth: 1.3); ctx.stroke(h(9), with: .color(Self.ink), lineWidth: 1.3)
            case .heavy: ctx.stroke(h(7), with: .color(Self.ink), lineWidth: 2.2)
            case .thin: ctx.stroke(h(7), with: .color(Self.ink), lineWidth: 0.9)
            case .dashedHeavy: ctx.stroke(h(7), with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.8, dash: [6, 2]))
            case .purlin: ctx.stroke(h(7), with: .color(Color(red: 0.42, green: 0.447, blue: 0.502)), lineWidth: 0.8)
            case .skyOK, .skyNo:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.812, green: 0.91, blue: 0.969)))
                if kind == .skyOK { ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.18, green: 0.561, blue: 0.859)), lineWidth: 1) }
                else { ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            case .ridge: ctx.stroke(h(7), with: .color(Self.ink), style: chain)
            case .section: ctx.stroke(h(7), with: .color(Color(red: 0.067, green: 0.094, blue: 0.153)), style: StrokeStyle(lineWidth: 1.8, dash: [6, 2, 1.5, 2]))
            case .pv:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.122, green: 0.31, blue: 0.561).opacity(0.85)))
                ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.863, green: 0.902, blue: 0.949)), lineWidth: 1)
            case .table: ctx.stroke(Path(r(2, 2, 20, 10)), with: .color(Theme.navy), lineWidth: 1.6)
            case .gap:
                ctx.stroke(h(7, 2, 22), with: .color(RoofPageWide.amber), lineWidth: 1.2)
                var t = Path(); t.move(to: CGPoint(x: 2 * sx, y: 4 * sy)); t.addLine(to: CGPoint(x: 2 * sx, y: 10 * sy))
                t.move(to: CGPoint(x: 22 * sx, y: 4 * sy)); t.addLine(to: CGPoint(x: 22 * sx, y: 10 * sy))
                ctx.stroke(t, with: .color(RoofPageWide.amber), lineWidth: 1.2)
            case .blocked: ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.122, green: 0.31, blue: 0.561)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .keepOut:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red.opacity(0.12)))
                ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red), lineWidth: 1)
            }
        }
        // drawn in the plan's dark ink, so it keeps the plan's white paper in dark mode
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}
#endif
