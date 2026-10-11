import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore
import SurveyUI

// MARK: - 1 Weather

/// The 15-cell strip 06…20: tap cycles F → C → R → blank; dragging across paints the first cell's next value.
struct WeatherCard: View {
    @Binding var weather: [RoutineReport.Weather?]
    @State private var paint: RoutineReport.Weather??

    var body: some View {
        ReportCard("1. สภาพอากาศ", trailing: {
            Button("ทั้งวันโปร่ง") { weather = weather.map { _ in .fine } }
                .font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }) {
            GeometryReader { g in
                let n = RoutineReport.weatherHours.count, w = g.size.width / CGFloat(n)
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in cell(i).frame(width: w) }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = Int(v.location.x / w)
                    guard weather.indices.contains(i) else { return }
                    if paint == nil {
                        let start = Int(v.startLocation.x / w)
                        paint = .some(RoutineReport.Weather.next(weather[safe: start] ?? nil))
                    }
                    if let p = paint { weather[i] = p }
                }.onEnded { _ in paint = nil })
            }
            .frame(height: 64)
            HStack(spacing: 14) {
                ForEach(RoutineReport.Weather.allCases, id: \.self) { w in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(Self.color(w)).frame(width: 14, height: 14)
                        Text("\(w.rawValue) \(w.title)")
                    }
                }
                Spacer()
                let blank = weather.filter { $0 == nil }.count
                if blank > 0 { Text("ว่าง \(blank) ชม.").foregroundStyle(Theme.dangerText) }
            }
            .font(.caption).foregroundStyle(Theme.inkMuted)
        }
    }

    private func cell(_ i: Int) -> some View {
        let w = weather[safe: i] ?? nil
        return VStack(spacing: 4) {
            Text(String(format: "%02d", RoutineReport.weatherHours[i])).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
            RoundedRectangle(cornerRadius: 6)
                .fill(w.map(Self.color) ?? Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderSubtle))
                .overlay(Text(w?.rawValue ?? "").font(.headline).foregroundStyle(Theme.navy))
                .frame(height: 44)
                .padding(.horizontal, 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RoutineReport.weatherHours[i]) นาฬิกา \(w?.title ?? "ว่าง")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { weather[i] = RoutineReport.Weather.next(w) }
    }

    static func color(_ w: RoutineReport.Weather) -> Color {
        switch w {
        case .fine: Theme.sun.opacity(0.55)
        case .cloudy: Theme.segmentTrack
        case .rain: Theme.primaryLight
        }
    }
}

// MARK: - 2 Crew · 3 Tools

struct CrewCard: View {
    @Binding var report: RoutineReport.Daily
    let roles: [String]

    var body: some View {
        ReportCard("2. กำลังคน", trailing: {
            Text("รวม \(report.crewTotal) คน").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.navy)
        }) {
            if !report.crewConfirmed {
                Button { report.crewConfirmed = true } label: {
                    Label("ใช้ค่าเมื่อวาน — แตะเพื่อยืนยันกำลังคนวันนี้", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: touchMin, alignment: .leading)
                }
                .buttonStyle(.bordered).tint(Theme.pending)
            } else {
                Label("ยืนยันกำลังคนวันนี้แล้ว", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.okText)
            }
            CountList(counts: $report.crew, names: roles, addTitle: "+ ตำแหน่ง", onChange: { report.crewConfirmed = true })
        }
    }
}

struct ToolsCard: View {
    @Binding var tools: [RoutineReport.Count]
    let names: [String]

    var body: some View {
        ReportCard("3. เครื่องมือ") {
            CountList(counts: $tools, names: names, addTitle: "+ เครื่องมือ")
        }
    }
}

/// Steppers for a list of named counts, plus a menu to add one from the settings list or by name.
struct CountList: View {
    @Binding var counts: [RoutineReport.Count]
    let names: [String]
    let addTitle: String
    var onChange: () -> Void = {}
    @State private var newName = ""
    @State private var askName = false

