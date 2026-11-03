#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

// MARK: - Mount Selection Inspector & BOQ Quantities

extension RoofPageWide {
    // MARK: Selection Inspector

    @ViewBuilder var mountInfo: some View {
        if let sel = mountSelection, let text = infoLines(sel) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text.title).font(.sarabunFixed(14, .bold))
                    Spacer(minLength: 6)
                    Button { mountSelection = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 44, height: 32)
                    }
                    .buttonStyle(.plain).accessibilityLabel("ปิดรายละเอียด")
                }
                ForEach(Array(text.lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.sarabunFixed(12.5)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(text.pills.enumerated()), id: \.offset) { _, p in
                    Text(p.text).font(.sarabunFixed(12, .bold)).foregroundStyle(p.ok ? Theme.okText : Theme.dangerText)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(p.ok ? Theme.okSoft : Theme.dangerSoft, in: Capsule())
                }
                if case .area(let i) = sel { obstacleEditor(i) }
            }
            .padding(10)
            .background(Self.soft, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    struct InfoText { var title: String; var lines: [String]; var pills: [(text: String, ok: Bool)] }

    func infoLines(_ sel: MountSelection) -> InfoText? {
        guard let m = shownMount else { return nil }
        let s = m.standard
        switch sel {
        case .area(let index):
            guard let a = Roof.areas(values).first(where: { $0.index == index }) else { return nil }
            let input = RoofMount.input(values, latitude: latitude)
            guard let o = input.obstacles.first(where: { $0.x == a.x && $0.y == a.y && $0.w == a.w && $0.h == a.h }) else { return nil }
            let tall = o.heightOrDefault > 0
            let hulls = m.faces.reduce(0) { $0 + ($1.shade.isEmpty ? 0 : 1) }
            var pills: [(String, Bool)] = [(tall ? "เว้นแผงจากเงา 09:00–15:00" : "ไม่สูงพอจะทอดเงา", !tall)]
            if tall && hulls == 0 { pills = [("เงาไม่ตกบนแผง", true)] }
            return InfoText(title: o.title,
                            lines: [String(format: "%.2f × %.2f ม. | สูง %.2f ม.", o.w, o.h, o.heightOrDefault)
                                    + (o.height == nil && o.kind.defaultHeight > 0 ? " (ตามชนิด)" : ""),
                                    String(format: "แผงเว้น %.2f ม. | ขาเว้น %.2f ม.", o.coverable ? 0 : o.kind.moduleClearance, o.footClearance)
                                    + (o.coverable ? " | วางทับได้" : "")],
                            pills: pills)
        case .slot(let ref):
            guard let f = m.faces.first(where: { $0.face.id == ref.face }), f.rows.indices.contains(ref.row),
                  f.rows[ref.row].slots.indices.contains(ref.column) else { return nil }
            let row = f.rows[ref.row], slot = row.slots[ref.column]
            let place = "ด้าน\(RoofFace.direction(f.face.azimuth)) | แถว \(ref.row + 1) | ช่อง \(ref.column + 1)"
            if let why = slot.blocked {
                return InfoText(title: "ช่องว่าง | " + place, lines: [], pills: [(why, false)])
            }
            guard let run = f.run(row: ref.row, column: ref.column) else { return nil }
            let k = run.count
            let bay = run.feet.flatMap { feet in zip(feet, feet.dropFirst()).map { $1 - $0 } }.max() ?? 0
            var pills: [(String, Bool)] = [("ขาไม่ชนสิ่งกีดขวาง", true)]
            pills.append((m.options.tileHooks ? "ขอเกี่ยวกระเบื้องยึดจันทัน" : m.options.ribClamp ? "จับสันลอน ¼ และ ¾ ของแผง"
                          : m.options.acrossPurlins ? "รางตัดแป | ขาตกทุกแป" : "รางตกแปทั้ง 2 เส้น",
                          RoofMountDrawings.rowPasses(row, in: m)))
            if run.moved { pills.append((m.options.tileHooks ? "ข้ามจันทันที่ชนสิ่งกีดขวาง" : "จัดระยะ L-foot ใหม่เพื่อหลบสิ่งกีดขวาง", true)) }
            return InfoText(title: "แผง | " + place,
                            lines: [String(format: "ชุดราง %d แผง (%.2f kWp) | รางยาว %.2f ม.", k, Double(k) * s.moduleKW, run.railLength),
                                    (m.options.tileHooks ? "ขอเกี่ยว " : "L-foot ")
                                    + "\(run.feet.map(\.count).map(String.init).joined(separator: " / ")) ตัวต่อราง | ห่างมากสุด "
                                    + String(format: "%.2f ม.", bay)],
                            pills: pills)
        }
    }

    /// The kind and height of an obstacle on the plan, for its shade.
    @ViewBuilder func obstacleEditor(_ index: Int) -> some View {
        let list = values.obstacles(Roof.Key.obstacles)
        if list.indices.contains(index), list[index].kind != Roof.skylightKind, list[index].kind != Roof.keepOutKind {
            let o = list[index]
            let kinds: [RoofObstacleKind] = [.turbine, .stack, .pipe, .other]
            let current = RoofObstacleKind(rawValue: o.kind) ?? .other
            HStack(spacing: 8) {
                Menu {
                    ForEach(kinds, id: \.self) { k in
                        Button(k.title) { editObstacle(index) { $0.kind = k.rawValue; if $0.label.isEmpty || kinds.map(\.title).contains($0.label) { $0.label = k.title } } }
                    }
                } label: {
                    Label(current.title, systemImage: "chevron.down").font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
                }
                Spacer(minLength: 4)
                Text("สูง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                let h = NumberInput.value(o.height) ?? current.defaultHeight
                stepButton("minus", enabled: h > 0) { editObstacle(index) { $0.height = fmt(max(0, h - 0.1)) } }
                Text(String(format: "%.1f ม.", h)).font(.sarabunFixed(15, .bold)).monospacedDigit().frame(minWidth: 56)
                stepButton("plus", enabled: h < 10) { editObstacle(index) { $0.height = fmt(min(10, h + 0.1)) } }
            }
        }
    }

    func editObstacle(_ index: Int, _ f: (inout Obstacle) -> Void) {
        update { v in
            var list = v.obstacles(Roof.Key.obstacles)
            guard list.indices.contains(index) else { return }
            f(&list[index])
            v[Roof.Key.obstacles] = .obstacles(list)
        }
    }

    // MARK: - BOQ Quantities & Standard

    /// The walkways' BOQ cells, when the layout has walkways.
    func walkwayCells(_ w: RoofWalkwayQuantities?) -> [(String, String)] {
        guard let w, w.walkways > 0 else { return [] }
        var cells: [(String, String)] = [
            ("ทางเดิน", String(format: "%d แนว %.1f ม.", w.walkways, w.length)), ("ตะแกรง HDG", "\(w.gratings) แผ่น"),
            ("รางขวาง | L-feet", "\(w.crossRails) | \(w.lFeet)"), ("สลิงกันตก", String(format: "%.1f ม. | %d เสา", w.lifeline, w.supports)),
            ("รางเคเบิล + PPR", String(format: "%.1f ม.", w.tray)),
        ]
        if w.ladders > 0 { cells.append(("บันไดลิง", w.cagedLadders > 0 ? "\(w.ladders) (กรง + ชานพัก)" : "\(w.ladders)")) }
        return cells
    }

    var mountQuantities: some View {
        let q = shownMount?.quantities
        let cells: [(String, String)] = [
            ("ราง", String(format: "%.1f ม.", q?.railLength ?? 0)), ("ต่อราง", "\(q?.splices ?? 0)"),
            (q.map(RoofMount.footName) ?? "L-foot", "\(q?.feet ?? 0)"),
            ("ตัวจับกลาง", "\(q?.midClamps ?? 0)"), ("ตัวจับปลาย", "\(q?.endClamps ?? 0)"), ("ชุดราง", "\(q?.runs ?? 0)"),
            ("ตัดแผง", "\(q?.cuts ?? 0)"), ("ขาชนสิ่งกีดขวาง", "0"),
        ] + walkwayCells(q?.walkway)
        // closed until tapped; an overloaded structure stays in view
        return VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { boqOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    A3Label(text: "ปริมาณวัสดุ (BOQ)")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        .rotationEffect(.degrees(boqOpen ? 180 : 0))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปริมาณวัสดุ BOQ")
            .accessibilityValue(boqOpen ? "เปิดอยู่" : "ปิดอยู่")
            if boqOpen {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: narrow ? 2 : 4), spacing: 6) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.1).font(.sarabunFixed(16, .bold)).monospacedDigit()
                            Text(c.0).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Self.track, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let q, q.modules > 0, boqOpen || q.overLoad {
                let over = q.overLoad
                Label(RoofMount.loadLine(q), systemImage: over ? "exclamationmark.triangle.fill" : "scalemass")
                    .font(.sarabunFixed(12.5, over ? .bold : .regular)).foregroundStyle(over ? Theme.dangerText : Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One value of the job's standard with − and + buttons.
    func standardStepper(_ title: String, _ kp: WritableKeyPath<RoofMountStandard, Double>, step: Double, fmt f: String = "%.2f") -> some View {
        let s = mountChoice.standardOrDefault
        return HStack(spacing: 6) {
            Text(title).font(.sarabunFixed(13)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            stepButton("minus", enabled: s[keyPath: kp] - step > 0) { setStandard { $0[keyPath: kp] = max(step, $0[keyPath: kp] - step) } }
            Text(String(format: f, s[keyPath: kp])).font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 48)
            stepButton("plus", enabled: true) { setStandard { $0[keyPath: kp] += step } }
        }
    }

    /// Edits the job's standard; the clamping zone follows a new module length until it was edited itself.
    func setStandard(_ f: (inout RoofMountStandard) -> Void) {
        changeChoice { c in
            var s = c.standardOrDefault
            let follows = s.clampFollowsModule, length = s.moduleLength
            f(&s)
            if follows && abs(s.moduleLength - length) > 1e-9 { (s.clampMin, s.clampMax) = s.clampFromModule }
            c.standard = s
        }
    }

    var mountFooter: some View {
        let assumed = RoofMount.assumptions(values, latitude: latitude)
        return VStack(alignment: .leading, spacing: 2) {
            if !assumed.isEmpty {
                Text("ค่าสมมติ: " + assumed.joined(separator: " | ")).font(.sarabunFixed(11.5)).foregroundStyle(Self.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง | ตรวจน้ำหนักบรรทุกของโครงหลังคากับวิศวกรโครงสร้าง")
                .font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
