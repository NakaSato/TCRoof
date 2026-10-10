#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore
import TCRoofUI

// MARK: small controls of the diagram

/// Small label above a control, with the red star of a required field.
struct A3Label: View {
    let text: String
    var required = false
    var body: some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            if required { Text("*").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.danger) }
        }
    }
}

/// Labelled text box (44 pt high), with an optional unit at the right.
struct A3Input: View {
    let label: String
    @Binding var text: String
    var required = false
    var unit: String?
    var keyboard: UIKeyboardType = .default
    /// The value came from the A2 picture.
    var a2 = false
    /// The value was read from a nameplate or a sensor.
    var source: FillSource? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: label, required: required)
            HStack(spacing: 4) {
                TextField("", text: $text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                if a2 { A2Badge() }
                SourceChip(source: source)
                if let unit { Text(unit).font(.system(size: 14)).foregroundStyle(Theme.inkMuted) }
            }
            .inputBox(minHeight: 44, trailing: 10)
        }
    }
}

/// One-of-n buttons; tapping the chosen one clears it.
struct A3Segments: View {
    let options: [String]
    var titles: [String]?
    let selected: String
    let set: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { n, o in
                let on = selected == o
                Button { set(on ? "" : o) } label: {
                    Text(titles?[n] ?? o).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.mint : Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.teal : Theme.borderControl.opacity(0.6), lineWidth: on ? 2 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// White card with a 1-pt navy border.
struct A3Panel<Content: View>: View {
    var accent = false
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent ? Theme.primary : Theme.navy.opacity(0.25), lineWidth: accent ? 2 : 1))
    }
}

/// Round badge with a short code ("TX 1", "MDB").
struct A3Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(Theme.navy, lineWidth: 1.5))
    }
}

func a3Chip(_ text: String, ok: Bool) -> some View {
    Text(text).font(.system(size: 13, weight: .bold)).lineLimit(1)
        .foregroundStyle(ok ? Theme.success : Theme.danger)
        .padding(.horizontal, 10).frame(minHeight: 26)
        .background((ok ? Theme.mint.opacity(0.4) : Theme.danger.opacity(0.1)), in: Capsule())
}

/// A small photo frame on the shared `PhotoSlot`: the compact empty layout, and the label on the filled photo.
struct A3PhotoTile: View {
    @Binding var photo: Photo?
    let jobID: UUID
    let label: String
    var required = false
    var height: CGFloat = 96
    @Environment(SurveyModel.self) private var model

