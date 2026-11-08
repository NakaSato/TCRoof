import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `บันทึกเครื่องมือและรถ` on iPad (docs/ui/tools-log-ipad, board `iPadToolsHub`): the tool and vehicle log as a logbook,
/// pushed from the `เครื่องมือ` tab's row (`ToolLogRow`). Left, `สมุดบันทึกเครื่องมือและรถ`: the kind tabs, what is out
/// now and the log by day with its filters, `ส่งออก CSV` and `โหลดเพิ่ม` (`+Ledger`). Right, the `เครื่องมือวัด` card
/// (KPIs and the chase list) and `บันทึกการใช้รถ` (`+Side`). The same data, forms and sync as `ToolLogCard` /
/// `VehicleCard`; the team's only. `-toolLogDemo YES` shows the board's example, nothing saved; `-toolLogFilter`,
/// `-toolLogRange`, `-toolLogAction`, `-toolLogVehicle` and `-toolLogMore` open its states.
struct ToolLogPadScreen: View {
    @Query(sort: \ToolEvent.at, order: .reverse) var stored: [ToolEvent]
    @Query var storedVehicles: [CompanyVehicle]
    @State var instruments = InstrumentStore.shared
    @State var sync = CloudSync.shared
    @Environment(\.modelContext) var context
    @Environment(\.permissions) var permissions
    @Environment(\.isPresented) private var isPushed
    @Environment(\.dismiss) private var dismiss

    /// The kind tab: nil is `ทั้งหมด`.
    @State var kind: ToolLog.Kind?
    @State var range: ToolLog.Period
    /// nil is `ทั้งหมด`, which alone shows `ทวงคืน`.
    @State var action: ToolLog.Action?
    @State var who: Who = .all
    @State var query = ""
    @State var searching = false
    /// Log rows shown; `โหลดเพิ่ม` adds 10, a filter change starts again at 10.
    @State var shown = ToolLogPadScreen.page
    @State var selectedVehicle: String?
    @State var form: ToolLogForm?
    @State var editing: Instrument?
    @State var chasing: ToolLog.Event?
    @State var shared: SharedCSV?
    /// The rows of the file being shared, for the toast once the share sheet closes.
    @State var lastExport: Int?
    @State var toast: String?

    static let page = 10

    /// The `ผู้ใช้ · งาน ▾` menu's pick.
    enum Who: Hashable {
        case all, person(String), job(String)
        var title: String {
            switch self {
            case .all: "ผู้ใช้ · งาน"
            case .person(let p): p
            case .job(let j): j
            }
        }
    }

    struct SharedCSV: Identifiable {
        let url: URL
        let count: Int
        var id: URL { url }
    }

    init() {
        var kind: ToolLog.Kind?, range = ToolLog.Period.week, action: ToolLog.Action?, vehicle: String?
        #if DEBUG
        let d = UserDefaults.standard
        switch d.string(forKey: "toolLogFilter") {
        case "tool": kind = .tool
        case "car": kind = .car
        default: break
        }
        switch d.string(forKey: "toolLogRange") {
        case "today": range = .today
        case "30": range = .month
        case "all": range = .all
        default: break
        }
        if d.bool(forKey: "toolLogMore") { range = .all }
        action = d.string(forKey: "toolLogAction").flatMap(ToolLog.Action.init(rawValue:)).flatMap { $0 == .remind ? nil : $0 }
        vehicle = d.string(forKey: "toolLogVehicle")
        #endif
        _kind = State(initialValue: kind)
        _range = State(initialValue: range)
        _action = State(initialValue: action)
        _selectedVehicle = State(initialValue: vehicle)
    }

    // MARK: data

    var events: [ToolLog.Event] { ToolLogDemo.on ? ToolLogDemo.events : stored.map(\.event) }
    var vehicles: [ToolLog.Vehicle] { (ToolLogDemo.on ? ToolLogDemo.vehicles : storedVehicles.map(\.vehicle)).sorted { $0.name < $1.name } }
    var loading: Bool { (sync.isLoading("toolEvents") || sync.isLoading("vehicles")) && events.isEmpty && vehicles.isEmpty }

    /// The log rows the filters keep, newest first.
    func rows(_ all: [ToolLog.Event], now: Date) -> [ToolLog.Event] {
        let person: String? = if case .person(let p) = who { p } else { nil }
        let job: String? = if case .job(let j) = who { j } else { nil }
        return ToolLog.filter(all, kind: kind, range: range, action: action, person: person, job: job, query: query, now: now)
    }

    /// Resets `shown` when any filter changes.
    var filterKey: String { "\(kind?.rawValue ?? "")|\(range.rawValue)|\(action?.rawValue ?? "")|\(who.title)|\(query)" }

    // MARK: body