    var body: some View {
        ForEach($counts) { $c in
            CountStepper(title: c.name, value: Binding(get: { c.count }, set: { c.count = $0; onChange() }))
        }
        let missing = names.filter { n in !counts.contains { $0.name == n } }
        Menu {
            ForEach(missing, id: \.self) { n in Button(n) { counts.append(.init(name: n, count: 1)); onChange() } }
            Button("พิมพ์ชื่อ…") { askName = true }
        } label: {
            Text(addTitle).font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }
        .alert(addTitle, isPresented: $askName) {
            TextField("ชื่อ", text: $newName)
            Button("เพิ่ม") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { counts.append(.init(name: n, count: 1)); onChange() }
                newName = ""
            }
            Button("ยกเลิก", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - 4 Materials

struct MaterialsCard: View {
    @Binding var materials: [RoutineReport.Material]
    let locations: [String]
    @State private var open = false

    var body: some View {
        ReportCard("4. วัสดุเข้าหน้างาน", trailing: {
            Button("+ เพิ่ม") { materials.append(.init()); open = true }.font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }) {
            if materials.isEmpty {
                Text("ไม่มี").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                DisclosureGroup(isExpanded: $open) {
                    ForEach($materials) { $m in row($m) }
                } label: {
                    Text("\(materials.count) รายการ").font(.subheadline).foregroundStyle(Theme.navy)
                }
            }
        }
    }

    private func row(_ m: Binding<RoutineReport.Material>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("รายการวัสดุ", text: m.name).textFieldStyle(.roundedBorder)
                Button(role: .destructive) { materials.removeAll { $0.id == m.wrappedValue.id } } label: {
                    Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                }
                .accessibilityLabel("ลบวัสดุ")
            }
            HStack {
                TextField("จำนวน", value: Binding(get: { m.wrappedValue.qty > 0 ? m.wrappedValue.qty : nil }, set: { m.wrappedValue.qty = $0 ?? 0 }), format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("หน่วย", text: m.unit).textFieldStyle(.roundedBorder).frame(width: 80)
                LocationMenu(location: m.location, locations: locations)
            }
            TextField("หมายเหตุ", text: m.remark).textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 6)
    }
}

/// A chip that picks one location from the station's list (or types one).
struct LocationMenu: View {
    @Binding var location: String
    let locations: [String]
    @State private var ask = false
    @State private var typed = ""

    var body: some View {
        Menu {
            ForEach(locations, id: \.self) { l in Button(l) { location = l } }
            Button("พิมพ์ตำแหน่ง…") { typed = location; ask = true }
            if !location.isEmpty { Button("ไม่ระบุ", role: .destructive) { location = "" } }
        } label: {
            Label(location.isEmpty ? "ตำแหน่ง" : location, systemImage: "mappin")
                .font(.subheadline).lineLimit(1).frame(minHeight: touchMin)
        }
        .alert("ตำแหน่ง", isPresented: $ask) {
            TextField("เช่น หลังคา 1", text: $typed)
            Button("ตกลง") { location = typed.trimmingCharacters(in: .whitespaces) }
            Button("ยกเลิก", role: .cancel) {}
        }
    }
}

// MARK: - 5 Progress

struct ProgressCard: View {
    @Binding var report: RoutineReport.Daily
    let previous: [RoutineReport.Daily]
    let job: Job
    @State private var showAdd = false

    var body: some View {
        ReportCard("5. ความก้าวหน้า", trailing: {
            Button("+ งาน") { showAdd = true }.font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }) {
            if report.progress.isEmpty {
                Text("ยังไม่มีงาน · ถ้าวันนี้หยุดงาน ระบุเหตุผล").font(.subheadline).foregroundStyle(Theme.muted)
                TextField("เหตุหยุดงาน เช่น ฝนตกทั้งวัน", text: $report.stopReason).textFieldStyle(.roundedBorder)
            }
            ForEach($report.progress) { $line in
                ProgressRow(line: $line, before: RoutineReport.previousPercent(line, before: report.date, in: previous),
                            locations: job.routineSettings.locations) {
                    report.progress.removeAll { $0.id == line.id }
                }
                Divider()
            }
        }
        .sheet(isPresented: $showAdd) {
            AddWorkSheet(locations: job.routineSettings.locations, plan: job.scheduleInput.map { MasterSchedule.plan($0) }) { lines in
                for var l in lines where !report.progress.contains(where: { $0.key == l.key }) {
                    l.percent = RoutineReport.previousPercent(l, before: report.date, in: previous)
                    report.progress.append(l)
                }
            }
        }
    }
}

/// One work line: MP task chip, description, location, and % สะสม with today's change beside it.
struct ProgressRow: View {
    @Binding var line: RoutineReport.ProgressLine
    /// The line's % in the previous report.
    let before: Double
    let locations: [String]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(line.task?.code ?? "อื่น").font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
                TextField(line.task?.title ?? "รายละเอียดงาน", text: $line.description).textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel("ลบงาน")
            }
            HStack(spacing: 8) {
                LocationMenu(location: $line.location, locations: locations)
                Spacer()
                let delta = line.percent - before
                Text(delta == 0 ? "วันนี้ 0%" : (delta > 0 ? "+" : "") + RoutineReport.percent(delta) + " วันนี้")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(delta < 0 ? Theme.dangerText : delta > 0 ? Theme.okText : Theme.muted)
            }
            HStack(spacing: 8) {
                Button { line.percent = max(0, line.percent - 5) } label: { Image(systemName: "minus").frame(width: touchMin, height: touchMin) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).accessibilityLabel("ลด 5%")
                Slider(value: $line.percent, in: 0...100, step: 5)
                Button { line.percent = min(100, line.percent + 5) } label: { Image(systemName: "plus").frame(width: touchMin, height: touchMin) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).accessibilityLabel("เพิ่ม 5%")
                Text("สะสม " + RoutineReport.percent(line.percent)).font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.navy).frame(minWidth: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 6 Problems

struct ProblemsCard: View {
    @Binding var problems: [RoutineReport.Problem]
    let date: Date

    var body: some View {
        ReportCard("6. ปัญหา / อุปสรรค", trailing: {
            Button("+ ปัญหา") { problems.append(.init(since: date)) }.font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
        }) {
            if problems.isEmpty { Text("ไม่มี").font(.subheadline).foregroundStyle(Theme.muted) }
            // open ones carried from earlier days first
            ForEach($problems.sorted { a, b in (a.wrappedValue.closed ? 1 : 0, a.wrappedValue.since) < (b.wrappedValue.closed ? 1 : 0, b.wrappedValue.since) }) { $p in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if p.since < date { Text("ตั้งแต่ \(RoutineReport.thaiDate(p.since))").font(.caption).foregroundStyle(Theme.muted) }
                        Spacer()
                        Button(p.closed ? "เปิดเรื่องอีกครั้ง" : "ปิดเรื่อง") { p.closed.toggle() }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: touchMin)
                        Button(role: .destructive) { problems.removeAll { $0.id == p.id } } label: {
                            Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                        }
                        .accessibilityLabel("ลบปัญหา")
                    }
                    TextField("ปัญหา", text: $p.description, axis: .vertical).textFieldStyle(.roundedBorder)
                    TextField("แนวทางแก้ไข", text: $p.solution, axis: .vertical).textFieldStyle(.roundedBorder)
                }
                .opacity(p.closed ? 0.6 : 1)
                Divider()
            }
        }
    }
}

