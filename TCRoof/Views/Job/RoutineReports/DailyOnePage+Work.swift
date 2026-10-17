import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

// Today's work (docs/ui/daily-report-ipad §4): a tab per line, then the selected line's panel with its quick picks,
// photos and standing against the MP plan, and its materials and problems under it.

extension DailyOnePage {
    var workCard: some View {
        AnyView(
            VStack(spacing: 0) {
                AnyView(lineTabs)
                if let i = report.progress.firstIndex(where: { $0.id == selected }) ?? report.progress.indices.first {
                    Rectangle().fill(color(report.progress[i])).frame(height: 2).padding(.horizontal, 12)
                    ScrollView {
                        DailyLinePanel(page: self, lineID: report.progress[i].id, selection: $selected).padding(12)
                    }
                } else {
                    emptyWork
                }
            }
            .frame(maxHeight: .infinity)
            .dailyCard()
        )
    }

    private var lineTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(report.progress) { line in AnyView(tab(line)) }
                Button { showAdd = true } label: {
                    Label("งาน", systemImage: "plus").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 14).frame(height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("เพิ่มงาน")
            }
            .padding(12)
        }
    }

    private func tab(_ line: RoutineReport.ProgressLine) -> some View {
        let on = selected == line.id, c = color(line), today = line.percent - before(line)
        return Button { selected = line.id } label: {
            HStack(spacing: 8) {
                Text("\(number(line))").font(.sarabunFixed(13, .heavy)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 24, height: 24).background(c, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.what(line)).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(line.location.isEmpty ? "ไม่ระบุตำแหน่ง" : line.location)
                        Image(systemName: "camera.fill").font(.system(size: 9))
                        Text("\(photos(of: line).count)")
                    }
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
                Text((today >= 0 ? "+" : "") + RoutineReport.percent(today)).font(.sarabunFixed(15, .heavy)).foregroundStyle(c)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10).frame(height: 56)
            .background(on ? c.opacity(0.08) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var emptyWork: some View {
        VStack(spacing: 8) {
            Text("ยังไม่มีงานวันนี้ · แตะ + บนผัง หรือ + งาน").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            TextField("ถ้าวันนี้หยุดงาน ระบุเหตุผล เช่น ฝนตกทั้งวัน", text: $report.stopReason)
                .textFieldStyle(OutlinedFieldStyle()).frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
    }

    /// The line's description, or its MP task's title.
    static func what(_ line: RoutineReport.ProgressLine) -> String {
        line.description.isEmpty ? (line.task?.title ?? "งานอื่น") : line.description
    }
}

/// The selected line's panel. Its own view, so the page's body stays small enough for the type checker.
struct DailyLinePanel: View {
    let page: DailyOnePage
    let lineID: UUID
    @Binding var selection: UUID?
    @State private var items: [PhotosPickerItem] = []
    @State private var showCamera = false

    /// Found by id each time: a removed line leaves the panel empty instead of reading past the list.
    private var index: Int? { page.report.progress.firstIndex { $0.id == lineID } }
    private var line: RoutineReport.ProgressLine { index.map { page.report.progress[$0] } ?? .init(task: nil, description: "", location: "") }
    private var c: Color { page.color(line) }
    private var before: Double { page.before(line) }

    var body: some View {
        if index != nil { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnyView(titleRow)
            AnyView(picksRow)
            AnyView(standingRow)
            AnyView(extras)
        }
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) { add(ImageUtil.compressed(data)) }
                }
                items = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) { StampedCamera { add($0) } }
    }

    private func add(_ data: Data) { page.photos.append(DraftPhoto(data: data, tag: line.id.uuidString)) }

    // MARK: title

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text("\(page.number(line))").font(.sarabunFixed(14, .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 28, height: 28).background(c, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                (Text(DailyOnePage.what(line)).bold() + Text(line.location.isEmpty ? "" : " · " + line.location))
                    .font(.sarabunFixed(16)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(taskLine).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            statusPill
            iconButton("shippingbox", "เพิ่มวัสดุที่\(line.location)") {
                page.report.materials.append(.init(location: line.location))
            }
            iconButton("exclamationmark.triangle", "เพิ่มปัญหา", tint: Theme.warningText) {
                page.report.problems.append(.init(since: page.date))
            }
            Button { remove() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("เอางานนี้ออก")
        }
    }

    /// `MP 2.1 · โครงสร้าง… · 20% · ใช้ สว่านไฟฟ้า`
    private var taskLine: String {
        guard let task = line.task else { return "งานอื่น · ไม่นับในแผน MP" }
        let w = page.weight(task)
        var parts = ["MP \(task.code)", task.title, RoutineReport.percent(w)]
        let tools = RoutineReport.suggestedTools(task)
        if !tools.isEmpty { parts.append("ใช้ " + tools.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var statusPill: some View {
        let done = line.percent >= 100 - 1e-9
        return Text(done ? "✓ งานเสร็จ" : "เหลือ " + RoutineReport.percent(100 - line.percent))
            .font(.sarabunFixed(12, .bold)).foregroundStyle(done ? Theme.successText : Theme.inkMuted)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(done ? Theme.successSoft : Theme.segmentTrack, in: Capsule())
    }

    private func iconButton(_ symbol: String, _ label: String, tint: Color = Theme.primary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderOutdoor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func remove() {
        let id = line.id
        page.photos.removeAll { $0.tag == id.uuidString }
        page.report.progress.removeAll { $0.id == id }
        selection = page.report.progress.first?.id
    }

    // MARK: วันนี้

    private var picksRow: some View {
        let picks = RoutineReport.quickPicks(before: before), today = line.percent - before
        return HStack(spacing: 8) {
            Text("วันนี้").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
            if picks.isEmpty {
                Text("งานนี้เสร็จก่อนวันนี้แล้ว").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(picks.enumerated()), id: \.offset) { i, x in
                let on = abs(today - x) < 1e-6, last = i == picks.count - 1
                Button { setToday(on ? 0 : x) } label: {
                    Text(last ? "เสร็จ" : "+" + RoutineReport.percent(x)).font(.sarabunFixed(17, .bold))
                        .foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(on ? Theme.dailyPick : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.success : Theme.borderOutdoor))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
            AnyView(photoStrip)
        }
    }

    private func setToday(_ x: Double) {
        guard let i = index else { return }
        page.report.progress[i].percent = min(before + x, 100)
    }

    private var photoStrip: some View {
        HStack(spacing: 6) {
            ForEach(page.photos(of: line), id: \.photo.id) { p in
                Thumbnail(data: p.photo.data).frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("\(p.index)").font(.sarabunFixed(10, .heavy)).foregroundStyle(Theme.navy)
                            .frame(width: 16, height: 16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 4)).padding(3)
                    }
                    .contextMenu {
                        Button("ลบรูป", role: .destructive) { page.photos.removeAll { $0.id == p.photo.id } }
                    }
                    .accessibilityLabel("รูปที่ \(p.index)")
            }
            cameraButton
        }
    }

    @ViewBuilder private var cameraButton: some View {
        let label = Image(systemName: "camera").font(.system(size: 17, weight: .semibold))
            .foregroundStyle(page.photos(of: line).isEmpty ? Theme.warningText : Theme.inkMuted)
            .frame(width: 52, height: 52)
            .background(page.photos(of: line).isEmpty ? Theme.pendingSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.borderOutdoor))
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showCamera = true } label: { label }.buttonStyle(.plain).accessibilityLabel("ถ่ายรูปงานนี้")
        } else {
            PhotosPicker(selection: $items, maxSelectionCount: 10, matching: .images) { label }.accessibilityLabel("เพิ่มรูปงานนี้")
        }
    }

    // MARK: standing

    private var standingRow: some View {
        let gain = RoutineReport.stationGain(line, on: page.report, previous: page.previous, settings: page.settings, weight: page.weight)
        return HStack(spacing: 10) {
            (Text(RoutineReport.percent(before) + " → ") + Text(RoutineReport.percent(line.percent)).bold()
             + Text(" · สถานี " + (gain >= 0 ? "+" : "") + String(format: "%.1f%%", gain)))
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit().fixedSize()
            GeometryReader { g in
                Capsule().fill(Theme.segmentTrack)
                    .overlay(alignment: .leading) { Capsule().fill(c).frame(width: g.size.width * min(line.percent, 100) / 100) }
            }
            .frame(height: 6)
            if let task = line.task, !page.plan.isEmpty {
                let st = RoutineReport.standing(task, on: page.report, previous: page.previous, settings: page.settings, plan: page.plan)
                (Text("MP \(task.code) รวม ") + Text(RoutineReport.percent(st.actual)).bold() + Text(" / แผน " + RoutineReport.percent(st.planned) + " ")
                 + Text(abs(st.behind) < 0.05 ? "ตามแผน" : st.behind > 0 ? String(format: "ช้ากว่า %.1f%%", st.behind) : String(format: "เร็วกว่า %.1f%%", -st.behind))
                    .bold().foregroundColor(st.behind > 0.05 ? Theme.dangerText : Theme.successText))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit().fixedSize()
            }
        }
    }

    // MARK: materials and problems

    @ViewBuilder private var extras: some View {
        let mats = page.report.materials.indices.filter { page.report.materials[$0].location == line.location }
        ForEach(mats, id: \.self) { i in
            let m = page.$report.materials[i]
            HStack(spacing: 8) {
                Image(systemName: "shippingbox").foregroundStyle(Theme.primary).frame(width: 24)
                TextField("รายการวัสดุ", text: m.name).textFieldStyle(OutlinedFieldStyle(dense: true))
                TextField("จำนวน", value: Binding(get: { m.wrappedValue.qty > 0 ? m.wrappedValue.qty : nil }, set: { m.wrappedValue.qty = $0 ?? 0 }),
                          format: .number).keyboardType(.decimalPad).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 90)
                TextField("หน่วย", text: m.unit).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 80)
                Button { page.report.materials.remove(at: i) } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 44, height: 44)
                }
                .accessibilityLabel("ลบวัสดุ")
            }
        }
        ForEach(page.report.problems.indices.filter { !page.report.problems[$0].closed }, id: \.self) { i in
            let p = page.$report.problems[i]
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warningText).frame(width: 24)
                TextField("ปัญหา", text: p.description).textFieldStyle(OutlinedFieldStyle(dense: true))
                TextField("แนวทางแก้ไข", text: p.solution).textFieldStyle(OutlinedFieldStyle(dense: true))
                Button { page.report.problems[i].closed = true } label: {
                    Text("ปิดเรื่อง").font(.sarabunFixed(13, .bold)).frame(minWidth: 44, minHeight: 44)
                }
                Button { page.report.problems.remove(at: i) } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 44, height: 44)
                }
                .accessibilityLabel("ลบปัญหา")
            }
        }
    }
}
