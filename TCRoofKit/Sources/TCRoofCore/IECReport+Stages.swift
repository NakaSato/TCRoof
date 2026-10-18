import Foundation

/// The 7 steps of the IEC 62446 test (the board `iPadIECStep1–7`, docs/ui/iec62446-step1-setup-ipad): whether each is
/// done and what it still lacks (derived, never stored), who confirmed it and when (stored, valid only while the step's
/// values are as they were), the files exported, and the closing result that locks the test.
public extension IECReport {
    enum Stage: Int, CaseIterable, Codable, Sendable, Identifiable {
        case setup = 1, beforeVoltage, beforeInsulation, afterVoltage, energy, thermal, review
        public var id: Int { rawValue }

        /// The board's step names.
        public var title: String {
            switch self {
            case .setup: "ตั้งค่าระบบ"
            case .beforeVoltage: "ก่อนออน · แรงดัน / กระแส"
            case .beforeInsulation: "ก่อนออน · ฉนวน (IR)"
            case .afterVoltage: "หลังออน · แรงดัน / กระแส"
            case .energy: "พลังงานและ PR"
            case .thermal: "ภาพถ่ายความร้อน"
            case .review: "ตรวจและส่งออก"
            }
        }
    }

    /// Who confirmed a step and the step's values then (`fingerprint`), so a later change shows it unconfirmed.
    struct StageRecord: Codable, Equatable, Sendable {
        public var confirmedAt: Date
        public var by: String
        public var fingerprint: String
        public init(confirmedAt: Date, by: String, fingerprint: String) { self.confirmedAt = confirmedAt; self.by = by; self.fingerprint = fingerprint }
    }

