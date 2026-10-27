#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// A2 full screen (docs/ui/survey-a2 v2 §4, §5): the picture with the same tools and undo history, pinch-to-zoom and pan,
/// and the building-model panel whose cards drop footprints on the picture at real scale.
extension SitePageWide {
    static let fullSpace = "a2full"
    static let fullBackground = Theme.mediaBackdrop

    var fullScreenView: some View {
        ZStack(alignment: .topLeading) {
            Self.fullBackground.ignoresSafeArea()
            Group {
                if isPhone { phoneFull } else { padFull }
            }
            ghost
        }
        .coordinateSpace(name: Self.fullSpace)
        .foregroundStyle(Theme.navy)
        .statusBarHidden(true)
    }

    /// iPad (v3): the bar, the picture fitted to the height under it, and the building panel floating on the right while
    /// it is open or a card is being dragged from it.
    var padFull: some View {
        VStack(spacing: 0) {
            fullHeader
            padFullPicture.padding(16)
        }
        .overlay(alignment: .topTrailing) {
            if panelShown {
                modelPanel
                    .frame(width: 290)
                    .shadow(color: Theme.navySolid.opacity(0.35), radius: 14, y: 4)
                    .padding(.top, 76).padding(.trailing, 16).padding(.bottom, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityIdentifier("a2.modelPanel")
            }
        }
    }

    /// iPad: the building panel shows while it is open, and stays while one of its cards is dragged.
    var panelShown: Bool { panelOpen || cardDrag != nil }

    /// The picture's own aspect, as large as fits `size` (the whole size until there is a picture).
    func fitted(_ size: CGSize) -> CGSize {
        guard let p = photo, let img = model.image(p, in: job.id), img.size.width > 0, img.size.height > 0 else { return size }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        return CGSize(width: img.size.width * k, height: img.size.height * k)
    }

    var padFullPicture: some View {
        GeometryReader { geo in
            let s = fitted(geo.size)
            fullPicture(radius: 8).frame(width: s.width, height: s.height)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    var fullPicture: some View { fullPicture(radius: 10) }

    func fullPicture(radius: CGFloat) -> some View {
        GeometryReader { geo in
            picture(geo.size, full: true)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .onAppear { fullFrame = geo.frame(in: .named(Self.fullSpace)) }
                .onChange(of: geo.frame(in: .named(Self.fullSpace))) { _, f in fullFrame = f }
        }
    }

    /// iPhone: the picture on top, the building list below it (it can be folded away to give the picture the screen).
    var phoneFull: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("ภาพสถานที่ติดตั้ง").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onMedia).lineLimit(1)
                Spacer(minLength: 8)
                Button { fullScreen = false } label: {
                    HStack(spacing: 6) {
                        A2Icon(name: "action-fullscreenExit", fallback: "arrow.down.right.and.arrow.up.left", size: 18)
                        Text("เสร็จ").font(.sarabunFixed(15, .bold))
                    }
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).accessibilityLabel("ออกจากเต็มจอ")
            }
            fullPicture
            Button { withAnimation(.easeOut(duration: 0.15)) { panelOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("อาคารในโครงการ").font(.sarabunFixed(14, .bold))
                    Image(systemName: panelOpen ? "chevron.down" : "chevron.up").font(.system(size: 12, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.onMedia).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if panelOpen { modelPanel.frame(height: 250) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// iPad's full-screen bar (v3): `ออกจากเต็มจอ` on the left, the title and hint centred, the building panel's toggle on the right.
    var fullHeader: some View {
        HStack(spacing: 12) {
            fullExitPill
            Spacer(minLength: 12)
            panelToggle
        }
        .overlay { fullTitle.padding(.horizontal, 270).allowsHitTesting(false) }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Theme.mediaBackdrop)
    }

    var fullTitle: some View {
        VStack(spacing: 1) {
            Text("A2 ภาพสถานที่ติดตั้ง").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onMedia)
            Text("ลากการ์ดอาคารไปวางบนภาพ · ลากเพื่อย้าย").font(.sarabunFixed(12.5)).foregroundStyle(Theme.onMedia.opacity(0.7))
        }
        .lineLimit(1).minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
    }

    var fullExitPill: some View {
        Button { fullScreen = false } label: {
            HStack(spacing: 10) {
                A2Icon(name: "action-fullscreenExit", fallback: "arrow.down.right.and.arrow.up.left", size: 16)
                    .foregroundStyle(Theme.navy)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface, in: Circle())
                Text("ออกจากเต็มจอ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onMedia).lineLimit(1)
            }
            .padding(.leading, 5).padding(.trailing, 18).frame(minHeight: 44)
            .background(Theme.onMedia.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.onMedia.opacity(0.28)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ออกจากเต็มจอ")
        .accessibilityIdentifier("a2.fullExit")
    }

    /// `อาคารในโครงการ · n/N`: placed models of the job's buildings; filled while the panel shows.
    var panelToggle: some View {
        let src = SiteModels.sources(job)
        let ids = Set(models.map(\.id))
        let n = src.filter { ids.contains($0.id) }.count
        let on = panelShown
        return Button { withAnimation(.easeOut(duration: 0.18)) { panelOpen = !on } } label: {
            HStack(spacing: 8) {
                // a plain glyph in the pill's ink (the catalog's model icons are coloured skins)
                A2Icon(name: nil, fallback: "building.2", size: 20)
                Text("อาคารในโครงการ · \(n)/\(src.count)").font(.sarabunFixed(15, .bold)).lineLimit(1)
            }
            .foregroundStyle(on ? Theme.onPrimary : Theme.onMedia)
            .padding(.horizontal, 18).frame(minHeight: 44)
            .background(on ? Theme.primary : Theme.onMedia.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.primary : Theme.onMedia.opacity(0.28)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("อาคารในโครงการ \(n) จาก \(src.count)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("a2.panelToggle")
    }

    // MARK: building-model panel

    var modelPanel: some View {
        let src = SiteModels.sources(job)
        let ids = Set(models.map(\.id))
        let selected = src.first { $0.id == selectedModel }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("อาคารในโครงการ").font(.sarabunFixed(15, .bold))
                Spacer(minLength: 6)
                Text("วางแล้ว \(src.filter { ids.contains($0.id) }.count)/\(src.count)").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            Text("โมเดลจากขั้นที่บันทึกแล้ว ขนาดจริงตามสเกลภาพ | ลากการ์ดไปวางบนภาพ แล้วลากโมเดลบนภาพเพื่อย้าย")
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            if metersAcross == nil { scaleNeeded }
            if src.isEmpty {
                Text("ยังไม่มีขั้นหลังคา ถังน้ำ ตู้ไฟฟ้า หรือห้องอินเวอร์เตอร์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            ScrollView {
                VStack(spacing: 8) { ForEach(src) { s in modelCard(s, placed: ids.contains(s.id)) } }
                    .padding(2)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(cardDrag != nil)
            if let selected {
                Divider()
                modelFooter(selected)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// No scale yet: models can't be sized, so offer the Measure tool (never guess a scale).
    var scaleNeeded: some View {
        HStack(spacing: 8) {
            Text("ต้องตั้งสเกลก่อน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.pending)
            Spacer(minLength: 4)
            Button { arm(.shape(.measure)) } label: {
                Label("วัดระยะ", systemImage: "ruler").font(.sarabunFixed(13, .bold))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.pending))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.pending)
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .background(Theme.pending.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    func color(_ s: SiteModels.Source) -> Color { Color(s.color) }

    func modelCard(_ s: SiteModels.Source, placed: Bool) -> some View {
        let on = selectedModel == s.id
        let canDrop = s.hasSize && metersAcross != nil
        let col = color(s)
        let icon: (String, String) = s.skin == .tank ? ("model-tank", "drop") : s.skin == .roof ? ("model-roof", "house") : ("model-building", "building.2")
        return HStack(spacing: 10) {
            A2Icon(name: icon.0, fallback: icon.1, size: 30)
                .foregroundStyle(col)
                .frame(width: 40, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(col, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.sarabunFixed(13, .bold)).lineLimit(2)
                Text(metersAcross == nil ? "ต้องตั้งสเกลก่อน" : s.subtitle).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(placed ? "วางแล้ว" : "ลากไปวาง").font(.sarabunFixed(11.5, .bold))
                .foregroundStyle(placed ? Theme.okText : Theme.primary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(placed ? Theme.success.opacity(0.14) : Theme.primary.opacity(0.12), in: Capsule())
                .opacity(canDrop || placed ? 1 : 0.45)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(on ? Theme.warning.opacity(0.08) : placed ? Theme.surface : Theme.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if on { RoundedRectangle(cornerRadius: 10).stroke(Theme.warning, lineWidth: 2) }
            else if placed { RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.18), lineWidth: 1) }
            else { RoundedRectangle(cornerRadius: 10).stroke(col, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])) }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedModel = s.id; editing = nil }
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.fullSpace))
            .onChanged { g in if canDrop { cardDrag = CardDrag(id: s.id, at: g.location) } }
            .onEnded { g in drop(s, at: g.location) })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ลาก " + s.title + " ไปวางบนภาพ")
        .accessibilityValue(placed ? "วางแล้ว" : "ยังไม่วาง")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A card let go over the picture places (or re-places) its model there.
    func drop(_ s: SiteModels.Source, at p: CGPoint) {
        let dragged = cardDrag != nil
        cardDrag = nil
        selectedModel = s.id
        guard dragged, s.hasSize, metersAcross != nil, fullFrame.contains(p), let r = currentRect(fullFrame.size) else { return }
        if let old = models.first(where: { $0.id == s.id }), isLocked(old) { return }
        // back through the zoom (about the centre) and pan
        let q = CGPoint(x: fullFrame.width / 2 + (p.x - fullFrame.midX - pan.width) / zoom,
                        y: fullFrame.height / 2 + (p.y - fullFrame.midY - pan.height) / zoom)
        guard let f = fraction(q, in: r) else { return }
        tool = nil; draft = []; editing = nil
        changeModels { a in
            let rotation = a.first { $0.id == s.id }?.rotation ?? 0
            a.removeAll { $0.id == s.id }
            a.append(SiteModel(id: s.id, x: f.x, y: f.y, rotation: rotation))
        }
    }

    /// The model at real scale following the finger while a card is dragged.
    @ViewBuilder var ghost: some View {
        if let d = cardDrag, let s = SiteModels.sources(job).first(where: { $0.id == d.id }), let m = metersAcross,
           let r = currentRect(fullFrame.size), r.width > 0 {
            Canvas { ctx, _ in
                let pw = Double(r.width * zoom), ph = Double(r.height * zoom)
                let box = Box(Double(d.at.x) - pw / 2, Double(d.at.y) - ph / 2, pw, ph)
                let ops = SiteModels.ops(SiteModel(id: s.id, x: 0.5, y: 0.5), s, in: box, metersAcross: m, detailed: true, selected: true)
                ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: selected model

    func modelFooter(_ s: SiteModels.Source) -> some View {
        let m = models.first { $0.id == s.id }
        let locked = m.map(isLocked) ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.title + " | " + s.sizeText).font(.sarabunFixed(13, .bold)).lineLimit(2)
            if let m {
                Text("หมุน \(Int(m.rotation))° | " + (locked ? (allLocked ? "ล็อกทั้งหมดจากแถบเครื่องมือ" : "ล็อกตำแหน่งแล้ว") : "ลากโมเดลบนภาพเพื่อย้าย"))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Button { changeModels { a in if let i = a.firstIndex(where: { $0.id == s.id }) { a[i].locked.toggle() } } } label: {
                    Text(m.locked ? "ปลดล็อกตำแหน่ง" : "ล็อกตำแหน่งตามที่วาง").font(.sarabunFixed(14, .bold))
                        .foregroundStyle(m.locked ? Theme.onPrimary : Theme.warningInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(m.locked ? Theme.warning : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warning, lineWidth: m.locked ? 0 : 1))
                }
                .buttonStyle(.plain).disabled(allLocked).opacity(allLocked ? 0.45 : 1)
                HStack(spacing: 8) {
                    rotateButton("↺ 15°", s.id, -15, label: "หมุนซ้าย 15 องศา")
                    rotateButton("↻ 15°", s.id, 15, label: "หมุนขวา 15 องศา")
                    rotateButton("90°", s.id, 90, label: "หมุน 90 องศา")
                }
                .disabled(locked).opacity(locked ? 0.4 : 1)
                Button { changeModels { a in a.removeAll { $0.id == s.id } } } label: {
                    Text("เอาโมเดลออกจากภาพ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.danger))
                }
                .buttonStyle(.plain).disabled(locked).opacity(locked ? 0.4 : 1)
            } else {
                Text(s.hasSize ? "ลากการ์ดไปวางบนภาพ" : "ใส่ขนาดอาคารก่อนวางบนภาพ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            if let i = job.modules.firstIndex(where: { $0.id.uuidString == s.id && $0.type == .panel }) { buildingSize(i) }
        }
    }

    func rotateButton(_ title: String, _ id: String, _ d: Double, label: String) -> some View {
        Button {
            changeModels { a in
                if let i = a.firstIndex(where: { $0.id == id }) { a[i].rotation = ((a[i].rotation + d).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
            }
        } label: {
            Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.25)))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    /// B1 has no building size on its form: it is entered here and kept in the B1 section (`bldW` / `bldL`).
    func buildingSize(_ i: Int) -> some View {
        func field(_ key: String, _ placeholder: String) -> some View {
            TextField(placeholder, text: Binding(
                get: { job.modules[safe: i]?.values.text(key) ?? "" },
                set: { v in if job.modules.indices.contains(i) { job.modules[i].values[key] = v.isEmpty ? nil : .text(v) } }))
                .keyboardType(.decimalPad).font(.sarabunFixed(15, .semibold))
                .padding(.horizontal, 10).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl.opacity(0.7)))
        }
        return HStack(spacing: 6) {
            Text("ขนาดอาคาร").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            field(SiteModels.buildingWidthKey, "ก")
            Text("×").foregroundStyle(Theme.inkMuted)
            field(SiteModels.buildingLengthKey, "ย")
            Text("ม.").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
    }
}
#endif
