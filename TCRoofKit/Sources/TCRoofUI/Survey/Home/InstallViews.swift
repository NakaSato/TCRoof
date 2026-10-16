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

/// "เพิ่มโครงการบำรุงรักษา": the stations being installed, furthest along first; adding one hands it over.
struct MaintenancePickerSheet: View {
    let stations: [InstallStationSummary]
    let add: (InstallStationSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    var rows: [InstallStationSummary] { stations.sorted { $0.actual != $1.actual ? $0.actual > $1.actual : $0.name < $1.name } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เพิ่มโครงการบำรุงรักษา").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                    Text("เลือกจากงานติดตั้ง · สถานีที่เพิ่มจะนับเป็นส่งมอบแล้ว").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
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
                TCEmptyState("ไม่มีงานติดตั้ง", systemImage: "list.clipboard", description: Text("เพิ่มโครงการเป็นงานติดตั้งก่อน แล้วจึงย้ายมาบำรุงรักษา"))
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { s in
                            row(s)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Theme.surface)
    }

    func row(_ s: InstallStationSummary) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if let mp = s.mpNumber { Text("MP \(mp)").font(.sarabun(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
                Text(s.name).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(detail(s)).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button { add(s) } label: {
                Text("เพิ่ม").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(minWidth: 88, minHeight: 44).padding(.horizontal, 6)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เพิ่ม \(s.name) เป็นงานบำรุงรักษา")
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    /// "ติดตั้ง 85% · 90 kWp · TCR02"
    func detail(_ s: InstallStationSummary) -> String {
        let kWp = s.kWp.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        return ["ติดตั้ง \(Int(s.actual.rounded()))%", s.kWp > 0 ? kWp + " kWp" : "", s.contractor].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
#endif
