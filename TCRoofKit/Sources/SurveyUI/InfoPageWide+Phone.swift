#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// A1 on iPhone (docs/ui/survey-a1-iphone, 390 × 844): the step line, then five full-width white bands — project,
/// location, coordinator, document, installation areas — in one scroll. Fields keep their `Schema.info` ids and storage.
extension InfoPageWide {
    /// Required fields of each band, for its `✓ n/m` chip (together they are the page's completion).
    static let projectIDs = ["projectName", "capacity", "internet"]
    static let locationIDs = ["gps", "address"]
    static let coordinatorIDs = ["coordinator", "phone"]
    static let documentIDs = ["docNo", "date", "engineer"]

    var phoneBody: some View {
        VStack(spacing: 0) {
            PageStepBar(job: job, here: .info, compact: true, chip: stepChip)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
            VStack(spacing: 0) {
                phoneBand("01", "โครงการ", chip: bandChip(Self.projectIDs)) { projectFields }
                phoneBand("02", "ที่ตั้ง", chip: bandChip(Self.locationIDs)) { locationFields }
                phoneBand("03", "ผู้ประสานงาน", chip: bandChip(Self.coordinatorIDs)) { coordinatorFields }
                phoneBand("04", "เอกสาร", chip: bandChip(Self.documentIDs)) { documentFields }
                phoneBand("05", "พื้นที่ติดตั้ง", chip: PhoneBand<EmptyView>.noteChip("รวม \(job.steps.count) ขั้น"), last: true) { areaFields }
            }
        }
        .onAppear {
            fillEngineer()
            #if DEBUG
            // `-surveyA1Internet yes|no` picks the answer, for `states/03-internet-none.png`
            if let a = UserDefaults.standard.string(forKey: "surveyA1Internet") { job.values["internet"] = .choice(a == "no" ? "ไม่มี" : "มี", other: "") }
            #endif
        }
    }

    // MARK: step line and bands

    /// `ครบ 11/11 ช่อง` (green) or `ขาด n ช่อง` (orange), from the page's own completion.
    var stepChip: (text: String, ok: Bool)? {
        guard let c = job.steps.first(where: { $0.page == .info })?.completion, c.total > 0 else { return nil }
        return c.isComplete ? ("ครบ \(c.filled)/\(c.total) ช่อง", true) : ("ขาด \(c.total - c.filled) ช่อง", false)
    }

    func bandChip(_ ids: [String]) -> (text: String, fg: Color, bg: Color) {
        PhoneBand<EmptyView>.countChip(ids.filter { spec($0).isFilled(job.values) }.count, ids.count)
    }

    func phoneBand<Content: View>(_ number: String, _ title: String, chip: PhoneBand<Content>.Chip, last: Bool = false,
                                  @ViewBuilder _ content: () -> Content) -> some View {
        PhoneBand(number: number, title: title, chip: chip, last: last, content: content)
    }

