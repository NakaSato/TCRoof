import Foundation

// MP plan links to the other modules (docs/specs/master-schedule-swift.md §5): permit tasks take their actual from the
// station's papers, and construction tasks name the install photos (`9 ภาพถ่ายติดตั้งระบบ`) they need before 100 %.

// MARK: - Permit tasks ← station papers

/// The permit tasks the PWA document flow answers: once the papers say a permit was approved, the task is booked at 100 %
/// in the week of the approval, finished on its day. The table is `sources`; `book` applies it.
public enum PermitLink {

    /// What says a permit was approved.
    public enum Source: Equatable, Sendable {
        /// This site paper is `อนุมัติแล้ว` (a paper the station doesn't need, by its conditions, is skipped).
        case paper(String)
        /// Every site paper of the package the station needs is `อนุมัติแล้ว` (papers marked not needed are skipped; at
        /// least one is left). Shared papers aren't counted: they live in each device's own library, not on the job.
        case sitePackage(StationDocs.Package)
        /// The ERC flow (200 kVA and over) has this step recorded.
        case erc(ERCFlow.Step)
    }

    /// Task → what approves it; any one source does, the earliest day wins. From `forms/pwa/projects/
    /// solar-rooftop-energy-mgmt/project.json` (1.4 → folder 4.1 and its `building_docs` rule, 1.5 → 4.3, 1.7 → 4.2) and
    /// `flow.mmd` (the เทศบาล issues อ.1, กกพ. issues พค.2, กฟภ. approves the grid-connection set).
    public static let sources: [(task: MasterSchedule.Task, sources: [Source])] = [
        // the เทศบาล's answer: the อ.1 it issued, or its acceptance of the exemption notice
        (.buildingPermit, [.paper("building_permit_o1"), .paper("building_exempt_notice")]),
        // the พค.1 request granted, or the signed พค.2 back from the ERC (flow step 6)
        (.pk2, [.paper("pk1_form"), .erc(.pk2Signed)]),
        // the ขนานไฟ set approved by the utility, or the connection itself (flow step 11)
        (.gridConnection, [.sitePackage(.gridConnection), .erc(.cod)]),
    ]

    public static func sources(for task: MasterSchedule.Task) -> [Source] {
        sources.first { $0.task == task }?.sources ?? []
    }

    /// The day the station's papers say this task's permit was approved; nil while they don't. A paper's day is the last
    /// time it changed (`updatedAt`, stamped when it was set approved), an ERC step's the day the team recorded.
    public static func approval(_ task: MasterSchedule.Task, station: StationDocs.Station, _ ctx: StationDocs.Context,
                                now: Date = .now) -> Date? {
        sources(for: task).compactMap { day($0, station: station, ctx, now: now) }.min()
    }

    static func day(_ source: Source, station: StationDocs.Station, _ ctx: StationDocs.Context, now: Date) -> Date? {
        switch source {
        case .paper(let id):
            guard let kind = StationDocs.kind(id), !kind.scope.isShared, StationDocs.applies(kind, ctx),
                  let s = station.docs[id], s.status == .approved else { return nil }
            return s.updatedAt ?? now
        case .sitePackage(let package):
            guard StationDocs.packages(ctx).contains(package) else { return nil }
            let states = StationDocs.papers(in: package, ctx).filter { !$0.scope.isShared }
                .map { station.docs[$0.id] ?? StationDocs.DocState() }
                .filter { $0.status != .notNeeded }
            guard !states.isEmpty, states.allSatisfy({ $0.status == .approved }) else { return nil }
            return states.map { $0.updatedAt ?? now }.max()
        case .erc(let step):
            return (station.erc?.events ?? []).filter { $0.step == step }
                .compactMap { MasterSchedule.date(fromKey: $0.day, calendar: MasterSchedule.calendar) }.min()
        }
    }

