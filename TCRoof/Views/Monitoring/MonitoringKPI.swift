import SwiftUI
import TCRoofUI

/// One of the six figure cards: an icon, its title, a small chart, the figure, and a chip with a line under it.
struct MonitoringKPI: View {
    enum Block { case on, off, unknown }
    enum Spark {
        case line([Double])
        case bars([Double], highlightLast: Bool)
        case blocks([Block])
    }

    let icon: String
    let tint: Color
    let title: String
    let value: String
    let unit: String
    var valueTint: Color? = nil
    let chip: (String, MonTone)
    let caption: String
    let spark: Spark

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 26, height: 26).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                sparkView.frame(width: 44, height: 22)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.sarabunFixed(28, .bold)).foregroundStyle(valueTint ?? Theme.navy).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 6) {
                MonChip(chip.0, chip.1)
                Text(caption).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var sparkView: some View {
        switch spark {
        case .line(let v): SparkLine(values: v, color: tint)
        case .bars(let v, let last): SparkBars(values: v, color: tint, highlightLast: last)
        case .blocks(let b): SparkBlocks(blocks: b)
        }
    }
}

private struct SparkLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let top = values.max(), top > 0 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(v / top)) * 0.9 + 1)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
            ctx.fill(area, with: .color(color.opacity(0.14)))
            ctx.stroke(line, with: .color(color), lineWidth: 1.6)
        }
        .accessibilityHidden(true)
    }
}

private struct SparkBars: View {
    let values: [Double]
    let color: Color
    let highlightLast: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let top = max(values.max() ?? 0, 1e-9), gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
            for (i, v) in values.enumerated() {
                let h = max(size.height * CGFloat(v / top), 2)
                let r = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                let last = i == values.count - 1
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(highlightLast && !last ? Theme.track : color))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SparkBlocks: View {
    let blocks: [MonitoringKPI.Block]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(b == .on ? Theme.success : b == .off ? Theme.danger : Theme.track)
            }
        }
        .accessibilityHidden(true)
    }
}