    var body: some View {
        PhotoSlot(photo: photo, jobID: jobID, hint: label + (required ? " *" : ""), required: required, title: label, dense: true,
                  onPick: { img in if let p = model.addPhoto(img, to: jobID) { photo = p } },
                  onClear: { photo = nil })
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay(alignment: .bottomLeading) {
                if photo != nil {
                    Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4)).padding(4)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: meter

extension ElectricalPageWide {
    /// Side by side on iPad; one above the other on iPhone.
    func rowStack<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let layout = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        return layout { content() }
    }

    /// Fields in a row on iPad; two across on iPhone.
    @ViewBuilder func inputRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if narrow {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 8) { content() }
        } else {
            HStack(spacing: 8) { content() }
        }
    }

    var meterCard: some View {
        A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "PEA")
                    Text("มิเตอร์ กฟภ.").font(.system(size: 18, weight: .bold))
                    if a2Badges.contains(.meter) { A2Badge() }
                }
                HStack(alignment: .bottom, spacing: 6) {
                    A3Input(label: "หมายเลขมิเตอร์", text: vText("meterNo"), required: true, source: job.values.source("meterNo"))
                    NameplateScanButton(target: .meterNumber, apply: { job.values.set("meterNo", .text($0), source: .nameplate) }, compact: true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    A3Label(text: "แรงดันที่รับไฟ (kV)", required: true)
                    A3Segments(options: Schema.meterKV, selected: vChoice("meterKV")) { setChoice("meterKV", $0) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    A3Label(text: "ระบบไฟ")
                    A3Segments(options: Schema.meterPhases, selected: vChoice("meterPhase")) { setChoice("meterPhase", $0) }
                }
                Button { withAnimation { moreMeter.toggle() } } label: {
                    Text(moreMeter ? "ซ่อนข้อมูลเพิ่มเติม ▴" : "แสดงข้อมูลเพิ่มเติม (4) ▾").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 44).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                if moreMeter {
                    A3Input(label: "เลขผู้ใช้ไฟ (CA)", text: vText("meterCA"), keyboard: .numbersAndPunctuation)
                    A3Input(label: "ประเภทผู้ใช้ไฟ / อัตรา", text: vText("meterRate"))
                    A3Input(label: "ขนาดมิเตอร์ / CT (A)", text: vText("meterCT"), keyboard: .numbersAndPunctuation)
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "ภาพมิเตอร์")
                        A3PhotoTile(photo: photoBinding("meterPic"), jobID: job.id, label: "ภาพมิเตอร์", height: 80)
                            .photoShot("meterPic")
                    }
                } else if let s = meterSummary {
                    Text(s).font(.system(size: 12)).foregroundStyle(Theme.success).lineLimit(2)
                }
            }
        }
    }

    /// "CA · อัตรา TOU · CT 400/5 · ภาพมิเตอร์ ครบแล้ว" — what the folded part holds.
    var meterSummary: String? {
        let v = job.values
        let parts = [v.text("meterCA").isEmpty ? nil : "CA", v.text("meterRate").isEmpty ? nil : "อัตรา " + v.text("meterRate"),
                     v.text("meterCT").isEmpty ? nil : "CT " + v.text("meterCT"), v.photo("meterPic") == nil ? nil : "ภาพมิเตอร์"].compactMap { $0 }
        return parts.isEmpty ? nil : "✓ " + parts.joined(separator: " · ") + " ครบแล้ว"
    }
}

// MARK: transformers

extension ElectricalPageWide {
    static let kvaSizes = ["50", "100", "160", "250", "315", "400", "500", "630", "800", "1000", "1250", "1500", "2000", "2500"]
    static let shortAngles = ["หน้า", "หลัง", "ซ้าย", "ขวา", "ป้ายพิกัด", "มุมกว้าง"]

    func photoCount(_ i: Int) -> Int { Schema.transformerAngles.filter { job.values.photo("tr\(i)_\($0.key)") != nil }.count }

    @ViewBuilder func transformerView(_ i: Int) -> some View {
        if i == openIndex { openTransformer(i) } else { foldedTransformer(i) }
    }