    /// Label 14 pt over a control, 5 pt apart.
    func pfield<C: View>(_ id: String, title: String? = nil, aside: String? = nil, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(spec: spec(id), filled: spec(id).isFilled(job.values), compact: true, title: title, aside: aside)
            control()
        }
    }

    func phoneText(_ id: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder(id), text: text(id)).keyboardType(keyboard).focused($focus, equals: id)
            .inputBox(calc: calc(id), focused: focus == id, minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
    }

    // MARK: 01 โครงการ

    @ViewBuilder var projectFields: some View {
        pfield("projectName", title: "ชื่อโครงการ / สถานี") { phoneText("projectName") }
        HStack(alignment: .top, spacing: 10) {
            pfield("capacity", title: "ขนาดติดตั้ง") { phoneCapacity }
            pfield("internet", title: "อินเทอร์เน็ต") { phoneInternet }
        }
    }

    var phoneCapacity: some View {
        let bad = !NumberInput.isValid(job.values.text("capacity"))
        return HStack(spacing: 6) {
            TextField("0", text: Binding(get: { job.values.text("capacity") }, set: {
                let c = NumberInput.clean($0)
                job.values["capacity"] = c.isEmpty ? nil : .text(c)
            }))
            .font(.system(size: 16, weight: .semibold))
            .keyboardType(.decimalPad).focused($focus, equals: "capacity")
            Text(unit("capacity")).font(.system(size: 14)).foregroundStyle(Theme.muted).fixedSize()
        }
        .inputBox(calc: calc("capacity"), focused: focus == "capacity", error: bad,
                  minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
    }

    /// `มี / ไม่มี` as a segmented control: grey track, the chosen one white and bold.
    var phoneInternet: some View {
        let chosen = job.values.choice("internet")
        return HStack(spacing: 3) {
            ForEach(Options.yesNo, id: \.self) { o in
                let on = chosen == o
                Button { job.values["internet"] = .choice(o, other: "") } label: {
                    Text(o).font(.system(size: 15, weight: on ? .bold : .regular)).foregroundStyle(on ? Home.navy : Home.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Color.white).shadow(color: Home.navy.opacity(0.2), radius: 1.5, y: 1) }
                        }
                        // 44 pt with the track's padding
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 02 ที่ตั้ง

    @ViewBuilder var locationFields: some View {
        SiteMapPreview(gps: text("gps"), zoom: Binding(get: { mapZoom }, set: { job.values["mapZoom"] = .text(String($0)) }),
                       crop: Binding(get: { mapCrop }, set: { job.values[MapCrop.key] = .text($0.text) }),
                       keys: model.settings.mapKeys, phone: true)
        pfield("gps", title: "พิกัด Google Map") { phoneGPS }
        pfield("address", title: "ที่อยู่สถานี / สถานที่ติดตั้ง") {
            TextField("", text: text("address"), axis: .vertical).lineLimit(1...3).focused($focus, equals: "address")
                .padding(.vertical, 10)
                .inputBox(calc: calc("address"), focused: focus == "address", minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
        }
        pfield("officeAddress", title: "ที่อยู่สำนักงาน / สาขา") {
            HStack(spacing: 6) {
                TextField("เหมือนที่อยู่สถานี", text: text("officeAddress")).focused($focus, equals: "officeAddress")
                // only offered while the field is empty, so it never overwrites an address someone typed
                if job.values.text("officeAddress").isEmpty {
                    Button("คัดลอก") { job.values["officeAddress"] = job.values["address"] }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Home.primary)
                        .frame(minHeight: 44).fixedSize()
                        .disabled(job.values.text("address").isEmpty)
                        .accessibilityLabel("คัดลอกที่อยู่สถานี")
                }
            }
            .inputBox(focused: focus == "officeAddress", minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
        }
    }

    /// The coordinate field and a 44-pt square locate button; the accuracy and format notes sit below.
    var phoneGPS: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField(placeholder("gps"), text: text("gps")).keyboardType(.numbersAndPunctuation).focused($focus, equals: "gps")
                    SourceChip(source: job.values.source("gps"))
                }
                .inputBox(focused: focus == "gps", minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
                Button(action: locate) {
                    Group {
                        if locating { ProgressView() } else { A2Icon(name: "ui-gps-locate", fallback: "scope", size: 20).foregroundStyle(Home.primary) }
                    }
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.35)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(locating)
                .accessibilityLabel("ตำแหน่งปัจจุบัน")
            }
            if locating, let a = liveAccuracy {
                Text("กำลังหาตำแหน่ง · ± \(Int(a.rounded())) ม.").font(.footnote).foregroundStyle(Home.muted)
            }
            gpsNote.font(.footnote)
        }
    }

    // MARK: 03 ผู้ประสานงาน

    @ViewBuilder var coordinatorFields: some View {
        HStack(alignment: .top, spacing: 10) {
            pfield("coordinator", title: "ชื่อ") { phoneText("coordinator") }
            pfield("phone", title: "เบอร์โทร") { phonePhoneInput }
        }
    }

    /// The number with a 16-pt phone icon at the trailing edge that calls it; the field stays editable.
    var phonePhoneInput: some View {
        let digits = job.values.text("phone").filter { $0.isNumber || $0 == "+" }
        return HStack(spacing: 0) {
            TextField("0xx-xxx-xxxx", text: text("phone")).keyboardType(.phonePad).focused($focus, equals: "phone")
            Button { if let u = URL(string: "tel:" + digits) { openURL(u) } } label: {
                A2Icon(name: "ui-phone", fallback: "phone", size: 16).foregroundStyle(Home.primary).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .disabled(digits.isEmpty)
            .accessibilityLabel("โทรหาผู้ประสานงาน")
        }
        .inputBox(calc: calc("phone"), focused: focus == "phone", minHeight: 44, trailing: 0, leading: 12, fontSize: 16, stroke: 0.35)
    }

    // MARK: 04 เอกสาร

    @ViewBuilder var documentFields: some View {
        HStack(alignment: .top, spacing: 10) {
            pfield("docNo", title: "เลขที่") { phoneText("docNo", keyboard: .numbersAndPunctuation) }
            pfield("rev", title: "REV.", aside: "") { phoneText("rev", keyboard: .numbersAndPunctuation) }
                .frame(width: 72)
        }
        HStack(alignment: .top, spacing: 10) {
            pfield("date", title: "วันที่สำรวจ") { dateButton(compact: true) }
            pfield("engineer", title: "วิศวกรผู้สำรวจ", aside: myEngineer.isEmpty ? "" : "จากการตั้งค่า") { phoneEngineer }
        }
    }

    var myEngineer: String { model.settings.engineer.trimmingCharacters(in: .whitespaces) }

    /// Read-only (grey, lock) while Settings has a name; the old editable field when it doesn't, so the page can still be completed.
    @ViewBuilder var phoneEngineer: some View {
        let value = job.values.text("engineer").trimmingCharacters(in: .whitespaces)
        if myEngineer.isEmpty {
            TextField("ชื่อวิศวกร", text: text("engineer")).focused($focus, equals: "engineer")
                .inputBox(focused: focus == "engineer", minHeight: 44, trailing: 12, leading: 12, fontSize: 16, stroke: 0.35)
        } else {
            HStack(spacing: 6) {
                Text(value.isEmpty ? myEngineer : value).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "lock").font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
            .font(.system(size: 15)).foregroundStyle(Home.muted)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Home.disabledFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.hairline))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("วิศวกรผู้สำรวจ \(value.isEmpty ? myEngineer : value) · ดึงจากการตั้งค่า แก้ไขไม่ได้")
        }
    }

    /// A job opened before the engineer was set takes the Settings name, as the read-only field shows it.
    func fillEngineer() {
        if !myEngineer.isEmpty, job.values.text("engineer").trimmingCharacters(in: .whitespaces).isEmpty {
            job.values["engineer"] = .text(myEngineer)
        }
    }

    // MARK: 05 พื้นที่ติดตั้ง

    @ViewBuilder var areaFields: some View {
        Text("กำหนดหน้า C / D ในแบบสำรวจ").font(.system(size: 12)).foregroundStyle(Theme.muted)
        areaTiles
    }
}
#endif
