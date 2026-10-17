import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// นำเข้ารายชื่อสถานี: the PWA tracking workbook's stations (`StationList`, docs/specs/master-schedule-swift.md §4) against
/// the app's PWA stations. A row with a clear match fills that station's empty fields (branch, kWp, inverter kW, address,
/// province, position) and keeps what it has, showing where the sheet differs; a row with no station becomes a new
/// งาน PWA job; a row with only near matches waits for the team to pick one, make it new or skip it.
struct StationListImportSheet: View {
    enum Choice: Hashable {
        case skip, create
        case station(PersistentIdentifier)
    }

    struct Item: Identifiable {
        let row: StationList.Row
        var choice: Choice
        var id: Int { row.id }
    }

    let stations: [Job]
    let fileName: String
    @State var items: [Item]
    /// Called with the stations created and filled.
    let done: (_ created: Int, _ filled: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// The rows of a file and their default choices, or why the file isn't the list.
    static func items(_ url: URL, stations: [Job]) -> Result<[Item], StationList.Failure> {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(.notWorkbook) }
        do {
            // a station's id is its place in `stations`
            let existing = stations.enumerated().map { i, job -> StationList.Existing in
                var e = job.stationListEntry
                e.id = String(i)
                return e
            }
            let rows = StationList.rows(try StationList.read(data), existing: existing)
            return .success(rows.map { r in
                var choice: Choice = r.ranked.isEmpty ? .create : .skip
                if let i = r.match.flatMap({ Int($0) }), stations.indices.contains(i) { choice = .station(stations[i].persistentModelID) }
                return Item(row: r, choice: choice)
            })
        } catch {
            return .failure(error as? StationList.Failure ?? .notWorkbook)
        }
    }

    private func job(_ id: PersistentIdentifier) -> Job? { stations.first { $0.persistentModelID == id } }

    private var picked: [PersistentIdentifier] {
        var out: [PersistentIdentifier] = []
        for it in items { if case .station(let id) = it.choice { out.append(id) } }
        return out
    }

    /// Stations two rows point at.
    private var twice: Set<PersistentIdentifier> {
        var seen = Set<PersistentIdentifier>(), out = Set<PersistentIdentifier>()
        for id in picked where !seen.insert(id).inserted { out.insert(id) }
        return out
    }

