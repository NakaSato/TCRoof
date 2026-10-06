import SwiftUI
import TCRoofUI
import SwiftData

/// iPhone install list (compact width), the root of the `ติดตั้ง` tab: `PhoneJobQueue` with a segmented
/// บันทึกประจำวัน / ใบตรวจรับ ICL filter that decides what the cards show and open.
struct PhoneInstallList: View {
    @State private var tab: InstallRecordsView.Tab = .logs
    @State private var showPicker = false
    @State private var pendingJob: Job?
    @State private var newLogJob: Job?

    var body: some View {
        PhoneJobQueue(title: "บันทึกงานติดตั้ง", noun: "งานติดตั้ง", historyLabel: "ประวัติบันทึกทั้งหมด",
                      fabSymbol: "plus", fabLabel: "เพิ่มบันทึกงานติดตั้ง", fab: { showPicker = true }) {
            TCSegmented(["บันทึกประจำวัน", "ใบตรวจรับ ICL"],
                        selection: Binding(get: { tab == .logs ? "บันทึกประจำวัน" : "ใบตรวจรับ ICL" },
                                           set: { tab = $0 == "บันทึกประจำวัน" ? .logs : .inspection }),
                        fontSize: 14, style: .filter)
        } history: {
            InstallLogHistoryView()
        } card: { job in
            CompactJobCard(job: job) {
                switch tab {
                case .logs: JobInstallLogsView(job: job)
                case .inspection: InspectionView(job: job)
                }
            } status: {
                switch tab {
                case .logs:
                    CompactStatusBox(key: "บันทึกประจำวัน", value: job.logs.isEmpty ? "ยังไม่มีบันทึก" : "\(job.logs.count) รายการ",
                                     valueColor: job.logs.isEmpty ? Theme.inkMuted : Theme.navy)
                case .inspection:
                    let s = InstallRecordsView.inspectionStatus(job)
                    CompactStatusBox(key: "ใบตรวจรับ", value: s.text, valueColor: s.color)
                }
            }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            if let job = pendingJob {
                pendingJob = nil
                newLogJob = job
            }
        }) {
            JobPickerSheet(title: "เลือกงานที่จะบันทึก") { pendingJob = $0 }
        }
        .sheet(item: $newLogJob) { job in InstallLogFormView(job: job, log: nil) }
    }
}
