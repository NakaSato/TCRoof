#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// "พื้นที่ติดตั้ง" (how many C1 roof and D1 tank sections the job has) and the location card.
/// Older jobs may carry a ground-area count (`groundAreas`); it is no longer shown or counted, but stays in the job
/// and its web backup (`WebBackup.extraJobKeys`).
extension InfoPageWide {
    // MARK: installation areas

    var areasBox: some View {
        A1Card(title: "พื้นที่ติดตั้ง", required: true, trailing: "กำหนดหน้า C / D ในแบบสำรวจ · รวม \(job.steps.count) ขั้น", spacing: 10) {
            // two across when the column is wide enough; one per row when the sidebar leaves it too narrow
            let layout = mainWidth >= 440 ? AnyLayout(RatioRow(weights: [1, 1], spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                areaTile("หลังคา", "หน้า C · หลัง", count: count(.roof)) { setCount(.roof, $0) }
                areaTile("ถังน้ำใส", "หน้า D1 · ถัง", count: count(.tank)) { setCount(.tank, $0) }
            }
        }
    }

    func areaTile(_ title: String, _ detail: String, count: Int, set: @escaping (Int) -> Void) -> some View {
        let on = count > 0
        return HStack(spacing: 2) {
            Button { set(on ? 0 : 1) } label: {
                HStack(spacing: 8) {
                    A2Icon(name: on ? "a1-checkbox-on" : "a1-checkbox-off", fallback: on ? "checkmark.square.fill" : "square", size: 22)
                        .foregroundStyle(Home.primary)
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
            stepButton("ui-minus", "minus", label: "ลด" + title) { set(count - 1) }.disabled(count == 0)
            Text("\(count)").font(.system(size: 16, weight: .bold)).monospacedDigit().frame(minWidth: 18)
            stepButton("ui-plus", "plus", label: "เพิ่ม" + title) { set(count + 1) }.disabled(count >= 20)
        }
        .padding(.leading, 12).padding(.trailing, 2)
        .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.navy.opacity(0.2) : Home.borderControl))
    }

    func stepButton(_ icon: String, _ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            A2Icon(name: icon, fallback: symbol, size: 18).frame(width: 30, height: 44).contentShape(Rectangle())
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
                               crop: Binding(get: { mapCrop }, set: { job.values[MapCrop.key] = .text($0.text) }),
                               googleKey: model.settings.googleMapsKey)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("ลากกรอบหรือมุมเพื่อเลือกพื้นที่ภาพในรายงาน PDF / Excel · แตะค้างที่หมุดเพื่อย้าย")
                        .font(.footnote).foregroundStyle(Home.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("รีเซ็ตกรอบ") { job.values[MapCrop.key] = .text(MapCrop.standard.text) }
                        .font(.footnote.weight(.bold)).foregroundStyle(Home.primary)
                        .frame(minWidth: 44, minHeight: 44).fixedSize()
                        .disabled(mapCrop == .standard)
                }
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
    /// Part of the map used as the report picture; a job from before the frame existed uses all of it.
    var mapCrop: MapCrop { MapCrop(job.values.text(MapCrop.key)) ?? .full }

    var gpsInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(placeholder("gps"), text: text("gps")).keyboardType(.numbersAndPunctuation).focused($focus, equals: "gps")
                    .inputBox(focused: focus == "gps")
                Button(action: locate) {
                    HStack(spacing: 8) {
                        if locating { ProgressView() } else { A2Icon(name: "ui-gps-locate", fallback: "scope", size: 20).foregroundStyle(Home.primary) }
                        if !phone { Text("ตำแหน่งปัจจุบัน").font(.system(size: 16, weight: .semibold)) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(locating).fixedSize()
                .accessibilityLabel("ตำแหน่งปัจจุบัน")
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

/// Blue title bar of the card pages (A1, A2), in place of the navigation bar: back and sidebar buttons,
/// page title with the report number and the TCRoof job it belongs to, and export.
struct InfoPageHeader: View {
    let job: Job
    var title = "A1 ข้อมูลโครงการ"
    let back: () -> Void
    let toggleSidebar: () -> Void
    let export: () -> Void
    /// Added after the project code (E1: "หน้าสุดท้ายของรายงาน PDF").
    var subtitleSuffix: String? = nil
    @Environment(SurveyModel.self) var model
    /// iPhone: tighter padding, smaller title, export as an icon.
    @Environment(\.horizontalSizeClass) var sizeClass

    var subtitle: String {
        // "TC-0012 · สถานีสูบน้ำ" → "TC-0012"; the project name is already on the page
        let code = job.jobSyncID.flatMap { model.linkedJobLabel?($0) }?.components(separatedBy: " · ").first
        return (["แบบสำรวจ NO.\(job.docNo.isEmpty ? "—" : job.docNo)"] + [code, subtitleSuffix].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        let phone = sizeClass == .compact
        return HStack(spacing: phone ? 4 : 12) {
            squareButton("chevron.left", "ย้อนกลับ", action: back)
            squareButton("sidebar.left", "แสดง/ซ่อนรายการหัวข้อ", action: toggleSidebar)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: phone ? 17 : 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.system(size: phone ? 13 : 15)).opacity(0.92).lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            .padding(.leading, 4)
            Spacer(minLength: phone ? 4 : 8)
            Button(action: export) {
                Group {
                    if phone { Image(systemName: "square.and.arrow.up") } else { Label("ส่งออก", systemImage: "square.and.arrow.up") }
                }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, phone ? 0 : 14).frame(minWidth: 44, minHeight: 44)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    // the export sheet explains the gap; this dot just says there is one
                    if !job.missingGroups.isEmpty { Circle().fill(.orange).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                }
            }
            .accessibilityLabel("ส่งออก")
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, phone ? 8 : 24).padding(.vertical, phone ? 6 : 10)
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

/// Bottom bar of the card pages: save state, save now, previous and next step. iPhone shows `BottomBar` instead.
struct InfoPageBar: View {
    /// A shortcut chip after "ยังขาด" (A2: LIST items not ticked yet).
    struct Gap: Identifiable { let id = UUID(); let title: String; let action: () -> Void }

    let job: Job
    var here: MissingGroup.Target = .info
    /// Portrait: the "previous" button shows only the step code, and the others tighten.
    var narrow = false
    /// Portrait with the sidebar open (or iPad mini): "save" and "previous" become icon buttons and "next" shrinks,
    /// so the bar never pushes the page wider than the screen.
    var tight = false
    var previous: (() -> Void)? = nil
    let next: (() -> Void)?
    var gaps: [Gap] = []
    /// Replaces the completion line (A4: the equipment height check); red when `statusAlert`.
    var statusText: String? = nil
    var statusAlert = false
    /// A warning that doesn't block completion (B5's button height): orange "!" and an orange status line.
    var statusWarn = false
    /// Steps the back / next buttons name, when not the ones either side of `here` (B1 shows every building on one page).
    var previousIndex: Int? = nil
    var nextIndex: Int? = nil
    /// E1: the badge follows the whole job, not this page.
    var badgeComplete: Bool? = nil
    /// E1 when nothing is missing anywhere: the status line in green.
    var statusOK = false
    /// Tapping the status line (C1: opens the first gap).
    var statusAction: (() -> Void)? = nil
    /// The last page's primary button ("ขั้นสุดท้าย" / "สรุปผล · ส่งออก"), in place of "next".
    var finish: (sub: String, title: String, action: () -> Void)? = nil
    @Environment(SurveyModel.self) var model
    /// iPhone: `phoneBar` (docs/ui/components/iphone-bottom-bar) in place of the iPad bar.
    @Environment(\.horizontalSizeClass) var sizeClass
    @State var savedNow: Date?

    /// Step names short enough for the previous / next buttons ("A3 หม้อแปลง · MDB", as in docs/ui/survey-a2).
    static func barTitle(_ s: SurveyStep) -> String {
        s.page == .electrical ? "หม้อแปลง · MDB" : s.title
    }

    @ViewBuilder var body: some View {
        if sizeClass == .compact { phoneBar } else { padBar }
    }

    /// iPhone (docs/ui/components/iphone-bottom-bar): "บันทึก" · ‹ · ›, icons only; the step line above shows the gaps.
    var phoneBar: some View {
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        let name: (SurveyStep) -> String = { $0.code + " " + Self.barTitle($0) }
        let before = previous == nil ? nil : steps[safe: previousIndex ?? i - 1]
        let back = before.map { s in BottomBar.Nav(label: "ก่อนหน้า " + name(s), action: previous) }
            ?? BottomBar.Nav(label: "ก่อนหน้า (ขั้นแรก)", hint: "ไม่มีหัวข้อก่อนหน้า", action: nil)
        let after = next == nil ? nil : steps[safe: nextIndex ?? i + 1]
        let forward = finish.map { f in BottomBar.Nav(label: "ถัดไป " + f.title, action: f.action) }
            ?? after.map { s in BottomBar.Nav(label: "ถัดไป " + name(s), action: next) }
            ?? BottomBar.Nav(label: "ถัดไป", action: nil)
        return BottomBar(variant: .steps(save: {
            model.flush(job.id)
            let now = Date()
            savedNow = now
            return now
        }, previous: back, next: forward))
    }

    var padBar: some View {
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        let c = steps[safe: i]?.completion ?? Completion()
        let saved = max(job.updated, savedNow ?? .distantPast)
        return HStack(spacing: 12) {
            HStack(spacing: 10) {
                badge(complete: badgeComplete ?? (c.isComplete && !statusAlert && !statusWarn))
                VStack(alignment: .leading, spacing: 1) {
                    Text("บันทึกอัตโนมัติ " + (Calendar.current.isDateInToday(saved) ? saved.formatted(.dateTime.hour().minute())
                                                    : saved.formatted(.dateTime.day().month().hour().minute()))).font(.system(size: 15, weight: .semibold))
                    status(c)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.flush(job.id); savedNow = Date() } label: {
                Group {
                    if tight { Image(systemName: "square.and.arrow.down").font(.system(size: 20, weight: .semibold)) }
                    else { Text("บันทึกร่างตอนนี้").font(.system(size: 16, weight: .semibold)).lineLimit(1) }
                }
                .frame(width: tight ? 56 : narrow ? 130 : 170, height: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("บันทึกร่างตอนนี้")
            if let previous, let pi = Optional(previousIndex ?? i - 1), let s = steps[safe: pi] {
                Button(action: previous) {
                    HStack(spacing: narrow ? 6 : 10) {
                        A2Icon(name: "ui-prev", fallback: "chevron.left", size: 20)
                        if !tight {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("ก่อนหน้า \(pi + 1)/\(steps.count)").font(.system(size: 12)).foregroundStyle(Home.muted)
                                Text(narrow ? s.code : s.code + " " + Self.barTitle(s)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            }
                        }
                    }
                    .frame(width: tight ? 56 : narrow ? 120 : 210, height: 56)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ก่อนหน้า " + s.code + " " + Self.barTitle(s))
            } else if !narrow {
                HStack(spacing: 8) { A2Icon(name: "ui-prev", fallback: "chevron.left", size: 18); Text("หัวข้อแรก") }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(white: 0.56))
                    .frame(width: 180, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.5)))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityHint("ไม่มีหัวข้อก่อนหน้า")
            }
            if let finish {
                Button(action: finish.action) {
                    HStack(spacing: tight ? 6 : 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(finish.sub).font(.system(size: 12)).opacity(0.9)
                            Text(finish.title).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        A2Icon(name: "ui-next", fallback: "chevron.right", size: 20)
                    }
                    .foregroundStyle(.white)
                    .frame(width: tight ? 120 : narrow ? 200 : 230, height: 56)
                    .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(finish.title)
            } else if let next, let ni = Optional(nextIndex ?? i + 1), let s = steps[safe: ni] {
                Button(action: next) {
                    HStack(spacing: tight ? 6 : 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("ถัดไป \(ni + 1)/\(steps.count)").font(.system(size: 12)).opacity(0.9)
                            Text(tight ? s.code : s.code + " " + Self.barTitle(s)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        }
                        A2Icon(name: "ui-next", fallback: "chevron.right", size: 20)
                    }
                    .foregroundStyle(.white)
                    .frame(width: tight ? 120 : narrow ? 220 : 250, height: 56)
                    .background(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ถัดไป " + s.code + " " + Self.barTitle(s))
            }
        }
        .foregroundStyle(Home.navy)
        .frame(maxWidth: 1240)
        .padding(.horizontal, tight ? 16 : 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(Color.white.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }

    /// #1E7B45, E1's "ครบทุกหน้าแล้ว" line.
    static let okText = Color(red: 0.118, green: 0.482, blue: 0.271)

    /// Filled circle left of the save time: green ✓ when the page is complete, orange ! while items are missing (docs/ui/survey-a2 v2).
    func badge(complete: Bool) -> some View {
        Text(complete ? "✓" : "!").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(complete ? Home.ok : Home.warn, in: Circle())
            .accessibilityLabel(complete ? "ครบแล้ว" : "ยังขาดข้อมูล")
    }

    /// "ครบ 9/10 ช่องในหน้านี้", or "ครบช่องบังคับแล้ว · ยังขาด [chips]" when the page lists gaps.
    @ViewBuilder func status(_ c: Completion) -> some View {
        let tint = statusOK ? Self.okText : !c.isComplete || statusAlert ? Home.danger : statusWarn ? Home.pending : Home.muted
        if let statusText, let statusAction {
            Button(action: statusAction) {
                Text(statusText).font(.system(size: 13)).foregroundStyle(tint).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("แตะเพื่อไปที่รายการแรกที่ยังขาด")
        } else if let statusText {
            Text(statusText).font(.system(size: 13)).foregroundStyle(tint)
        } else if gaps.isEmpty {
            Text("ครบ \(c.filled)/\(c.total) ช่องในหน้านี้").font(.system(size: 13)).foregroundStyle(tint)
        } else {
            HStack(spacing: 6) {
                Text((c.isComplete ? "ครบช่องบังคับแล้ว" : "ครบ \(c.filled)/\(c.total) ช่อง") + " · ยังขาด").font(.system(size: 13)).foregroundStyle(tint)
                ForEach(gaps.prefix(tight ? 0 : narrow ? 1 : 3)) { g in
                    Button(action: g.action) {
                        Text(g.title + " ›").font(.system(size: 12, weight: .bold)).foregroundStyle(Home.pending)
                            .padding(.horizontal, 8).frame(minHeight: 26)
                            .background(Home.pending.opacity(0.12), in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if gaps.count > (tight ? 0 : narrow ? 1 : 3) { Text("+\(gaps.count - (tight ? 0 : narrow ? 1 : 3))").font(.system(size: 12, weight: .bold)).foregroundStyle(Home.pending) }
            }
            .frame(height: 22)
        }
    }
}
#endif
