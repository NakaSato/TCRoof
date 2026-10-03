import Foundation

/// A tap area of the diagram, in design units.
public struct SLHit: Sendable {
    public var box: Box
    public var target: SLTarget
}

/// The diagram as drawing operations in design units (1560 wide, height grows with the content), plus its tap areas.
/// The screen and the A3 PDF both draw these same ops, so they always match. Reference: docs/ui/survey-sld/diagram-lv.svg.
public struct SingleLineDrawing: Sendable {
    public var sketch: Sketch
    public var hits: [SLHit]
    /// The inverters, FTS DC cut, PV arrays and Emergency button with its control lines (B5's crop).
    public var ftsBox: Box? = nil
    /// The zero-export parts: LV the incomer CT, relay box and control line in the connection board; HV the meter,
    /// CT/VT, relay box and HV bus (B4's crop).
    public var zeroExportBox: Box? = nil
    public var width: Double { sketch.width }
    public var height: Double { sketch.height }
}

public enum SingleLineLayout {
    public static let width = 1560.0

    public static let ink = RGBA(hex: 0x2B2B2B), red = RGBA(hex: 0xD9453B), amber = RGBA(hex: 0xB7791F), green = RGBA(hex: 0x2E7D4F)
    public static let blue = RGBA(hex: 0x1F4E8C), grey = RGBA(hex: 0x6B7280), pole = RGBA(hex: 0x9CA3AF)

    static func color(_ s: SLStatus) -> RGBA {
        switch s {
        case .known: return ink
        case .missing: return red
        case .assumed: return grey
        case .new: return blue
        case .condition(let c): return c == .good ? green : c == .fair ? amber : red
        }
    }

    public static func draw(_ m: SingleLine) -> SingleLineDrawing {
        var d = Drawer(m: m)
        return d.run()
    }
}

private struct Drawer {
    let m: SingleLine
    var o: [DrawOp] = []
    var hits: [SLHit] = []
    var midX = 780.0
    var ftsBox: Box?
    var zeroExportBox: Box?
    typealias L = SingleLineLayout
    var ink: RGBA { L.ink }

    init(m: SingleLine) { self.m = m }

    // MARK: primitives

