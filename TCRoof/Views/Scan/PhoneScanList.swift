import SwiftUI
import TCRoofUI
import SwiftData

/// iPhone scan list (compact width, `สแกนอุปกรณ์` from the home row): `PhoneJobQueue` whose cards show the panels
/// scanned against the estimate and open the job's devices; the FAB picks a job and opens the scanner.
struct PhoneScanList: View {
    @State private var showPicker = false
    @State private var pendingJob: Job?
    @State private var scanJob: Job?
    @State private var sync = CloudSync.shared

    var body: some View {
        PhoneJobQueue(title: "สแกนอุปกรณ์", noun: "งานติดตั้ง", historyLabel: "ประวัติการสแกน",
                      fabSymbol: "barcode.viewfinder", fabLabel: "สแกนอุปกรณ์", fab: { showPicker = true },
                      loading: sync.isLoading("devices")) {
            EmptyView()
        } history: {
            ScanHistoryView()
        } card: { job in
            CompactJobCard(job: job) { JobDevicesView(job: job) } status: { status(job) }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            if let job = pendingJob {
                pendingJob = nil
                scanJob = job
            }
        }) {
            JobPickerSheet(title: "เลือกงานที่จะสแกนอุปกรณ์") { pendingJob = $0 }
        }
        .fullScreenCover(item: $scanJob) { job in ScannerView(job: job) }
    }

    /// `แผง 12/26 | อื่น 1` with a short bar of panels scanned against the estimate.
    private func status(_ job: Job) -> some View {
        let panels = job.devices.filter { $0.kind == .panel }.count
        let others = job.devices.count - panels
        let estimate = max(job.estimatedPanels, 1)
        return CompactStatusBox(key: "แผง", value: "\(panels)/\(job.estimatedPanels)" + (others > 0 ? " | อื่น \(others)" : "")) {
            ProgressView(value: Double(min(panels, estimate)), total: Double(estimate))
                .tint(Theme.teal).frame(width: 64)
                .accessibilityHidden(true)
        }
    }
}
