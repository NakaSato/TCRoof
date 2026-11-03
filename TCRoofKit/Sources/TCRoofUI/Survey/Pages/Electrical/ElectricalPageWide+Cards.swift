#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore

// MARK: - Meter & Transformers Extension

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

    // MARK: - Meter Card

    var meterCard: some View {
        A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "PEA")
                    Text("มิเตอร์ กฟภ.").font(.sarabunFixed(18, .bold))
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
                    Text(moreMeter ? "ซ่อนข้อมูลเพิ่มเติม ▴" : "แสดงข้อมูลเพิ่มเติม (4) ▾").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 44).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                if moreMeter {
                    A3Input(label: "เลขผู้ใช้ไฟ (CA)", text: vText("meterCA"), keyboard: .numbersAndPunctuation)
                    A3Input(label: "ประเภทผู้ใช้ไฟ / อัตรา", text: vText("meterRate"))
                    if narrow {
                        A3Input(label: "ขนาดมิเตอร์ / CT (A)", text: vText("meterCT"), keyboard: .numbersAndPunctuation)
                    } else {
                        meterSizeField
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "ภาพมิเตอร์")
                        A3PhotoTile(photo: photoBinding("meterPic"), jobID: job.id, label: "ภาพมิเตอร์", height: 80)
                            .photoShot("meterPic")
                    }
                } else if let s = meterSummary {
                    Text(s).font(.sarabunFixed(12)).foregroundStyle(Theme.success).lineLimit(2)
                }
            }
        }
    }

    /// "CA | อัตรา TOU | CT 400/5 | ภาพมิเตอร์ ครบแล้ว" — what the folded part holds.
    var meterSummary: String? {
        let v = job.values
        let parts = [v.text("meterCA").isEmpty ? nil : "CA", v.text("meterRate").isEmpty ? nil : "อัตรา " + v.text("meterRate"),
                     v.text("meterCT").isEmpty ? nil : (A3Options.meterSizes.contains(v.text("meterCT")) ? "มิเตอร์ " : "CT ") + v.text("meterCT"),
                     v.photo("meterPic") == nil ? nil : "ภาพมิเตอร์"].compactMap { $0 }
        return parts.isEmpty ? nil : "✓ " + parts.joined(separator: " | ") + " ครบแล้ว"
    }

    // MARK: - Transformers

    static let kvaSizes = ["50", "100", "160", "250", "315", "400", "500", "630", "800", "1000", "1250", "1500", "2000", "2500"]
    static let shortAngles = ["หน้า", "หลัง", "ซ้าย", "ขวา", "ป้ายพิกัด", "มุมกว้าง"]

    func photoCount(_ i: Int) -> Int { Schema.transformerAngles.filter { job.values.photo("tr\(i)_\($0.key)") != nil }.count }

    @ViewBuilder func transformerView(_ i: Int) -> some View {
        if i == openIndex { openTransformer(i) } else { foldedTransformer(i) }
    }

    func kvaField(_ i: Int) -> some View {
        HStack(spacing: 0) {
            TextField("", text: kvaText(i)).keyboardType(.numberPad)
                .font(.sarabunFixed(17, .semibold))
            Text("kVA").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            if a2Badges.contains(.kva(i)) { A2Badge().padding(.leading, 4) }
            SourceChip(source: job.values.source("tr\(i)_kva")).padding(.leading, 4)
            NameplateScanButton(kind: .transformer, compact: true) { fields, image in applyPlate(i, fields, frame: image) }
            kvaPicker(i)
        }
        .padding(.leading, 12).frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
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
                    Text("หม้อแปลง TX \(i + 1)").font(.sarabunFixed(16, .bold)).lineLimit(1)
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

    func typeSegments(_ i: Int) -> some View {
        A3Segments(options: ["oil", "dry"], titles: ["Oil immersed", "Dry type"], selected: trafos[safe: i]?.type ?? "") { v in edit(i) { $0.type = v } }
    }

    func openTransformer(_ i: Int) -> some View {
        let n = photoCount(i)
        return A3Panel(accent: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "TX \(i + 1)")
                    Text("หม้อแปลง TX \(i + 1)").font(.sarabunFixed(18, .bold))
                    Spacer(minLength: 0)
                    a3Chip("ภาพ \(n)/6", ok: n == 6)
                    Button { confirmRemove = i } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 44, height: 44)
                            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).accessibilityLabel("ลบหม้อแปลง TX \(i + 1)")
                }
                if narrow {
                    rowStack {
                        VStack(alignment: .leading, spacing: 3) { A3Label(text: "ขนาด", required: true); kvaField(i) }
                        typeSegments(i)
                    }
                } else {
                    // iPad: the size's hint shares the label line, so the card keeps its height
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) { A3Label(text: "ขนาด", required: true); sizeHint(i) }
                        HStack(spacing: 8) { kvaField(i).frame(width: 190); typeSegments(i) }
                    }
                }
                platePhotoSuggestion(i)
                nameplateRows(i)
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
#endif