    struct ExportRecord: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case excel, word }
        public var kind: Kind
        public var name: String
        public var at: Date
        /// The whole test's values when the file was made.
        public var fingerprint: String
        public init(kind: Kind, name: String, at: Date, fingerprint: String) { self.kind = kind; self.name = name; self.at = at; self.fingerprint = fingerprint }
    }

    /// The closing of the test: when, by whom, each inverter's pass before and after then, and the values it closed on.
    struct TestResult: Codable, Equatable, Sendable {
        public struct Inverter: Codable, Equatable, Sendable {
            public var before: Bool?
            public var after: Bool?
            public init(before: Bool?, after: Bool?) { self.before = before; self.after = after }
        }
        public var completedAt: Date
        public var by: String
        public var inverters: [Inverter]
        public var fingerprint: String
        public init(completedAt: Date, by: String, inverters: [Inverter], fingerprint: String) {
            self.completedAt = completedAt; self.by = by; self.inverters = inverters; self.fingerprint = fingerprint
        }
        /// true when every inverter passed both phases, false when any failed one.
        public var passed: Bool { inverters.allSatisfy { $0.before == true && $0.after == true } }
    }

    /// The contractor's hand-over (`ส่งผลให้ทีม`): who sent the filled test and the values sent. The internal team then
    /// closes it (`complete`) or sends it back (`sendBack`), the same as a daily report the foreman fills and our
    /// engineer signs.
    struct Submission: Codable, Equatable, Sendable {
        public var submittedAt: Date
        public var by: String
        public var fingerprint: String
        public init(submittedAt: Date, by: String, fingerprint: String) { self.submittedAt = submittedAt; self.by = by; self.fingerprint = fingerprint }
    }

    /// The team's answer when it sends a test back: when, who, and what to fix.
    struct SendBack: Codable, Equatable, Sendable {
        public var at: Date
        public var by: String
        public var note: String
        public init(at: Date, by: String, note: String) { self.at = at; self.by = by; self.note = note }
    }

    // MARK: done and missing

    /// What a step still lacks, as the bottom bar and step 7's list say it; empty = done.
    func missing(_ stage: Stage) -> [String] {
        let strings = inverters.flatMap { $0.strings.map(\.value) }
        func short(_ n: Int, _ what: String) -> String? { n > 0 ? "\(what) \(n) สตริง" : nil }
        func photos(_ kinds: [PhotoKind]) -> Int { strings.filter { s in kinds.contains { s.photo($0) == nil } }.count }
        func checks(_ k: KeyPath<Inverter, Check?>) -> Int { inverters.filter { $0[keyPath: k] == nil }.count }
        var out: [String?] = []
        switch stage {
        case .setup:
            if sld == nil { out.append("แบบ SLD") }
            if inverters.isEmpty || strings.isEmpty { out.append("inverter และสตริง") }
            if inverters.contains(where: { $0.ratedKW <= 0 }) { out.append("พิกัด inverter") }
            if module.powerW <= 0 { out.append("กำลังต่อแผง") }
            if testDate == nil { out.append("วันที่ทดสอบ") }
            if tester.trimmingCharacters(in: .whitespaces).isEmpty { out.append("ผู้ทดสอบ") }
            if !instruments.isComplete { out.append("S/N เครื่องมือ") }
        case .beforeVoltage:
            out.append(short(strings.filter { $0.vocV == nil || $0.iBeforeA == nil }.count, "Voc / กระแส"))
            out.append(short(strings.filter { $0.polarityOK == nil }.count, "ขั้วสาย"))
            out.append(short(photos([.voltageBefore, .currentBefore]), "รูปแรงดัน / กระแส"))
            if !before.isComplete { out.append("สภาพการทดสอบก่อนเชื่อมต่อ") }
        case .beforeInsulation:
            out.append(short(strings.filter { $0.irPosMOhm == nil || $0.irNegMOhm == nil }.count, "IR (MΩ)"))
            out.append(short(photos([.insulation]), "รูปเครื่องวัด IR"))
            let n = checks(\.continuity) + checks(\.functionalBefore)
            if n > 0 { out.append("ผลตรวจ Continuity / Inverter \(n) ช่อง") }
        case .afterVoltage:
            out.append(short(strings.filter { $0.vmpV == nil || $0.impA == nil }.count, "Vmp / Imp"))
            out.append(short(photos([.voltageAfter, .currentAfter]), "รูปแรงดัน / กระแส หลังเชื่อมต่อ"))
            if checks(\.functionalAfter) > 0 { out.append("ผลตรวจ Inverter หลังเชื่อมต่อ \(checks(\.functionalAfter)) ช่อง") }
            if !after.isComplete { out.append("สภาพการทดสอบหลังเชื่อมต่อ") }
        case .energy:
            let n = inverters.filter { $0.energy7dKWh == nil }.count
            if n > 0 { out.append("พลังงาน 7 วัน \(n) inverter") }
            if yrKWhM2Day == nil { out.append("ค่าแสงเฉลี่ย (Yr)") }
            if arrayTempC == nil { out.append("Array Temperature") }
            if module.areaM2 == nil { out.append("พื้นที่แผงต่อแผ่น") }
            if irradiancePhoto == nil { out.append("รูปเครื่องวัดแสง") }
        case .thermal:
            if thermalPhotos.isEmpty { out.append("ภาพถ่ายความร้อนอย่างน้อย 1 รูป") }
        case .review:
            let open = Stage.allCases.filter { $0 != .review && !isDone($0) }
            if !open.isEmpty { out.append("ขั้นที่ " + open.map { String($0.rawValue) }.joined(separator: ", ") + " ยังไม่ครบ") }
        }
        return out.compactMap { $0 }
    }

    func isDone(_ stage: Stage) -> Bool { missing(stage).isEmpty }

    /// Confirmed by someone and nothing of the step changed since.
    func isConfirmed(_ stage: Stage) -> Bool { stageRecords[String(stage.rawValue)].map { $0.fingerprint == fingerprint(stage) } ?? false }

    func record(_ stage: Stage) -> StageRecord? { isConfirmed(stage) ? stageRecords[String(stage.rawValue)] : nil }

    /// Marks a done step confirmed; a step that isn't done stays as it is (false).
    @discardableResult
    mutating func confirm(_ stage: Stage, by: String, at: Date = .now) -> Bool {
        guard isDone(stage) else { return false }
        stageRecords[String(stage.rawValue)] = StageRecord(confirmedAt: at, by: by, fingerprint: fingerprint(stage))
        return true
    }

    // MARK: result and lock

    /// Sent to the team (`ส่งผลให้ทีม`) or closed (`ปิดการทดสอบ`): edits are refused until the team sends it back or
    /// reopens it.
    var isLocked: Bool { result != nil || submission != nil }

    /// Sent and waiting for the team to close it or send it back.
    var isAwaitingClose: Bool { submission != nil && result == nil }

    /// What a locked page says instead of its own status line.
    var lockedLine: String? {
        if result != nil { return "ปิดการทดสอบแล้ว · ดูได้อย่างเดียว" }
        if submission != nil { return "ส่งผลให้ทีมแล้ว · รอทีมภายในปิด · ดูได้อย่างเดียว" }
        return nil
    }

    /// `ส่งผลให้ทีม`: the contractor hands the filled test over when steps 1–6 are done, confirming every step in its
    /// name. Clears an earlier send-back.
    @discardableResult
    mutating func submit(by: String, at: Date = .now) -> Bool {
        guard !isLocked, isDone(.review) else { return false }
        for s in Stage.allCases where !isConfirmed(s) { confirm(s, by: by, at: at) }
        submission = Submission(submittedAt: at, by: by, fingerprint: fingerprint(.review))
        sentBack = nil
        return true
    }

    /// The values changed after they were sent (a sync from a device that hadn't seen the hand-over): the team can't
    /// close what it hasn't seen, so it sends it back.
    var submissionIsStale: Bool { submission.map { $0.fingerprint != fingerprint(.review) } ?? false }

    /// `ส่งกลับให้แก้`: the team returns a sent test to the contractor with what to fix; it opens for editing again.
    @discardableResult
    mutating func sendBack(by: String, note: String, at: Date = .now) -> Bool {
        guard isAwaitingClose else { return false }
        submission = nil
        sentBack = SendBack(at: at, by: by, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }

    /// `ปิดการทดสอบ`: the internal team closes a sent test, keeping each inverter's pass. Only this counts in the MP
    /// plan (3.1). A test that wasn't sent, was changed since, or is closed already stays as it is (false).
    @discardableResult
    mutating func complete(by: String, at: Date = .now) -> Bool {
        guard isAwaitingClose, !submissionIsStale, isDone(.review) else { return false }
        for s in Stage.allCases where !isConfirmed(s) { confirm(s, by: by, at: at) }
        result = TestResult(completedAt: at, by: by,
                            inverters: inverters.map { .init(before: passes($0, .before), after: passes($0, .after)) },
                            fingerprint: fingerprint(.review))
        return true
    }

    /// `แก้ไข` on a closed test: back to the contractor's editing, to be sent and closed again.
    mutating func reopen() { result = nil; submission = nil }

    /// Where the hand-over stands, as the job's Firestore document carries it (`iecState`) beside the test, so the
    /// rules can refuse a contractor's edit of a sent or closed test, or a close they made themselves.
    enum LockState: String, Codable, Sendable { case open, sent, closed }

    var lockState: LockState { result != nil ? .closed : submission != nil ? .sent : .open }

    /// The test as it arrives from Firestore with the document's `iecState`: a close the document doesn't record was
    /// never made by the team (only they can set `closed`), so it is dropped. Nil (an app version without the state)
    /// keeps the test as it came.
    func trusting(_ state: LockState?) -> IECReport {
        guard let state, state != .closed, result != nil else { return self }
        var r = self
        r.result = nil
        return r
    }

    /// The values changed after the test was closed (a sync from another device that hadn't seen the lock).
    var resultIsStale: Bool { result.map { $0.fingerprint != fingerprint(.review) } ?? false }

    mutating func recordExport(_ kind: ExportRecord.Kind, name: String, at: Date = .now) {
        exports.append(ExportRecord(kind: kind, name: name, at: at, fingerprint: fingerprint(.review)))
    }

    /// The newest file of a kind, and whether it still has the current values.
    func lastExport(_ kind: ExportRecord.Kind) -> (record: ExportRecord, current: Bool)? {
        exports.last { $0.kind == kind }.map { ($0, $0.fingerprint == fingerprint(.review)) }
    }

    // MARK: fingerprints

    /// A stable digest of the values a step is made of (FNV-1a over their text, the same on every device and run).
    func fingerprint(_ stage: Stage) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in stageText(stage).utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }

    private func stageText(_ stage: Stage) -> String {
        func t(_ v: Any?) -> String { v.map { "\($0)" } ?? "-" }
        func d(_ v: Date?) -> String { v.map { String($0.timeIntervalSinceReferenceDate) } ?? "-" }
        func each(_ f: (Slot) -> [Any?]) -> String {
            inverters.map { inv in inv.slots.map { s in s.map { f($0).map(t).joined(separator: ",") } ?? "_" }.joined(separator: ";") }.joined(separator: "|")
        }
        func cond(_ c: Conditions) -> String { [t(c.ambientC), t(c.irradianceWm2), t(c.time)].joined(separator: ",") }
        switch stage {
        case .setup:
            let invs = inverters.map { inv in
                ([t(inv.ratedKW), inv.serial, t(inv.model), t(inv.mppt)] + InverterPhoto.allCases.map { t(inv.photos[$0.rawValue]) }).joined(separator: ",")
            }.joined(separator: "|")
            let diagram = sld.map { "\($0.name)#\($0.version)" } ?? "-"
            return [stationLine, module.brand, t(module.powerW), d(testDate), tester, instruments.multimeterClamp, instruments.insulationTester,
                    instruments.irradianceMeter, instruments.thermalCamera, invs, diagram, each { [$0.modules, $0.brand, $0.optimizers] }].joined(separator: "\n")
        case .beforeVoltage:
            return [each { [$0.vocV, $0.iBeforeA, $0.polarityOK, $0.photo(.voltageBefore), $0.photo(.currentBefore)] }, cond(before)].joined(separator: "\n")
        case .beforeInsulation:
            let checks = inverters.map { [t($0.continuity?.rawValue), t($0.functionalBefore?.rawValue)].joined(separator: ",") }.joined(separator: "|")
            return [each { [$0.irTestV, $0.irPosMOhm, $0.irNegMOhm, $0.photo(.insulation)] }, checks].joined(separator: "\n")
        case .afterVoltage:
            let checks = inverters.map { t($0.functionalAfter?.rawValue) }.joined(separator: "|")
            return [each { [$0.vmpV, $0.impA, $0.photo(.voltageAfter), $0.photo(.currentAfter)] }, checks, cond(after), d(gridOnAt)].joined(separator: "\n")
        case .energy:
            let invs = inverters.map { [t($0.energy7dKWh), $0.remark].joined(separator: ",") }.joined(separator: "|")
            return [invs, t(yrKWhM2Day), t(arrayTempC), t(module.areaM2), t(irradiancePhoto)].joined(separator: "\n")
        case .thermal:
            return thermalPhotos.map { $0 + "=" + (thermalPlaces[$0] ?? "") }.joined(separator: "|")
        case .review:
            return Stage.allCases.filter { $0 != .review }.map(stageText).joined(separator: "\n#\n")
        }
    }
}

