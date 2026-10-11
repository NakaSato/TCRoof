#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import TCRoofUI

/// "Start a new survey": pick the kind of site; its sections are added and can be changed later in the editor.
struct NewJobSheet: View {
    let create: (JobTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    Text("เลือกประเภทสถานที่").font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    ForEach(JobTemplate.all) { t in
                        Button { create(t) } label: { card(t) }.buttonStyle(.plain)
                    }
                    Label("ทุกแบบมี A ข้อมูลทั่วไป และ E สรุปผลและลงนาม · เพิ่มหรือลบหัวข้อภายหลังได้ในหน้าแก้ไขงาน", systemImage: "info.circle")
                        .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).padding(.top, 4)
                }
                .padding(20)
            }
        }
        .background(Paper.page)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("เริ่มงานสำรวจใหม่").font(.sarabun(22, .bold, relativeTo: .title2))
                Text("แบบสำรวจเพื่อออกแบบ (เบื้องต้น)").font(.sarabun(15, relativeTo: .subheadline)).opacity(0.9)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.sarabun(17, .bold, relativeTo: .body)).frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("ยกเลิก")
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(20)
        .background(LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .leading, endPoint: .trailing))
    }

    func card(_ t: JobTemplate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.symbol[t.id] ?? "doc").font(.sarabun(22, relativeTo: .title2)).foregroundStyle(Theme.primary)
                .frame(width: 48, height: 48).background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(t.label).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.navy)
                if t.modules.isEmpty {
                    Text("ยังไม่มีหัวข้อสำรวจ — เพิ่มเองทีละรายการ").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(t.modules, id: \.self) { m in
                            Text("\(m.code) \(Schema.spec(m).short)").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.navy)
                                .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.mint.opacity(0.45), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary).padding(.top, 14)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    static let symbol = ["station": "building.2", "house": "house", "blank": "square.dashed"]
}
#endif
