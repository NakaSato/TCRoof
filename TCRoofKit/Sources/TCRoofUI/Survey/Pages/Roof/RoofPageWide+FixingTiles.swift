#if canImport(UIKit)
import SwiftUI

/// The fixing choices of C1's card (`Resources/roof-fixing-options.json`): each has a title and options, each option a
/// title and a drawing as marks in unit coordinates (purlins as thin lines, rails thick, the module a rectangle).
struct FixingChoice: Decodable {
    struct Mark: Decodable {
        enum Kind: String, Decodable { case line, path, module, dot }
        enum Tone: String, Decodable { case ink, accent, faint }
        let type: Kind
        var from: [Double]?, to: [Double]?, at: [Double]?, rect: [Double]?, points: [[Double]]?
        var width: Double?
        var tone: Tone?
    }
    struct Option: Decodable { let title: String; let glyph: [Mark] }
    let title: String
    let options: [Option]

    private struct File: Decodable { let fixingChoices: [String: FixingChoice] }

    static let all: [String: FixingChoice] = {
        guard let url = Bundle.module.url(forResource: "roof-fixing-options", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.fixingChoices
    }()
}

/// One pick of a fixing choice as a tile: a small drawing over its name, the picked one outlined.
struct FixingTiles: View {
    let options: [FixingChoice.Option]
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let on = selected == i
                Button { pick(i) } label: {
                    VStack(spacing: 4) {
                        FixingGlyphView(marks: o.glyph, on: on).frame(height: 44)
                        Text(o.title).font(.sarabunFixed(14, on ? .bold : .medium)).lineLimit(2).minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.primary : Theme.hairline, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(o.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct FixingGlyphView: View {
    let marks: [FixingChoice.Mark]
    let on: Bool

    var body: some View {
        Canvas { ctx, size in
            let ink = on ? Theme.navy : Theme.inkMuted, accent = on ? Theme.primary : Theme.inkMuted
            func point(_ v: [Double]) -> CGPoint { CGPoint(x: size.width * v[0], y: size.height * v[1]) }
            func color(_ t: FixingChoice.Mark.Tone?) -> Color {
                switch t ?? .ink { case .ink: ink; case .accent: accent; case .faint: ink.opacity(0.45) }
            }
            for m in marks {
                switch m.type {
                case .line:
                    guard let a = m.from, let b = m.to, a.count == 2, b.count == 2 else { continue }
                    var p = Path(); p.move(to: point(a)); p.addLine(to: point(b))
                    ctx.stroke(p, with: .color(color(m.tone)), lineWidth: m.width ?? 1)
                case .path:
                    guard let pts = m.points, pts.count > 1, pts.allSatisfy({ $0.count == 2 }) else { continue }
                    var p = Path(); p.move(to: point(pts[0]))
                    for v in pts.dropFirst() { p.addLine(to: point(v)) }
                    ctx.stroke(p, with: .color(color(m.tone)), lineWidth: m.width ?? 1)
                case .module:
                    guard let r = m.rect, r.count == 4 else { continue }
                    let box = CGRect(x: size.width * r[0], y: size.height * r[1], width: size.width * r[2], height: size.height * r[3])
                    ctx.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(accent.opacity(0.18)))
                    ctx.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(accent), lineWidth: 1.5)
                case .dot:
                    guard let at = m.at, at.count == 2 else { continue }
                    let c = point(at)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(ink))
                }
            }
        }
        .frame(maxWidth: 96)
        .accessibilityHidden(true)
    }
}
#endif
