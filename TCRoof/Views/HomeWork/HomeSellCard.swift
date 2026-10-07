import SwiftUI
import TCRoofUI
import TCRoofCore

/// A date the job may or may not have yet: a button to set it, then a Thai (พ.ศ.) date picker and a clear button.
struct HomeDateRow: View {
    let title: String
    @Binding var date: Date?
    var caption: String
    var warning = false
    var setLabel = "ใส่วันที่"

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(caption).font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(warning ? Theme.dangerText : Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            if date != nil {
                DatePicker(title, selection: Binding(get: { date ?? .now }, set: { date = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "th_TH"))
                    .environment(\.calendar, Calendar(identifier: .buddhist))
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle").frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                .accessibilityLabel("ล้าง\(title)")
            } else {
                TCButton(setLabel, systemImage: "calendar", kind: .secondary, size: .card) { date = .now }
            }
        }
    }
}

/// Selling route (ภาคประชาชน 2569): the sell request and its locked sizes, the announcement and the three 30-day
/// deadlines it starts, SCOD, the connection request and COD.
struct HomeSellCard: View {
    @Binding var home: HomeJob

    var body: some View {
        PermitSection(title: "คำขอขายไฟและสัญญา",
                      subtitle: "ยื่น PPIM 2 ครั้ง: คำขอขายไฟ → ประกาศ · ชำระ · สัญญา → ขออนุญาตเชื่อมต่อ") {
            PermitField("เลขคำขอขายไฟ (PPIM)", text: $home.ppimRequestNo)
            offerRow
            HomeDateRow(title: "วันที่ PEA ประกาศรายชื่อ", date: $home.announcedOn,
                        caption: "เริ่มนับ 30 วัน: ชำระ 2,140 บาท · ส่งเอกสารสัญญา 2 ชุด · ลงนามสัญญา")
            HomeDateRow(title: "SCOD ตามสัญญา", date: $home.scod, caption: "ต้องจ่ายไฟเข้าระบบภายในวันนี้ (ภายในปี 2570)")
            if !home.sellDeadlines.isEmpty { deadlines }
            PermitField("เลขคำขอขออนุญาตเชื่อมต่อ (PPIM)", text: $home.connectRequestNo)
            HomeDateRow(title: "วัน COD ที่ PEA แจ้ง", date: $home.cod, caption: "ลงทะเบียน e-bill และบัญชีรับเงินภายในสิ้นเดือนนี้")
        }
    }

    // MARK: Sizes filed in the sell request

    private var offerRow: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ขนาดที่ยื่นขอขายไฟ").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(offerText).font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(home.offerIssues.isEmpty ? Theme.inkMuted : Theme.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            TCButton(home.offer == nil ? "ล็อกขนาด" : "ล็อกใหม่", systemImage: "lock", kind: .secondary, size: .card) {
                home.lockOffer()
            }
            .disabled(HomeJob.number(home.pvKWp) == nil || HomeJob.number(home.inverterKW) == nil || HomeJob.number(home.sellKW) == nil)
        }
    }

    private var offerText: String {
        guard let o = home.offer else {
            return "ล็อกตอนยื่นคำขอขายไฟ คำขอเชื่อมต่อยื่นเกินค่าเหล่านี้ไม่ได้"
        }
        let parts = [o.pvKWp.map { "แผง \(HomeOffer.text($0)) kWp" }, o.inverterKW.map { "อินเวอร์เตอร์ \(HomeOffer.text($0)) kW" },
                     o.sellKW.map { "ขาย \(HomeOffer.text($0)) kW" }].compactMap { $0 }
        let issues = home.offerIssues
        return parts.joined(separator: " · ") + (issues.isEmpty ? "" : "\n" + issues.joined(separator: "\n"))
    }

    // MARK: Deadlines

    private var deadlines: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TCFieldLabel("เส้นตาย")
            ForEach(home.sellDeadlines) { deadlineRow($0) }
        }
    }

    private func deadlineRow(_ d: HomeDeadline) -> some View {
        let left = d.daysLeft()
        return HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title).font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ภายใน " + PermitDate.short(d.due)).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Space.s)
            chip(d, left)
        }
        .padding(Space.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    @ViewBuilder private func chip(_ d: HomeDeadline, _ left: Int) -> some View {
        if d.done {
            TCStatusChip("เสร็จแล้ว", kind: .done)
        } else if left < 0 {
            TCStatusChip("เลย \(-left) วัน", kind: .overdue)
        } else if left <= 7 {
            TCStatusChip(left == 0 ? "วันนี้" : "เหลือ \(left) วัน", kind: .pending)
        } else {
            TCStatusChip("เหลือ \(left) วัน", kind: .active)
        }
    }
}
