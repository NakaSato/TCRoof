#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// "พื้นที่ติดตั้ง" (how many C1 roof and D1 tank sections the job has) and the location column.
extension InfoPageWide {
    // MARK: installation areas

    var areasBox: some View {
        A1Card(title: "พื้นที่ติดตั้ง", required: true, trailing: "กำหนดหน้า C / D ในแบบสำรวจ · รวม \(job.steps.count) ขั้น", spacing: 10) {
            // three across when the column is wide enough; one per row when the sidebar leaves it too narrow
            let layout = mainWidth >= 620 ? AnyLayout(RatioRow(weights: [1, 1, 1], spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                areaTile("หลังคา", "หน้า C · หลัง", count: count(.roof)) { setCount(.roof, $0) }
                areaTile("ถังน้ำใส", "หน้า D1 · ถัง", count: count(.tank)) { setCount(.tank, $0) }
                areaTile("พื้นดิน", "ลานจอด", count: Int(job.values.text(Self.groundKey)) ?? 0) {
                    job.values[Self.groundKey] = $0 > 0 ? .text(String($0)) : nil
                }
            }
        }
    }

    func areaTile(_ title: String, _ detail: String, count: Int, set: @escaping (Int) -> Void) -> some View {
        let on = count > 0
        return HStack(spacing: 2) {
            Button { set(on ? 0 : 1) } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(on ? Home.primary : Color.white)
                        if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) }
                        else { RoundedRectangle(cornerRadius: 3).stroke(Home.borderControl, lineWidth: 1.5) }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.system(size: 15, weight: .bold))
                        Text(detail).font(.system(size: 12)).foregroundStyle(Home.muted)
                    }
                    .lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 50).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(on ? .isSelected : [])
            stepButton("minus", label: "ลด" + title) { set(count - 1) }.disabled(count == 0)
            Text("\(count)").font(.system(size: 16, weight: .bold)).monospacedDigit().frame(minWidth: 18)
            stepButton("plus", label: "เพิ่ม" + title) { set(count + 1) }.disabled(count >= 20)
        }
        .padding(.leading, 12).padding(.trailing, 2)
        .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.navy.opacity(0.2) : Home.borderControl))
    }

    func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).frame(width: 30, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Home.primary)
        .accessibilityLabel(label)
    }

    func count(_ t: ModuleType) -> Int { job.modules.filter { $0.type == t }.count }

    /// Adds or removes sections of one type to match `n`; asks first when a section to remove has answers.
    func setCount(_ t: ModuleType, _ n: Int) {
        let current = job.modules.filter { $0.type == t }
        if n > current.count {
            for _ in current.count..<n { job.insertModule(SurveyModule(type: t)) }
        } else if n < current.count {
            // blank sections go first, from the end, so a filled one is only removed when nothing else can be
            let order = current.reversed().filter { !hasAnswers($0) } + current.reversed().filter(hasAnswers)
            let losing = Array(order.prefix(current.count - n))
            if losing.contains(where: hasAnswers) { areaChange = AreaChange(losing: losing) } else { remove(losing) }
        }
    }

    func hasAnswers(_ m: SurveyModule) -> Bool { !m.values.storage.isEmpty || !m.name.trimmingCharacters(in: .whitespaces).isEmpty }

    func remove(_ ms: [SurveyModule]) {
        let ids = Set(ms.map(\.id))
        job.modules.removeAll { ids.contains($0.id) }
        areaChange = nil
    }

    /// "C1.2 หลังคา · อาคารสูบน้ำ"
    func sectionName(_ m: SurveyModule) -> String {
        job.steps.first { $0.page == .module(m.id) }.map { $0.code + " " + $0.title } ?? m.title
    }

    // MARK: location

    var locationBox: some View {
        A1Card(title: "ที่ตั้ง") {
            VStack(alignment: .leading, spacing: 8) {
                SiteMapPreview(gps: text("gps"), zoom: Binding(get: { mapZoom }, set: { job.values["mapZoom"] = .text(String($0)) }),
                               googleKey: model.settings.googleMapsKey)
                Text("ระดับซูมที่เลือกใช้เป็นภาพแผนที่ในรายงาน PDF และแผ่น Excel").font(.footnote).foregroundStyle(Home.muted)
            }
            field("gps") { gpsInput }
            field("address") {
                TextField("", text: text("address"), axis: .vertical).lineLimit(2...4).focused($focus, equals: "address")
                    .padding(.vertical, 14)
                    .inputBox(calc: calc("address"), focused: focus == "address", minHeight: 74)
            }
            field("officeAddress") {
                HStack(spacing: 6) {
                    TextField("เหมือนที่อยู่สถานี", text: text("officeAddress")).focused($focus, equals: "officeAddress")
                    Button("คัดลอก") { job.values["officeAddress"] = job.values["address"] }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.primary)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(job.values.text("address").isEmpty)
                        .accessibilityLabel("คัดลอกที่อยู่สถานี")
                }
                .inputBox(focused: focus == "officeAddress", trailing: 8)
            }
        }
    }

    /// Zoom of this job's site picture; follows the settings until a level is picked here.
    var mapZoom: Int { Int(job.values.text("mapZoom")) ?? model.settings.mapZoom }

    var gpsInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(placeholder("gps"), text: text("gps")).keyboardType(.numbersAndPunctuation).focused($focus, equals: "gps")
                    .inputBox(focused: focus == "gps")
                Button(action: locate) {
                    HStack(spacing: 8) {
                        if locating { ProgressView() } else { Image(systemName: "scope").foregroundStyle(Home.primary) }
                        Text("ตำแหน่งปัจจุบัน").font(.system(size: 16, weight: .semibold))
                    }
                    .padding(.horizontal, 14).frame(minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(locating).fixedSize()
            }
            gpsNote.font(.footnote)
        }
    }

    @ViewBuilder var gpsNote: some View {
        switch GPS.check(job.values.text("gps")) {
        case .invalid:
            Text("รูปแบบไม่ถูกต้อง ใช้ ละติจูด, ลองจิจูด เช่น 17.0062, 99.8235").foregroundStyle(Home.danger)
        case .outsideThailand:
            Text("พิกัดอยู่นอกประเทศไทย ตรวจค่าอีกครั้ง").foregroundStyle(Home.pending)
        case .swapped(let fixed):
            HStack(spacing: 8) {
                Text("ดูเหมือนสลับละติจูดกับลองจิจูด").foregroundStyle(Home.pending)
                Button("สลับเป็น \(fixed)") { job.values["gps"] = .text(fixed) }.frame(minHeight: 44)
            }
        case .ok, .empty:
            if let gpsFailure { Text(gpsFailure).foregroundStyle(Home.danger) }
            else if let fix { Text("ความแม่นยำ ±\(Int(fix.accuracy.rounded())) ม. · บันทึกเมื่อ \(fix.time.formatted(.dateTime.hour().minute()))").foregroundStyle(Home.muted) }
        }
    }

    func locate() {
        locating = true
        gpsFailure = nil
        locator.request { result in
            locating = false
            switch result {
            case .success(let loc):
                job.values["gps"] = .text(GPS.format(loc.coordinate.latitude, loc.coordinate.longitude))
                fix = (loc.horizontalAccuracy, loc.timestamp)
            case .failure(let error):
                gpsFailure = error.localizedDescription
            }
        }
    }
}