    func kvaField(_ i: Int) -> some View {
        HStack(spacing: 0) {
            TextField("", text: kvaText(i)).keyboardType(.numberPad)
                .font(.system(size: 17, weight: .semibold))
            Text("kVA").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            if a2Badges.contains(.kva(i)) { A2Badge().padding(.leading, 4) }
            SourceChip(source: job.values.source("tr\(i)_kva")).padding(.leading, 4)
            NameplateScanButton(kind: .transformer, compact: true) { fields, image in applyPlate(i, fields, frame: image) }
            Menu {
                ForEach(Self.kvaSizes, id: \.self) { k in Button(k + " kVA") { edit(i) { $0.kva = k }; job.values.forgetSource("tr\(i)_kva") } }
            } label: { Image(systemName: "chevron.down").frame(width: 36, height: 44) }
        }
        .padding(.leading, 12).frame(minHeight: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.45)))
    }

    /// Typing a kVA by hand forgets that it was read from the nameplate.
    func kvaText(_ i: Int) -> Binding<String> { plateText(i, \.kva, key: "kva", number: true) }

    /// A nameplate field of transformer `i`: typing forgets that it was read from the plate.
    func plateText(_ i: Int, _ kp: WritableKeyPath<Transformer, String>, key: String, number: Bool = false) -> Binding<String> {
        let t = tText(i, kp, number: number)
        return Binding(get: { t.wrappedValue }, set: { t.wrappedValue = $0; job.values.forgetSource("tr\(i)_\(key)") })
    }

    /// Writes confirmed nameplate values into transformer `i`, each marked as read from the plate, and keeps the scanned
    /// frame as its nameplate photo when that slot is empty.
    func applyPlate(_ i: Int, _ fields: [NameplateParser.Field], frame: UIImage? = nil) {
        let paths: [String: WritableKeyPath<Transformer, String>] = ["kva": \.kva, "voltage": \.voltage, "vectorGroup": \.vectorGroup,
                                                                     "impedance": \.impedance, "year": \.year]
        edit(i) { t in for f in fields { if let kp = paths[f.key] { t[keyPath: kp] = f.value } } }
        for f in fields { job.values.markSource("tr\(i)_\(f.key)", .nameplate) }
        if let frame, job.values.photo("tr\(i)_plate") == nil, let p = model.addPhoto(frame, to: job.id) {
            job.values["tr\(i)_plate"] = .photo(p)
        }
    }

    /// Values the transformer's nameplate photo shows that its fields don't have yet.
    @ViewBuilder func platePhotoSuggestion(_ i: Int) -> some View {
        if let photo = job.values.photo("tr\(i)_plate"), let t = trafos[safe: i] {
            PlatePhotoSuggestion(photo: photo, jobID: job.id,
                                 current: ["kva": t.kva, "voltage": t.voltage, "vectorGroup": t.vectorGroup, "impedance": t.impedance, "year": t.year]) {
                applyPlate(i, $0)
            }
        }
    }

    func foldedTransformer(_ i: Int) -> some View {
        let n = photoCount(i)
        return A3Panel {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    A3Badge(text: "TX \(i + 1)")
                    Text("หม้อแปลง TX \(i + 1)").font(.system(size: 16, weight: .bold)).lineLimit(1)
                    if !narrow { kvaField(i).frame(width: 150) }
                    Spacer(minLength: 0)
                    a3Chip(n == 6 ? "6/6 ✓" : "\(n)/6", ok: n == 6)
                }
                if narrow { kvaField(i) }
                HStack(spacing: 5) {
                    ForEach(Array(Schema.transformerAngles.enumerated()), id: \.offset) { _, a in
                        let has = job.values.photo("tr\(i)_\(a.key)") != nil
                        RoundedRectangle(cornerRadius: 4)
                            .fill(has ? Theme.mint.opacity(0.55) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(has ? Theme.teal : Theme.danger, style: StrokeStyle(lineWidth: 1, dash: has ? [] : [3, 2])))
                            .frame(height: 22)
                    }
                }
            }
            .padding(.top, -2)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { open = i } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("แตะเพื่อกางมาแก้")
    }

    func openTransformer(_ i: Int) -> some View {
        let n = photoCount(i)
        return A3Panel(accent: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "TX \(i + 1)")
                    Text("หม้อแปลง TX \(i + 1)").font(.system(size: 18, weight: .bold))
                    Spacer(minLength: 0)
                    a3Chip("ภาพ \(n)/6", ok: n == 6)
                    Button { confirmRemove = i } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 44, height: 44)
                            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).accessibilityLabel("ลบหม้อแปลง TX \(i + 1)")
                }
                rowStack {
                    VStack(alignment: .leading, spacing: 3) { A3Label(text: "ขนาด", required: true); kvaField(i) }.frame(width: narrow ? nil : 190)
                    A3Segments(options: ["oil", "dry"], titles: ["Oil immersed", "Dry type"], selected: trafos[safe: i]?.type ?? "") { v in edit(i) { $0.type = v } }
                }
                platePhotoSuggestion(i)
                inputRow {
                    A3Input(label: "แรงดัน", text: plateText(i, \.voltage, key: "voltage"), required: true, unit: "V",
                            source: job.values.source("tr\(i)_voltage"))
                    A3Input(label: "Vector group", text: plateText(i, \.vectorGroup, key: "vectorGroup"), required: true,
                            source: job.values.source("tr\(i)_vectorGroup"))
                    A3Input(label: "%Z", text: plateText(i, \.impedance, key: "impedance"), required: true, unit: "%", keyboard: .decimalPad,
                            source: job.values.source("tr\(i)_impedance"))
                }
                inputRow {
                    A3Input(label: "ยี่ห้อ", text: tText(i, \.brand))
                    A3Input(label: "Serial no.", text: tText(i, \.serial))
                    A3Input(label: "ปีผลิต", text: plateText(i, \.year, key: "year", number: true), keyboard: .numberPad,
                            source: job.values.source("tr\(i)_year"))
                }
                rowStack {
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "อุปกรณ์ตัดตอนแรงสูง", required: true)
                        A3Segments(options: ["DO fuse", "DS", "VCB"], selected: trafos[safe: i]?.hvProtection ?? "") { v in edit(i) { $0.hvProtection = v } }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "กับดักฟ้าผ่า (LA)")
                        A3Segments(options: ["มี", "ไม่มี"], selected: trafos[safe: i]?.hasLA.map { $0 ? "มี" : "ไม่มี" } ?? "") { v in
                            edit(i) { $0.hasLA = v.isEmpty ? nil : v == "มี" }
                        }
                    }
                    .frame(width: narrow ? nil : 150)
                }
                rowStack {
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "สภาพ", required: true)
                        A3Segments(options: ["ดี", "พอใช้", "ชำรุด"], selected: trafos[safe: i]?.condition ?? "") { v in edit(i) { $0.condition = v } }
                    }
                    A3Input(label: "หมายเหตุสภาพ", text: tText(i, \.conditionNote))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(Schema.transformerAngles.enumerated()), id: \.offset) { n, a in
                        A3PhotoTile(photo: photoBinding("tr\(i)_\(a.key)"), jobID: job.id, label: "\(n + 1). \(Self.shortAngles[n])",
                                    required: a.key == "wide" && photoCount(i) > 0 && job.values.photo("tr\(i)_wide") == nil, height: 100)
                            .photoShot("tr\(i)_\(a.key)")
                    }
                }
            }
        }
    }
}

