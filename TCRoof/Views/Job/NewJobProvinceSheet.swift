import SwiftUI
import TCRoofUI
import TCRoofCore
import SurveyUI

/// The full-height province sheet of the new-customer sheet (docs/ui/tcroof-new-job-iphone §7): search, `ใช้บ่อย` chips,
/// and all 77 provinces grouped by first consonant.
struct NewJobProvinceSheet: View {
    @Binding var province: String
    let close: () -> Void
    @State private var query = ""

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var groups: [(key: String, names: [String])] { ThaiProvince.grouped(query) }
    private var found: Int { groups.reduce(0) { $0 + $1.names.count } }

    var body: some View {
        VStack(spacing: 0) {
            top
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(searching ? "พบ \(found) จังหวัด" : "ทั้งหมด \(ThaiProvince.all.count) จังหวัด")
                        .font(.sarabun(13)).foregroundStyle(Theme.groupHeader).padding(.leading, 16)
                    if found == 0 {
                        Text("ไม่พบจังหวัดที่ค้นหา").font(.sarabun(15)).foregroundStyle(Theme.groupFooter)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if searching {
                        card(groups.flatMap(\.names))
                    } else {
                        ForEach(groups, id: \.key) { g in
                            Text(g.key).font(.sarabun(13, .bold)).foregroundStyle(Theme.groupHeader).padding(.leading, 16).padding(.top, 6)
                            card(g.names)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("จังหวัด").font(.sarabun(17, .bold))
                Spacer()
                Button(action: close) {
                    Text("เสร็จ").font(.sarabun(16, .semibold)).foregroundStyle(Theme.iosBlue).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            searchField
            if !searching { frequent }
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.groupFooter)
            TextField("ค้นหาจังหวัด", text: $query).font(.sarabun(16)).submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.groupFooter)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(.leading, 12).frame(minHeight: 44)
        .background(Theme.searchFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var frequent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ใช้บ่อย").font(.sarabun(13)).foregroundStyle(Theme.groupHeader)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(ThaiProvince.frequent, id: \.self) { name in
                    let on = name == province
                    Button { pick(name) } label: {
                        Text(name).font(.sarabun(15, .semibold)).foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 13).frame(minHeight: 40)
                            .background(on ? Theme.iosBlue : Theme.surface, in: Capsule())
                            .overlay { if !on { Capsule().strokeBorder(Theme.separatorLine, lineWidth: 1) } }
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func card(_ names: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.element) { i, name in
                let on = name == province
                Button { pick(name) } label: {
                    HStack {
                        Text(name).font(.sarabun(16, on ? .semibold : .regular)).foregroundStyle(on ? Theme.iosBlue : Color.primary)
                        Spacer()
                        if on { Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.iosBlue) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .overlay(alignment: .bottom) {
                    if i < names.count - 1 { Theme.separatorLine.frame(height: 1).padding(.leading, 16) }
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pick(_ name: String) {
        province = name
        close()
    }
}