// MARK: - Photo files

public extension IECReport {
    /// The Drive folder of the test's photos, under the job's folder.
    static let photoFolder = ["IEC 62446", "รูปถ่าย"]

    /// Every photo id of the test with its file name, labelled as the Word appendix labels them:
    /// `INV1ST3 ก่อน แรงดัน.jpg`, `ความเข้มแสง.jpg`, `ความร้อน 2 ตู้ DC.jpg`.
    func photoFileNames() -> [String: String] {
        var out: [String: String] = [:]
        let kinds: [(PhotoKind, String)] = [(.voltageBefore, "ก่อน แรงดัน"), (.currentBefore, "ก่อน กระแส"), (.insulation, "ก่อน IR"),
                                            (.voltageAfter, "หลัง แรงดัน"), (.currentAfter, "หลัง กระแส")]
        for (i, inv) in inverters.enumerated() {
            for k in InverterPhoto.allCases { if let id = inv.photos[k.rawValue] { out[id] = "INV\(i + 1) \(k.title.replacingOccurrences(of: " · ", with: " ")).jpg" } }
            for s in inv.strings {
                for (k, text) in kinds { if let id = s.value.photo(k) { out[id] = "\(Self.label(inverter: i + 1, seq: s.seq)) \(text).jpg" } }
            }
        }
        if let id = irradiancePhoto { out[id] = "ความเข้มแสง.jpg" }
        for (n, id) in thermalPhotos.enumerated() {
            out[id] = "ความร้อน \(n + 1)" + (thermalPlaces[id].map { " " + $0 } ?? "") + ".jpg"
        }
        out.merge(installPhotoFileNames()) { a, _ in a }
        return out
    }
}
