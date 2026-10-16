import SwiftUI
import UIKit
import SwiftData
import TCRoofUI
import TCRoofCore

extension IECVIPage {
    /// Strings of the inverter still missing Voc, current or polarity, in slot order.
    func unfinished(_ r: IECReport, _ i: Int) -> [Int] {
        guard r.inverters.indices.contains(i) else { return [] }
        let inv = r.inverters[i]
        return inv.strings.filter { !IECReport.viDone($0.value, phase) }.map(\.slot)
    }

    /// Photo first: a value without its photo opens the camera, then the dialog.
    func open(_ kind: IECVIEntry.Kind, _ s: IECReport.Slot, continuous: IECVIEntry.Continuous? = nil, at target: Int? = nil) {
        let n = target ?? slot
        let photo = kind.photoKind(phase)
        let next = IECVIEntry.Target(slot: n, kind: kind, continuous: continuous)
        if s.photo(photo) == nil { shooting = Shot(slot: n, kind: photo, then: next) } else { entry = next }
    }

    /// `วัดต่อเนื่อง`: the first unfinished string at or after the selected one (then from the start).
    func startContinuous(_ r: IECReport, _ i: Int) {
        let left = unfinished(r, i)
        guard let first = left.first(where: { $0 >= slot }) ?? left.first, let s = r.inverters[i].slots[first - 1] else { return }
        slot = first
        let total = r.inverters[i].strings.count
        open(.voltage, s, continuous: .init(done: total - left.count, total: total), at: first)
    }

    /// A photo came back from the camera (or the stub): kept on the string, then its dialog opens.
    func stored(_ shot: Shot, _ data: Data) {
        let i = inverter
        guard let old = report.inverters[safe: i]?.slots[shot.slot - 1] else { return }
        let id = job.storeIECPhoto(data, replacing: old.photo(shot.kind), context: context)
        job.updateIEC(context) { $0.inverters[i].slots[shot.slot - 1]?.photos[shot.kind.rawValue] = id }
        if let then = shot.then {
            // after the camera's cover has gone, or the dialog would open under it
            Task { try? await Task.sleep(for: .milliseconds(450)); entry = then }
        }
    }

    /// What the stub camera's photo shows: the string's Voc as typed (or its group's median), 0.00 A.
    func stubReading(_ shot: Shot) -> String {
        let r = report
        guard let inv = r.inverters[safe: inverter], let s = inv.slots[shot.slot - 1] else { return "0.0" }
        switch shot.kind {
        case .currentBefore: return "0.00"
        case .currentAfter: return String(format: "%.2f", s.impA ?? 12.5)
        case .voltageAfter:
            // Vmp ≈ 0.815 × Voc, as the board's example
            let v = s.vmpV ?? r.vmpMedians(inv).first { $0.modules == s.modules }?.median ?? (s.vocV ?? Double(s.modules) * 47) * 0.815
            return String(format: "%.1f", v)
        default: break
        }
        let v = s.vocV ?? r.vocMedians(inv).first { $0.modules == s.modules }?.median ?? Double(s.modules) * 47
        return String(format: "%.1f", v)
    }

    // MARK: entry dialog

    @ViewBuilder func entryOverlay(_ r: IECReport) -> some View {
        if let target = entry, let inv = r.inverters[safe: inverter], let s = inv.slots[target.slot - 1] {
            ZStack {
                Theme.navy.opacity(0.45).ignoresSafeArea().onTapGesture { entry = nil }
                IECVIEntry(job: job, phase: phase, report: r, inverter: inverter, slot: s, target: target,
                                 reading: reading(target, s), sample: r.sampleName != nil,
                                 nextLabel: nextLabel(r, target),
                                 save: { v in save(v, target) },
                                 keep: { v in keep(v, target) },
                                 retake: { shooting = Shot(slot: target.slot, kind: target.kind.photoKind(phase), then: target); entry = nil },
                                 close: { entry = nil })
                    .frame(width: 1000)
                    .task(id: s.photo(target.kind.photoKind(phase))) { await read(s.photo(target.kind.photoKind(phase))) }
            }
            .transition(.opacity)
        }
    }

    /// The photo's reading once read; `.some(nil)` = read, nothing found; nil = not read yet.
    func reading(_ target: IECVIEntry.Target, _ s: IECReport.Slot) -> Double? {
        s.photo(target.kind.photoKind(phase)).flatMap { readings[$0] ?? nil }
    }

    func read(_ id: String?) async {
        guard let id, readings[id] == nil, let asset = job.iecPhoto(id), let img = UIImage(data: asset.data) else { return }
        let text = await PlatePhotoReader.text(in: img)
        readings[id] = .some(IECReport.meterReading(in: text))
    }

