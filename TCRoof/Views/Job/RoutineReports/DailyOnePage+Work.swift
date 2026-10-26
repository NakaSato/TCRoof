import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

// Today's work (docs/ui/daily-report-ipad-v2 §2, §4–5): the key plan and the task list in one scroll, the lines
// grouped by location, each with its 10-segment bar; the selected line's detail is pinned under the scroll.

extension DailyOnePage {
    /// A photo to take for a line, or to retake in place of one.
    struct Shot: Identifiable {
        let id = UUID()
        let line: UUID
        var replacing: UUID?
    }

    /// `narrow` (under 700 pt, an iPad in portrait): each row and the footer take two lines.
    func leftCard(planHeight: CGFloat, narrow: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    keyPlanCard.frame(height: planHeight).padding(.top, 10)
                    AnyView(taskList(narrow: narrow)).allowsHitTesting(!readOnly)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
            if let line = report.progress.first(where: { $0.id == selected }) ?? report.progress.first {
                DailyLineFooter(page: self, lineID: line.id, narrow: narrow)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dailyCard()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func taskList(narrow: Bool) -> some View {
        if report.progress.isEmpty {
            emptyWork
        } else {
            ForEach(RoutineReport.locationGroups(report.progress), id: \.location) { group in
                groupHeader(group.location, group.lines)
                ForEach(group.lines) { line in DailyTaskRow(page: self, lineID: line.id, narrow: narrow) }
            }
        }
    }

    private func groupHeader(_ location: String, _ lines: [RoutineReport.ProgressLine]) -> some View {
        let gain = lines.reduce(0) { $0 + max($1.percent - before($1), 0) }
        return HStack(spacing: 6) {
            Image(systemName: "building.2").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            Text(location.isEmpty ? "ไม่ระบุตำแหน่ง" : location).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
            Text("\(lines.count) งาน | +\(RoutineReport.percent(gain)) วันนี้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
        }
        .padding(.top, 6).padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyWork: some View {
        VStack(spacing: 8) {
            Text("ยังไม่มีงานวันนี้ | แตะ + บนผังเพื่อเพิ่มงานตามแผน MP").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            TextField("ถ้าวันนี้หยุดงาน ระบุเหตุผล เช่น ฝนตกทั้งวัน", text: $report.stopReason)
                .textFieldStyle(OutlinedFieldStyle()).frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity).padding(16)
    }

    /// The line's description, or its MP task's title.
    static func what(_ line: RoutineReport.ProgressLine) -> String {
        line.description.isEmpty ? (line.task?.title ?? "งานอื่น") : line.description
    }

    // MARK: photos

    /// Selects the line and takes a photo for it (in place of `replacing`): the camera, else the photo library.
    func shoot(_ line: UUID, replacing: UUID? = nil) {
        selected = line
        let s = Shot(line: line, replacing: replacing)
        #if DEBUG
        // `-routineCameraStub YES`: a drawn photo, for the simulator
        if UserDefaults.standard.bool(forKey: "routineCameraStub") { return took(s, Self.demoPhoto(photos.count)) }
        #endif
        if UIImagePickerController.isSourceTypeAvailable(.camera) { cameraShot = s } else { libraryShot = s; showShotLibrary = true }
    }

    func took(_ s: Shot, _ data: Data) {
        let photo = DraftPhoto(data: data, tag: s.line.uuidString)
        if let r = s.replacing, let i = photos.firstIndex(where: { $0.id == r }) { photos[i] = photo } else { photos.append(photo) }
    }
}

/// One line of the task list. Its own view, so the page's body stays small enough for the type checker.
struct DailyTaskRow: View {
    let page: DailyOnePage
    let lineID: UUID
    var narrow = false

    private var index: Int? { page.report.progress.firstIndex { $0.id == lineID } }
    private var line: RoutineReport.ProgressLine { index.map { page.report.progress[$0] } ?? .init(task: nil, description: "", location: "") }
    private var c: Color { page.color(line) }
    private var before: Double { page.before(line) }
    private var today: Double { max(line.percent - before, 0) }
    private var left: Double { max(100 - before, 0) }
    private var on: Bool { page.selected == lineID }

    var body: some View {
        if index != nil {
            Group {
                if narrow {
                    VStack(spacing: 2) {
                        HStack(spacing: 10) { pin; AnyView(title); AnyView(camera) }
                        HStack(spacing: 10) { AnyView(progress); Spacer(minLength: 0); AnyView(doneToggle) }
                    }
                } else {
                    HStack(spacing: 10) { pin; AnyView(title); AnyView(progress); AnyView(doneToggle); AnyView(camera) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c : Theme.borderSubtle, lineWidth: on ? 1.5 : 1))
            .shadow(color: on ? c.opacity(0.18) : .clear, radius: 6, y: 2)
        }
    }

    private var pin: some View {
        Text("\(page.number(line))").font(.sarabunFixed(13, .heavy)).foregroundStyle(Theme.onPrimary)
            .frame(width: 26, height: 26).background(c, in: Circle())
            .accessibilityHidden(true)
    }

    /// Tap = select the line and take a photo for it.
    private var title: some View {
        Button { page.shoot(lineID) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(DailyOnePage.what(line)).font(.sarabunFixed(14.5, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text((line.task.map { "MP \($0.code)" } ?? "งานอื่น") + " | ก่อนวันนี้ " + RoutineReport.percent(before))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DailyOnePage.what(line) + " | แตะเพื่อถ่ายรูป")
        .accessibilityIdentifier("dailyLineTitle")
    }

    private func set(_ t: Double) {
        guard let i = index else { return }
        page.selected = lineID
        page.report.progress[i].percent = min(before + t, 100)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            stepButton("minus", "ลด 5%", -5)
            bar
            stepButton("plus", "เพิ่ม 5%", 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(RoutineReport.percent(line.percent)).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                if today > 1e-9 {
                    Text("+" + RoutineReport.percent(today) + " วันนี้").font(.sarabunFixed(11.5, .bold)).foregroundStyle(c).monospacedDigit()
                } else {
                    Text("ยังไม่กรอก").font(.sarabunFixed(11.5, .bold)).foregroundStyle(Theme.pending)
                }
            }
            .lineLimit(1).frame(width: 74, alignment: .leading)
        }
    }

    private func stepButton(_ icon: String, _ label: String, _ step: Double) -> some View {
        let next = RoutineReport.stepToday(today, before: before, by: step)
        return Button { set(next) } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.navy)
                .frame(width: 36, height: 40)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderOutdoor))
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(abs(next - today) < 1e-9)
        .accessibilityLabel(label)
    }

    /// Ten segments of 10 % of the whole task: grey before today, the line's colour to today's end, light after.
    private var bar: some View {
        let width: CGFloat = 150
        return HStack(spacing: 2) {
            ForEach(1...10, id: \.self) { i in
                let end = Double(i * 10)
                Rectangle().fill(end <= before + 1e-9 ? Theme.inkFaint : end <= line.percent + 1e-9 ? c : Theme.segmentTrack)
            }
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: width, height: 44)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            let segment = Int(tap.location.x / width * 10) + 1
            if let t = RoutineReport.todayFromSegment(segment, before: before) { set(t) }
        })
        .accessibilityElement()
        .accessibilityLabel("ความคืบหน้า " + DailyOnePage.what(line))
        .accessibilityValue("ถึง " + RoutineReport.percent(line.percent))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment:
                if let t = RoutineReport.todayFromSegment(Int((line.percent / 10).rounded(.down)) + 1, before: before) { set(t) }
            case .decrement:
                set(max((line.percent / 10).rounded(.up) * 10 - 10 - before, 0))
            @unknown default: break
            }
        }
    }

    private var doneToggle: some View {
        let done = left > 1e-9 && today >= left - 1e-9
        return Button { set(done ? 0 : left) } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                Text("เสร็จ").font(.sarabunFixed(14, .bold))
            }
                .fixedSize()
                .foregroundStyle(done ? Theme.onPrimary : Theme.success)
                .padding(.horizontal, 12).frame(height: 40)
                .background(done ? Theme.success : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.success, lineWidth: done ? 0 : 1.2))
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(left <= 1e-9)
        .accessibilityLabel(left <= 1e-9 ? "เสร็จก่อนวันนี้แล้ว" : "เสร็จวันนี้")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private var camera: some View {
        let count = page.photos(of: line).count
        return Button { page.shoot(lineID) } label: {
            Image(systemName: "camera").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(count > 0 ? Theme.primary : Theme.pending)
                .frame(width: 44, height: 40)
                .background(count > 0 ? Theme.primarySoft : Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if count == 0 {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)").font(.sarabunFixed(10, .heavy)).foregroundStyle(Theme.onPrimary)
                            .frame(minWidth: 16, minHeight: 16).background(c, in: Circle()).offset(x: 5, y: -5)
                    }
                }
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "ถ่ายรูปงานนี้ มี \(count) รูป" : "ถ่ายรูปงานนี้ ยังไม่มีรูป")
    }
}

