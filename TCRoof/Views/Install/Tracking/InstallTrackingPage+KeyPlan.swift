import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ความคืบหน้าเทียบแผน`'s third view, `Key Plan` (docs/ui/install-tracking-ipad-keyplan): the station's key plan with a
/// pin per MP task × location coloured by its progress against today's plan, beside the list of those points. Placing
/// a point writes its location's `Settings.keyPoints`, so every task at that location moves with it.
extension InstallTrackingPage {
    /// The settings the view reads and writes: the job's, or the board's example in memory with `-installDemo YES`.
    var keySettings: RoutineReport.Settings {
        #if DEBUG
        if Debug.demo { return keyDemo ?? KeyPlanDemo.settings }
        #endif
        return job.routineSettings
    }

    func keyPlanModel(_ data: InstallPageData) -> InstallKeyPlan {
        #if DEBUG
        if Debug.demo { return InstallKeyPlan(rows: KeyPlanDemo.rows, planned: KeyPlanDemo.planned, settings: keySettings) }
        #endif
        return InstallKeyPlan(rows: data.gantt?.rows ?? [], planned: data.plannedByTask, settings: keySettings)
    }

    /// Saves the way `KeyPlanSheet` does.
    func saveKeySettings(_ s: RoutineReport.Settings) {
        #if DEBUG
        if Debug.demo { keyDemo = s; return }
        #endif
        job.routineSettings = s
        try? context.save()
    }

    func keyPlanPanel(_ data: InstallPageData) -> some View {
        InstallKeyPlanPanel(job: job, model: keyPlanModel(data), settings: keySettings, save: saveKeySettings,
                            canEdit: permissions.can(.dailyFill, on: job.access), demo: Debug.demo)
    }

    /// `เสร็จ · ตามแผน · ช้ากว่าแผน · ยังไม่เริ่ม`.
    var keyPlanLegend: some View {
        HStack(spacing: 14) {
            ForEach([InstallKeyPlan.State.done, .onPlan, .late, .notStarted], id: \.self) { s in
                HStack(spacing: 5) {
                    Circle().fill(KeyPlanStyle.color(s)).frame(width: 10, height: 10)
                    Text(KeyPlanStyle.title(s))
                }
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    /// `วางแล้ว n/N`, amber while some are left.
    func keyPlanChip(_ m: InstallKeyPlan) -> some View {
        let left = m.placedCount < m.points.count
        return Text("วางแล้ว \(m.placedCount)/\(m.points.count)").font(.sarabunFixed(12, .bold))
            .foregroundStyle(left ? Theme.pending : Theme.successInk).monospacedDigit()
            .padding(.horizontal, 10).frame(height: 22)
            .background(left ? Theme.pendingSoft : Theme.successSoft, in: Capsule())
            .fixedSize()
            .accessibilityIdentifier("keyPlanPlaced")
    }
}

/// A point's colour and words.
enum KeyPlanStyle {
    static func color(_ s: InstallKeyPlan.State) -> Color {
        switch s {
        case .done: Theme.success
        case .onPlan: Theme.primary
        case .late: Theme.danger
        case .notStarted: Theme.muted
        }
    }

    static func title(_ s: InstallKeyPlan.State) -> String {
        switch s {
        case .done: "เสร็จ"
        case .onPlan: "ตามแผน"
        case .late: "ช้ากว่าแผน"
        case .notStarted: "ยังไม่เริ่ม"
        }
    }

    /// Under the %: `เสร็จ`, `แผน 80%` when late, `ตามแผน`, `ยังไม่เริ่ม`.
    static func note(_ p: InstallKeyPlan.Point) -> String {
        p.state == .late ? "แผน \(Int(p.planned.rounded()))%" : title(p.state)
    }
}

/// The plan on the left and the list on the right, with the selection and place mode between them.
struct InstallKeyPlanPanel: View {
    let job: Job
    let model: InstallKeyPlan
    let settings: RoutineReport.Settings
    let save: (RoutineReport.Settings) -> Void
    let canEdit: Bool
    let demo: Bool

    @State private var selected: String?
    /// The point being placed.
    @State private var placing: String?
    /// 0 all, 1 unplaced.
    @State private var filter = 0
    @State private var toast: String?
    @State private var picture: (image: UIImage, uploaded: Bool)?
    @State private var loaded = false
    @State private var debugApplied = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                KeyPlanBoard(model: model, picture: picture?.image, loaded: loaded, selected: selected, placing: placingPoint,
                             select: select, place: place, cancel: { placing = nil })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if picture != nil {
                    Text([picture?.uploaded == true ? "ผังที่อัปโหลด" : "ภาพ A2 จากรายงานสำรวจ", "จุดติดตั้งดึงจากแผน MP"].joined(separator: " · "))
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1)
            KeyPlanList(model: model, filter: $filter, selected: selected, placing: placing, canEdit: canEdit && picture != nil,
                        select: select, arm: { placing = $0; selected = $0 }, remove: remove)
                .frame(width: 360)
        }
        .padding(.bottom, 6)
        .tcToast($toast)
        .task {
            if demo { picture = (Job.demoPicture.image, false) } else if let p = job.keyPlanPicture {
                picture = (p.image, job.uploadedKeyPlan != nil)
            }
            loaded = true
            #if DEBUG
            applyDebug()
            #endif
        }
    }

    private var placingPoint: InstallKeyPlan.Point? { placing.flatMap { id in model.points.first { $0.id == id } } }

    /// A pin or a row: selects it, or clears it when it is already selected.
    private func select(_ id: String?) {
        guard placing == nil else { return }
        selected = selected == id ? nil : id
    }

    /// Writes the armed point's location where the plan was tapped, then arms the next unplaced point.
    private func place(_ x: Double, _ y: Double) {
        guard let p = placingPoint, let l = p.location else { return }
        var s = settings
        s.keyPoints[l] = [x, y]
        save(s)
        let moved = model.sharing(p).count + 1
        toast = moved > 1 ? "\(p.placed ? "ย้าย" : "วาง") \(moved) จุดของ \(l)" : "\(p.placed ? "ย้าย" : "วาง") \(p.label) ที่ \(l)"
        // the model is this tap's: the points at this location are placed now
        let next = model.points.filter { !$0.placed && $0.location != nil && $0.location != l }
        let after = model.points.firstIndex { $0.id == p.id }.flatMap { i in next.first { n in (model.points.firstIndex { $0.id == n.id } ?? 0) > i } }
        let n = after ?? next.first
        placing = n?.id
        selected = n?.id ?? p.id
    }

    private func remove(_ p: InstallKeyPlan.Point) {
        guard let l = p.location else { return }
        var s = settings
        s.keyPoints[l] = nil
        save(s)
    }

    #if DEBUG
    /// `-installKeyPlanState selected|placing|placed` (docs/ui/install-tracking-ipad-keyplan states 02–04).
    private func applyDebug() {
        guard !debugApplied else { return }
        debugApplied = true
        switch UserDefaults.standard.string(forKey: "installKeyPlanState") {
        case "selected":
            selected = model.points.filter(\.placed).dropFirst(3).first?.id
        case "placing":
            filter = 1
            placing = model.nextUnplaced(after: nil)?.id
            selected = placing
        case "placed":
            filter = 1
            placing = model.nextUnplaced(after: nil)?.id
            place(0.82, 0.78)
        default: break
        }
    }
    #endif
}

/// The key plan with a pin per placed point, the banner while placing, or the empty state without a picture.
struct KeyPlanBoard: View {
    let model: InstallKeyPlan
    let picture: UIImage?
    let loaded: Bool
    let selected: String?
    let placing: InstallKeyPlan.Point?
    let select: (String?) -> Void
    let place: (Double, Double) -> Void
    let cancel: () -> Void

    var body: some View {
        if let picture {
            VStack(spacing: 8) {
                if let p = placing { banner(p) }
                KeyPlanImage(image: picture, points: []) { x, y in
                    if placing != nil { place(x, y) } else { select(nil) }
                }
                .overlay { if placing != nil { Theme.navySolid.opacity(0.12).allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: 8)) } }
                .overlay { pins }
                .accessibilityIdentifier("keyPlanImage")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
        } else if loaded {
            VStack(spacing: 8) {
                TCEmptyState("ยังไม่มีผัง", systemImage: "map",
                             description: Text("อัปโหลดผังได้ที่ อัปโหลดผัง ในรายงานประจำวัน หรือเพิ่มภาพ A2 ในรายงานสำรวจ"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Color.clear
        }
    }

    private var pins: some View {
        let offsets = model.fanOffsets()
        return GeometryReader { g in
            ForEach(model.points.filter(\.placed)) { p in
                let o = offsets[p.id] ?? (0, 0)
                KeyPlanPin(point: p, selected: selected == p.id) { select(p.id) }
                    .position(x: (p.at?.x ?? 0) * g.size.width + o.dx, y: (p.at?.y ?? 0) * g.size.height + o.dy)
                    .allowsHitTesting(placing == nil)
            }
        }
    }

    /// `แตะบนผังเพื่อวาง 2.5-1 · ห้องอินเวอร์เตอร์` with `ยกเลิก`.
    private func banner(_ p: InstallKeyPlan.Point) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.primary)
            Text("แตะบนผังเพื่อวาง \(p.label) · \(p.location ?? "")").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Button("ยกเลิก", action: cancel).buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4)
        .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("keyPlanPlacing")
    }
}

/// A pill with the point's label, filled by its colour; ringed and larger when selected. Its hit area is 44 pt.
struct KeyPlanPin: View {
    let point: InstallKeyPlan.Point
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        let c = KeyPlanStyle.color(point.state)
        Button(action: tap) {
            Text(point.label).font(.sarabunFixed(selected ? 15 : 12, .bold)).foregroundStyle(Theme.onPrimary).monospacedDigit()
                .padding(.horizontal, selected ? 10 : 7).frame(height: selected ? 30 : 22)
                .background(c, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.paper, lineWidth: 1.5))
                .padding(selected ? 3 : 0)
                .overlay { if selected { Capsule().strokeBorder(c.opacity(0.45), lineWidth: 3) } }
                .shadow(color: Theme.navySolid.opacity(0.25), radius: 2, y: 1)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel("จุด \(point.label) \(point.location ?? "") \(Int(point.actual.rounded()))% \(KeyPlanStyle.title(point.state))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// `ทั้งหมด N | ยังไม่วาง m`, then the points grouped by MP task. It scrolls inside the card.
struct KeyPlanList: View {
    let model: InstallKeyPlan
    @Binding var filter: Int
    let selected: String?
    let placing: String?
    let canEdit: Bool
    let select: (String?) -> Void
    let arm: (String) -> Void
    let remove: (InstallKeyPlan.Point) -> Void

    var body: some View {
        VStack(spacing: 10) {
            TCCountSegments([.init("ทั้งหมด", count: model.points.count), .init("ยังไม่วาง", count: model.unplaced.count)], selection: $filter)
                .accessibilityLabel("กรองจุด")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.groups) { g in
                            let shown = g.points.filter { filter == 0 || !$0.placed }
                            if !shown.isEmpty {
                                header(g)
                                ForEach(shown) { p in
                                    KeyPlanRow(point: p, selected: selected == p.id, placing: placing == p.id, canEdit: canEdit,
                                               select: { select(p.id) }, arm: { arm(p.id) }, remove: { remove(p) })
                                        .id(p.id)
                                }
                            }
                        }
                        if filter == 1, model.unplaced.isEmpty {
                            Text("วางครบทุกจุดแล้ว").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                                .frame(maxWidth: .infinity).padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: selected) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    /// `2.1 ติดตั้งโครงสร้าง…` with `5 จุด · เฉลี่ย 62%`.
    private func header(_ g: InstallKeyPlan.Group) -> some View {
        HStack(spacing: 8) {
            Text(g.code).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                .padding(.horizontal, 6).frame(height: 20).background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            Text(g.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 6)
            Text("\(g.points.count) จุด · เฉลี่ย \(Int(g.average.rounded()))%").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).fixedSize()
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One point: its number in its colour, the location and whether it is on the plan, the % with its note, a bar with a
/// tick at the plan; expanded when selected with `ย้ายจุดบนผัง` / `เอาออกจากผัง`, or `วางบนผัง`.
struct KeyPlanRow: View {
    let point: InstallKeyPlan.Point
    let selected: Bool
    let placing: Bool
    let canEdit: Bool
    let select: () -> Void
    let arm: () -> Void
    let remove: () -> Void

    var body: some View {
        let c = KeyPlanStyle.color(point.state)
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Button(action: select) { summary(c).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
            if selected, canEdit, point.location != nil { actions }
        }
        .padding(12)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(selected ? (point.placed ? c : Theme.navy) : Theme.borderSubtle, lineWidth: selected ? 2 : 1))
    }

    private func summary(_ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    if point.placed { Circle().fill(c) } else { Circle().strokeBorder(Theme.chevron, lineWidth: 1.5) }
                    Text("\(point.number)").font(.sarabunFixed(13, .bold)).foregroundStyle(point.placed ? Theme.onPrimary : Theme.inkMuted)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(point.location ?? "ไม่ระบุตำแหน่ง").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(point.placed ? "อยู่บนผัง · \(point.label)" : point.location == nil ? "ยังไม่กำหนดตำแหน่งในงาน" : "ยังไม่วางบนผัง")
                        .font(.sarabunFixed(13, point.placed ? .regular : .bold))
                        .foregroundStyle(point.placed ? Theme.inkMuted : Theme.dangerText).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(point.actual.rounded()))%").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    Text(KeyPlanStyle.note(point)).font(.sarabunFixed(12, point.state == .late ? .bold : .regular))
                        .foregroundStyle(point.state == .late ? Theme.dangerText : point.state == .done ? Theme.successInk : Theme.inkMuted)
                }
            }
            bar(c)
        }
        .frame(minHeight: 44)
    }

    /// The % filled in the point's colour, a tick at the planned %.
    private func bar(_ c: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ganttTrack)
                Capsule().fill(c).frame(width: g.size.width * point.actual / 100)
                if point.planned > 0 {
                    Rectangle().fill(Theme.navy).frame(width: 2, height: 10).offset(x: min(g.size.width * point.planned / 100, g.size.width - 2))
                }
            }
        }
        .frame(height: 5)
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if point.placed {
                Button(placing ? "แตะบนผัง…" : "ย้ายจุดบนผัง", action: arm).buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                Button("เอาออกจากผัง", action: remove).buttonStyle(TCButtonStyle(.destructive, size: .card)).fixedSize()
            } else {
                Button(placing ? "แตะบนผัง…" : "วางบนผัง", action: arm).buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
            }
        }
        .disabled(placing)
    }
}

#if DEBUG
/// `-installView keyplan -installDemo YES`: the board's example (assets/sample-data.json) on the drawn demo picture.
enum KeyPlanDemo {
    typealias Task = MasterSchedule.Task
    static let lines: [(Task, [(String, Double)])] = [
        (.structure, [("หลังคา 1", 100), ("หลังคา 2", 100), ("หลังคา 3", 70), ("หลังคา 4", 40), ("หลังคา 5", 0)]),
        (.dcSide, [("หลังคา 3", 60), ("ห้องอินเวอร์เตอร์", 0)]),
        (.panels, [("หลังคา 1", 50), ("หลังคา 2", 20), ("ถังน้ำใส 1", 0), ("ถังน้ำใส 2", 0)]),
        (.inverter, [("ห้องอินเวอร์เตอร์", 0)]),
        (.acSide, [("ห้องอินเวอร์เตอร์", 0)]),
        (.zeroExport, [("ตู้ MDB", 0)]),
        (.monitoring, [("ตู้ MDB", 0)]),
        (.preCommissioning, [("ห้องอินเวอร์เตอร์", 0)]),
    ]
    static let planned: [String: Double] = [Task.structure.rawValue: 80, Task.dcSide.rawValue: 60, Task.panels.rawValue: 30]
    static var rows: [InstallGantt.Row] {
        let day = Calendar.current.startOfDay(for: .now)
        return lines.map { t, subs in
            InstallGantt.Row(id: t.rawValue, code: t.code, title: t.title, status: .current, start: day, end: day, percent: 0,
                             subs: subs.map { .init($0.0, percent: $0.1) })
        }
    }
    /// Where the example locations sit on `Job.demoPicture`; the inverter room and the MDB are left to place.
    static var settings: RoutineReport.Settings {
        var s = RoutineReport.Settings()
        s.keyPoints = ["หลังคา 1": [0.30, 0.31], "หลังคา 2": [0.56, 0.26], "หลังคา 3": [0.72, 0.55], "หลังคา 4": [0.50, 0.715],
                       "หลังคา 5": [0.15, 0.18], "ถังน้ำใส 1": [0.25, 0.70], "ถังน้ำใส 2": [0.86, 0.20]]
        return s
    }
}
#endif