    mutating func add(_ ops: [DrawOp]) { o += ops }
    mutating func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ c: RGBA = L.ink, w: Double = 2, dash: [Double] = []) {
        o.append(.line(Pt(x1, y1), Pt(x2, y2), width: w, color: c, dash: dash))
    }
    /// Dashed blue control line (design: 1.5 wide, 5 4).
    mutating func control(_ pts: [(Double, Double)]) {
        for (a, b) in zip(pts, pts.dropFirst()) { line(a.0, a.1, b.0, b.1, L.blue, w: 1.5, dash: [5, 4]) }
    }
    mutating func text(_ s: String, _ x: Double, _ y: Double, size: Double = 12, bold: Bool = false, _ c: RGBA = L.ink, align: TextAlign = .left, angle: Double = 0) {
        o.append(.text(s, at: Pt(x, y), size: size, bold: bold, color: c, align: align, angle: angle))
    }
    static func isCondition(_ s: SLStatus) -> Bool { if case .condition = s { return true }; return false }
    mutating func text(_ t: SLText, _ x: Double, _ y: Double, size: Double = 12, align: TextAlign = .left) {
        text(t.text, x, y, size: size, bold: t.bold || Self.isCondition(t.status), L.color(t.status), align: align)
    }
    mutating func dashedRect(_ b: Box, _ c: RGBA, w: Double = 1.2, dash: [Double] = [10, 5]) {
        line(b.x, b.y, b.maxX, b.y, c, w: w, dash: dash); line(b.maxX, b.y, b.maxX, b.maxY, c, w: w, dash: dash)
        line(b.maxX, b.maxY, b.x, b.maxY, c, w: w, dash: dash); line(b.x, b.maxY, b.x, b.y, c, w: w, dash: dash)
    }
    mutating func dot(_ x: Double, _ y: Double, r: Double = 3.5, _ c: RGBA = L.ink) { o.append(.circle(Pt(x, y), r: r, stroke: nil, fill: c)) }
    mutating func hit(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ t: SLTarget) { hits.append(SLHit(box: Box(x, y, w, h), target: t)) }

    /// Shortens a label so it stays in its column.
    func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }

    /// Text lines beside a breaker: type, AT (underlined), AF, IC, brand, condition, note.
    mutating func stack(_ b: SLBreaker, x: Double, y: Double) {
        var yy = y
        text(b.type, x, yy); yy += 18
        text(b.at, x, yy)
        line(x, yy + 5, x + 46, yy + 5, L.color(b.at.status), w: 1)
        yy += 20
        text(b.af, x, yy); yy += 18
        text(b.ic, x, yy); yy += 18
        if b.brand.status == .missing { text(b.brand, x, yy) } else { text(b.brand.text, x, yy, L.grey) }
        yy += 18
        if let c = b.condition { text(c, x, yy); yy += 18 }
        if let n = b.note { text(n, x, yy) }
    }

    // MARK: run

    mutating func run() -> SingleLineDrawing {
        let n = max(m.transformers.count, 1)
        let hv = m.zeroExportHV
        // transformers spread evenly from 240; the last keeps room for its nameplate text
        let step = n == 1 ? 0.0 : min(320.0, 1060.0 / Double(n - 1))
        let first = n == 1 ? 500.0 : 240.0
        func cx(_ i: Int) -> Double { first + step * Double(i) }
        let busY = 250.0
        let mid = (cx(0) + cx(n - 1)) / 2
        midX = mid

        // --- PEA line, tap, meter
        line(40, 60, 1520, 60)
        for x in [110.0, 1080.0, 1470.0] { o.append(SLSymbols.pole(x: x, y: 60)) }
        for x in [260.0, 560.0, 1240.0] { add(SLSymbols.lineBreak(x: x)) }
        text(m.sourceLabel, 430, 48, size: 13, bold: true, align: .center)
        add(SLSymbols.openSwitch(x: mid, y: 60))
        text(m.protection, mid + 18, 95)
        o.append(SLSymbols.pole(x: mid, y: 107))
        add(SLSymbols.meter(x: mid, y: 140))
        line(mid, 112, mid, 126)
        for (k, t) in m.meter.enumerated() { text(t, mid + 24, 132 + Double(k) * 18) }
        hit(mid - 20, 120, 330, 62, SLTarget(.electrical))
        if hv {
            // HV zero export: CT/VT in the line under the meter, relay box on the left, dashed control line
            line(mid, 154, mid, 178); add(SLSymbols.ct(x: mid, y: 192)); line(mid, 206, mid, busY)
            text("CT/VT แรงสูง (ใหม่)", mid + 22, 196, size: 12, L.blue)
            o.append(.rect(Box(80, 172, 210, 44), stroke: L.blue, fill: .white, width: 2))
            text("รีเลย์กันย้อน แรงสูง", 185, 191, size: 13, bold: true, L.blue, align: .center)
            text("\(m.pole == "เสาเดิม" ? "เสาเดิม" : "เสาใหม่") (B4)", 185, 208, size: 11, L.blue, align: .center)
            control([(290, 190), (mid - 14, 190)])
            hit(80, 172, 210, 44, .module(.backfeed))
            zeroExportBox = Box(60, 30, max(mid + 260, 700) - 60, 380)
        } else {
            line(mid, 154, mid, busY)
        }

        // --- HV bus
        line(min(cx(0), mid), busY, max(cx(n - 1), mid), busY)
        dot(mid, busY)

        // --- transformers
        let forkY = 520.0
        let frameTop = 540.0, pitch = 230.0
        let connT = m.connection.trafo, connB = m.connection.board
        var maxRows = 0
        for tx in m.transformers {
            let x = cx(tx.index)
            add(SLSymbols.hvSwitch(x: x, y: busY))
            line(x, busY + 40, x, 318)
            // lightning arrester: drawn when present, `LA ?` when not answered
            if tx.hasLA != false {
                line(x, 300, x - 60, 300)
                if tx.hasLA == true {
                    add(SLSymbols.arrester(x: x - 60))
                    text("LA", x - 86, 350, size: 11, L.grey)
                } else {
                    line(x - 60, 300, x - 60, 310)
                    text("LA ?", x - 86, 330, size: 11, bold: true, L.red)
                }
            }
            add(SLSymbols.cableTerminations(x: x))
            add(SLSymbols.transformer(x: x))
            for (k, t) in tx.lines.enumerated() {
                let s = SLText(clip(t.text, 34), t.status, bold: t.bold)
                text(s, x + 30, k == 0 ? 366 : 388 + Double(k - 1) * 18, size: k == 0 ? 13 : 12)
            }
            hit(x - 70, 300, 70 + min(step == 0 ? 230 : step - 30, 230), 170, tx.target)

            // LV side: cable, trunk down to the boards (the connection transformer also forks left to the PV board)
            let isConnT = tx.index == connT
            let others = tx.boards.filter { !(isConnT && $0.index == connB) }
            maxRows = max(maxRows, others.count)
            // one board on its own takes the trunk straight down; several branch off it
            let direct = others.count == 1 && !isConnT
            let fx = direct ? x : x + (isConnT ? 80 : 40)
            let lastStub = others.isEmpty ? forkY : frameTop + Double(others.count - 1) * pitch - 20
            line(x, 414, x, direct ? frameTop + 50 : max(forkY, lastStub))
            text(tx.cable.text, x - 12, 470, size: 11, L.color(tx.cable.status), align: .center, angle: -90)
            if isConnT && !others.isEmpty { line(x, forkY, fx, forkY, w: 3) }
            for (j, bd) in others.enumerated() { board(bd, fx: fx, trunk: x, top: frameTop + Double(j) * pitch, direct: direct, tx: tx) }
        }

        // --- connection board
        let C = max(820.0, frameTop + 200 + Double(max(maxRows, 1) - 1) * pitch + 80)
        connection(C: C, colX: cx(connT), forkY: forkY, hasOthers: maxRows > 0)

        let h = C + 660
        o.insert(.rect(Box(0, 0, L.width, h), stroke: nil, fill: .white), at: 0)
        return SingleLineDrawing(sketch: Sketch(width: L.width, height: h, ops: o), hits: hits, ftsBox: ftsBox, zeroExportBox: zeroExportBox)
    }

    // MARK: a board under a transformer

    /// Dashed frame 180 × 200; the feeder runs down at `fx` (frame.x + 20) to an arrow.
    mutating func board(_ bd: SLBoard, fx: Double, trunk: Double, top: Double, direct: Bool, tx: SLTransformer) {
        dashedRect(Box(fx - 20, top, 180, 200), L.ink)
        if !direct { line(trunk, top - 20, fx, top - 20); line(fx, top - 20, fx, top + 50) }
        text(clip(bd.name, 16), fx + 10, top + 20, size: 13, bold: true)
        line(fx, top + 50, fx, top + 200)
        add(SLSymbols.breaker(x: fx, y: top + 50))
        stack(bd.main, x: fx + 16, y: top + 60)
        o.append(.polygon([Pt(fx - 6, top + 200), Pt(fx + 6, top + 200), Pt(fx, top + 211)], stroke: nil, fill: L.ink))
        text(clip("ปลายสาย TX\(tx.index + 1)" + (bd.location.isEmpty ? "" : " · " + bd.location), 28), fx + 14, top + 212, size: 11, L.grey)
        hit(fx - 20, top, 180, 200, bd.target)
        hit(fx - 20, top + 40, 180, 130, bd.main.target)
    }

    // MARK: the PV connection board

    mutating func connection(C: Double, colX: Double, forkY: Double, hasOthers: Bool) {
        guard let cb = m.connectionBoard, let tx = m.transformers[safe: m.connection.trafo] else { return }
        let hv = m.zeroExportHV
        let inX = min(max(colX - 100, 200.0), 700.0)
        let outX0 = inX + 160
        let pvX = min(max(1180.0, outX0 + Double(cb.breakers.count) * 150 + 40), 1330)
        let busY = C + 200
        let relayX = max(700.0, inX + 240)

        // frame and title
        dashedRect(Box(60, C, 1440, 360), L.ink)
        text("\(cb.name) (TX\(tx.index + 1))" + (cb.location.isEmpty ? "" : " · " + cb.location), inX + 26, C + 20, size: 14, bold: true)
        text("LV 230/400 V · 3P 4W", 1484, C + 20, size: 12, L.grey, align: .right)
        hit(60, C, 600, 34, cb.target)

        // feeder from the transformer: fork, then the incomer with its draw-out main breaker
        line(colX, forkY, inX, forkY, w: 3)
        line(inX, forkY, inX, C + 42)
        text("สาย LV จาก TX\(tx.index + 1) · ขนาด ? (A3)", inX - 18, (forkY + C) / 2, size: 11, L.red, align: .center, angle: -90)
        add(SLSymbols.breaker(x: inX, y: C + 52, drawout: true))
        stack(cb.main, x: inX + 18, y: C + 56)
        hit(inX - 12, C + 40, 200, 150, cb.main.target)
        line(inX, C + 102, inX, hv ? busY : C + 160)

        // zero export on the low-voltage side: CT in the incomer, relay box, dashed links
        if !hv {
            add(SLSymbols.ct(x: inX, y: C + 174))
            line(inX, C + 188, inX, busY)
            text("CT กันย้อน (ใหม่)", inX - 110, C + 178, size: 12, L.blue)
            o.append(.rect(Box(relayX, C + 40, 200, 46), stroke: L.blue, fill: .white, width: 2))
            text("รีเลย์กันย้อน แรงต่ำ", relayX + 100, C + 60, size: 13, bold: true, L.blue, align: .center)
            text("Zero export (B4)", relayX + 100, C + 77, size: 11, L.blue, align: .center)
            control([(inX + 14, C + 174), (relayX + 60, C + 174), (relayX + 60, C + 86)])
            hit(relayX, C + 40, 200, 46, .module(.backfeed))
            zeroExportBox = Box(inX - 120, C - 40, relayX + 240 - (inX - 120), 340)
        }

        // main bus
        let n = cb.breakers.count
        let space = n == 0 ? 160 : max(130, min(160, (pvX - 40 - outX0) / Double(n)))
        line(inX, busY, pvX, busY, w: 5)
        dot(inX, busY, r: 4)
        let at = cb.main.at.isMissing ? "?" : cb.main.at.text.replacingOccurrences(of: "AT", with: "")
        let lastOut = n == 0 ? inX : outX0 + Double(n - 1) * space
        text("MAIN BUS \(at) A, 3Ø 4W, 400/230 V", (lastOut + pvX) / 2 + 10, busY - 8, size: 11, bold: true, align: .center)

        // outgoing breakers with their load blocks
        for (k, br) in cb.breakers.enumerated() {
            let x = outX0 + Double(k) * space
            dot(x, busY, r: 4)
            text("\(k + 1)", x, busY - 8, size: 12, align: .center)
            line(x, busY, x, busY + 14); line(x, busY + 50, x, busY + 220)
            add(SLSymbols.breaker(x: x, y: busY + 14))
            stack(br, x: x + 16, y: busY + 24)
            o.append(SLSymbols.load(x: x, y: busY + 220))
            for (i, t) in br.destination.enumerated() {
                text(SLText(clip(t.text, 18), t.status, bold: t.bold), x, busY + 256 + [0.0, 16, 34][min(i, 2)], size: i == 2 ? 11 : 12, align: .center)
            }
            hit(x - 20, busY + 6, space - 4, 250, br.target)
        }

        // PV breaker at the end of the bus
        let pv = m.pv
        dot(pvX, busY, r: 4, L.blue)
        text("PV", pvX, busY - 8, size: 12, bold: true, L.blue, align: .center)
        line(pvX, busY, pvX, busY + 14, L.blue); line(pvX, busY + 50, pvX, C + 410, L.blue)
        add(SLSymbols.breaker(x: pvX, y: busY + 14, color: L.blue))
        let tot = pv.totalAT.map { "\($0)" } ?? "?"
        let pvc = pv.totalAT == nil ? L.red : L.blue
        text("MCCB,3P", pvX - 110, busY + 24, size: 12, L.blue)
        text("\(tot)AT", pvX - 110, busY + 42, size: 12, pvc)
        line(pvX - 110, busY + 47, pvX - 64, busY + 47, pvc, w: 1)
        text("\(tot)AF", pvX - 110, busY + 62, size: 12, pvc)
        text(pv.requiredIC.map { "IC ≥ \($0) kA (ใหม่)" } ?? "IC ≥ ? kA (ใหม่)", pvX - 110, busY + 80, size: 12, pv.requiredIC == nil ? L.red : L.blue)
        hit(pvX - 116, busY + 6, 130, 100, .module(.inverter))

        // SMDB-PV and one column per inverter (at most 3 drawn)
        let smdbY = C + 410
        text(pv.mainCable ?? "CV ?", pvX + 14, C + 332, size: 10, L.blue, align: .center, angle: -90)
        let cols = min(pv.inverterCount ?? 1, 3)
        let colStep = 90.0
        let invX0 = pvX - 40
        let lastX = invX0 + Double(cols - 1) * colStep
        line(pvX - 100, smdbY, lastX + 60, smdbY, L.blue, w: 5)
        text("SMDB-PV (ใหม่)", pvX - 124, smdbY + 2, size: 13, bold: true, L.blue, align: .right)
        for i in 0..<cols {
            let x = invX0 + Double(i) * colStep
            line(x, smdbY, x, smdbY + 12, L.blue)
            add(SLSymbols.breaker(x: x, y: smdbY + 12, color: L.blue))
            line(x, smdbY + 48, x, smdbY + 60, L.blue)
            add(SLSymbols.inverter(x: x, y: smdbY + 60))
            add(SLSymbols.dcDisconnect(x: x, y: smdbY + 96))
            add(SLSymbols.pvArray(x: x, y: smdbY + 150))
        }
        if (pv.inverterCount ?? 0) > cols { text("… × \(pv.inverterCount!)", lastX + 50, smdbY + 80, size: 12, bold: true, L.blue) }
        let brT = pv.inverterAT.map { "\($0)" } ?? "?"
        let brC = pv.inverterAT == nil ? L.red : L.blue
        text("3P", lastX + 16, smdbY + 30, size: 11, L.blue)
        text("\(brT)AT", lastX + 40, smdbY + 24, size: 12, brC)
        line(lastX + 38, smdbY + 30, lastX + 82, smdbY + 30, brC, w: 1)
        text("\(brT)AF", lastX + 40, smdbY + 44, size: 12, brC)
        text(pv.inverterCable ?? "CV ?", invX0 - 28, smdbY + 66, size: 10, L.blue, align: .right)
        let invLabel = pv.inverterCount == nil ? "อินเวอร์เตอร์ ? (B2)" : "อินเวอร์เตอร์ \(pv.inverterSummary) (B2)"
        text(invLabel, invX0 - 60, smdbY + 84, size: 12, pv.inverterCount == nil ? L.red : L.blue, align: .right)
        text("ตู้ FTS ตัดวงจร DC (B5)", invX0 - 60, smdbY + 140, size: 12, L.blue, align: .right)
        let kwp = pv.capacityKWp.map { SingleLine.fmt($0) } ?? "?"
        text("แผง PV รวม \(kwp) kWp (A1)", invX0 - 60, smdbY + 168, size: 12, pv.capacityKWp == nil ? L.red : L.blue, align: .right)
        text("สั่งควบคุมกำลังผลิต", invX0 - 44, smdbY + 106, size: 11, L.blue, align: .right)
        hit(invX0 - 240, smdbY - 6, (lastX - invX0) + 340, 190, .module(.inverter))

        // dashed frame round SMDB-PV and its breakers (design: 264 × 84)
        dashedRect(Box(invX0 - 74, smdbY - 26, (lastX - invX0) + 174, 84), L.blue)

        // control links: zero-export relay → inverters, inverters → emergency button
        let emgX = min(lastX + 110, 1440.0)
        let ctrlY = smdbY + 112
        let ctrlX = emgX + 60
        control([(invX0, ctrlY), (ctrlX, ctrlY)])
        if hv {
            control([(80, 216), (80, C - 40), (1500, C - 40), (1500, ctrlY), (ctrlX, ctrlY)])
        } else {
            control([(relayX + 200, C + 62), (ctrlX, C + 62), (ctrlX, ctrlY)])
        }
        let ey = smdbY + 192
        control([(lastX + 10, smdbY + 124), (emgX, smdbY + 124), (emgX, ey - 12)])
        add(SLSymbols.emergency(x: emgX, y: ey))
        text("ปุ่ม Emergency", emgX, ey + 28, size: 11, L.blue, align: .center)
        hit(emgX - 40, ey - 16, 80, 56, .module(.fts))
        let left = invX0 - 250, right = max(ctrlX, emgX + 50) + 14
        ftsBox = Box(left, smdbY + 56, right - left, ey + 40 - (smdbY + 56))
    }
}