// MARK: boards

extension ElectricalPageWide {
    /// "125A×4, 63A×2" from the breakers' sizes.
    func sizeSummary(_ bs: [Breaker]) -> String {
        var order: [String] = [], counts: [String: Int] = [:]
        for b in bs where !b.at.isEmpty {
            if counts[b.at] == nil { order.append(b.at) }
            counts[b.at, default: 0] += max(b.count, 1)
        }
        return order.prefix(2).map { "\($0)A×\(counts[$0] ?? 0)" }.joined(separator: ", ")
    }
    func breakerTotal(_ bs: [Breaker]) -> Int { bs.reduce(0) { $0 + max($1.count, 1) } }

    func mainName(_ i: Int) -> Binding<String> {
        Binding(get: { job.values.text("tr\(i)_feed") }, set: { v in
            let before = job
            job.values["tr\(i)_feed"] = v.isEmpty ? nil : .text(v)
            SiteSync.pull(&job, since: before)
        })
    }
    func boardName(_ i: Int, _ k: Int) -> String {
        if k == 0 { let n = job.values.text("tr\(i)_feed"); return n.isEmpty ? "ตู้หลัก" : n }
        let n = boards(i)[safe: k]?.name ?? ""
        return n.isEmpty ? "SDB \(k)" : n
    }

