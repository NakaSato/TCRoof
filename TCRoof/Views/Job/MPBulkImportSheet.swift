import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// นำเข้าไฟล์แผนหลายสถานี: many stations' plan files at once (`MPWorkbook`). Each file is matched to a PWA station by the
/// station its `PROJECT` line names, its kWp and an MP number in its name (`MPWorkbook.match`); the team checks or
/// changes each pick, then every file with a station is imported as one would be on its own (`MPWorkbookFlow.install`).
struct MPBulkImportSheet: View {
    /// One picked file.
    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let data: Data?
        let imported: MPWorkbook.Imported?
        let error: String?
        let station: MPWorkbook.FileStation
        /// Matching stations, best first.
        let ranked: [PersistentIdentifier]
        var job: PersistentIdentifier?
    }

    let stations: [Job]
    @State var items: [Item]
    /// Called with the number of stations imported.
    let done: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Reads the files and picks their stations.
    static func items(_ urls: [URL], stations: [Job]) -> [Item] {
        let candidates = stations.enumerated().map {
            MPWorkbook.Candidate(id: String($0.offset), name: $0.element.stationName, mpNumber: $0.element.mpNumber, kWp: $0.element.capacityKW)
        }
        let byKey = Dictionary(uniqueKeysWithValues: stations.enumerated().map { (String($0.offset), $0.element.persistentModelID) })
        return urls.map { url in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                let imported = try MPWorkbook.read(data)
                let station = MPWorkbook.station(project: imported.project, fileName: name)
                let m = MPWorkbook.match(station, among: candidates)
                return Item(name: name, data: data, imported: imported, error: nil, station: station,
                            ranked: m.ranked.compactMap { byKey[$0] }, job: m.pick.flatMap { byKey[$0] })
            } catch {
                return Item(name: name, data: nil, imported: nil, error: (error as? MPWorkbook.Failure)?.message ?? error.localizedDescription,
                            station: MPWorkbook.station(project: nil, fileName: name), ranked: [], job: nil)
            }
        }
    }

    private func job(_ id: PersistentIdentifier?) -> Job? { id.flatMap { i in stations.first { $0.persistentModelID == i } } }

    /// Stations two files point at.
    private var twice: Set<PersistentIdentifier> {
        var seen = Set<PersistentIdentifier>(), out = Set<PersistentIdentifier>()
        for case let j? in items.map(\.job) where !seen.insert(j).inserted { out.insert(j) }
        return out
    }

    private var ready: [Item] { items.filter { $0.job != nil && $0.imported != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("เลือกสถานีของแต่ละไฟล์ ระบบเลือกให้จากชื่อสถานีในไฟล์ ขนาด kWp และเลข MP ตรวจก่อนนำเข้า")
                        .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
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
            .navigationTitle("นำเข้าไฟล์แผน \(items.count) ไฟล์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("นำเข้า \(ready.count) สถานี", action: apply).disabled(ready.isEmpty || !twice.isEmpty)
                }
            }
        }
    }

    private func row(_ item: Binding<Item>) -> some View {
        let it = item.wrappedValue, picked = job(it.job)
        return VStack(alignment: .leading, spacing: 8) {
            Text(it.name).font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(2)
            if let error = it.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.dangerText)
            } else {
                Text(fileLine(it)).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                HStack(spacing: 8) {
                    Picker("สถานี", selection: item.job) {
                        Text("ไม่นำเข้า").tag(PersistentIdentifier?.none)
                        ForEach(order(it)) { j in Text(label(j)).tag(Optional(j.persistentModelID)) }
                    }
                    .pickerStyle(.menu)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .tint(it.job == nil ? Theme.dangerText : Theme.primary)
                    .accessibilityLabel("สถานีของ \(it.name)")
                    .accessibilityIdentifier("mpBulk.station")
                    Spacer(minLength: 8)
                    if let j = it.job, twice.contains(j) {
                        TCStatusChip("ซ้ำกับไฟล์อื่น", fill: Theme.dangerSoft, text: Theme.dangerText)
                    } else if picked?.scheduleInput != nil {
                        TCStatusChip("แทนแผนเดิม", fill: Theme.primarySoft, text: Theme.navy)
                    } else if it.job == nil {
                        TCStatusChip(it.ranked.isEmpty ? "ไม่พบสถานี" : "เลือกสถานี", fill: Theme.dangerSoft, text: Theme.dangerText)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: touchMin, alignment: .leading)
    }

    /// `สถานีผลิตน้ำประปาบางไทร · 414.96 kWp · 18 งาน · ติดตั้ง 23 ต.ค. 67 – 22 ธ.ค. 67`
    private func fileLine(_ it: Item) -> String {
        var parts: [String] = []
        if let n = it.station.name { parts.append(n) }
        if let k = it.station.kWp { parts.append("\(k.formatted()) kWp") }
        if let r = it.imported {
            parts.append("\(r.tasks.count) งาน")
            parts.append("ติดตั้ง \(r.input.installStart.thaiShort) – \(r.input.installEnd.thaiShort)")
        }
        return parts.joined(separator: " · ")
    }

    /// The matching stations first, then the rest by name.
    private func order(_ it: Item) -> [Job] {
        let ranked = it.ranked.compactMap(job)
        let rest = stations.filter { s in !it.ranked.contains(s.persistentModelID) }.sorted { $0.stationName < $1.stationName }
        return ranked + rest
    }

    private func label(_ j: Job) -> String {
        [j.mpNumber.map { "MP \($0)" }, j.stationName].compactMap { $0 }.joined(separator: " · ")
    }

    private func apply() {
        var n = 0
        for it in ready {
            guard let j = job(it.job), let imported = it.imported, let data = it.data else { continue }
            MPWorkbookFlow.install(imported, data: data, name: it.name, on: j)
            n += 1
        }
        try? context.save()
        dismiss()
        done(n)
    }
}
