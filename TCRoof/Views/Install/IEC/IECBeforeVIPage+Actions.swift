import SwiftUI
import UIKit
import SwiftData
import TCRoofUI
import TCRoofCore

extension IECBeforeVIPage {
    /// Strings of the inverter still missing Voc, current or polarity, in slot order.
    func unfinished(_ r: IECReport, _ i: Int) -> [Int] {
        guard r.inverters.indices.contains(i) else { return [] }
        let inv = r.inverters[i]
        return inv.strings.filter { $0.value.vocV == nil || $0.value.iBeforeA == nil || $0.value.polarityOK == nil }.map(\.slot)
    }

    /// Photo first: a value without its photo opens the camera, then the dialog.
    func open(_ kind: IECBeforeVIEntry.Kind, _ s: IECReport.Slot, continuous: IECBeforeVIEntry.Continuous? = nil, at target: Int? = nil) {
        let n = target ?? slot
        let photo: IECReport.PhotoKind = kind == .voltage ? .voltageBefore : .currentBefore
        let next = IECBeforeVIEntry.Target(slot: n, kind: kind, continuous: continuous)
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
        if shot.kind == .currentBefore { return "0.00" }
        let v = s.vocV ?? r.vocMedians(inv).first { $0.modules == s.modules }?.median ?? Double(s.modules) * 47
        return String(format: "%.1f", v)
    }

    // MARK: entry dialog

    @ViewBuilder func entryOverlay(_ r: IECReport) -> some View {
        if let target = entry, let inv = r.inverters[safe: inverter], let s = inv.slots[target.slot - 1] {
            ZStack {
                Theme.navy.opacity(0.45).ignoresSafeArea().onTapGesture { entry = nil }
                IECBeforeVIEntry(job: job, report: r, inverter: inverter, slot: s, target: target,
                                 reading: reading(target, s), sample: r.sampleName != nil,
                                 nextLabel: nextLabel(r, target),
                                 save: { v in save(v, target) },
                                 keep: { v in keep(v, target) },
                                 retake: { shooting = Shot(slot: target.slot, kind: target.photoKind, then: target); entry = nil },
                                 close: { entry = nil })
                    .frame(width: 1000)
                    .task(id: s.photo(target.photoKind)) { await read(s.photo(target.photoKind)) }
            }
            .transition(.opacity)
        }
    }

    /// The photo's reading once read; `.some(nil)` = read, nothing found; nil = not read yet.
    func reading(_ target: IECBeforeVIEntry.Target, _ s: IECReport.Slot) -> Double? {
        s.photo(target.photoKind).flatMap { readings[$0] ?? nil }
    }

    func read(_ id: String?) async {
        guard let id, readings[id] == nil, let asset = job.iecPhoto(id), let img = UIImage(data: asset.data) else { return }
        let text = await PlatePhotoReader.text(in: img)
        readings[id] = .some(IECReport.meterReading(in: text))
    }

    /// The pad's `บันทึก` sub label: where it goes next.
    func nextLabel(_ r: IECReport, _ t: IECBeforeVIEntry.Target) -> String {
        guard let inv = r.inverters[safe: inverter] else { return "" }
        if t.kind == .voltage { return inv.slots[t.slot - 1]?.photo(.currentBefore) == nil ? "→ ถ่ายแคลมป์ A" : "→ แคลมป์ A" }
        guard let n = nextSlot(r, after: t) else { return "→ จบ INV\(inverter + 1)" }
        return "→ " + IECReport.label(inverter: inverter + 1, seq: inv.strings.first { $0.slot == n }?.seq ?? 0)
    }

    /// The next string after a current is saved: the next unfinished one in continuous mode, else the next string.
    func nextSlot(_ r: IECReport, after t: IECBeforeVIEntry.Target) -> Int? {
        guard let inv = r.inverters[safe: inverter] else { return nil }
        if t.continuous != nil { return unfinished(r, inverter).first { $0 > t.slot } ?? unfinished(r, inverter).first { $0 != t.slot } }
        return inv.strings.first { $0.slot > t.slot }?.slot
    }

    func keep(_ value: Double, _ t: IECBeforeVIEntry.Target) {
        let i = inverter
        job.updateIEC(context) { r in
            if t.kind == .voltage { r.setVoc(value, inverter: i, slot: t.slot) } else { r.inverters[i].slots[t.slot - 1]?.iBeforeA = value }
        }
    }

    /// `บันทึก`: V → the clamp's photo → A → the next string's photo, or closes on the last.
    func save(_ value: Double, _ t: IECBeforeVIEntry.Target) {
        let i = inverter
        job.updateIEC(context) { r in
            if t.kind == .voltage { r.setVoc(value, inverter: i, slot: t.slot) } else { r.inverters[i].slots[t.slot - 1]?.iBeforeA = value }
        }
        let r = report
        guard let s = r.inverters[safe: i]?.slots[t.slot - 1] else { entry = nil; return }
        entry = nil
        if t.kind == .voltage {
            open(.current, s, continuous: t.continuous, at: t.slot)
            return
        }
        guard let n = nextSlot(r, after: t), let next = r.inverters[i].slots[n - 1] else { return }
        slot = n
        let c = t.continuous.map { IECBeforeVIEntry.Continuous(done: min($0.done + 1, $0.total), total: $0.total) }
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
extension IECBeforeVIPage {
    /// `-iecStep2State default|inv2|voc|clamp|continuous|fail|empty|todo|differs`: the board's states 01–09 on the
    /// sample `-iecStep2` seeded (the changes go into that sample test).
    static var debugState: String? { UserDefaults.standard.string(forKey: "iecStep2State") }

    func applyDebugState() {
        guard !debugApplied, let state = Self.debugState else { return }
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

extension Job {
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