/// Blue title bar of the A1 card page, in place of the navigation bar: back and sidebar buttons,
/// page title with the report number and the TCRoof job it belongs to, and export.
struct InfoPageHeader: View {
    let job: Job
    let back: () -> Void
    let toggleSidebar: () -> Void
    let export: () -> Void
    @Environment(SurveyModel.self) var model

    var subtitle: String {
        // "TC-0012 · สถานีสูบน้ำ" → "TC-0012"; the project name is already on the page
        let code = job.jobSyncID.flatMap { model.linkedJobLabel?($0) }?.components(separatedBy: " · ").first
        return (["แบบสำรวจ NO.\(job.docNo.isEmpty ? "—" : job.docNo)"] + [code].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            squareButton("chevron.left", "ย้อนกลับ", action: back)
            squareButton("sidebar.left", "แสดง/ซ่อนรายการหัวข้อ", action: toggleSidebar)
            VStack(alignment: .leading, spacing: 0) {
                Text("A1 ข้อมูลโครงการ").font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 15)).opacity(0.92).lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            .padding(.leading, 4)
            Spacer(minLength: 8)
            Button(action: export) {
                Label("ส่งออก", systemImage: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        // the export sheet explains the gap; this dot just says there is one
                        if !job.missingGroups.isEmpty { Circle().fill(.orange).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                    }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // runs up under the status bar
        .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15))
            .ignoresSafeArea(edges: .top))
    }

    /// White 36-pt square like the design's close button, inside a 44-pt tap area.
    func squareButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(Home.primary)
                .frame(width: 36, height: 36).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Bottom bar of the wide A1 page: save state, save now, previous (none) and next.
struct InfoPageBar: View {
    let job: Job
    /// Portrait with the sidebar open: drops the disabled "previous" button and tightens the others.
    var narrow = false
    let next: (() -> Void)?
    @Environment(SurveyModel.self) var model
    @State var savedNow: Date?

    var body: some View {
        let c = Schema.info.completion(job.values)
        let steps = job.steps
        let saved = max(job.updated, savedNow ?? .distantPast)
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Home.ok)
                VStack(alignment: .leading, spacing: 1) {
                    Text("บันทึกอัตโนมัติแล้ว " + (Calendar.current.isDateInToday(saved) ? saved.formatted(.dateTime.hour().minute())
                                                    : saved.formatted(.dateTime.day().month().hour().minute()))).font(.system(size: 15, weight: .semibold))
                    Text("ครบ \(c.filled)/\(c.total) ช่องในหน้านี้").font(.system(size: 13)).foregroundStyle(Home.muted)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.flush(job.id); savedNow = Date() } label: {
                Text("บันทึกร่างตอนนี้").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    .frame(width: narrow ? 140 : 170, height: 56)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.6)))
            }
            .buttonStyle(.plain)
            if !narrow {
                HStack(spacing: 8) { Image(systemName: "chevron.left"); Text("หัวข้อแรก") }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(white: 0.56))
                    .frame(width: 180, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.5)))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityHint("ไม่มีหัวข้อก่อนหน้า")
            }
            if let next, let s = steps.dropFirst().first {
                Button(action: next) {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("ถัดไป 2/\(steps.count)").font(.system(size: 12)).opacity(0.9)
                            Text(s.code + " " + s.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: narrow ? 220 : 250, height: 56)
                    .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Home.navy)
        .frame(maxWidth: 1240)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(Color.white.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }
}
#endif
