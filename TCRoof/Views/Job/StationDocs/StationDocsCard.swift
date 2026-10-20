import SwiftUI
import TCRoofUI
import TCRoofCore

/// Job detail's "เอกสารสถานี กปภ." card: ready papers per submission, papers that expire soon, and the way into the list.
struct StationDocsCard: View {
    @Bindable var job: Job
    @State private var library = StationDocsStore.loadLibrary()

    var body: some View {
        let ctx = job.stationContext
        let station = job.stationDocs
        let expiring = StationDocs.kinds.compactMap { k -> (StationDocs.Kind, StationDocs.Expiry)? in
            StationDocs.expiry(k, StationDocs.state(k, station: station, library: library)).map { (k, $0) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("เอกสารสถานี กปภ.").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                if ctx.over200kVA { TCStatusChip("ต้องยื่น พค.2", fill: Theme.warningSoft, text: Theme.pending) }
            }
            packages(ctx, station)
            if let record = station.erc {
                Label("ลำดับ กกพ. · " + ERCFlow.headline(record, job.ercContext), systemImage: "arrow.triangle.branch")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                ForEach(ERCFlow.waits(record, job.ercContext).filter { $0.left <= ERCNotification.lead }, id: \.step) { wait in
                    Label("\(wait.title) \(wait.text)", systemImage: "clock.badge.exclamationmark")
                        .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(wait.left < 0 ? Theme.dangerText : Theme.pending)
                }
            }
            ForEach(expiring, id: \.0.id) { pair in
                Label(expiryText(pair.0, pair.1), systemImage: "exclamationmark.triangle.fill")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            }
            NavigationLink { StationDocsScreen(job: job) } label: {
                Label("เปิดรายการเอกสาร", systemImage: "folder").font(.sarabun(15, .semibold, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .onAppear { library = StationDocsStore.loadLibrary() }
    }

    private func packages(_ ctx: StationDocs.Context, _ station: StationDocs.Station) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: isPhone ? 2 : 5), spacing: 10) {
            ForEach(StationDocs.packages(ctx)) { p in
                let pr = StationDocs.progress(p, station: station, library: library, ctx)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    Text("\(pr.ready)/\(pr.total)").font(.sarabun(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(pr.isComplete ? Theme.okText : Theme.navy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func expiryText(_ kind: StationDocs.Kind, _ e: StationDocs.Expiry) -> String {
        switch e {
        case .expired: "\(kind.name) หมดอายุแล้ว"
        case .soon(let d): "\(kind.name) หมดอายุใน \(d) วัน"
        }
    }
}