// MARK: - Photos

/// Photos of the day; each can be tagged with a progress line for the weekly report.
struct DailyPhotosCard: View {
    @Binding var photos: [DraftPhoto]
    let lines: [RoutineReport.ProgressLine]
    @State private var items: [PhotosPickerItem] = []
    @State private var showCamera = false

    var body: some View {
        ReportCard("ภาพถ่ายประจำวัน", trailing: {
            Text("\(photos.count) รูป").font(.subheadline).foregroundStyle(Theme.muted)
        }) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) {
                    Label("คลังภาพ", systemImage: "photo.on.rectangle").frame(minHeight: touchMin)
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("ถ่ายรูป", systemImage: "camera").frame(minHeight: touchMin) }
                }
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            if photos.isEmpty {
                Text("ยังไม่มีรูป").font(.subheadline).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach($photos) { $p in tile($p) }
            }
        }
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) { photos.append(.init(data: ImageUtil.compressed(data), tag: "")) }
                }
                items = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) { StampedCamera { photos.append(.init(data: $0, tag: "")) } }
    }

    private func tile(_ p: Binding<DraftPhoto>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumbnail(data: p.wrappedValue.data).frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    Button { photos.removeAll { $0.id == p.wrappedValue.id } } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6)).frame(width: touchMin, height: touchMin)
                    }
                    .accessibilityLabel("ลบรูป")
                }
            Menu {
                Button("ไม่ระบุงาน") { p.wrappedValue.tag = "" }
                ForEach(lines) { l in Button(l.title) { p.wrappedValue.tag = l.id.uuidString } }
            } label: {
                let title = lines.first { $0.id.uuidString == p.wrappedValue.tag }?.title
                Label(title ?? "ระบุงาน", systemImage: "tag").font(.caption).lineLimit(1).frame(minHeight: touchMin, alignment: .leading)
            }
        }
    }
}
