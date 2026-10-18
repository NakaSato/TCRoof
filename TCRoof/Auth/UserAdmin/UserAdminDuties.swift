import SwiftUI
import TCRoofCore
import TCRoofUI

/// `หน้าที่ต้องส่ง · ผู้รับเหมา` (docs/ui/user-admin-iphone states 02, 09, 10): what an external member must send on
/// the jobs assigned to them. Each row reads `ต้องส่ง` while the external cell of its capability (with the pending
/// overrides) lets them do it, else `ปิดอยู่`.
struct DutyCard: View {
    /// The member's assigned jobs.
    let jobs: Int
    let overrides: RoleOverrides

    static let duties: [(tag: String, title: String, detail: String, capability: Capability)] = [
        ("รายวัน", "รายงานประจำวัน", "ทุกวันที่เข้างาน · ทีมของเราเซ็นรับทราบจึงนับเข้าแผน MP", .dailyFill),
        ("R1", "คำขอรายสัปดาห์", "ทุกสัปดาห์ · คน เครื่องมือ แผน ความเสี่ยง · ทีมภายในอนุมัติ", .weeklyRequest),
        ("IEC", "ทดสอบ IEC 62446", "ก่อนและหลังขนาน · ส่งผลให้ทีม ทีมภายในปิด", .iecFillSubmit),
    ]

    static func isDue(_ c: Capability, overrides: RoleOverrides) -> Bool {
        [.allow, .conditional].contains(c.access(.external, overrides: overrides))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("หน้าที่ต้องส่ง · ผู้รับเหมา").font(.sarabun(14, .bold))
             + Text("  " + (jobs > 0 ? "ใน \(jobs) งานที่ได้รับมอบหมาย" : "เริ่มเมื่อได้รับมอบหมายงาน")).font(.sarabun(12.5)))
                .foregroundStyle(Theme.warningText)
            ForEach(Self.duties, id: \.tag) { d in row(d) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dutyFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.dutyLine))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("userAdmin.duties")
    }

    private func row(_ d: (tag: String, title: String, detail: String, capability: Capability)) -> some View {
        let due = Self.isDue(d.capability, overrides: overrides)
        return HStack(spacing: 10) {
            Text(d.tag).font(.sarabun(12, .heavy)).foregroundStyle(Theme.warningText)
                .frame(width: 40, height: 40)
                .background(Theme.warningTint, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text(d.title).font(.sarabun(14, .bold)).foregroundStyle(Theme.navy)
                Text(d.detail).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(due ? "ต้องส่ง" : "ปิดอยู่").font(.sarabun(12, .bold))
                .foregroundStyle(due ? Theme.onPrimary : Theme.inkFaint)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(due ? Theme.warningText : Theme.stripeLight, in: Capsule())
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.title) · \(due ? "ต้องส่ง" : "ปิดอยู่")")
        .accessibilityIdentifier("userAdmin.duty.\(d.capability.rawValue)")
    }
}
