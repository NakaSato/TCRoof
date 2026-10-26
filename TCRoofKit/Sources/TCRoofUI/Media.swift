#if canImport(UIKit)
import SwiftUI
import UIKit

/// Section 6 | Media (docs/ui/components/sections/06-media.png).

/// A photo slot. Empty: dashed pink box with the hint, `อัปโหลด` and `กล้อง`.
/// Filled: the photo, a green ✓, ✕ to delete, a caption chip bottom-left and an optional teal mark.
public struct TCPhotoSlot<Photo: View>: View {
    /// A teal label and dashed box drawn on the photo, in unit coordinates of the slot.
    public struct Mark: Sendable {
        public let title: String
        public let rect: CGRect
        public init(title: String, rect: CGRect) { self.title = title; self.rect = rect }
    }

    let hint: String
    let filled: Bool
    var caption: String?
    var mark: Mark?
    var height: CGFloat
    let onUpload: () -> Void
    let onCamera: () -> Void
    let onDelete: () -> Void
    let photo: Photo

    public init(hint: String, filled: Bool, caption: String? = nil, mark: Mark? = nil, height: CGFloat = 150,
                onUpload: @escaping () -> Void, onCamera: @escaping () -> Void, onDelete: @escaping () -> Void,
                @ViewBuilder photo: () -> Photo) {
        self.hint = hint; self.filled = filled; self.caption = caption; self.mark = mark; self.height = height
        self.onUpload = onUpload; self.onCamera = onCamera; self.onDelete = onDelete; self.photo = photo()
    }

    public var body: some View {
        if filled { full } else { empty }
    }

    var empty: some View {
        VStack(spacing: 10) {
            Text(hint).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.s) {
                TCButton("อัปโหลด", systemImage: "photo", kind: .secondary, size: .card, action: onUpload)
                TCButton("กล้อง", systemImage: "camera", kind: .primaryGradient, size: .card, action: onCamera)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(Theme.photoEmptyFill, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.photoEmptyBorder, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    var full: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                photo.frame(width: g.size.width, height: g.size.height).clipped()
                if let mark {
                    let r = CGRect(x: mark.rect.minX * g.size.width, y: mark.rect.minY * g.size.height,
                                   width: mark.rect.width * g.size.width, height: mark.rect.height * g.size.height)
                    Rectangle().fill(Theme.teal.opacity(0.25))
                        .overlay(Rectangle().strokeBorder(Theme.teal, style: StrokeStyle(lineWidth: 3, dash: [6, 4])))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                    Text(mark.title).font(.sarabun(12, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, Space.s).padding(.vertical, 3)
                        .background(Theme.teal, in: RoundedRectangle(cornerRadius: 7))
                        .fixedSize()
                        .offset(x: max(0, r.minX - 12), y: max(0, r.minY - 26))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(alignment: .topLeading) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Theme.success, in: Circle())
                .padding(Space.s)
                .accessibilityLabel("มีภาพแล้ว")
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Color.black.opacity(0.55), in: Circle())
                    .frame(width: touchMin, height: touchMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TCPressStyle())
            .padding(2)
            .accessibilityLabel("ลบภาพ")
        }
        .overlay(alignment: .bottomLeading) {
            if let caption {
                Text(caption).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, Space.s).padding(.vertical, 2)
                    .background(Theme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
                    .padding(Space.s)
            }
        }
    }
}

/// Controls laid over any map: layer chips top-left, zoom +/− top-right, the scale bottom-right.
public struct TCMapControls: View {
    let layers: [String]
    @Binding var layer: Int
    var scale: String
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    public init(layers: [String] = ["พื้นที่", "สถานี", "อาคาร"], layer: Binding<Int>, scale: String,
                onZoomIn: @escaping () -> Void, onZoomOut: @escaping () -> Void) {
        self.layers = layers; self._layer = layer; self.scale = scale; self.onZoomIn = onZoomIn; self.onZoomOut = onZoomOut
    }

    public var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(layers.indices, id: \.self) { i in
                    Button { layer = i } label: {
                        Text(layers[i]).font(.sarabun(14, i == layer ? .bold : .regular))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(i == layer ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: touchMin)
                    .accessibilityAddTraits(i == layer ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: Radius.sm))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 0) {
                zoom("plus", label: "ซูมเข้า", action: onZoomIn)
                Rectangle().fill(Theme.borderSubtle).frame(width: touchMin, height: 1)
                zoom("minus", label: "ซูมออก", action: onZoomOut)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            Text(scale).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.navy)
                .padding(.horizontal, Space.s).padding(.vertical, 3)
                .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityLabel("มาตราส่วน " + scale)
        }
        .padding(Space.s)
    }

    func zoom(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: touchMin, height: touchMin).contentShape(Rectangle())
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel(label)
    }
}

/// North arrow: white disc with a shadow, `N`, red north half and grey south half of the needle. `heading` turns it.
public struct TCCompass: View {
    var heading: Double
    var size: CGFloat

    public init(heading: Double = 0, size: CGFloat = 64) { self.heading = heading; self.size = size }

    public var body: some View {
        ZStack {
            Circle().fill(Color.white).shadow(color: Theme.navy.opacity(0.18), radius: 6, y: 2)
            ZStack {
                Text("N").font(.system(size: size * 0.16, weight: .heavy)).foregroundStyle(Theme.navy)
                    .offset(y: -size * 0.36)
                Needle(north: true).fill(Theme.danger)
                Needle(north: false).fill(Theme.muted)
                Circle().fill(Color.white).frame(width: size * 0.06, height: size * 0.06)
            }
            .rotationEffect(.degrees(heading))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("เข็มทิศ")
        .accessibilityValue("ทิศเหนือ \(Int(heading.rounded())) องศา")
    }

    struct Needle: Shape {
        let north: Bool
        func path(in r: CGRect) -> Path {
            let c = CGPoint(x: r.midX, y: r.midY), w = r.width * 0.1, l = r.height * 0.3
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: north ? c.y - l : c.y + l))
            p.addLine(to: CGPoint(x: c.x + w, y: c.y))
            p.addLine(to: CGPoint(x: c.x - w, y: c.y))
            p.closeSubpath()
            return p
        }
    }
}

/// Shadow animation play (blue) / pause (orange), 64 pt.
public struct TCPlayPauseButton: View {
    @Binding var playing: Bool
    var size: CGFloat

    public init(playing: Binding<Bool>, size: CGFloat = 64) { self._playing = playing; self.size = size }

    public var body: some View {
        Button { playing.toggle() } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(playing ? Theme.warning : Theme.primary, in: RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel(playing ? "หยุดแอนิเมชันเงา" : "เล่นแอนิเมชันเงา")
    }
}

/// Outlined full-screen button, 64 pt.
public struct TCFullscreenButton: View {
    var size: CGFloat
    let action: () -> Void

    public init(size: CGFloat = 64, action: @escaping () -> Void) { self.size = size; self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(width: size, height: size)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.borderControl))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel("เต็มจอ")
    }
}

/// Small segmented control (`แปลน` / `3 มิติ`): light track, white selected pill with a shadow.
public struct TCSmallSegmented: View {
    let options: [String]
    @Binding var selection: Int

    public init(_ options: [String] = ["แปลน", "3 มิติ"], selection: Binding<Int>) {
        self.options = options; self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i]).font(.sarabun(14.5, i == selection ? .bold : .regular))
                        .foregroundStyle(i == selection ? Theme.navy : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: touchMin)
                        .background {
                            if i == selection {
                                RoundedRectangle(cornerRadius: 9).fill(Theme.surface)
                                    .shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(i == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: Radius.lg))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
#endif