    /// The pad's `บันทึก` sub label: where it goes next.
    func nextLabel(_ r: IECReport, _ t: IECVIEntry.Target) -> String {
        guard let inv = r.inverters[safe: inverter] else { return "" }
        if t.kind == .voltage { return inv.slots[t.slot - 1]?.photo(IECVIEntry.Kind.current.photoKind(phase)) == nil ? "→ ถ่ายแคลมป์ A" : "→ แคลมป์ A" }
        guard let n = nextSlot(r, after: t) else { return "→ จบ INV\(inverter + 1)" }
        return "→ " + IECReport.label(inverter: inverter + 1, seq: inv.strings.first { $0.slot == n }?.seq ?? 0)
    }

    /// The next string after a current is saved: the next unfinished one in continuous mode, else the next string.
    func nextSlot(_ r: IECReport, after t: IECVIEntry.Target) -> Int? {
        guard let inv = r.inverters[safe: inverter] else { return nil }
        if t.continuous != nil { return unfinished(r, inverter).first { $0 > t.slot } ?? unfinished(r, inverter).first { $0 != t.slot } }
        return inv.strings.first { $0.slot > t.slot }?.slot
    }

    /// A typed value into its field: Voc (and the polarity from its sign) or the current before; Vmp or Imp after.
    func write(_ value: Double, _ t: IECVIEntry.Target, inverter i: Int) {
        let phase = phase
        job.updateIEC(context) { r in
            switch (t.kind, phase) {
            case (.voltage, .before): r.setVoc(value, inverter: i, slot: t.slot)
            case (.current, .before): r.inverters[i].slots[t.slot - 1]?.iBeforeA = value
            case (.voltage, .after): r.inverters[i].slots[t.slot - 1]?.vmpV = value
            case (.current, .after): r.inverters[i].slots[t.slot - 1]?.impA = value
            }
        }
    }

    func keep(_ value: Double, _ t: IECVIEntry.Target) {
        let i = inverter
        write(value, t, inverter: i)
    }

    /// `บันทึก`: V → the clamp's photo → A → the next string's photo, or closes on the last.
    func save(_ value: Double, _ t: IECVIEntry.Target) {
        let i = inverter
        write(value, t, inverter: i)
        let r = report
        guard let s = r.inverters[safe: i]?.slots[t.slot - 1] else { entry = nil; return }
        entry = nil
        if t.kind == .voltage {
            open(.current, s, continuous: t.continuous, at: t.slot)
            return
        }
        guard let n = nextSlot(r, after: t), let next = r.inverters[i].slots[n - 1] else { return }
        slot = n
        let c = t.continuous.map { IECVIEntry.Continuous(done: min($0.done + 1, $0.total), total: $0.total) }
        open(.voltage, next, continuous: c, at: n)
    }

    // MARK: empty slots

    /// `ตั้งช่อง n เป็นว่าง` / `+ มีสตริงในช่อง n`: a string with values or photos is asked about first.
    func toggleEmpty(_ n: Int) {
        let i = inverter
        guard let inv = report.inverters[safe: i] else { return }
        if let s = inv.slots[n - 1] {
            let used = s.vocV != nil || s.iBeforeA != nil || s.vmpV != nil || s.impA != nil || s.irPosMOhm != nil || !s.photos.isEmpty
            if used { confirmEmpty = n } else { setEmpty(n) }
        } else {
            // a new string of the inverter's usual size and the station's panel
            let counts = Dictionary(grouping: inv.strings.map(\.value.modules), by: { $0 }).mapValues(\.count)
            let modules = counts.max { $0.value < $1.value }?.key ?? 0
            let brand = report.module.brand
            job.updateIEC(context) { $0.inverters[i].slots[n - 1] = IECReport.Slot(modules: modules, brand: brand.isEmpty ? nil : brand) }
        }
    }

    func setEmpty(_ n: Int) {
        let i = inverter
        guard let s = report.inverters[safe: i]?.slots[n - 1] else { return }
        for id in s.photos.values { job.removeIECPhoto(id, context: context) }
        job.updateIEC(context) { $0.inverters[i].slots[n - 1] = nil }
        confirmEmpty = nil
    }
}

#if DEBUG
extension IECVIPage {
    /// `-iecStep2State default|inv2|voc|clamp|continuous|fail|empty|todo|differs`: the board's states 01–09 on the
    /// sample `-iecStep2` seeded (the changes go into that sample test).
    static var debugState: String? { UserDefaults.standard.string(forKey: "iecStep2State") }
    /// `-iecStep4State default|vmp|imp|partial|fail|continuous|done|todo|inv2`: step 4's states 01–09.
    static var debugState4: String? { UserDefaults.standard.string(forKey: "iecStep4State") }

