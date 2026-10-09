#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// "พื้นที่ติดตั้ง" (how many C1 roof and D1 tank sections the job has) and the location card.
/// Older jobs may carry a ground-area count (`groundAreas`); it is no longer shown or counted, but stays in the job
/// and its web backup (`WebBackup.extraJobKeys`).
extension InfoPageWide {
    // MARK: installation areas

    var areasBox: some View {
        A1Card(title: "พื้นที่ติดตั้ง", required: true, trailing: "กำหนดหน้า C / D ในแบบสำรวจ · รวม \(job.steps.count) ขั้น", spacing: 10, vertical: 14) {
            areaTiles
        }
    }

    /// Two across when the column is wide enough; one per row when the sidebar leaves it too narrow.
    var areaTiles: some View {
        let layout = mainWidth >= 440 ? AnyLayout(RatioRow(weights: [1, 1], spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            areaTile("หลังคา", "หน้า C · หลัง", count: count(.roof)) { setCount(.roof, $0) }
            areaTile("ถังน้ำใส", "หน้า D1 · ถัง", count: count(.tank)) { setCount(.tank, $0) }
        }
    }

    /// iPad (docs/ui/survey-a1-ipad): 60 high, 12-pt corners, 44-pt − / + targets. iPhone keeps 50, 10 and 30.
    func areaTile(_ title: String, _ detail: String, count: Int, set: @escaping (Int) -> Void) -> some View {
        let on = count > 0
        let pad = sizeClass != .compact
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
                .frame(minHeight: pad ? 60 : 50).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(on ? .isSelected : [])
            stepButton("ui-minus", "minus", label: "ลด" + title, width: pad ? 44 : 30) { set(count - 1) }.disabled(count == 0)
            Text("\(count)").font(.system(size: 16, weight: .bold)).monospacedDigit().frame(minWidth: 18)
            stepButton("ui-plus", "plus", label: "เพิ่ม" + title, width: pad ? 44 : 30) { set(count + 1) }.disabled(count >= 20)
        }
        .padding(.leading, 12).padding(.trailing, pad ? 4 : 2)
        .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: pad ? 12 : 10))
        .overlay(RoundedRectangle(cornerRadius: pad ? 12 : 10).stroke(on ? Home.navy.opacity(0.2) : Home.borderControl))
    }

    func stepButton(_ icon: String, _ symbol: String, label: String, width: CGFloat = 30, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            A2Icon(name: icon, fallback: symbol, size: 18).frame(width: width, height: 44).contentShape(Rectangle())
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

    /// Map, its hint and the GPS (docs/ui/survey-a1-ipad). In landscape the map takes the card's free height.
    /// The station address is in `projectCoordinatorBox`; the office address isn't on the iPad page (it stays in the job,
    /// the iPhone page and the export).
    var locationBox: some View {
        A1Card(title: "ที่ตั้ง") {
            VStack(alignment: .leading, spacing: 8) {
                SiteMapPreview(gps: text("gps"), zoom: Binding(get: { mapZoom }, set: { job.values["mapZoom"] = .text(String($0)) }),
                               crop: Binding(get: { mapCrop }, set: { job.values[MapCrop.key] = .text($0.text) }),
                               keys: model.settings.mapKeys, fill: twoColumns)
                HStack(alignment: .center, spacing: 8) {
                    Text("ลากกรอบหรือมุมเพื่อเลือกพื้นที่ภาพในรายงาน PDF / Excel · แตะค้างที่หมุดเพื่อย้าย")
                        .font(.system(size: 13)).foregroundStyle(Home.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("รีเซ็ตกรอบ") { job.values[MapCrop.key] = .text(MapCrop.standard.text) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Home.primary)
                        .frame(minWidth: 44, minHeight: 44).fixedSize()
                        .disabled(mapCrop == .standard)
                }
                .padding(.vertical, -6)
            }
            field("gps", title: "พิกัดดาวเทียม Google Map") { gpsInput }
        }
    }

    /// Zoom of this job's site picture; follows the settings until a level is picked here.
    var mapZoom: Int { Int(job.values.text("mapZoom")) ?? model.settings.mapZoom }
    /// Part of the map used as the report picture; a job from before the frame existed uses all of it.
    var mapCrop: MapCrop { MapCrop(job.values.text(MapCrop.key)) ?? .full }

    var gpsInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField(placeholder("gps"), text: text("gps")).keyboardType(.numbersAndPunctuation).focused($focus, equals: "gps")
                    SourceChip(source: job.values.source("gps"))
                }
                .inputBox(focused: focus == "gps", radius: InfoPageWide.inputRadius)
                Button(action: locate) {
                    HStack(spacing: 8) {
                        if locating { ProgressView() } else { A2Icon(name: "ui-gps-locate", fallback: "scope", size: 20).foregroundStyle(Home.primary) }
                        if locating, let a = liveAccuracy { Text("± \(Int(a.rounded())) ม.").font(.system(size: 16, weight: .semibold).monospacedDigit()) }
                        else if !phone { Text("ตำแหน่งปัจจุบัน").font(.system(size: 16, weight: .semibold)) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: InfoPageWide.inputRadius))
                    .overlay(RoundedRectangle(cornerRadius: InfoPageWide.inputRadius).stroke(Home.navy.opacity(0.45)))
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
            else if let fix {
                Text(GPSGrade.note(accuracy: fix.accuracy) + " · บันทึกเมื่อ \(fix.time.formatted(.dateTime.hour().minute()))")
                    .foregroundStyle(GPSGrade(accuracy: fix.accuracy) == .approximate ? Home.pending : Home.muted)
            }
        }
    }

    func locate() {
        locating = true
        gpsFailure = nil
        liveAccuracy = nil
        locator.progress = { liveAccuracy = $0 }
        locator.request { result in
            locating = false
            switch result {
            case .success(let loc):
                job.values.set("gps", .text(GPS.format(loc.coordinate.latitude, loc.coordinate.longitude)), source: .gps)
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

/// Bottom bar of the card pages. iPad: the shared `TCPadStepBar` (docs/ui/survey-bar-ipad); iPhone: `BottomBar`.
struct InfoPageBar: View {
    let job: Job
    var here: MissingGroup.Target = .info
    /// Portrait: the "previous" button shows only the step code, and the others tighten.
    var narrow = false
    /// Portrait with the sidebar open (or iPad mini): "save" and "previous" become icon buttons and "next" shrinks,
    /// so the bar never pushes the page wider than the screen.
    var tight = false
    var previous: (() -> Void)? = nil
    let next: (() -> Void)?
    /// The page's own status (A2's chip, A3's photo gaps, B1's building chip), in place of the one built from the fields below.
    var status: TCBarStatus? = nil
    /// Replaces the completion line (A4: the equipment height check); red when `statusAlert`.
    var statusText: String? = nil
    var statusAlert = false
    /// A warning that doesn't block completion (B5's button height): orange "!" and an orange status line.
    var statusWarn = false
    /// Steps the back / next buttons name, when not the ones either side of `here` (B1 shows every building on one page).
    var previousIndex: Int? = nil
    var nextIndex: Int? = nil
    /// Nothing is missing (E1: anywhere in the job; C1: no gaps): the status line in bold green.
    var statusOK = false
    /// Tapping the status line (C1: opens the first gap).
    var statusAction: (() -> Void)? = nil
    /// The last page's primary button ("ขั้นสุดท้าย" / "สรุปผล · ส่งออก"), in place of "next".
    var finish: (sub: String, title: String, action: () -> Void)? = nil
    /// iPhone: VoiceOver names for ‹ › when they step within the page (D1's sub-steps), in place of the steps either side.
    var previousLabel: String? = nil
    var nextLabel: String? = nil
    @Environment(SurveyModel.self) var model
    /// iPhone: `phoneBar` (docs/ui/components/iphone-bottom-bar) in place of the iPad bar.
    @Environment(\.horizontalSizeClass) var sizeClass

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
        var back = before.map { s in BottomBar.Nav(label: "ก่อนหน้า " + name(s), action: previous) }
            ?? BottomBar.Nav(label: "ก่อนหน้า (ขั้นแรก)", hint: "ไม่มีหัวข้อก่อนหน้า", action: nil)
        let after = next == nil ? nil : steps[safe: nextIndex ?? i + 1]
        if let previousLabel { back = BottomBar.Nav(label: previousLabel, action: previous) }
        if let nextLabel { return bar(back, BottomBar.Nav(label: nextLabel, action: next)) }
        let forward = finish.map { f in BottomBar.Nav(label: "ถัดไป " + f.title, action: f.action) }
            ?? after.map { s in BottomBar.Nav(label: "ถัดไป " + name(s), action: next) }
            ?? BottomBar.Nav(label: "ถัดไป", action: nil)
        return bar(back, forward)
    }

    func bar(_ back: BottomBar.Nav, _ forward: BottomBar.Nav) -> BottomBar {
        BottomBar(variant: .steps(save: save, version: job.editVersion, previous: back, next: forward))
    }

    /// Writes the job now; the save button shows "บันทึกแล้ว" once it returns.
    @MainActor func save() async -> Date {
        model.flush(job.id)
        return Date()
    }

    /// iPad: status · save · ‹ · ›. Portrait narrows the buttons (`narrow`, `tight`) and the status truncates first.
    var padBar: some View {
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        let c = steps[safe: i]?.completion ?? Completion()
        let navWidth: CGFloat = tight ? 56 : narrow ? 120 : 230
        let pi = previousIndex ?? i - 1
        let back = previous.flatMap { action in steps[safe: pi].map { s in
            TCStepNavButton(direction: .previous, index: pi + 1, count: steps.count, title: narrow ? s.code : s.code + " " + Self.barTitle(s),
                            width: navWidth, iconOnly: tight, action: action)
        } } ?? TCStepNavButton(direction: .previous, index: 0, count: steps.count, title: "หัวข้อแรก", width: navWidth, iconOnly: tight, action: nil)
        let ni = nextIndex ?? i + 1
        let nextWidth: CGFloat = tight ? 120 : narrow ? 210 : 230
        let forward: TCStepNavButton
        if let finish {
            forward = TCStepNavButton(direction: .next, index: 0, count: steps.count, title: finish.title, caption: finish.sub,
                                      width: nextWidth, action: finish.action)
        } else if let next, let s = steps[safe: ni] {
            forward = TCStepNavButton(direction: .next, index: ni + 1, count: steps.count, title: tight ? s.code : s.code + " " + Self.barTitle(s),
                                      width: nextWidth, action: next)
        } else {
            forward = TCStepNavButton(direction: .next, index: 0, count: steps.count, title: "ถัดไป", width: nextWidth, action: nil)
        }
        return TCPadStepBar(status: status ?? padStatus(c),
                            save: .pad(width: tight ? 56 : narrow ? 130 : 170, icon: tight ? "square.and.arrow.down" : nil,
                                       save: save, version: job.editVersion),
                            previous: back, next: forward, sides: tight ? 16 : 24)
            .foregroundStyle(Home.navy)
    }

    /// `ครบ 11/11 ช่องในหน้านี้`, or the page's own line; green ✓ only when nothing is missing or warned about.
    func padStatus(_ c: Completion) -> TCBarStatus {
        let alert = !c.isComplete || statusAlert
        let text = statusText ?? "ครบ \(c.filled)/\(c.total) ช่องในหน้านี้"
        if statusOK { return .allDone(text) }
        if alert || statusWarn { return .missing(text, warn: !alert, action: statusAction) }
        return .complete(text)
    }
}
#endif
