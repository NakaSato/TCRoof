import SwiftUI
import TCRoofUI
import TCRoofCore

/// `จับคู่สถานีกับ Plant` (issue #259 §7), the page `ตั้งค่า Monitoring`'s `ดูรายการ ›` opens inside the dialog. Left:
/// the handed-over stations, each with the plant it is paired with or `ยังไม่จับคู่`, and the count line. Right: the
/// picker for the selected station: the server (a switch when there are several), a search, the server's plants
/// (`plant/list`, loaded behind a skeleton), the suggestions marked `แนะนำ` (`Monitoring.Pairing.suggest`: the
/// station's name in the plant's, or a size within 10 %), and `เลิกจับคู่`. Every choice lands in the dialog's draft;
/// `บันทึก` writes it. Others than managers look without changing.
///
/// `stub` (`-monitoringPairing YES`) lists `Monitoring.Pairing.demoPlants()` in place of the server's, with no network.
struct MonitoringPairingPane: View {
    let stations: [Monitoring.Station]
    @Binding var draft: Monitoring.Settings
    let canEdit: Bool
    var stub = false

    @State private var selected: String?
    @State private var serverID: UUID?
    @State private var search = ""
    /// The plants read, by server (`stubKey` for the stub); loading and the error per server.
    @State private var plants: [UUID: [Monitoring.Pairing.Plant]] = [:]
    @State private var loading: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]

    private static let stubKey = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stationsCard.frame(maxWidth: .infinity)
            pickerCard.frame(maxWidth: .infinity)
        }
        .padding(24)
        .task(id: cacheKey) { await load() }
    }

    // MARK: stations

    private var stationsCard: some View {
        card("สถานี", note: "ส่งมอบแล้ว · แตะเพื่อเลือก Plant") {
            ScrollView {
                VStack(spacing: 0) {
                    if stations.isEmpty {
                        Text("ยังไม่มีสถานีที่ส่งมอบแล้ว").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(stations) { s in
                        stationRow(s)
                        Divider()
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                Text("\(draft.paired(of: stations.map(\.id)))/\(stations.count) สถานีจับคู่กับ Plant ใน Growatt แล้ว")
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("monitoring.pairing.count")
                Spacer()
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
        }
    }

    private func stationRow(_ s: Monitoring.Station) -> some View {
        let on = selected == s.id
        let plantID = draft.pairings[s.id]
        return Button {
            select(s)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text([s.mpNumber.map { "MP \($0)" }, MonFormat.number(s.kWp, s.kWp.rounded() == s.kWp ? 0 : 1) + " kWp"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                if let plantID {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(plantName(plantID, station: s.id)).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successInk).lineLimit(1)
                        Text("Plant " + plantID).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                    }
                } else {
                    Text("ยังไม่จับคู่").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56)
            .background(on ? Theme.primarySoft : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monitoring.pairing.station." + s.id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The plant's name from what was read, else its id.
    private func plantName(_ plantID: String, station: String) -> String {
        let key = draft.server(for: station)?.id ?? Self.stubKey
        if let p = plants[key]?.first(where: { $0.id == plantID }) { return p.name }
        if let p = plants.values.lazy.compactMap({ $0.first(where: { $0.id == plantID }) }).first { return p.name }
        return "Plant " + plantID
    }

    private func select(_ s: Monitoring.Station) {
        selected = s.id
        serverID = draft.server(for: s.id)?.id ?? draft.servers.first?.id
        search = ""
    }

    // MARK: picker

    private var station: Monitoring.Station? { stations.first { $0.id == selected } }
    private var server: Monitoring.Settings.Server? { draft.servers.first { $0.id == serverID } ?? draft.servers.first }
    private var cacheKey: UUID? {
        guard selected != nil else { return nil }
        return stub ? Self.stubKey : server?.id
    }

    private var pickerCard: some View {
        card("Plant ใน Growatt", note: station?.name ?? "เลือกสถานีทางซ้ายก่อน") {
            if let station {
                serverLine
                Divider()
                if cacheKey == nil {
                    Text("ยังไม่มีเซิร์ฟเวอร์ข้อมูล · เพิ่มเซิร์ฟเวอร์ในหน้าตั้งค่าก่อน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        .padding(16)
                } else {
                    TCTextField("ค้นหาชื่อ Plant เมือง หรือรหัส", text: $search).padding(.horizontal, 16).padding(.vertical, 10)
                    Divider()
                    plantList(station)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus").font(.system(size: 28)).foregroundStyle(Theme.inkMuted.opacity(0.6))
                    Text("แตะสถานีทางซ้ายเพื่อเลือก Plant ที่ตรงกัน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    /// Which server the plants are read from: a switch between several, a line for one, the stub's note without any.
    @ViewBuilder private var serverLine: some View {
        HStack(spacing: 12) {
            if draft.servers.count > 1 {
                Text("เซิร์ฟเวอร์").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 8)
                MonSwitch(options: draft.servers.map { ($0.id as UUID?, $0.name) }, selection: $serverID)
            } else if let s = draft.servers.first {
                Image(systemName: "server.rack").font(.system(size: 14)).foregroundStyle(Theme.primary)
                Text(s.name + " · " + s.host).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer()
            } else if stub {
                Image(systemName: "server.rack").font(.system(size: 14)).foregroundStyle(Theme.primary)
                Text("เซิร์ฟเวอร์ตัวอย่าง · ไม่ต่อเครือข่าย").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Spacer()
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
    }

    @ViewBuilder private func plantList(_ station: Monitoring.Station) -> some View {
        let key = cacheKey ?? Self.stubKey
        if loading.contains(key) {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in TCSkeletonRow(avatar: false).padding(.horizontal, 16) }
            }
            .accessibilityIdentifier("monitoring.pairing.loading")
        } else if let error = errors[key] {
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.sarabunFixed(14)).foregroundStyle(Theme.dangerText)
                Button { errors[key] = nil; Task { await load() } } label: { Text(verbatim: "ลองใหม่") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: false))
            }
            .padding(16)
        } else {
            let all = plants[key] ?? []
            let shown = Monitoring.Pairing.ordered(Monitoring.Pairing.search(all, search), station: station.name, kWp: station.kWp)
            let suggested = Set(Monitoring.Pairing.suggest(station: station.name, kWp: station.kWp, in: all).map(\.id))
            ScrollView {
                VStack(spacing: 0) {
                    if shown.isEmpty {
                        Text(all.isEmpty ? "เซิร์ฟเวอร์นี้ไม่มี Plant" : "ไม่พบ Plant ที่ตรงกับคำค้น").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(shown) { p in
                        plantRow(p, station: station, suggested: suggested.contains(p.id))
                        Divider()
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text("แนะนำ = ชื่อตรงกับสถานี หรือขนาดต่างกันไม่เกิน 10 %").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Spacer()
                if canEdit, draft.pairings[station.id] != nil {
                    Button { draft.unpair(station.id) } label: { Text(verbatim: "เลิกจับคู่") }
                        .buttonStyle(TCButtonStyle(.destructive, size: .card, fullWidth: false))
                        .accessibilityIdentifier("monitoring.pairing.unpair")
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
        }
    }

    private func plantRow(_ p: Monitoring.Pairing.Plant, station: Monitoring.Station, suggested: Bool) -> some View {
        let current = draft.pairings[station.id] == p.id
        let elsewhere = stations.first { $0.id != station.id && draft.pairings[$0.id] == p.id }
        return Button {
            draft.pair(station.id, plant: p.id, server: stub ? draft.servers.first?.id : server?.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: current ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(current ? Theme.success : Theme.borderControl)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(p.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        if suggested { MonChip("แนะนำ", .info) }
                    }
                    Text([p.detail.isEmpty ? nil : p.detail, "Plant " + p.id,
                          elsewhere.map { "จับคู่กับ " + ($0.mpNumber.map { "MP \($0)" } ?? $0.name) + " แล้ว" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.sarabunFixed(12)).foregroundStyle(elsewhere == nil ? Theme.inkMuted : Theme.warningInk)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityIdentifier("monitoring.pairing.plant." + p.id)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    // MARK: loading

    /// Reads the server's plants once (`plant/list`, every page), or the stub's after a moment.
    private func load() async {
        guard let key = cacheKey, plants[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        if stub {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            plants[key] = Monitoring.Pairing.demoPlants()
            return
        }
        guard let server, let token = MonitoringToken.token(server.id), let url = URL(string: server.url) else {
            errors[key] = "ไม่มี Token ของเซิร์ฟเวอร์นี้ในเครื่อง · ใส่ Token ในหน้าตั้งค่าก่อน"
            return
        }
        let api = GrowattAPI(baseURL: url, token: token)
        var all: [Monitoring.Pairing.Plant] = []
        do {
            for page in 1...10 {
                let rows = try await api.plants(page: page)
                all += rows.map(Monitoring.Pairing.Plant.init)
                if rows.count < 100 { break }
            }
            guard !Task.isCancelled else { return }
            plants[key] = all
            errors[key] = nil
        } catch let f as GrowattAPI.Failure {
            errors[key] = f.message
        } catch {
            errors[key] = GrowattAPI.Failure.badResponse.message
        }
    }

    // MARK: parts

    private func card<Content: View>(_ title: String, note: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                if let note { Text(note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted.opacity(0.75)).lineLimit(1) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            content()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}
