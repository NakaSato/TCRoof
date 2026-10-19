import Foundation

// MARK: - build

public extension SingleLine {
    /// - Parameter hvOverride: previews the other zero-export side without touching B4.
    static func build(_ job: Job, hvOverride: Bool? = nil) -> SingleLine {
        var b = Builder(job: job, hvOverride: hvOverride)
        return b.build()
    }
}

private func num(_ s: String) -> Double? { NumberInput.value(s) }
private func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
private func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

private struct Builder {
    let job: Job
    let hvOverride: Bool?
    var v: Values { job.values }
    var missing: [SLMissing] = []
    var assumptions: [SLAssumption] = []

    init(job: Job, hvOverride: Bool?) { self.job = job; self.hvOverride = hvOverride }

    mutating func miss(_ id: String, _ label: String, blocking: Bool, _ target: SLTarget) {
        missing.append(SLMissing(id: id, label: label, blocking: blocking, target: target))
    }

    func value(_ s: String, _ unit: String = "") -> SLText { blank(s) ? SLText("?", .missing) : SLText(t(s) + unit) }

    // MARK: breakers and boards

    /// Shows `?` in place of each empty part; `lead` is the breaker type with poles ("MCCB,3P").
    func breaker(type: String, poles: String, at: String, af: String, ic: String, brand: String, condition: String, note: String,
                 id: UUID, trafo: Int, board: Int, isMain: Bool, number: Int, name: String) -> SLBreaker {
        let kind = blank(type) ? "MCCB" : t(type)
        let p = blank(poles) ? "3P" : t(poles)
        let typeText = SLText(kind + "," + p, blank(type) ? .assumed : .known)
        let cond = SLCondition(condition)
        var br = SLBreaker(
            id: id, trafo: trafo, board: board,
            type: typeText,
            at: blank(at) ? SLText("?AT", .missing) : SLText(t(at) + "AT"),
            af: blank(af) ? SLText("?AF", .missing) : SLText(t(af) + "AF"),
            ic: blank(ic) ? SLText("IC ? kA", .missing) : SLText("IC " + t(ic) + " kA"),
            brand: blank(brand) ? SLText("ยี่ห้อ ?", .missing) : SLText(t(brand)))
        br.number = number; br.isMain = isMain; br.name = name
        br.atAmps = num(at); br.icKA = num(ic)
        if let cond { br.condition = SLText("สภาพ: " + t(condition), .condition(cond), bold: true) }
        if !blank(note) { br.note = SLText(t(note), cond.map { .condition($0) } ?? .known) }
        return br
    }

