#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore

/// B1 on iPad (docs/ui/survey-b1): every building panel (`.panel` section) on one page. Landscape has the master list, the
/// selected building's photos and its A3 link / load side by side; portrait stacks them under a row of building chips.
/// Field ids are unchanged and the new answers (`a3Breaker`, `pvPoint`, `spareSlots`) are optional; iPhone keeps `groupPage`.
struct PanelsPageWide: View {
    @Binding var job: Job
    /// The building shown.
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    var stacked = false
    /// Shows another section (a card tapped, a building added or deleted).
    let select: (UUID?) -> Void
    /// Opens the old per-section form for this building.
    let openForm: () -> Void
    @Environment(SurveyModel.self) var model

    enum PhotoField: String { case wide = "photoWide", breaker = "photoBreaker" }
    @State var viewing: Photo?
    @State var renaming = false
    @State var nameText = ""
    @State var confirmDelete = false
    /// The PV point being dragged out on the wide photo.
    @State var dragRect: (ShapePoint, ShapePoint)?

    static let listWidth: CGFloat = 240, sideWidth: CGFloat = 380, gap: CGFloat = 24

    var panels: [SurveyModule] { job.modules.filter { $0.type == .panel } }
    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var module: SurveyModule? { index.map { job.modules[$0] } }
    var values: Values { module?.values ?? Values() }
    var title: String { module.map { BuildingPanels.name($0, in: job) } ?? "" }

    func set(_ id: String, _ v: FieldValue?) { if let i = index { job.modules[i].values[id] = v } }
    func text(_ id: String) -> Binding<String> {
        Binding(get: { values.text(id) }, set: { set(id, $0.isEmpty ? nil : .text($0)) })
    }

    func label(_ t: String, required: Bool = false, aside: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(t) + (required ? Text(" *").foregroundColor(Home.danger) : Text(""))).font(.system(size: 17, weight: .bold))
            Spacer(minLength: 8)
            if let aside { Text(aside).font(.footnote).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8) }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: "ตู้ไฟฟ้าอาคาร · \(panels.count) อาคาร")
            if stacked { stackedLayout } else { wideLayout }
        }
        .foregroundStyle(Home.navy)
        .sheet(item: $viewing) { p in if let img = model.image(p, in: job.id) { PhotoViewer(image: img, title: title) } }
        .alert("ชื่ออาคาร", isPresented: $renaming) {
            TextField("เช่น โรงสูบน้ำ", text: $nameText)
            Button("ตกลง") { BuildingPanels.rename(&job, panel: moduleID, to: nameText.trimmingCharacters(in: .whitespaces)) }
            Button("ยกเลิก", role: .cancel) {}
        }
        .confirmationDialog("ลบอาคาร \(title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("ลบอาคาร", role: .destructive) { delete() }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("ภาพและข้อมูลของอาคารนี้จะถูกลบ และเบรกเกอร์ในผัง A3 จะไม่ชี้มาที่อาคารนี้อีก") }
        .onAppear { refreshLink() }
    }

    var wideLayout: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ScrollView { buildingList.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(width: Self.listWidth)
            ScrollView { middleColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(maxWidth: .infinity)
            ScrollView { sideColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(width: Self.sideWidth)
        }
        .frame(maxHeight: .infinity)
    }

    var stackedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                buildingChips
                middleColumn
                sideColumn
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: buildings

    var buildingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("อาคาร").font(.system(size: 17, weight: .bold))
            ForEach(panels) { m in buildingCard(m) }
            addButton
        }
    }

    func buildingCard(_ m: SurveyModule) -> some View {
        let on = m.id == moduleID, pill = BuildingPanels.pill(m.values)
        return Button { select(m.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(BuildingPanels.name(m, in: job)).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    pillView(pill)
                }
                Text(BuildingPanels.subLine(m, in: job)).font(.system(size: 12.5)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Home.primary : Home.border, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func pillView(_ p: BuildingPanels.Pill) -> some View {
        Text(p.text).font(.system(size: 12, weight: .bold)).lineLimit(1)
            .foregroundStyle(p.ok ? Home.ok : Home.red)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((p.ok ? Home.ok : Home.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    var addButton: some View {
        Button { add() } label: {
            HStack(spacing: 6) {
                A2Icon(name: "ui-add", fallback: "plus", size: 14)
                Text("เพิ่มอาคาร").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Home.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.primary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Portrait: the buildings as a row of chips.
    var buildingChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(panels) { m in
                    let on = m.id == moduleID, pill = BuildingPanels.pill(m.values)
                    Button { select(m.id) } label: {
                        HStack(spacing: 6) {
                            Text(BuildingPanels.name(m, in: job)).font(.system(size: 15, weight: .bold)).lineLimit(1)
                            pillView(pill)
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Home.primary : Home.border, lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
                addButton.frame(width: 150)
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }

    func add() {
        let used = Set(panels.map(\.name))
        var n = panels.count + 1
        while used.contains("อาคาร \(n)") { n += 1 }
        let m = SurveyModule(type: .panel, name: "อาคาร \(n)")
        job.insertModule(m)
        select(m.id)
    }

    func delete() {
        let list = panels
        let i = list.firstIndex { $0.id == moduleID } ?? 0
        let next = list.indices.contains(i + 1) ? list[i + 1].id : i > 0 ? list[i - 1].id : nil
        BuildingPanels.delete(&job, panel: moduleID)
        select(next)
    }

    /// Picks up an AT changed on A3 since the link was made.
    func refreshLink() {
        guard let m = module, let link = BuildingPanels.linked(m, in: job), !link.at.isEmpty, link.at != m.values.text(BuildingPanels.Key.breakerAT) else { return }
        BuildingPanels.refresh(&job, panel: moduleID)
    }

    // MARK: middle

    var middleColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            widePhotoCard
            breakerPhotoCard
        }
    }

    var heading: some View {
        HStack(spacing: 10) {
            Button { nameText = module?.name ?? ""; renaming = true } label: {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 26, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Home.muted)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("แตะเพื่อเปลี่ยนชื่ออาคาร")
            Spacer(minLength: 8)
            Button { openForm() } label: {
                Text("แบบฟอร์มเดิม").font(.system(size: 13, weight: .semibold)).foregroundStyle(Home.primary)
                    .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { confirmDelete = true } label: {
                Text("ลบอาคาร").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.red)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.red.opacity(0.8)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