    func boardsRow(_ i: Int) -> some View {
        let bs = boards(i), isOpen = i == openIndex
        return HStack(alignment: .top, spacing: Self.boardGap) {
            ForEach(Array(bs.enumerated()), id: \.element.id) { k, b in
                if isOpen {
                    (k == 0 ? AnyView(mainBoardCard(i)) : AnyView(subBoardCard(i, k)))
                        .frame(width: k == 0 ? Self.mainW : Self.subW, height: Self.expandedH)
                } else {
                    miniBoardCard(i, k, b).frame(width: Self.miniW, height: Self.collapsedH)
                }
            }
            Group {
                if bs.count < Transformer.maxBoards {
                    Button { editBoards(i) { $0.append(Board(name: "SDB \($0.count)")) }; withAnimation { open = i } } label: {
                        Text("+ เพิ่มตู้").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                            .frame(width: Self.addW, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, isOpen ? 4 : 20)
        }
    }

    func miniBoardCard(_ i: Int, _ k: Int, _ b: Board) -> some View {
        A3Panel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(boardName(i, k)).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("ปลายสาย").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 6).frame(minHeight: 20).background(Theme.mint.opacity(0.4), in: Capsule())
                }
                HStack(spacing: 6) {
                    Text(b.at.isEmpty ? "—" : b.at).font(.system(size: 16, weight: .bold))
                    Text("AT").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 0)
                }
                Text("CB ย่อย \(breakerTotal(b.breakers))" + (sizeSummary(b.breakers).isEmpty ? "" : " · " + sizeSummary(b.breakers)))
                    .font(.system(size: 11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { open = i } }
        .accessibilityAddTraits(.isButton)
    }

    // main board (k = 0)

    func mainBoardCard(_ i: Int) -> some View {
        let b = boards(i)[0]
        let shots = Self.mainPhotoSlots
        let have = shots.filter { job.values.photo("tr\(i)_\($0.key)") != nil }.count
        return A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "MDB")
                    HStack(spacing: 6) {
                        TextField("MDP-1", text: mainName(i)).font(.system(size: 18, weight: .bold))
                        if a2Badges.contains(.boardName(i, 0)) { A2Badge() }
                    }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.3)))
                    Text("ตู้หลัก · ปลายสาย").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 10).frame(minHeight: 26).background(Theme.mint.opacity(0.4), in: Capsule())
                }
                (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "เมนเบรกเกอร์ (Main CB)", required: true)
                            A3Segments(options: ["ACB", "MCCB"], selected: b.mainType) { v in editBoards(i) { $0[0].mainType = v } }
                        }
                        HStack(spacing: 8) {
                            A3Input(label: "AT (ตั้งตัด)", text: bText(i, 0, \.at, number: true), required: true, unit: "A", keyboard: .numberPad,
                                    a2: a2Badges.contains(.boardAT(i, 0)))
                            A3Input(label: "AF (เฟรม)", text: bText(i, 0, \.af, number: true), required: true, unit: "A", keyboard: .numberPad)
                        }
                        HStack(alignment: .bottom, spacing: 8) {
                            A3Input(label: "Icu", text: bText(i, 0, \.icu, number: true), required: true, unit: "kA", keyboard: .decimalPad)
                            VStack(alignment: .leading, spacing: 3) {
                                A3Label(text: "จำนวนขั้ว", required: true)
                                A3Segments(options: ["3P", "4P"], selected: b.poles) { v in editBoards(i) { $0[0].poles = v } }
                            }
                        }
                        A3Input(label: "ยี่ห้อ / รุ่น", text: bText(i, 0, \.brand))
                        breakerList(i, 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            A3Label(text: "ภาพตู้หลัก", required: true)
                            Spacer(minLength: 0)
                            a3Chip("\(have)/4", ok: have == 4)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(Array(shots.enumerated()), id: \.offset) { n, s in
                                A3PhotoTile(photo: photoBinding("tr\(i)_\(s.key)"), jobID: job.id, label: "\(n + 1). \(s.label)", required: s.key == "mdbSpace", height: 104)
                                    .photoShot("tr\(i)_\(s.key)")
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "สภาพอุปกรณ์", required: true)
                            A3Segments(options: ["ดี", "พอใช้", "ชำรุด"], selected: b.condition) { v in editBoards(i) { $0[0].condition = v } }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "หมายเหตุสภาพ")
                            TextField("", text: bText(i, 0, \.conditionNote), axis: .vertical).lineLimit(2...3)
                                .inputBox(minHeight: 66, trailing: 10)
                        }
                        A3Input(label: "ตำแหน่งตู้", text: vText("tr\(i)_feedLoc"))
                    }
                    .frame(width: narrow ? nil : 258)
                }
            }
        }
    }

    /// Outgoing breakers of the main board: one row each, tap to edit.
    func breakerList(_ i: Int, _ k: Int) -> some View {
        let list = boards(i)[safe: k]?.breakers ?? []
        return VStack(alignment: .leading, spacing: 6) {
            A3Label(text: "CB ลูกย่อย · แตะแถวเพื่อแก้")
            let rows = VStack(spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, br in
                    Button { editBreaker = BreakerEdit(id: br.id, trafo: i, board: k) } label: { breakerRow(n + 1, br) }.buttonStyle(.plain)
                }
            }
            // iPhone: the page scrolls, so the list takes its own height
            if narrow { rows } else { ScrollView { rows }.scrollIndicators(.hidden) }
            Button {
                let br = Breaker()
                editBoards(i) { $0[k].breakers.append(br) }
                editBreaker = BreakerEdit(id: br.id, trafo: i, board: k)
            } label: {
                Text("+ เพิ่ม CB ลูกย่อย").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    func breakerRow(_ n: Int, _ b: Breaker) -> some View {
        func v(_ s: String, _ unit: String) -> Text { s.isEmpty ? Text("?" + unit).foregroundColor(Theme.danger).bold() : Text(s + unit) }
        let unknown = b.at.isEmpty || b.af.isEmpty || b.ic.isEmpty || b.brand.isEmpty
        let line1 = Text(b.poles.isEmpty ? "" : "\(b.poles)P · ") + v(b.at, "AT") + Text("/") + v(b.af, "AF") + Text(" · ") + v(b.ic, "kA")
        let line2 = [b.brand.isEmpty ? "ยี่ห้อ ?" : b.brand, b.target.isEmpty ? nil : "→ " + b.target].compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 8) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).frame(width: 24, height: 24).background(Theme.primarySoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                line1.font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(line2).font(.system(size: 12)).foregroundStyle(b.brand.isEmpty ? Theme.danger : Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !b.condition.isEmpty { a3Chip(b.condition, ok: b.condition != "ชำรุด") }
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(unknown ? Theme.danger.opacity(0.7) : Theme.navy.opacity(0.2)))
        .contentShape(Rectangle())
    }

    // sub-board (k > 0)

    func subBoardCard(_ i: Int, _ k: Int) -> some View {
        let b = boards(i)[k]
        return A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    A3Badge(text: "SDB")
                    TextField("ชื่อตู้", text: bText(i, k, \.name)).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        .padding(.horizontal, 8).frame(minHeight: 44)
                    Button { editBoards(i) { if $0.indices.contains(k) { $0.remove(at: k) } } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("ลบตู้")
                }
                A3Input(label: "เมนเบรกเกอร์", text: bText(i, k, \.at, number: true), required: true, unit: "AT", keyboard: .numberPad)
                HStack {
                    A3Label(text: "CB ลูกย่อย")
                    Spacer(minLength: 0)
                    Text("รวม \(breakerTotal(b.breakers)) ลูก").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                }
                ForEach(b.breakers) { br in sizeRow(i, k, br) }
                Button { editBoards(i) { $0[k].breakers.append(Breaker()) } } label: {
                    Text("+ เพิ่มขนาด CB").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                A3Input(label: "ตำแหน่งตู้", text: bText(i, k, \.location))
                Spacer(minLength: 0)
                A3PhotoTile(photo: Binding(get: { boards(i)[safe: k]?.photos.first },
                                           set: { p in editBoards(i) { if $0.indices.contains(k) { $0[k].photos = p.map { [$0] } ?? [] } } }),
                            jobID: job.id, label: "ภาพตู้ (ไม่บังคับ)", height: 84)
            }
        }
    }

    /// "100 A × [− 2 +]": breakers of one size.
    func sizeRow(_ i: Int, _ k: Int, _ br: Breaker) -> some View {
        func set(_ body: @escaping (inout Breaker) -> Void) {
            editBoards(i) { b in if b.indices.contains(k), let n = b[k].breakers.firstIndex(where: { $0.id == br.id }) { body(&b[k].breakers[n]) } }
        }
        return HStack(spacing: 4) {
            TextField("", text: Binding(get: { br.at }, set: { v in set { $0.at = NumberInput.clean(v) } })).keyboardType(.numberPad)
                .frame(width: 44).multilineTextAlignment(.trailing)
            Text("A ×").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            stepper("minus") {
                editBoards(i) { b in
                    guard b.indices.contains(k), let n = b[k].breakers.firstIndex(where: { $0.id == br.id }) else { return }
                    if b[k].breakers[n].count <= 1 { b[k].breakers.remove(at: n) } else { b[k].breakers[n].count -= 1 }
                }
            }
            Text("\(max(br.count, 1))").font(.system(size: 15, weight: .bold)).frame(minWidth: 18)
            stepper("plus") { set { $0.count = max($0.count, 1) + 1 } }
        }
        .padding(.leading, 8).frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.3)))
    }

    func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary).frame(width: 34, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "เพิ่ม" : "ลด")
    }
}