    /// "ตู้ไฟฟ้า โรงสูบน้ำ (B1)" → "โรงสูบน้ำ"; also drops a numbered tag ("(B1.2)").
    static func targetName(_ target: String) -> String {
        target.replacingOccurrences(of: "ตู้ไฟฟ้า", with: "")
            .replacingOccurrences(of: #"\(B1(\.\d+)?\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The load block under an outgoing breaker: the B1 building linked to it (`a3Breaker`), else one whose name or number
    /// the breaker's target mentions (jobs from before the link).
    func loadText(for target: String, breaker id: UUID? = nil) -> [SLText] {
        let sections = job.sectionsByCategory.flatMap(\.sections).filter { $0.module.type == .panel }
        let trimmed = t(target)
        let linked = id.flatMap { id in sections.first { BuildingPanels.BreakerRef($0.module.values.text(BuildingPanels.Key.a3Breaker))?.breaker == id } }
        let match = linked ?? sections.first { s in
            let n = t(s.module.name)
            return (!n.isEmpty && trimmed.contains(n)) || (!trimmed.isEmpty && trimmed.contains("(\(s.number))"))
        }
        let name = linked.map { t($0.module.name).isEmpty ? $0.number : t($0.module.name) } ?? Self.targetName(trimmed)
        var out = [SLText("ตู้ไฟฟ้า", bold: true)]
        out.append(name.isEmpty ? SLText("?", .missing, bold: true) : SLText(name, bold: true))
        if let m = match?.module {
            let kw = t(m.values.text("loadKW")), time = t(m.values.text("loadTime"))
            out.append(kw.isEmpty ? SLText("โหลด ? (B1)", .missing) : SLText("โหลด \(kw) kW" + (time.isEmpty ? "" : " @\(time)")))
        } else {
            out.append(SLText("โหลด ? (B1)", .missing))
        }
        return out
    }

    // MARK: build

    mutating func build() -> SingleLine {
        let trafos = v.transformers("trafos")
        let b4 = job.sectionsByCategory.flatMap(\.sections).first { $0.module.type == .backfeed }?.module
        let hv = hvOverride ?? (b4?.values.choice("level") == "กันย้อนที่แรงสูง")
        let pole = b4?.values.choice("pole") ?? "เสาใหม่"

        // connection point
        let connT = min(max(Int(v.text("sldTransformer")) ?? 0, 0), max(trafos.count - 1, 0))
        let connBoards = trafos[safe: connT]?.resolvedBoards ?? []
        let connB = connBoards.firstIndex { $0.id.uuidString == v.text("sldBoard") } ?? 0

        // transformers
        var sl: [SLTransformer] = []
        for (i, tr) in trafos.enumerated() { sl.append(transformer(tr, i, connection: (connT, connB))) }

        // short circuit at the connection bus
        let ct = sl[safe: connT]
        var zAssumed = false
        var isc: Double?
        if let ct, let kva = ct.kva {
            var z = ct.zPercent
            if z == nil { z = SLConstants.defaultZPercent; zAssumed = true }
            isc = SingleLine.shortCircuit(kva: kva, zPercent: z!)
        }
        if zAssumed { assumptions.append(SLAssumption(id: "z", text: "%Z ของ TX\(connT + 1) ไม่มีข้อมูล ใช้ \(SingleLine.fmt(SLConstants.defaultZPercent)) % คำนวณกระแสลัดวงจร")) }
        if isc != nil { assumptions.append(SLAssumption(id: "isc", text: "Isc = S / (√3 × 400 V × Z) · แหล่งจ่ายแรงสูงไม่จำกัด ไม่นับอิมพีแดนซ์สาย")) }

        // PV side
        let pv = pvBranch(isc: isc, connT: connT)

        // missing items of the boards
        collectBoardMissing(sl, connection: (connT, connB))

        // breaker check on the connection bus
        var checks: [SLCheck] = []
        if let board = sl[safe: connT]?.boards[safe: connB] {
            let bn = board.name
            checks.append(SLCheck(id: board.main.id.uuidString, name: "\(bn) \(board.main.type.text.split(separator: ",").first ?? "") เมน",
                                  icKA: board.main.icKA, state: SingleLine.classify(ic: board.main.icKA, isc: isc), target: board.main.target))
            for br in board.breakers {
                checks.append(SLCheck(id: br.id.uuidString, name: "CB\(br.number) \(br.name)".trimmingCharacters(in: .whitespaces),
                                      icKA: br.icKA, state: SingleLine.classify(ic: br.icKA, isc: isc), target: br.target))
            }
        }

        // flood
        var flood: SLFlood?
        let fr = job.floodCheck
        if fr.state == .flooded || fr.state == .unknownFetched {
            let year = t(v.text("floodYear"))
            let when = fr.state == .flooded ? (year.isEmpty ? "" : " (ปี \(year))") : " (ประเมิน GISTDA)"
            flood = SLFlood(text: "\(fr.mdbName) น้ำเคยเข้า \(Int(fr.level)) ซม.\(when) · ตู้ SMDB-PV และรีเลย์กันย้อนต้องสูง ≥ \(fr.minCm) ซม.",
                            minCm: fr.minCm, levelCm: Int(fr.level))
        }

        // conditions
        var bad = 0, fair = 0
        func count(_ c: String) { switch SLCondition(c) { case .bad?: bad += 1; case .fair?: fair += 1; default: break } }
        for tr in trafos { count(tr.condition); for bd in tr.resolvedBoards { count(bd.condition); for br in bd.breakers { count(br.condition) } } }

        // source
        let kv = t(v.choice("meterKV") ?? v.text("meterKV"))
        let phase = t(v.choice("meterPhase") ?? v.text("meterPhase"))
        let kvText = kv.isEmpty ? "?" : kv
        let sourceLabel = "ระบบจำหน่าย กฟภ. \(kvText) kV, 3Ø 3W, 50 Hz"
        let meterNo = t(v.text("meterNo")), ca = t(v.text("meterCA")), rate = t(v.text("meterRate")), ctv = t(v.text("meterCT"))
        let meter = [
            SLText("PEA METER " + (meterNo.isEmpty ? "?" : meterNo), meterNo.isEmpty ? .missing : .known, bold: true),
            SLText("CA \(ca.isEmpty ? "?" : ca) · อัตรา \(rate.isEmpty ? "?" : rate)", ca.isEmpty || rate.isEmpty ? .missing : .known),
            SLText("รับไฟ \(kvText) kV \(phase.isEmpty ? "?" : phase) · CT \(ctv.isEmpty ? "?" : ctv) A", kv.isEmpty || phase.isEmpty || ctv.isEmpty ? .missing : .known),
        ]
        if meterNo.isEmpty { miss("meter", "มิเตอร์: หมายเลข", blocking: false, SLTarget(.electrical)) }
        let protections = Set(trafos.map { t($0.hvProtection) }.filter { !$0.isEmpty })
        let protection = protections.count == 1 ? SLText(protections.first!) : SLText("Drop Out Fuse / Disconnecting Switch")

        let pn = t(v.text("projectName")), doc = t(v.text("docNo"))
        var out = SingleLine(sourceLabel: sourceLabel, meter: meter, protection: protection, zeroExportHV: hv, hasB4: b4 != nil, pole: pole,
                             transformers: sl, connection: (connT, connB), pv: pv, isc: isc, iscAssumedZ: zAssumed, checks: checks,
                             missing: missing, assumptions: assumptions, flood: flood, conditionCounts: (bad, fair),
                             projectLine: [pn, doc.isEmpty ? nil : "NO.\(doc)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
        out.protectionKind = protections.count == 1 ? protections.first! : ""
        out.hasB5 = job.modules.contains { $0.type == .fts }
        return out
    }

    // MARK: transformer

    mutating func transformer(_ tr: Transformer, _ i: Int, connection: (Int, Int)) -> SLTransformer {
        let n = i + 1
        let kind = tr.type == "oil" ? " OIL IMMERSED" : tr.type == "dry" ? " DRY TYPE" : ""
        let fields = [tr.type, tr.voltage, tr.vectorGroup, tr.impedance, tr.brand, tr.serial, tr.year]
        let missingCount = fields.filter(blank).count
        let collapsed = missingCount * 2 > fields.count
        var lines = [SLText("TX\(n)" + kind, bold: true)]
        let kva = num(tr.kva)
        if collapsed {
            lines.append(blank(tr.kva) ? SLText("? kVA", .missing) : SLText(t(tr.kva) + " kVA"))
            lines.append(SLText("ป้ายพิกัดยังไม่ครบ", .missing))
        } else {
            lines.append(blank(tr.voltage) ? SLText("? V", .missing) : SLText(t(tr.voltage) + " V"))
            let vec = blank(tr.vectorGroup) ? "Vector ?" : t(tr.vectorGroup)
            let z = blank(tr.impedance) ? "?" : t(tr.impedance)
            lines.append(SLText("\(vec), Z=\(z)%", blank(tr.vectorGroup) || blank(tr.impedance) ? .missing : .known))
            lines.append(blank(tr.kva) ? SLText("? kVA", .missing) : SLText(t(tr.kva) + " kVA"))
            let id = "\(blank(tr.brand) ? "" : t(tr.brand) + " · ")SN \(blank(tr.serial) ? "?" : t(tr.serial)) · ปี \(blank(tr.year) ? "?" : t(tr.year))"
            lines.append(SLText(id, blank(tr.serial) || blank(tr.year) ? .missing : .known))
            if let c = SLCondition(tr.condition) {
                lines.append(SLText("สภาพ: " + t(tr.condition) + (blank(tr.conditionNote) ? "" : " — " + t(tr.conditionNote)), .condition(c), bold: true))
            } else {
                lines.append(SLText("สภาพ: ?", .missing, bold: true))
            }
        }

        // boards
        var boards: [SLBoard] = []
        // PV connects to a board even when none is filled in yet, so an empty transformer gets a placeholder main board
        var raw = tr.resolvedBoards
        if raw.isEmpty { var b = Board(isMain: true); b.id = tr.id; raw = [b] }
        for (k, bd) in raw.enumerated() {
            let feed = t(v.text("tr\(i)_feed")), feedLoc = t(v.text("tr\(i)_feedLoc"))
            var name = t(bd.name)
            if name.isEmpty && k == 0 { name = feed }
            if name.isEmpty { name = "MDB\(k + 1)" }
            var loc = t(bd.location)
            if loc.isEmpty && k == 0 { loc = feedLoc }
            let main = breaker(type: bd.mainType, poles: bd.poles, at: bd.at, af: bd.af, ic: bd.icu, brand: bd.brand, condition: bd.condition,
                               note: bd.conditionNote, id: bd.id, trafo: i, board: k, isMain: true, number: 0, name: name)
            var outs: [SLBreaker] = []
            for (j, br) in bd.breakers.enumerated() {
                var o = breaker(type: "MCCB", poles: br.poles, at: br.at, af: br.af, ic: br.ic, brand: br.brand, condition: br.condition,
                                note: "", id: br.id, trafo: i, board: k, isMain: false, number: j + 1,
                                name: BuildingPanels.panel(linkedTo: br.id, in: job).map { BuildingPanels.name($0, in: job) } ?? Self.targetName(t(br.target)))
                o.destination = (i == connection.0 && k == connection.1) ? loadText(for: br.target, breaker: br.id) : []
                outs.append(o)
            }
            boards.append(SLBoard(id: bd.id, trafo: i, index: k, name: name, location: loc, isMain: k == 0, main: main, breakers: outs))
        }
        let z = num(tr.impedance)
        // nameplate gaps: %Z is blocking (handled with the boards), the rest are not
        return SLTransformer(id: tr.id, index: i, lines: lines, collapsed: collapsed, hasLA: tr.hasLA, cable: SLText("สาย ? (A3)", .missing),
                             boards: boards, kva: kva, zPercent: z, protection: t(tr.hvProtection))
    }

    mutating func collectBoardMissing(_ trafos: [SLTransformer], connection: (Int, Int)) {
        let raw = v.transformers("trafos")
        for tx in trafos {
            let n = tx.index + 1
            let r = raw[tx.index]
            // %Z is needed wherever boards are drawn
            if !tx.boards.isEmpty && blank(r.impedance) {
                miss("z\(tx.index)", "TX\(n): %Z (ดวงจรฝั่ง \(tx.boards.first?.name ?? "MDB"))", blocking: true, tx.target)
            }
            var other: [String] = []
            if blank(r.kva) { other.append("kVA") }
            if blank(r.type) { other.append("ชนิด") }
            if blank(r.voltage) { other.append("แรงดัน") }
            if blank(r.vectorGroup) { other.append("Vector") }
            if blank(r.brand) { other.append("ยี่ห้อ") }
            if blank(r.serial) { other.append("SN") }
            if blank(r.year) { other.append("ปี") }
            if SLCondition(r.condition) == nil { other.append("สภาพ") }
            if r.hasLA == nil { other.append("LA") }
            if !other.isEmpty { miss("tx\(tx.index)", "TX\(n): " + other.joined(separator: ", "), blocking: false, tx.target) }

            for bd in tx.boards {
                let onConn = tx.index == connection.0 && bd.index == connection.1
                var mainGaps: [String] = []
                if bd.main.at.isMissing { mainGaps.append("AT") }
                if bd.main.icKA == nil { mainGaps.append("IC kA") }
                if !mainGaps.isEmpty {
                    miss("m\(bd.id)", "\(bd.name) เมนเบรกเกอร์: " + mainGaps.joined(separator: ", "), blocking: onConn, bd.main.target)
                }
                for br in bd.breakers {
                    var gaps: [String] = []
                    if br.ic.isMissing { gaps.append("IC kA") }
                    if br.af.isMissing { gaps.append("AF") }
                    if br.brand.isMissing { gaps.append("ยี่ห้อ") }
                    if !gaps.isEmpty { miss("b\(br.id)", "\(bd.name) CB\(br.number): " + gaps.joined(separator: ", "), blocking: onConn, br.target) }
                    if onConn, br.destination.contains(where: { $0.isMissing && $0.text.contains("B1") }) {
                        miss("l\(br.id)", "โหลด CB\(br.number) \(br.name) (B1)", blocking: false, SLTarget(.module(.panel)))
                    }
                }
            }
        }
    }

    // MARK: PV

    mutating func pvBranch(isc: Double?, connT: Int) -> SLPV {
        var pv = SLPV()
        let sections = job.sectionsByCategory.flatMap(\.sections)
        let cap = v.number("capacity")
        pv.capacityKWp = (cap ?? 0) > 0 ? cap : nil
        let invSections = sections.filter { $0.module.type == .inverter }
        let count = invSections.reduce(0) { $0 + Int($1.module.values.number("inverterCount") ?? 0) }
        pv.inverterCount = count > 0 ? count : nil

        if pv.capacityKWp == nil { miss("capacity", "A1 กำลังผลิตติดตั้ง (kWp)", blocking: true, .info) }
        if pv.inverterCount == nil { miss("invCount", "B2 จำนวนอินเวอร์เตอร์", blocking: true, .module(.inverter)) }

        let capT = pv.capacityKWp.map { SLText(SingleLine.fmt($0) + " kWp", .new) } ?? SLText("?", .missing)
        var rows: [SLRow] = [SLRow(label: "PV", value: capT)]
        // B2 sizes (every B2 section with inverters must have them): catalog Imax, B2 breakers and the B2 feeder
        let stations = invSections.filter { ($0.module.values.number("inverterCount") ?? 0) > 0 }.map { InverterStation($0.module.values) }
        let picked = !stations.isEmpty && stations.allSatisfy { !$0.sizesAssumed } ? stations.flatMap(\.sizes) : []
        if let n = pv.inverterCount, !picked.isEmpty, picked.count == n {
            let all = InverterStation(sizes: picked), fd = all.feeder
            let ats = picked.map { all.breaker(kw: $0).at }
            pv.inverterSizes = picked
            pv.inverterKW = Set(picked).count == 1 ? Double(picked[0]) : nil
            pv.inverterAT = ats.max()
            pv.totalAT = fd.at
            pv.inverterCable = Set(ats).count == 1 ? InverterStation.cable(at: ats[0]).label : ats.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.map { InverterStation.cable(at: $0).label }.joined(separator: " / ")
            pv.mainCable = fd.label
            pv.busbar = SingleLine.busbar(forAT: fd.at)
            pv.cableRuns = n + 1
            pv.totalCableM = pv.cableRuns * SLConstants.cableRunM
            if let isc { pv.requiredIC = SingleLine.requiredIC(isc: isc) }
            assumptions.append(SLAssumption(id: "length", text: "ระยะสาย AC \(SLConstants.cableRunM) ม./เส้น × \(pv.cableRuns) เส้น = \(pv.totalCableM) ม. (ไม่มีข้อมูลระยะจริง)"))
            let icText = pv.requiredIC.map { " · IC ≥ \($0) kA" } ?? " · IC ≥ ? kA"
            rows += [SLRow(label: "อินเวอร์เตอร์", value: SLText(pv.inverterSummary, .new)),
                     SLRow(label: "เบรกเกอร์อินเวอร์เตอร์", value: SLText(all.breakerSummary, .new)),
                     SLRow(label: "เบรกเกอร์ PV รวม", value: SLText("\(fd.at) AT" + icText, pv.requiredIC == nil ? .missing : .new)),
                     SLRow(label: "ราง AC (SMDB-PV)", value: SLText("ทองแดง \(pv.busbar!) มม.", .new)),
                     SLRow(label: "สาย AC อินเวอร์เตอร์", value: SLText(pv.inverterCable! + " มม²", .new)),
                     SLRow(label: "สาย AC → \(job.mainBoardName)", value: SLText(fd.label + " มม²", .new))]
        } else if let kwp = pv.capacityKWp, let n = pv.inverterCount {
            let kw = SingleLine.standardInverter(kwp / Double(n))
            pv.inverterKW = kw
            let at = SingleLine.breakerAT(kw: kw), total = SingleLine.breakerAT(kw: kw * Double(n))
            pv.inverterAT = at; pv.totalAT = total
            pv.inverterCable = SingleLine.cable(forAT: at)
            pv.mainCable = SingleLine.cable(forAT: total)
            pv.busbar = SingleLine.busbar(forAT: total)
            pv.cableRuns = n + 1
            pv.totalCableM = pv.cableRuns * SLConstants.cableRunM
            if let isc { pv.requiredIC = SingleLine.requiredIC(isc: isc) }
            assumptions.append(SLAssumption(id: "invKW", text: "กำลังอินเวอร์เตอร์ \(SingleLine.fmt(kw)) kW/เครื่อง = A1 ÷ B2 ปัดเป็นขนาดมาตรฐาน (B2 ยังไม่มีช่อง kW)"))
            assumptions.append(SLAssumption(id: "sizes", text: "สาย/ราง ตามตาราง CV 0.6/1 kV ร้อยท่อ (เบรกเกอร์ = I × 1.25 ตามเกณฑ์ทีม)"))
            assumptions.append(SLAssumption(id: "length", text: "ระยะสาย AC \(SLConstants.cableRunM) ม./เส้น × \(pv.cableRuns) เส้น = \(pv.totalCableM) ม. (ไม่มีข้อมูลระยะจริง)"))
            let icText = pv.requiredIC.map { " · IC ≥ \($0) kA" } ?? " · IC ≥ ? kA"
            rows += [SLRow(label: "อินเวอร์เตอร์", value: SLText("\(n) × \(SingleLine.fmt(kw)) kW", .new)),
                     SLRow(label: "เบรกเกอร์อินเวอร์เตอร์", value: SLText("\(at) AT × \(n)", .new)),
                     SLRow(label: "เบรกเกอร์ PV รวม", value: SLText("\(total) AT" + icText, pv.requiredIC == nil ? .missing : .new)),
                     SLRow(label: "ราง AC (SMDB-PV)", value: SLText("ทองแดง \(pv.busbar!) มม.", .new)),
                     SLRow(label: "สาย AC อินเวอร์เตอร์", value: SLText(pv.inverterCable! + " มม²", .new)),
                     SLRow(label: "สาย AC → \(job.mainBoardName)", value: SLText(pv.mainCable! + " มม²", .new))]
        } else {
            for l in ["อินเวอร์เตอร์", "เบรกเกอร์อินเวอร์เตอร์", "เบรกเกอร์ PV รวม", "ราง AC (SMDB-PV)", "สาย AC อินเวอร์เตอร์", "สาย AC → \(job.mainBoardName)"] {
                rows.append(SLRow(label: l, value: SLText("?", .missing)))
            }
        }
        pv.rows = rows
        return pv
    }
}