/// The selected line's detail, pinned under the scroll: its standing, photos, materials and problems.
struct DailyLineFooter: View {
    let page: DailyOnePage
    let lineID: UUID
    var narrow = false

    private var index: Int? { page.report.progress.firstIndex { $0.id == lineID } }
    private var line: RoutineReport.ProgressLine { index.map { page.report.progress[$0] } ?? .init(task: nil, description: "", location: "") }
    private var c: Color { page.color(line) }

    var body: some View {
        if index != nil {
            VStack(alignment: .leading, spacing: 8) {
                if narrow {
                    HStack(spacing: 12) { AnyView(summary); Spacer(minLength: 8); AnyView(actionsRow) }
                    AnyView(photoStrip)
                } else {
                    HStack(spacing: 12) {
                        AnyView(summary)
                        AnyView(photoStrip)
                        Spacer(minLength: 8)
                        AnyView(actionsRow)
                    }
                }
                Group {
                    AnyView(materialRows)
                    AnyView(problemRows)
                }
                .allowsHitTesting(!page.readOnly)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Text("\(page.number(line))").font(.sarabunFixed(15, .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 32, height: 32).background(c, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(DailyOnePage.what(line)).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                standing.font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).monospacedDigit()
            }
        }
        .frame(minWidth: 150, maxWidth: 260, alignment: .leading)
    }

    /// `หลังคา 1 | 0% → 100% | เร็วกว่า 23.0%`: the variance is the MP task's actual against its plan to date.
    private var standing: Text {
        let place = line.location.isEmpty ? "ไม่ระบุตำแหน่ง" : line.location
        let head = Text(place + " | " + RoutineReport.percent(page.before(line)) + " → " + RoutineReport.percent(line.percent))
        guard let task = line.task, !page.plan.isEmpty else { return head }
        let st = RoutineReport.standing(task, on: page.report, previous: page.previous, settings: page.settings, plan: page.plan)
        let words = abs(st.behind) < 0.05 ? "ตามแผน" : st.behind > 0 ? String(format: "ช้ากว่า %.1f%%", st.behind) : String(format: "เร็วกว่า %.1f%%", -st.behind)
        return head + Text(" | ") + Text(words).bold().foregroundColor(st.behind > 0.05 ? Theme.dangerText : Theme.successText)
    }

    private var photoStrip: some View {
        let shots = page.photos(of: line)
        return HStack(spacing: 6) {
            ForEach(shots, id: \.photo.id) { p in
                Button {
                    if page.readOnly {
                        page.viewing = .init(images: shots.map(\.photo.data), start: shots.firstIndex { $0.photo.id == p.photo.id } ?? 0)
                    } else {
                        page.shoot(lineID, replacing: p.photo.id)
                    }
                } label: {
                    Thumbnail(data: p.photo.data).frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text("\(p.index)").font(.sarabunFixed(10, .heavy)).foregroundStyle(Theme.onPrimary)
                                .frame(width: 16, height: 16).background(c, in: Circle()).padding(3)
                        }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !page.readOnly {
                        Button("ลบรูป", role: .destructive) { page.photos.removeAll { $0.id == p.photo.id } }
                    }
                }
                .accessibilityLabel("รูปที่ \(p.index) | " + (page.readOnly ? "แตะเพื่อดูเต็มจอ" : "แตะเพื่อถ่ายใหม่"))
            }
            if !page.readOnly { addShot }
            Text(shots.isEmpty ? "ถ่ายอย่างน้อย 1 รูป" : "\(shots.count) รูป | ใช้ในรายงาน")
                .font(.sarabunFixed(12)).foregroundStyle(shots.isEmpty ? Theme.pending : Theme.inkMuted).lineLimit(1).fixedSize()
        }
    }

