#if canImport(UIKit)
import SwiftUI
import SurveyCore

/// "Start a new survey": pick the kind of site; its sections are added and can be changed later in the editor.
struct NewJobSheet: View {
    let create: (JobTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    Text("เลือกประเภทสถานที่").font(.subheadline.weight(.bold)).foregroundStyle(Home.muted)
                    ForEach(JobTemplate.all) { t in
                        Button { create(t) } label: { card(t) }.buttonStyle(.plain)
                    }
                    Label("ทุกแบบมี A ข้อมูลทั่วไป และ E สรุปผลและลงนาม · เพิ่มหรือลบหัวข้อภายหลังได้ในหน้าแก้ไขงาน", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Home.muted).padding(.top, 4)
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
                Text("เริ่มงานสำรวจใหม่").font(.title2.bold())
                Text("แบบสำรวจเพื่อออกแบบ (เบื้องต้น)").font(.subheadline).opacity(0.9)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.bold)).frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("ยกเลิก")
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing))
    }

    func card(_ t: JobTemplate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.symbol[t.id] ?? "doc").font(.title2).foregroundStyle(Home.primary)
                .frame(width: 48, height: 48).background(Home.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(t.label).font(.system(size: 17, weight: .bold)).foregroundStyle(Home.navy)
                if t.modules.isEmpty {
                    Text("ยังไม่มีหัวข้อสำรวจ — เพิ่มเองทีละรายการ").font(.subheadline).foregroundStyle(Home.muted)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(t.modules, id: \.self) { m in
                            Text("\(m.code) \(Schema.spec(m).short)").font(.caption.weight(.bold)).foregroundStyle(Home.navy)
                                .padding(.horizontal, 9).padding(.vertical, 4).background(Home.mint.opacity(0.45), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Home.primary).padding(.top, 14)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Home.border))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    static let symbol = ["station": "building.2", "house": "house", "blank": "square.dashed"]
}
#endif
