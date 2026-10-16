import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// iPhone "add new customer" sheet for home jobs (docs/ui/tcroof-new-job-iphone): grouped cards, one grid picker,
/// a province sheet, and a pinned save button. `NewJobView` shows it at compact width only.
struct NewJobPhoneView: View {
    /// Called by `เปิดงาน` on the saved banner, after the sheet is dismissed.
    var onOpen: ((Job) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Field { case name, phone, address, project }
    @FocusState private var focus: Field?

    @State private var today = Date().startOfDay
    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var province = ThaiProvince.defaultName
    @State private var day = Date().startOfDay.adding(days: 1)
    @State private var hour = 9
    @State private var minute = 0
    @State private var kWp: Double?
    @State private var team = Team.t1
    @State private var project = ""
    @State private var installOffset = 14
    @State private var installDays = 2
    @State private var showDetails = false
    @State private var picker: NewJobPicker?
    @State private var triedSave = false
    @State private var saved: Job?

    // MARK: derived

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var surveyDate: Date { NewJobRules.surveyDate(day: day, hour: hour, minute: minute) }
    private var phoneOK: Bool { NewJobRules.isValidPhone(phone) }
    private var nameMissing: Bool { triedSave && trimmedName.isEmpty }
    private var timeText: String { String(format: "%02d:%02d น.", hour, minute) }
    private var dayText: String {
        NewJobRules.relativeDay(day, from: today) + " · " + ThaiFormat.weekdayTiny.string(from: day)
    }
    private var installRange: (start: Date, end: Date) {
        NewJobRules.installRange(survey: day, offsetDays: installOffset, days: installDays)
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            TCGradientHeader(title: "เพิ่มลูกค้าใหม่", subtitle: "สำรวจหน้างาน · งานบ้าน", onClose: { dismiss() }) { EmptyView() }
            ScrollView {
                VStack(spacing: 22) {
                    customerGroup
                    appointmentGroup
                    detailsGroup
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            saveBar
        }
        .background(Theme.groupedPage.ignoresSafeArea())
        .overlay(alignment: .bottom) { savedBanner }
        .animation(.easeOut(duration: 0.2), value: showDetails)
        #if DEBUG
        .task { await applyDebugState() }
        #endif
        .sheet(item: $picker) { kind in
            NewJobPickerSheet(kind: kind, current: $picker, today: today, day: $day, hour: $hour, minute: $minute, kWp: $kWp,
                              team: $team, installOffset: $installOffset, installDays: $installDays, province: $province)
        }
    }

    #if DEBUG
    /// `-surveyNewJob empty|filled|details|date|time|kwp|team|install|province|search|invalid|saved` opens that state of
    /// docs/ui/tcroof-new-job-iphone/states (the sheet itself is opened by `PhoneSurveyList`).
    private func applyDebugState() async {
        guard let state = UserDefaults.standard.string(forKey: "surveyNewJob") else { return }
        if !["empty", "invalid"].contains(state) {
            name = "คุณมานพ ศรีสวัสดิ์"; phone = "081-234-5678"; address = "27/4 ม.6 ต.บางรักพัฒนา อ.บางบัวทอง"
            province = "นนทบุรี"
        }
        if ["details", "kwp", "team", "install", "saved"].contains(state) {
            kWp = 5; team = .t3; project = "บ้านคุณมานพ — หลังคาโรงจอดรถ"; showDetails = true
        }
        try? await Task.sleep(for: .milliseconds(600))
        switch state {
        case "date": picker = .date
        case "time": picker = .time
        case "kwp": picker = .kWp
        case "team": picker = .team
        case "install": picker = .install
        case "province", "search": picker = .province
        case "invalid": triedSave = true
        case "saved": save()
        default: break
        }
    }
    #endif

    // MARK: groups

    private var customerGroup: some View {
        FormGroup(header: "ลูกค้า") {
            FormRow(label: "ชื่อลูกค้า", required: true, highlight: nameMissing) {
                TextField("ชื่อ-นามสกุล", text: $name)
                    .textContentType(.name).focused($focus, equals: .name)
                    .submitLabel(.next).onSubmit { focus = .phone }
            }
            FormRow(label: "เบอร์โทร", highlight: !phoneOK) {
                TextField("0X-XXXX-XXXX", text: $phone)
                    .keyboardType(.phonePad).textContentType(.telephoneNumber).monospacedDigit()
                    .focused($focus, equals: .phone)
                    .onChange(of: phone) { _, new in
                        let f = NewJobRules.formatPhone(new)
                        if f != new { phone = f }
                    }
            }
            FormRow(label: "ที่อยู่", multiline: true) {
                TextField("บ้านเลขที่ ซอย ถนน ตำบล อำเภอ", text: $address, axis: .vertical)
                    .textContentType(.fullStreetAddress).focused($focus, equals: .address)
            }
            FormRow(label: "จังหวัด", disclosure: true, separator: false, action: { open(.province) }) {
                Text(province).foregroundStyle(Theme.groupFooter)
            }
        }
    }

    private var appointmentGroup: some View {
        FormGroup(header: "นัดสำรวจ", footer: "ทีม \(team.rawValue) จะเห็นนัดนี้ในปฏิทินแผนก่อสร้าง") {
            FormRow(label: "วันที่", disclosure: true, action: { open(.date) }) {
                Text(dayText).font(.sarabun(16, .semibold)).foregroundStyle(Theme.iosBlue)
            }
            FormRow(label: "เวลา", disclosure: true, separator: false, action: { open(.time) }) {
                Text(timeText).font(.sarabun(16, .semibold)).monospacedDigit().foregroundStyle(Theme.iosBlue)
            }
        }
    }

    private var detailsGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("รายละเอียดงาน · ไม่บังคับ").font(.sarabun(13)).foregroundStyle(Theme.groupHeader)
                Spacer()
                Text(showDetails ? "ซ่อน" : "แสดง").font(.sarabun(14, .semibold)).foregroundStyle(Theme.iosBlue)
            }
            .padding(.leading, 16).padding(.trailing, 16)
            .frame(minHeight: 44).contentShape(Rectangle())
            .onTapGesture { showDetails.toggle(); focus = nil }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(showDetails ? "ขยายอยู่" : "ย่ออยู่")
            if showDetails {
                detailsCard
                Text("ติดตั้งโดยประมาณ \(installRangeText) · ปรับได้ภายหลังในรายละเอียดงาน")
                    .font(.sarabun(12.5)).foregroundStyle(Theme.groupFooter).padding(.horizontal, 16)
            }
        }
    }

    private var installRangeText: String {
        let r = installRange
        return "\(ThaiFormat.weekdayTiny.string(from: r.start)) – \(ThaiFormat.weekdayTiny.string(from: r.end)) \(ThaiFormat.year.string(from: r.end))"
    }

    private var detailsCard: some View {
        FormCard {
            FormRow(label: "ขนาดระบบ", disclosure: true, action: { open(.kWp) }) {
                if let kWp {
                    Text("\(kWp.formatted(.number.precision(.fractionLength(0...1)))) kWp · ~\(NewJobRules.panelCount(kWp: kWp)) แผง")
                } else {
                    Text("ยังไม่ทราบ").foregroundStyle(Theme.placeholder)
                }
            }
            FormRow(label: "ทีม", disclosure: true, action: { open(.team) }) {
                Text(team.rawValue).font(.sarabun(16, .bold)).foregroundStyle(team.color)
            }
            FormRow(label: "ชื่องาน") {
                TextField("ใช้ชื่อลูกค้า", text: $project).focused($focus, equals: .project)
            }
            FormRow(label: "เริ่มติดตั้ง", disclosure: true, separator: false, action: { open(.install) }) {
                Text("+\(installOffset) วัน · \(installDays) วัน").font(.sarabun(16, .semibold)).foregroundStyle(Theme.iosBlue)
            }
        }
    }

    private func open(_ kind: NewJobPicker) {
        focus = nil
        picker = kind
    }

    // MARK: save

    private var saveBar: some View {
        Button(action: save) { saveLabel }
            .buttonStyle(TCPressStyle())
            .disabled(saved != nil)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 26)
            .background(Theme.groupedPage)
    }

    private enum SaveState { case empty, invalid, phone, ready, saved }
    private var saveState: SaveState {
        if saved != nil { return .saved }
        if trimmedName.isEmpty { return triedSave ? .invalid : .empty }
        return phoneOK ? .ready : .phone
    }

    private var saveLabel: some View {
        let s = saveState
        let sub: String? = switch s {
        case .empty: "ใส่ชื่อลูกค้าอย่างเดียวก็บันทึกได้"
        case .invalid: "ใส่ชื่อลูกค้าก่อน"
        case .phone: "เบอร์โทรต้องมี 9–10 หลัก"
        case .ready: "นัดสำรวจ \(NewJobRules.relativeDay(day, from: today)) \(timeText)"
        case .saved: nil
        }
        let fill: AnyShapeStyle = switch s {
        case .empty: AnyShapeStyle(Theme.separatorLine)
        case .invalid, .phone: AnyShapeStyle(Theme.dangerSoft)
        case .ready: AnyShapeStyle(Theme.actionGradient)
        case .saved: AnyShapeStyle(Theme.okSoft)
        }
        let ink: Color = switch s {
        case .empty: Theme.groupFooter
        case .invalid, .phone: Theme.dangerText
        case .ready: Theme.onPrimary
        case .saved: Theme.okTick
        }
        return VStack(spacing: 1) {
            Text(s == .saved ? "✓ บันทึกแล้ว" : "บันทึกลูกค้า").font(.sarabun(17, .bold))
            if let sub { Text(sub).font(.sarabun(12, .medium)).opacity(0.85) }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: s == .ready ? Theme.fabShadow : .clear, radius: 8, y: 6)
    }

    private func save() {
        guard saved == nil else { return }
        guard !trimmedName.isEmpty else {
            triedSave = true
            focus = .name
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        guard phoneOK else { focus = .phone; return }
        let proj = project.trimmingCharacters(in: .whitespaces)
        let r = installRange
        let job = Job(code: SampleData.newJobCode(), projectName: proj.isEmpty ? trimmedName : proj, customerName: trimmedName,
                      phone: phone, address: address.trimmingCharacters(in: .whitespacesAndNewlines), province: province,
                      capacityKW: kWp ?? 0, team: team, status: .interested,
                      surveyDate: surveyDate, installStart: r.start, installDays: installDays)
        job.kind = .home
        context.insert(job)
        try? context.save()
        focus = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.2)) { saved = job }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if saved === job { dismiss() }
        }
    }

    // MARK: banner

    @ViewBuilder private var savedBanner: some View {
        if let job = saved {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 28, height: 28).background(Theme.paperTick, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("เพิ่มลูกค้าแล้ว").font(.sarabun(14, .bold))
                    Text("\(job.code) · อยู่ในรายการงานสำรวจ").font(.sarabun(12)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let onOpen {
                    Button {
                        dismiss()
                        onOpen(job)
                    } label: {
                        Text("เปิดงาน").font(.sarabun(14, .bold)).foregroundStyle(Theme.mint)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
            .background(Theme.bannerFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.bannerFill.opacity(0.35), radius: 13, y: 10)
            .padding(.horizontal, 16).padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

/// Thai short weekdays as the board shows them (`พฤ.`); `ThaiFormat.weekdayShort` gives `พฤหัส`. With the date:
/// `ThaiFormat.weekdayTiny`.
enum NewJobFormat {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = ThaiFormat.locale; f.dateFormat = format; return f
    }
    static let weekday = make("EEEEEE")
}

// MARK: - Group, card, row

/// A grouped-list section: header above, white card, optional footer below.
private struct FormGroup<Content: View>: View {
    let header: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header).font(.sarabun(13)).foregroundStyle(Theme.groupHeader).padding(.leading, 16)
            FormCard { content }
            if let footer {
                Text(footer).font(.sarabun(12.5)).foregroundStyle(Theme.groupFooter).padding(.horizontal, 16)
            }
        }
    }
}

private struct FormCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One 52 pt row: a 96 pt label and a trailing value. With `action` it is a button (a picker row).
private struct FormRow<Value: View>: View {
    let label: String
    var required = false
    var multiline = false
    var disclosure = false
    var highlight = false
    var separator = true
    var action: (() -> Void)?
    @ViewBuilder var value: Value

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .background(highlight ? Theme.dangerSoft : Color.clear)
        .overlay(alignment: .bottom) {
            if separator { Theme.separatorLine.frame(height: 1).padding(.leading, 16) }
        }
    }

    private var row: some View {
        HStack(alignment: multiline ? .top : .center, spacing: 12) {
            (Text(label) + (required ? Text(" *").foregroundColor(Theme.danger) : Text("")))
                .font(.sarabun(16)).foregroundStyle(Theme.navy)
                .frame(width: 96, alignment: .leading)
                .padding(.top, multiline ? 15 : 0)
            value
                .font(.sarabun(16)).foregroundStyle(.primary)
                .multilineTextAlignment(.trailing).lineLimit(multiline ? nil : 1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, multiline ? 15 : 0)
            if disclosure {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.placeholder)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