    var body: some View {
        Group {
            if permissions.role == .external {
                // the log is the team's; a contractor never gets here from the tab, and `-screen toollog` shows nothing
                Text("บันทึกเครื่องมือและรถเป็นของทีมงาน").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .padDock(fade: nil)
        .task { CloudSync.shared.loadToolRecords() }
        .onChange(of: filterKey) { _, _ in shown = Self.page }
        .sheet(item: $form) { ToolLogFormSheet(form: $0, events: events, vehicles: vehicles) }
        .sheet(item: $editing) { tool in
            InstrumentForm(tool: tool, isNew: !instruments.all.contains { $0.id == tool.id }, save: instruments.save, delete: instruments.delete)
        }
        // the toast once the share sheet closes, where it can be seen
        .sheet(item: $shared, onDismiss: {
            if let count = lastExport { toast = "ส่งออก CSV \(count) รายการตามตัวกรองที่เลือก" }
            lastExport = nil
        }) { ActivitySheet(items: [$0.url]) }
        .alert(chasing.map { "ทวงคืน \($0.person)?" } ?? "", isPresented: Binding(get: { chasing != nil }, set: { if !$0 { chasing = nil } }),
               presenting: chasing) { e in
            Button("ทวงคืน") {
                ToolLogCard.remind(e, in: context)
                toast = "บันทึกการทวงคืน \(e.itemName) จาก \(e.person) แล้ว"
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: { e in
            Text("\(e.itemName) เกินกำหนดคืน \(ToolLog.daysLate(e)) วัน การทวงคืนจะลงในบันทึกให้ทีมเห็น")
        }
        .tcToast($toast)
    }

    private var content: some View {
        GeometryReader { g in
            let wide = g.size.width >= 1200
            HStack(alignment: .top, spacing: 16) {
                ledgerCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 16) {
                    instrumentsCard
                    vehiclesCard.frame(maxHeight: .infinity)
                }
                .frame(width: wide ? 452 : 380)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            if isPushed {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(Theme.onPrimary.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.onPrimary.opacity(0.35)))
                }
                .buttonStyle(.plain).accessibilityLabel("กลับ").accessibilityIdentifier("toollog.back")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("บันทึกเครื่องมือและรถ").font(.sarabunFixed(24, .bold)).accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text("บันทึก · เครื่องมือวัด · การใช้รถ").font(.sarabunFixed(14)).opacity(0.92)
                    if ToolLogDemo.on { TCSampleChip() }
                }
            }
            .foregroundStyle(Theme.onPrimary)
            .lineLimit(1)
            Spacer(minLength: 12)
            if permissions.role != .external {
                recordMenu {
                    Label("สแกน / บันทึก", systemImage: "qrcode.viewfinder").font(.sarabunFixed(15, .semibold)).foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 18).frame(minHeight: 48)
                        .background(Theme.onPrimary.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.onPrimary.opacity(0.35)))
                }
                .accessibilityIdentifier("toollog.scan")
            }
        }
        .padding(.leading, isPushed ? 24 : 32).padding(.trailing, 24)
        .padding(.top, 10).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// `สแกน / บันทึก` and `+ บันทึกรายการ`: the log's three forms (QR scanning is a hand-off of its own).
    func recordMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        let vehicle = vehicles.first { $0.id == currentVehicle(events)?.id }
        return Menu {
            Button("ยืมเครื่องมือ", systemImage: "arrow.up.right.square") { form = .borrow }
            Button("ออกรถ", systemImage: "car") { form = .carOut(nil) }.disabled(vehicles.isEmpty)
            Button("เติมน้ำมัน", systemImage: "fuelpump") { if let vehicle { form = .fuel(vehicle) } }.disabled(vehicle == nil)
        } label: { label() }
        .buttonStyle(.plain)
    }

    // MARK: export

    /// `ส่งออก CSV`: every filtered row, not only those shown, to a temporary file for the share sheet.
    func export(_ list: [ToolLog.Event], log: [ToolLog.Event], now: Date) {
        let c = MasterSchedule.calendar.dateComponents([.year, .month, .day], from: now)
        let name = String(format: "บันทึกเครื่องมือและรถ-%04d-%02d-%02d.csv", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("toollog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try Data(ToolLog.csv(list, log: log).utf8).write(to: url, options: .atomic)
            lastExport = list.count
            shared = SharedCSV(url: url, count: list.count)
        } catch {
            toast = "ส่งออก CSV ไม่สำเร็จ: \(error.localizedDescription)"
        }
    }
}

/// The `เครื่องมือ` tab's row on iPad (`ToolsView`, regular width) that pushes `ToolLogPadScreen`:
/// `บันทึกเครื่องมือและรถ`, `ใช้งานอยู่ n · เกินกำหนดคืน n`.
struct ToolLogRow: View {
    @Query(sort: \ToolEvent.at, order: .reverse) private var stored: [ToolEvent]

    var body: some View {
        let outs = ToolLog.outs(ToolLogDemo.on ? ToolLogDemo.events : stored.map(\.event))
        let late = outs.filter(\.late).count
        NavigationLink { ToolLogPadScreen() } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.clipboard").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 44, height: 44).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Radius.md))
                VStack(alignment: .leading, spacing: 2) {
                    Text("บันทึกเครื่องมือและรถ").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text("ใช้งานอยู่ \(outs.count) · เกินกำหนดคืน \(late)").font(.sarabun(14, relativeTo: .subheadline))
                        .foregroundStyle(late > 0 ? Theme.dangerText : Theme.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.chevron)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 72)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .cardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toollog.row")
    }
}
