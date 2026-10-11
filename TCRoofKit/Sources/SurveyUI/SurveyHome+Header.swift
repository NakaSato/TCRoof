#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import TCRoofUI

/// Blue header (title, search, more menu), stage tabs, filter boxes, list heading and the floating add buttons.
extension SurveyHomeView {
    var engineerLine: String {
        let e = model.settings.engineer.trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? subtitle : subtitle + " · วิศวกร " + e
    }

    var header: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .center, spacing: 12) {
                if isPushed {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.sarabun(20, .semibold, relativeTo: .title3)).frame(width: 40, height: 40)
                            .background(Theme.onPrimary.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("ย้อนกลับ")
                }
                VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                    Text(title).font(.system(size: compact ? 22 : 30, weight: .bold))
                    // iPhone: the subtitle only (docs/ui/pwa-solar-survey-iphone)
                    if compact {
                        Text(subtitle).font(.system(size: 13)).opacity(0.9).lineLimit(1).truncationMode(.tail)
                    } else {
                        Text(engineerLine).font(.system(size: 15)).opacity(0.92).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if !compact { searchField.frame(width: 330) }
                moreMenu
            }
            if compact { searchField }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, compact ? 16 : 24).padding(.top, compact ? 6 : 22).padding(.bottom, compact ? 14 : 26)
        .frame(maxWidth: 1240).frame(maxWidth: .infinity)
        // runs up under the status bar
        .background(LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .leading, endPoint: .trailing)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
            .padding(.top, -400))
    }

    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
            TextField(compact ? "ค้นหาเลขที่ ชื่อโครงการ…" : "ค้นหาเลขที่ ชื่อโครงการ สถานที่…", text: $search).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted) }
                    .accessibilityLabel("ล้างคำค้น")
            }
        }
        .padding(.horizontal, compact ? 12 : 14).frame(height: compact ? 44 : 46)
        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: stage tabs

    var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(JobStage.allCases.enumerated()), id: \.element) { i, t in
                let on = tab == t
                Button { withAnimation(.snappy) { tab = t } } label: {
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 22, height: 22).background(on ? Theme.primary : Theme.disabledText, in: Circle())
                        // iPhone: drop the count before the name gets cut
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { Text(t.title).font(.sarabun(15, .bold, relativeTo: .subheadline)); countText(t) }
                            Text(t.title).font(.sarabun(15, .bold, relativeTo: .subheadline))
                            Text(t.shortTitle).font(.sarabun(15, .bold, relativeTo: .subheadline))
                        }
                        .lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 10).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.15), radius: 3, y: 1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.title) \(model.jobs(in: t).count) งาน")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
    }

    func countText(_ t: JobStage) -> some View {
        Text("\(model.jobs(in: t).count) งาน").font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).monospacedDigit()
    }

    /// Installation or maintenance tab with nothing in it yet.
    var stageEmpty: some View {
        VStack(spacing: 8) {
            Text(tab == .install ? "ยังไม่มีงานติดตั้งในเครื่องนี้" : "ยังไม่มีงานบำรุงรักษา").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            if tab == .install {
                Text("กด \"เพิ่มโครงการ\" เพื่อดึงงานสำรวจที่ครบ 100% มาเป็นงานติดตั้ง").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: compact ? 280 : 520)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderControl.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    @ViewBuilder var floatingButton: some View {
        switch tab {
        case .survey:
            Button { showNew = true } label: {
                if compact {
                    // iPhone: 60 pt with the board's gradient (icons/fab-60.svg)
                    Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 60, height: 60)
                        .background(LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .shadow(color: Theme.navySolid.opacity(0.35), radius: 8, y: 6)
                } else {
                    Image(systemName: "plus").font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 68, height: 68)
                        .background(Theme.primary, in: Circle())
                        .shadow(color: Theme.navy.opacity(0.3), radius: 8, y: 4)
                }
            }
            .accessibilityLabel("งานสำรวจใหม่")
        case .install:
            Button { showInstallPicker = true } label: {
                Label("เพิ่มโครงการ", systemImage: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 28).frame(height: 64)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: Theme.navy.opacity(0.3), radius: 8, y: 4)
            }
        case .maintenance:
            EmptyView()
        }
    }

    var moreMenu: some View {
        Menu {
            // sync moved here from the header (docs/ui/pwa-solar-survey v2)
            let n = model.jobsToSync.count
            Button { syncAll() } label: { Label("ซิงก์ทั้งหมด (\(n))", systemImage: "arrow.triangle.2.circlepath.icloud") }
                .disabled(n == 0 || busy != nil)
            Divider()
            Button { showDriveOpen = true } label: { Label("เปิดจาก Google Drive", systemImage: "icloud.and.arrow.down") }
            Button { importing = true } label: { Label("นำเข้าไฟล์ข้อมูล (.json)", systemImage: "square.and.arrow.down") }
            Button { do { share = try model.exportBackup() } catch { self.error = error.localizedDescription } } label: { Label("สำรองข้อมูลทุกงาน", systemImage: "externaldrive") }
                .disabled(model.jobs.isEmpty)
            Divider()
            Button { showSettings = true } label: { Label("ตั้งค่า", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.sarabun(20, .semibold, relativeTo: .title3)).frame(width: compact ? 44 : 40, height: compact ? 44 : 40)
                .background(Theme.onPrimary.opacity(0.18), in: Circle())
        }
        .accessibilityLabel("เมนูเพิ่มเติม")
    }

    /// "ซิงก์ n งาน" beside the list heading while the รอซิงก์ box is selected.
    var syncListButton: some View {
        let n = model.jobsToSync.count
        return Button { syncAll() } label: {
            Label("ซิงก์ \(n) งาน", systemImage: "arrow.triangle.2.circlepath.icloud")
                .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
        }
        .buttonStyle(.plain)
        .disabled(n == 0 || busy != nil)
    }

    // MARK: stats and list heading

    var stats: some View {
        let jobs = searched
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Filter.allCases, id: \.self) { f in
                let on = filter == f
                Button { withAnimation(.snappy) { filter = f } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(jobs.filter { matches($0, f) }.count)").font(.system(size: 26, weight: .bold)).monospacedDigit()
                        Text(f.title).font(.sarabun(15, .bold, relativeTo: .subheadline))
                        Text(f.detail).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    }
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                    .shadow(color: on ? Theme.primary.opacity(0.15) : .clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// iPhone: one row of three pills instead of the boxes (docs/ui/pwa-solar-survey-iphone); รอซิงก์ stays in the ••• menu,
    /// and shows as a fourth pill only while it is the filter (opened from the sync notification, or kept from the iPad layout).
    var filterPills: some View {
        let jobs = searched
        return HStack(spacing: 6) {
            ForEach([Filter.all, .active, .draft] + (filter == .unsynced ? [.unsynced] : []), id: \.self) { f in
                let on = filter == f
                let n = jobs.filter { matches($0, f) }.count
                Button { withAnimation(.snappy) { filter = f } } label: {
                    HStack(spacing: 5) {
                        Text(f.shortTitle).font(.system(size: 13, weight: on ? .bold : .semibold)).lineLimit(1)
                        Text("\(n)").font(.system(size: 12, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                            .background(on ? Theme.onPrimary.opacity(0.22) : Theme.hairline, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(on ? Theme.onPrimary : Theme.navySolid)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(on ? Theme.navySolid : Theme.surface, in: Capsule())
                    .overlay { if !on { Capsule().stroke(Theme.borderSubtle) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(f.title) \(n) งาน")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// iPhone: heading, count and a sort menu on one row.
    var compactListHeading: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(tab == .survey ? filter.heading : tab.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            Text("\(shown.count) งาน").font(.system(size: 13)).foregroundStyle(Theme.inkMuted).monospacedDigit().lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Picker("เรียงตาม", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sort.title).font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("เรียงตาม \(sort.title)")
        }
    }

    var listHeading: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tab == .survey ? filter.heading : tab.title).font(.sarabun(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
                Text("\(shown.count) งาน").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            }
            if !compact { Spacer() }
            HStack(spacing: 8) {
                if tab == .survey && filter == .unsynced { syncListButton.padding(.trailing, 4) }
                Text("เรียงตาม").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                TCSegmented(Sort.allCases.map(\.title), selection: Binding(
                    get: { sort.title }, set: { t in if let s = Sort.allCases.first(where: { $0.title == t }) { sort = s } }))
                    .frame(width: 330).accessibilityLabel("เรียงตาม")
            }
        }
    }
}

extension JobStage {
    var title: String { [.survey: "งานสำรวจ", .install: "งานติดตั้ง", .maintenance: "งานบำรุงรักษา"][self]! }
    /// For a narrow iPhone tab.
    var shortTitle: String { [.survey: "สำรวจ", .install: "ติดตั้ง", .maintenance: "บำรุงรักษา"][self]! }
}
#endif