    func applyDebugState() {
        guard !debugApplied else { return }
        if phase == .after { applyStep4Debug(); return }
        guard let state = Self.debugState else { return }
        debugApplied = true
        let clearLast = { (job: Job, context: ModelContext) in
            // INV1ST14–16 (slots 15, 17, 19) not measured yet
            job.updateIEC(context) { r in for n in [15, 17, 19] { r.inverters[0].slots[n - 1]?.vocV = nil; r.inverters[0].slots[n - 1]?.iBeforeA = nil } }
        }
        switch state {
        case "inv2": inverter = 1; slot = 1
        case "voc", "differs": entry = .init(slot: 1, kind: .voltage)
        case "clamp": entry = .init(slot: 1, kind: .current)
        case "continuous": clearLast(job, context); slot = 15; startContinuous(report, 0)
        case "fail": job.updateIEC(context) { $0.inverters[0].slots[4]?.vocV = 712 }; slot = 5
        case "empty": slot = 8
        case "todo": clearLast(job, context); filter = .todo; slot = 15
        default: slot = 1
        }
    }
}

extension IECVIPage {
    func applyStep4Debug() {
        guard let state = Self.debugState4 else { return }
        debugApplied = true
        /// INV 1's first `n` strings measured (Vmp ≈ Voc × 0.815, Imp 12.2–12.6 A) with drawn photos.
        func measure(_ n: Int) {
            job.updateIEC(context) { r in
                for (k, st) in r.inverters[0].strings.prefix(n).enumerated() {
                    let voc = st.value.vocV ?? 753
                    r.inverters[0].slots[st.slot - 1]?.vmpV = (voc * 0.815 * 10).rounded() / 10
                    r.inverters[0].slots[st.slot - 1]?.impA = [12.5, 12.4, 12.3, 12.2, 12.6][k % 5]
                }
            }
            for st in report.inverters[0].strings.prefix(n) { addAfterPhotos(st.slot) }
        }
        switch state {
        case "vmp": addAfterPhotos(1, values: false); entry = .init(slot: 1, kind: .voltage)
        case "imp":
            addAfterPhotos(1, values: false)
            job.updateIEC(context) { $0.inverters[0].slots[0]?.vmpV = 615.3 }
            entry = .init(slot: 1, kind: .current)
        case "partial": measure(9); slot = 11
        case "fail": measure(9); job.updateIEC(context) { $0.inverters[0].slots[4]?.vmpV = 561 }; slot = 5
        case "continuous": measure(9); slot = 11; startContinuous(report, 0)
        case "done": measure(16); slot = 1
        case "todo": measure(9); filter = .todo; slot = 11
        case "inv2": inverter = 1; slot = 1
        default: slot = 1
        }
    }

    /// Drawn meter and clamp photos for a string's after readings (its values, or the board's example ones).
    func addAfterPhotos(_ n: Int, values: Bool = true) {
        let i = inverter
        guard let s = report.inverters[safe: i]?.slots[n - 1] else { return }
        let v = String(format: "%.1f", values ? (s.vmpV ?? 615.3) : 615.3), a = String(format: "%.2f", values ? (s.impA ?? 12.5) : 12.5)
        let vid = job.storeIECPhoto(IECCamera.stubPhoto(v), replacing: s.photo(.voltageAfter), context: context)
        let aid = job.storeIECPhoto(IECCamera.stubPhoto(a), replacing: s.photo(.currentAfter), context: context)
        job.updateIEC(context) { r in
            r.inverters[i].slots[n - 1]?.photos[IECReport.PhotoKind.voltageAfter.rawValue] = vid
            r.inverters[i].slots[n - 1]?.photos[IECReport.PhotoKind.currentAfter.rawValue] = aid
        }
    }
}

extension Job {
    /// `-iecStep4 YES`: the sample (it has no after readings), its before photos left as they were.
    func seedIECStep4Demo(context: ModelContext) {
        seedIECDemo(replacing: true)
        try? context.save()
    }

    /// `-iecStep2 YES`: the sample with a drawn meter photo for every string's Voc and current (for good).
    func seedIECStep2Demo(context: ModelContext) {
        seedIECDemo(replacing: true)
        guard var r = iecReport else { return }
        for p in iecPhotos { context.delete(p) }
        func store(_ reading: String) -> String {
            let id = UUID().uuidString, a = PhotoAsset(data: IECCamera.stubPhoto(reading), tag: id)
            context.insert(a); a.iecJob = self
            return id
        }
        for i in r.inverters.indices {
            for n in r.inverters[i].slots.indices {
                guard let s = r.inverters[i].slots[n] else { continue }
                r.inverters[i].slots[n]?.photos[IECReport.PhotoKind.voltageBefore.rawValue] = store(String(format: "%.1f", s.vocV ?? 0))
                r.inverters[i].slots[n]?.photos[IECReport.PhotoKind.currentBefore.rawValue] = store("0.00")
            }
        }
        iecReport = r
        try? context.save()
    }
}
#endif
