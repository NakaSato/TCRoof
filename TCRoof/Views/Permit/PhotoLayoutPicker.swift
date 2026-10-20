import SwiftUI
import TCRoofUI
import TCRoofCore

/// Picks how an attachment page arranges its photos; each tile is a small drawing of the page area with numbered cells.
struct PhotoLayoutPicker: View {
    @Binding var selection: PhotoLayout
    /// Photos on the attachment now; `อัตโนมัติ` draws the layout it resolves to for this count.
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel("รูปแบบหน้า")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(PhotoLayout.allCases, id: \.self) { tile($0) }
                }
                .padding(.vertical, 2)
            }
            if count > selection.resolved(count).capacity {
                Text("รูปแบบนี้ลงได้ \(selection.resolved(count).capacity) รูป รูปที่เกินจะเก็บไว้แต่ไม่ลงหน้าเอกสาร")
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.pending)
            }
        }
    }

    private func tile(_ layout: PhotoLayout) -> some View {
        let on = layout == selection
        return Button { selection = layout } label: {
            VStack(spacing: 4) {
                PhotoLayoutDiagram(layout: layout.resolved(max(count, 1)), highlight: on)
                    .frame(width: 46, height: 64)
                Text(layout.title).font(.sarabun(11.5, on ? .bold : .regular, relativeTo: .caption2))
                    .foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 72)
            }
            .padding(6)
            .frame(minHeight: touchMin)
            .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The page area as a portrait card with the layout's cells numbered in photo order.
struct PhotoLayoutDiagram: View {
    let layout: PhotoLayout
    var highlight = false

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.surface))
            let cells = layout.cells(in: [2, 2, Double(size.width) - 4, Double(size.height) - 4], count: layout.capacity, gap: 3)
            for (i, c) in cells.enumerated() {
                let r = CGRect(x: c[0], y: c[1], width: c[2], height: c[3])
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(highlight ? Theme.primarySoft : Theme.track))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 1.5), with: .color(highlight ? Theme.primary : Theme.borderControl), lineWidth: 0.8)
                ctx.draw(Text("\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundColor(highlight ? Theme.primary : Theme.inkMuted),
                         at: CGPoint(x: r.midX, y: r.midY))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.borderControl, lineWidth: 0.8))
        .accessibilityHidden(true)
    }
}

/// The attachment's photos in page order: the number matches the layout's cell; arrows move a photo one place.
struct PhotoOrderStrip: View {
    let images: [Data]
    /// Photos the layout prints; the rest show as not printed.
    let capacity: Int
    let move: (_ index: Int, _ step: Int) -> Void
    /// Opens the photo's caption / crop / marks editor.
    let edit: (_ index: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel("ลำดับในหน้า | แตะรูปเพื่อใส่คำบรรยายและกรอบแดง")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(images.indices, id: \.self) { item($0) }
                }
            }
        }
    }

    private func item(_ i: Int) -> some View {
        let printed = i < capacity
        return VStack(spacing: 2) {
            Button { edit(i) } label: { thumbnail(i, printed: printed) }
                .buttonStyle(.plain)
                .accessibilityLabel("แก้รูปที่ \(i + 1)")
            HStack(spacing: 0) {
                arrow("chevron.left", enabled: i > 0, label: "เลื่อนรูปที่ \(i + 1) ไปก่อน") { move(i, -1) }
                arrow("chevron.right", enabled: i < images.count - 1, label: "เลื่อนรูปที่ \(i + 1) ไปหลัง") { move(i, 1) }
            }
        }
    }

    private func thumbnail(_ i: Int, printed: Bool) -> some View {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = UIImage(data: images[i]) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.track
                    }
                }
                .frame(width: 88, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .opacity(printed ? 1 : 0.4)
                Text(printed ? "\(i + 1)" : "ไม่ลง")
                    .font(.sarabun(12, .bold, relativeTo: .caption))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(printed ? Theme.primary : Theme.inkMuted, in: Capsule())
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.primary, Theme.surface)
                    .padding(3)
            }
    }

    private func arrow(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .frame(width: touchMin, height: touchMin)
                .foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