    private var addShot: some View {
            Button { page.shoot(lineID) } label: {
                VStack(spacing: 0) {
                    Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                    Text("ถ่าย").font(.sarabunFixed(10.5))
                }
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ถ่ายรูปงานนี้เพิ่ม")
    }

    @ViewBuilder private var actionsRow: some View {
        if !page.readOnly { editActions }
    }

    private var editActions: some View {
        HStack(spacing: 8) {
            pill("+ วัสดุ", ink: Theme.primary, fill: Theme.primarySoft) {
                page.report.materials.append(.init(location: line.location))
            }
            pill("+ ปัญหา", ink: Theme.warningText, fill: Theme.warningSoft) {
                page.report.problems.append(.init(since: page.date, lineKey: line.key))
            }
            Button { remove() } label: {
                Text("เอาออก").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted).fixedSize().frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เอางานนี้ออกจากวันนี้")
        }
    }

    private func pill(_ title: String, ink: Color, fill: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(ink).fixedSize()
                .padding(.horizontal, 12).frame(height: 40)
                .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func remove() {
        let id = line.id
        page.photos.removeAll { $0.tag == id.uuidString }
        page.report.progress.removeAll { $0.id == id }
        page.selected = page.report.progress.first?.id
    }

    // MARK: materials and problems

    @ViewBuilder private var materialRows: some View {
        let mats = page.report.materials.indices.filter { page.report.materials[$0].location == line.location }
        ForEach(mats, id: \.self) { i in
            let m = page.$report.materials[i]
            HStack(spacing: 8) {
                rowLabel("วัสดุ", Theme.primary)
                TextField("รายการวัสดุ", text: m.name).textFieldStyle(OutlinedFieldStyle(dense: true))
                TextField("จำนวน", value: Binding(get: { m.wrappedValue.qty > 0 ? m.wrappedValue.qty : nil }, set: { m.wrappedValue.qty = $0 ?? 0 }),
                          format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 80)
                TextField("หน่วย", text: m.unit).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 90)
                removeButton("ลบวัสดุ") { page.report.materials.remove(at: i) }
            }
        }
    }

    /// The line's open problems, and open ones raised under no line (carried from earlier days), so they can be closed.
    @ViewBuilder private var problemRows: some View {
        let key = line.key
        let rows = page.report.problems.indices.filter { i in
            let p = page.report.problems[i]
            return !p.closed && (p.lineKey == key || p.lineKey == nil)
        }
        ForEach(rows, id: \.self) { i in
            let p = page.$report.problems[i]
            HStack(spacing: 8) {
                rowLabel("ปัญหา", Theme.pending)
                TextField("ปัญหา", text: p.description).textFieldStyle(OutlinedFieldStyle(dense: true))
                TextField("แนวทางแก้ไข", text: p.solution).textFieldStyle(OutlinedFieldStyle(dense: true))
                // one carried from an earlier day is closed (it stays in that day's report); today's is removed
                removeButton(p.wrappedValue.since < page.date ? "ปิดเรื่อง" : "ลบปัญหา") {
                    if page.report.problems[i].since < page.date { page.report.problems[i].closed = true } else { page.report.problems.remove(at: i) }
                }
            }
        }
    }

    private func rowLabel(_ text: String, _ ink: Color) -> some View {
        Text(text).font(.sarabunFixed(12.5, .bold)).foregroundStyle(ink).frame(width: 44, alignment: .leading)
    }

    private func removeButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
