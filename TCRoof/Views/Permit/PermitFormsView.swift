import SwiftUI
import TCRoofUI
import TCRoofCore

/// The job's PEA permit forms (Solar Rooftop ภาคประชาชน 2569, บ้านอยู่อาศัย).
struct PermitFormsView: View {
    let job: Job

    @State private var poa: PowerOfAttorney?
    @State private var selfCert: SelfCertification?

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "เอกสารขออนุญาต PEA", trail: ["หน้าหลัก", job.code], current: "เอกสารขออนุญาต PEA")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Solar Rooftop ภาคประชาชน 2569 · บ้านอยู่อาศัย · แบบฟอร์มต้นฉบับของ กฟภ. เติมข้อมูลแล้วพิมพ์ให้เซ็น")
                        .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
                    row("หนังสือมอบอำนาจ", "ใช้ตอนยื่นคำขอ ส่งเอกสารสัญญา และขอเชื่อมต่อ · เซ็นสด + อากร 30 บาท",
                        "signature", issues: poa?.issues) { PowerOfAttorneyView(job: job) }
                    row("แบบฟอร์มรับรองตนเอง (VSPP)", "ขอเชื่อมต่อ (ขั้น 9) · 12 หน้า พร้อมเอกสารแนบ 1–10 · วิศวกรเซ็นทุกแผ่น",
                        "checkmark.seal", issues: selfCert?.issues) { SelfCertificationView(job: job) }
                }
                .padding(isPhone ? Space.l : Space.xl)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let store = PermitStore(job: job)
            poa = store.load(PowerOfAttorney.self, PowerOfAttorneyView.file)
            selfCert = store.load(SelfCertification.self, SelfCertificationView.file)
        }
    }

    private func row<D: View>(_ title: String, _ detail: String, _ symbol: String, issues: [String]?,
                              @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: Radius.lg))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text(detail).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                status(issues)
                Image(systemName: "chevron.right").foregroundStyle(Theme.chevron)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func status(_ issues: [String]?) -> some View {
        if let issues {
            if issues.isEmpty { TCStatusChip("ครบ", kind: .done) } else { TCStatusChip("ขาด \(issues.count)", kind: .pending) }
        } else {
            TCStatusChip("ยังไม่เริ่ม", fill: Theme.disabledFill, text: Theme.inkMuted)
        }
    }
}
