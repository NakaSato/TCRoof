#if canImport(UIKit)
import SwiftUI
import SurveyCore

/// Blue header (title, search, sync, new survey, more menu), filter boxes and the list heading.
extension SurveyHomeView {
    var engineerLine: String {
        let e = model.settings.engineer.trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? subtitle : subtitle + " · วิศวกร " + e
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if isPushed {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("ย้อนกลับ")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: compact ? 24 : 30, weight: .bold))
                    Text(engineerLine).font(.subheadline).opacity(0.9).lineLimit(compact ? 2 : 1)
                }
                Spacer(minLength: 12)
                if !compact {
                    searchField.frame(width: 300)
                    syncButton
                    newButton
                }
                moreMenu
            }
            if compact {
                searchField
                HStack(spacing: 10) { syncButton; newButton }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 16 : 24).padding(.vertical, compact ? 14 : 20)
        .frame(maxWidth: 1240).frame(maxWidth: .infinity)
        // runs up under the status bar
        .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
            .padding(.top, -400))
    }

    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Home.muted)
            TextField("ค้นหาเลขที่ ชื่อโครงการ ที่อยู่", text: $search).foregroundStyle(Home.navy)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Home.muted) }
                    .accessibilityLabel("ล้างคำค้น")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    var newButton: some View {
        Button { showNew = true } label: {
            Label("งานสำรวจใหม่", systemImage: "plus").font(.body.weight(.bold)).foregroundStyle(Home.primary)
                .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: compact ? .infinity : nil)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    var moreMenu: some View {
        Menu {
            Button { showDriveOpen = true } label: { Label("เปิดจาก Google Drive", systemImage: "icloud.and.arrow.down") }
            Button { importing = true } label: { Label("นำเข้าไฟล์ข้อมูล (.json)", systemImage: "square.and.arrow.down") }
            Button { do { share = try model.exportBackup() } catch { self.error = error.localizedDescription } } label: { Label("สำรองข้อมูลทุกงาน", systemImage: "externaldrive") }
                .disabled(model.jobs.isEmpty)
            Divider()
            Button { showSettings = true } label: { Label("ตั้งค่า", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                .background(.white.opacity(0.18), in: Circle())
        }
        .accessibilityLabel("เมนูเพิ่มเติม")
    }

    var syncButton: some View {
        let n = model.jobsToSync.count
        return Button { syncAll() } label: {
            Label(n > 0 ? "ซิงก์ (\(n))" : "ซิงก์แล้ว", systemImage: n > 0 ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.45)))
        }
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
                        Text(f.title).font(.subheadline.weight(.bold))
                        Text(f.detail).font(.caption).foregroundStyle(Home.muted)
                    }
                    .foregroundStyle(Home.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Home.primary : Home.border, lineWidth: on ? 2 : 1))
                    .shadow(color: on ? Home.primary.opacity(0.15) : .clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var listHeading: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(filter.heading).font(.title3.bold()).foregroundStyle(Home.navy)
                Text("\(shown.count) งาน").font(.subheadline).foregroundStyle(Home.muted)
            }
            if !compact { Spacer() }
            HStack(spacing: 8) {
                Text("เรียงตาม").font(.caption).foregroundStyle(Home.muted)
                Picker("เรียงตาม", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
            }
        }
    }
}
#endif