    /// Books each permit task the papers approve: 100 % in the week of the approval, finished on its day (a start after
    /// it moves back to it), and remembered in `Actual.fromDocuments`. Each task is booked once, so this can run after
    /// every change to the papers; a task already at 100 % is only remembered, and an approval taken back changes
    /// nothing. Tasks without weight in the plan (พค.2 under 200 kVA) are skipped. Returns the tasks it booked.
    @discardableResult
    public static func book(_ actual: inout MasterSchedule.Actual, input: MasterSchedule.Input,
                            station: StationDocs.Station, _ ctx: StationDocs.Context, now: Date = .now,
                            calendar cal: Calendar = MasterSchedule.calendar) -> [MasterSchedule.Task] {
        var booked: [MasterSchedule.Task] = []
        for (task, _) in sources {
            let key = task.rawValue, weight = input.weight(task)
            guard actual.fromDocuments[key] == nil, weight > 0,
                  let approved = approval(task, station: station, ctx, now: now) else { continue }
            let day = cal.startOfDay(for: approved)
            actual.fromDocuments[key] = day
            let done = (actual.points[key] ?? [:]).values.reduce(0, +)
            if done >= weight - 1e-9 { continue }
            actual.setPercent(100, task: task, week: day, weight: weight, calendar: cal)
            actual.setDates(task, started: actual.started[key].map { min($0, day) }, finished: day, calendar: cal)
            booked.append(task)
        }
        return booked
    }
}

// MARK: - Construction tasks → install photos

public extension IECReport {

    /// A photo of `9 ภาพถ่ายติดตั้งระบบ` a construction task needs.
    struct TaskPhoto: Equatable, Sendable {
        public let page: InstallPage
        public let slot: InstallSlot

        /// `ตู้ AC | ภาพถ่ายตู้ควบคุม… (ด้านใน)`
        public var label: String { page.title + " | " + slot.caption }
    }

    /// The construction task a report slot shows, after the `photo_slots` of `forms/pwa/projects/
    /// solar-rooftop-energy-mgmt/project.json`: roof structure (2.1), panels from above (2.3), DC box and DC ground
    /// (2.2), inverters and the Inverter Station (2.5), AC box and AC ground (2.6), Smart energy (2.8), PQM (2.9).
    /// 2.4 Firefighter Safety Switch and 2.7 the control cabinet have no slot in the report, so they need none.
    static func installTask(page: InstallPage, slot index: Int) -> MasterSchedule.Task? {
        let id = page.id
        if id.hasSuffix(".a") { return .structure }
        if id.hasSuffix(".b") { return index == 1 ? .panels : .structure }
        switch id {
        case "dc", "gdc": return .dcSide
        case "ac": return .acSide
        case "gac": return index == 0 ? .acSide : .inverter
        case "se": return .zeroExport
        case "pqm": return .monitoring
        default: return id.hasPrefix("inv") ? .inverter : nil
        }
    }

    /// The report's photos the task needs, in the report's order.
    func installPhotos(for task: MasterSchedule.Task) -> [TaskPhoto] {
        installPages.flatMap { page in
            page.slots.enumerated().compactMap { k, slot in
                Self.installTask(page: page, slot: k) == task ? TaskPhoto(page: page, slot: slot) : nil
            }
        }
    }

    /// The task's photos not taken yet; empty when it needs none or has them all.
    func missingInstallPhotos(for task: MasterSchedule.Task) -> [TaskPhoto] {
        installPhotos(for: task).filter { installPhoto($0.slot) == nil }
    }

    /// What to warn about before booking a construction task at 100 %: its missing photos' labels, plus a line when
    /// inverters are needed but none is set up yet (their photos come from step 1 of the test). Empty for a task outside
    /// part 2 or with nothing missing. `report` nil (no IEC test yet) counts as an empty one.
    static func missingPhotoLabels(_ report: IECReport?, for task: MasterSchedule.Task) -> [String] {
        guard task.part == .construction else { return [] }
        let r = report ?? IECReport()
        var out = r.missingInstallPhotos(for: task).map(\.label)
        if task == .inverter, r.inverters.isEmpty { out.insert("Inverter | ยังไม่ได้เพิ่มเครื่องในขั้น 1 ของการทดสอบ IEC", at: 0) }
        return out
    }
}
