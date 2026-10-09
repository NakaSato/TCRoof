#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// A2 full screen (docs/ui/survey-a2 v2 §4, §5): the picture with the same tools and undo history, pinch-to-zoom and pan,
/// and the building-model panel whose cards drop footprints on the picture at real scale.
extension SitePageWide {
    static let fullSpace = "a2full"
    static let fullBackground = Color(red: 14 / 255, green: 26 / 255, blue: 43 / 255)

    var fullScreenView: some View {
        ZStack(alignment: .topLeading) {
            Self.fullBackground.ignoresSafeArea()
            Group {
                if isPhone { phoneFull } else { padFull }
            }
            ghost
        }
        .coordinateSpace(name: Self.fullSpace)
        .foregroundStyle(Home.navy)
        .statusBarHidden(true)
    }

    var padFull: some View {
        VStack(alignment: .leading, spacing: 14) {
            fullHeader
            HStack(alignment: .top, spacing: 16) {
                fullPicture
                modelPanel.frame(width: 290)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    var fullPicture: some View {
        GeometryReader { geo in
            picture(geo.size, full: true)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear { fullFrame = geo.frame(in: .named(Self.fullSpace)) }
                .onChange(of: geo.frame(in: .named(Self.fullSpace))) { _, f in fullFrame = f }
        }
    }

    /// iPhone: the picture on top, the building list below it (it can be folded away to give the picture the screen).
    var phoneFull: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("ภาพสถานที่ติดตั้ง").font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Button { fullScreen = false } label: {
                    HStack(spacing: 6) {
                        A2Icon(name: "action-fullscreenExit", fallback: "arrow.down.right.and.arrow.up.left", size: 18)
                        Text("เสร็จ").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Home.navy)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).accessibilityLabel("ออกจากเต็มจอ")
            }
            fullPicture
            Button { withAnimation(.easeOut(duration: 0.15)) { panelOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("อาคารในโครงการ").font(.system(size: 14, weight: .bold))
                    Image(systemName: panelOpen ? "chevron.down" : "chevron.up").font(.system(size: 12, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if panelOpen { modelPanel.frame(height: 250) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    var fullHeader: some View {
        HStack(spacing: 14) {
            Text("ภาพสถานที่ติดตั้ง").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Text("เต็มจอ · ใช้เครื่องมือวาด / วางสัญลักษณ์ได้เหมือนเดิม · หนีบ 2 นิ้วเพื่อซูม")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button { fullScreen = false } label: {
                HStack(spacing: 8) {
                    A2Icon(name: "action-fullscreenExit", fallback: "arrow.down.right.and.arrow.up.left", size: 18)
                    Text("ออกจากเต็มจอ").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Home.navy)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: building-model panel

    var modelPanel: some View {
        let src = SiteModels.sources(job)
        let ids = Set(models.map(\.id))
        let selected = src.first { $0.id == selectedModel }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("อาคารในโครงการ").font(.system(size: 15, weight: .bold))
                Spacer(minLength: 6)
                Text("วางแล้ว \(src.filter { ids.contains($0.id) }.count)/\(src.count)").font(.system(size: 12)).foregroundStyle(Home.muted)
            }
            Text("โมเดลจากขั้นที่บันทึกแล้ว ขนาดจริงตามสเกลภาพ · ลากการ์ดไปวางบนภาพ แล้วลากโมเดลบนภาพเพื่อย้าย")
                .font(.system(size: 12)).foregroundStyle(Home.muted).fixedSize(horizontal: false, vertical: true)
            if metersAcross == nil { scaleNeeded }
            if src.isEmpty {
                Text("ยังไม่มีขั้นหลังคา ถังน้ำ ตู้ไฟฟ้า หรือห้องอินเวอร์เตอร์").font(.system(size: 13)).foregroundStyle(Home.muted)
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    /// No scale yet: models can't be sized, so offer the Measure tool (never guess a scale).
    var scaleNeeded: some View {
        HStack(spacing: 8) {
            Text("ต้องตั้งสเกลก่อน").font(.system(size: 13, weight: .bold)).foregroundStyle(Home.pending)
            Spacer(minLength: 4)
            Button { arm(.shape(.measure)) } label: {
                Label("วัดระยะ", systemImage: "ruler").font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.pending))
            }
            .buttonStyle(.plain).foregroundStyle(Home.pending)
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .background(Home.pending.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    func color(_ s: SiteModels.Source) -> Color { Color(red: s.color.r, green: s.color.g, blue: s.color.b) }

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
                Text(s.title).font(.system(size: 13, weight: .bold)).lineLimit(2)
                Text(metersAcross == nil ? "ต้องตั้งสเกลก่อน" : s.subtitle).font(.system(size: 11)).foregroundStyle(Home.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(placed ? "วางแล้ว" : "ลากไปวาง").font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(placed ? Color(red: 0.118, green: 0.482, blue: 0.271) : Home.primary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(placed ? Home.ok.opacity(0.14) : Home.primary.opacity(0.12), in: Capsule())
                .opacity(canDrop || placed ? 1 : 0.45)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(on ? Home.warn.opacity(0.08) : placed ? Color.white : Home.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if on { RoundedRectangle(cornerRadius: 10).stroke(Home.warn, lineWidth: 2) }
            else if placed { RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.18), lineWidth: 1) }
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
            Text(s.title + " · " + s.sizeText).font(.system(size: 13, weight: .bold)).lineLimit(2)
            if let m {
                Text("หมุน \(Int(m.rotation))° · " + (locked ? (allLocked ? "ล็อกทั้งหมดจากแถบเครื่องมือ" : "ล็อกตำแหน่งแล้ว") : "ลากโมเดลบนภาพเพื่อย้าย"))
                    .font(.system(size: 12)).foregroundStyle(Home.muted)
                Button { changeModels { a in if let i = a.firstIndex(where: { $0.id == s.id }) { a[i].locked.toggle() } } } label: {
                    Text(m.locked ? "ปลดล็อกตำแหน่ง" : "ล็อกตำแหน่งตามที่วาง").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(m.locked ? Color.white : Color(red: 0.698, green: 0.416, blue: 0))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(m.locked ? Home.warn : Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.warn, lineWidth: m.locked ? 0 : 1))
                }
                .buttonStyle(.plain).disabled(allLocked).opacity(allLocked ? 0.45 : 1)
                HStack(spacing: 8) {
                    rotateButton("↺ 15°", s.id, -15, label: "หมุนซ้าย 15 องศา")
                    rotateButton("↻ 15°", s.id, 15, label: "หมุนขวา 15 องศา")
                    rotateButton("90°", s.id, 90, label: "หมุน 90 องศา")
                }
                .disabled(locked).opacity(locked ? 0.4 : 1)
                Button { changeModels { a in a.removeAll { $0.id == s.id } } } label: {
                    Text("เอาโมเดลออกจากภาพ").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.danger))
                }
                .buttonStyle(.plain).disabled(locked).opacity(locked ? 0.4 : 1)
            } else {
                Text(s.hasSize ? "ลากการ์ดไปวางบนภาพ" : "ใส่ขนาดอาคารก่อนวางบนภาพ").font(.system(size: 12)).foregroundStyle(Home.muted)
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
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Home.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.25)))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    /// B1 has no building size on its form: it is entered here and kept in the B1 section (`bldW` / `bldL`).
    func buildingSize(_ i: Int) -> some View {
        func field(_ key: String, _ placeholder: String) -> some View {
            TextField(placeholder, text: Binding(
                get: { job.modules[safe: i]?.values.text(key) ?? "" },
                set: { v in if job.modules.indices.contains(i) { job.modules[i].values[key] = v.isEmpty ? nil : .text(v) } }))
                .keyboardType(.decimalPad).font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.borderControl.opacity(0.7)))
        }
        return HStack(spacing: 6) {
            Text("ขนาดอาคาร").font(.system(size: 12)).foregroundStyle(Home.muted)
            field(SiteModels.buildingWidthKey, "ก")
            Text("×").foregroundStyle(Home.muted)
            field(SiteModels.buildingLengthKey, "ย")
            Text("ม.").font(.system(size: 12)).foregroundStyle(Home.muted)
        }
    }
}
#endif