// MARK: breaker sheet

/// Edit one outgoing breaker of the main board.
struct BreakerSheet: View {
    @Binding var breaker: Breaker
    let isMain: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// iPhone: delete and done in the bottom bar (docs/ui/components/iphone-bottom-bar, state 07).
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let phone = sizeClass == .compact
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        A3Input(label: "AT (ตั้งตัด)", text: Binding(get: { breaker.at }, set: { breaker.at = NumberInput.clean($0) }), unit: "A", keyboard: .numberPad)
                        A3Input(label: "AF (เฟรม)", text: Binding(get: { breaker.af }, set: { breaker.af = NumberInput.clean($0) }), unit: "A", keyboard: .numberPad)
                        A3Input(label: "IC", text: Binding(get: { breaker.ic }, set: { breaker.ic = NumberInput.clean($0) }), unit: "kA", keyboard: .decimalPad)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "จำนวนขั้ว")
                        A3Segments(options: ["2", "3", "4"], titles: ["2P", "3P", "4P"], selected: breaker.poles) { breaker.poles = $0 }
                    }
                    A3Input(label: "ยี่ห้อ / รุ่น", text: $breaker.brand)
                    A3Input(label: "ปลายทาง (ป้อนไปที่)", text: $breaker.target)
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "สภาพ")
                        A3Segments(options: ["ดี", "พอใช้", "ชำรุด"], selected: breaker.condition) { breaker.condition = $0 }
                    }
                    if !phone {
                        Button(role: .destructive, action: onDelete) {
                            Label("ลบ CB ลูกย่อยนี้", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered).padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if phone {
                    BottomBar(variant: .detail(destructive: .init(title: "ลบ CB ลูกย่อยนี้", action: onDelete),
                                               primary: .init(title: "เสร็จ") { dismiss() }))
                }
            }
            .navigationTitle("CB ลูกย่อย").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !phone { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } } }
        }
    }
}
#endif
