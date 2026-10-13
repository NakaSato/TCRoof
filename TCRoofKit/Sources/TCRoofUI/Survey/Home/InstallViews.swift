#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// "เพิ่มโครงการติดตั้ง": every survey still in the survey stage, complete ones first; only those can be added.
struct InstallPickerSheet: View {
    let jobs: [Job]
    let add: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var rows: [Job] {
        jobs.sorted { a, b in
            if a.canMoveToInstall != b.canMoveToInstall { return a.canMoveToInstall }
            return a.completion.fraction > b.completion.fraction
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เพิ่มโครงการติดตั้ง").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                    Text("ดึงข้อมูลจากงานสำรวจ · เลือกได้เฉพาะงานที่สำรวจครบ 100%").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Divider()
            if rows.isEmpty {
                TCEmptyState("ไม่มีงานสำรวจ", systemImage: "list.clipboard", description: Text("งานสำรวจทุกงานย้ายไปงานติดตั้งแล้ว"))
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { j in
                            row(j)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Theme.surface)
    }

    func row(_ j: Job) -> some View {
        let ok = j.canMoveToInstall
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(j.docNo.isEmpty ? "NO. —" : "NO.\(j.docNo)").font(.sarabun(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                Text(j.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : j.projectName).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(detail(j)).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1)
            .opacity(ok ? 1 : 0.55)
            Spacer(minLength: 0)
            if ok {
                Button { add(j.id) } label: {
                    Text("เพิ่มได้").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(minWidth: 120, minHeight: 44).padding(.horizontal, 6)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("เพิ่ม \(j.projectName) เป็นงานติดตั้ง")
            } else {
                Text("เพิ่มไม่ได้").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.disabledText)
                    .frame(minWidth: 120, minHeight: 44).padding(.horizontal, 6)
                    .background(Theme.disabledFill, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("เพิ่มไม่ได้ สำรวจยังไม่ครบ")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    /// "สถานที่ · 90 kWp · 36 รูป"
    func detail(_ j: Job) -> String {
        let kw = j.values.text("capacity").trimmingCharacters(in: .whitespaces)
        return [j.values.text("address").trimmingCharacters(in: .whitespacesAndNewlines), kw.isEmpty ? "" : kw + " kWp", "\(j.photoCount) รูป"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Installation tracking of one job.
// TODO: build from the canvas board `iPadInstall.dc.html` (steps, team, handover); only a placeholder for now.
struct InstallTrackingView: View {
    let job: Job

    var body: some View {
        VStack(spacing: 12) {
            Text(job.docNo.isEmpty ? "NO. —" : "NO.\(job.docNo)").font(.sarabun(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            Text(job.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : job.projectName).font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)
            Label("อยู่ระหว่างพัฒนา", systemImage: "hammer").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.inkMuted).padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("ติดตามงานติดตั้ง")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .tcPadNavBar("ติดตามงานติดตั้ง", trail: ["หน้าหลัก", "PWA Solar Survey"])
    }
}
#endif