    private var creating: Int { items.filter { $0.choice == .create }.count }
    /// Matched rows that change something.
    private var filling: Int {
        var n = 0
        for it in items {
            if case .station(let id) = it.choice, let j = job(id), !fills(it, j).isEmpty { n += 1 }
        }
        return n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    VStack(spacing: 0) {
                        ForEach($items) { $item in
                            row($item)
                            if item.id != items.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                    .cardStyle(padding: 0)
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageGradient.ignoresSafeArea())
            .navigationTitle("รายชื่อสถานี \(items.count) แถว")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("นำเข้า", action: apply)
                        .disabled(creating + filling == 0 || !twice.isEmpty)
                        .accessibilityIdentifier("stationList.import")
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fileName).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(2)
            Text("สร้างงาน PWA ใหม่ \(creating) สถานี · เติมข้อมูลที่ว่าง \(filling) สถานี · ข้าม \(items.filter { $0.choice == .skip }.count) แถว")
                .font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
            Text("สถานีที่มีอยู่แล้วเติมเฉพาะช่องที่ยังว่าง ค่าที่ต่างจากไฟล์คงตามในแอป ตรวจสถานีที่ระบบเลือกให้ก่อนนำเข้า")
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            if !twice.isEmpty {
                Label("มีสองแถวเลือกสถานีเดียวกัน แก้ก่อนนำเข้า", systemImage: "exclamationmark.triangle.fill")
                    .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.dangerText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row(_ item: Binding<Item>) -> some View {
        let it = item.wrappedValue, s = it.row.station
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let p = s.phase, let o = s.order {
                    Text("ระยะ \(p) · \(o)").font(.sarabun(13, .semibold, relativeTo: .footnote).monospacedDigit()).foregroundStyle(Theme.primary)
                }
                Text(s.name).font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(2)
            }
            Text(line(s)).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            HStack(spacing: 8) {
                choiceMenu(item)
                Spacer(minLength: 8)
                chip(it)
            }
            if case .station(let id) = it.choice, let j = job(id) { changes(it, j) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: touchMin, alignment: .leading)
    }

    /// `การประปาส่วนภูมิภาคสาขาชัยบาดาล · 163.02 kWp · อินเวอร์เตอร์ 160 kW · ลพบุรี`
    private func line(_ s: StationList.Station) -> String {
        var parts = [s.branch]
        if let k = s.kWp { parts.append("\(k.formatted()) kWp") }
        if let i = s.inverterKW { parts.append("อินเวอร์เตอร์ \(i.formatted()) kW") }
        parts.append(s.province)
        if s.latitude == nil { parts.append("ไม่มีพิกัด") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func choiceMenu(_ item: Binding<Item>) -> some View {
        let it = item.wrappedValue
        return Menu {
            Picker("สถานี", selection: item.choice) {
                Text("สร้างงาน PWA ใหม่").tag(Choice.create)
                Text("ข้าม").tag(Choice.skip)
                ForEach(order(it)) { j in Text(j.stationName).tag(Choice.station(j.persistentModelID)) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(it.choice)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.sarabun(12, relativeTo: .caption))
            }
            .font(.sarabun(17, relativeTo: .body))
            .foregroundStyle(it.choice == .skip ? Theme.inkMuted : Theme.primary)
            .frame(minHeight: touchMin)
        }
        .accessibilityLabel("สถานีของ \(it.row.station.name)")
        .accessibilityValue(title(it.choice))
        .accessibilityIdentifier("stationList.choice")
    }

    private func title(_ c: Choice) -> String {
        switch c {
        case .create: "สร้างงาน PWA ใหม่"
        case .skip: "ข้าม"
        case .station(let id): job(id).map { "อัปเดต \($0.stationName)" } ?? "ข้าม"
        }
    }

    @ViewBuilder private func chip(_ it: Item) -> some View {
        switch it.choice {
        case .station(let id):
            if twice.contains(id) {
                TCStatusChip("ซ้ำกับแถวอื่น", fill: Theme.dangerSoft, text: Theme.dangerText)
            } else if let j = job(id), fills(it, j).isEmpty {
                TCStatusChip("ครบแล้ว", fill: Theme.okSoft, text: Theme.okText)
            } else {
                TCStatusChip("เติมข้อมูล", fill: Theme.primarySoft, text: Theme.navy)
            }
        case .create:
            TCStatusChip("ใหม่", fill: Theme.okSoft, text: Theme.okText)
        case .skip:
            if !it.row.ranked.isEmpty { TCStatusChip("เลือกสถานี", fill: Theme.warningTint, text: Theme.warningText) }
        }
    }

    /// What the row fills, and where the station keeps a value other than the sheet's.
    @ViewBuilder private func changes(_ it: Item, _ j: Job) -> some View {
        let fill = fills(it, j), differ = StationList.differs(it.row.station, j.stationListEntry)
        if !fill.isEmpty {
            Text("เติม: " + fill.map(\.label).joined(separator: " · "))
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.okText)
        }
        if !differ.isEmpty {
            Label("ต่างจากไฟล์ (คงตามในแอป): " + differ.map { describe($0, it.row.station, j) }.joined(separator: " · "),
                  systemImage: "exclamationmark.circle")
                .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.warningText)
        }
    }

    /// `kWp 90 (ไฟล์ 88.92)`
    private func describe(_ f: StationList.Field, _ s: StationList.Station, _ j: Job) -> String {
        func n(_ v: Double?) -> String { v.map { $0.formatted() } ?? "-" }
        switch f {
        case .kWp: return "kWp \(n(j.capacityKW)) (ไฟล์ \(n(s.kWp)))"
        case .inverterKW: return "อินเวอร์เตอร์ \(n(j.inverterKW)) (ไฟล์ \(n(s.inverterKW)))"
        case .province: return "จังหวัด \(j.province) (ไฟล์ \(s.province))"
        default: return f.label
        }
    }

    private func fills(_ it: Item, _ j: Job) -> [StationList.Field] { StationList.fills(it.row.station, j.stationListEntry) }

    /// The matching stations first, then the rest by name.
    private func order(_ it: Item) -> [Job] {
        let byIndex = it.row.ranked.compactMap { Int($0) }.filter { stations.indices.contains($0) }.map { stations[$0] }
        let ids = Set(byIndex.map(\.persistentModelID))
        return byIndex + stations.filter { !ids.contains($0.persistentModelID) }.sorted { $0.stationName < $1.stationName }
    }

    private func apply() {
        var created = 0, filled = 0
        for it in items {
            let s = it.row.station
            switch it.choice {
            case .skip: continue
            case .create:
                let job = Job(code: SampleData.newJobCode(), projectName: s.name, customerName: s.branch.isEmpty ? s.name : s.branch,
                              address: s.address, province: s.province, capacityKW: s.kWp ?? 0, team: .t1, status: .interested,
                              surveyDate: Job.unscheduled, installStart: Job.unscheduled, installDays: 1)
                job.kind = .pwa
                job.inverterKW = s.inverterKW
                job.latitude = s.latitude; job.longitude = s.longitude
                context.insert(job)
                created += 1
            case .station(let id):
                guard let j = job(id) else { continue }
                let fill = fills(it, j)
                guard !fill.isEmpty else { continue }
                j.fill(fill, from: s)
                filled += 1
            }
        }
        try? context.save()
        dismiss()
        done(created, filled)
    }
}

extension Job {
    /// No appointment and no install days yet: a station imported from the tracking workbook. Its install dates come
    /// with its MP plan (`scheduleInput`); 1970 is a day no calendar or reminder reaches.
    static let unscheduled = Date(timeIntervalSince1970: 0)

    /// This job for `StationList`: a branch that is only the station's name again counts as empty.
    var stationListEntry: StationList.Existing {
        StationList.Existing(id: "", name: stationName, branch: customerName == projectName ? "" : customerName,
                             kWp: capacityKW > 0 ? capacityKW : nil, inverterKW: inverterKW, address: address, province: province,
                             latitude: latitude, longitude: longitude)
    }

    /// Takes the sheet's value for each field it has empty.
    func fill(_ fields: [StationList.Field], from s: StationList.Station) {
        for f in fields {
            switch f {
            case .branch: customerName = s.branch
            case .kWp: if let v = s.kWp { capacityKW = v }
            case .inverterKW: inverterKW = s.inverterKW
            case .address: address = s.address
            case .province: province = s.province
            case .coordinates: latitude = s.latitude; longitude = s.longitude
            }
        }
    }
}
