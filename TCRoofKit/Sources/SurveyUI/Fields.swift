#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// One question of the form, drawn from its schema entry.
struct FieldView: View {
    let spec: FieldSpec
    @Binding var values: Values
    let jobID: UUID
    var moduleType: ModuleType? = nil
    /// The job's GPS, for fields that can be filled from a satellite map.
    var gps: String = ""
    static let mapFields: Set<String> = ["siteMap", "roofPhoto", "aerialPhoto"]

    var body: some View {
        switch spec.kind {
        case .note(let text):
            Text(text).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.dangerText).padding(.horizontal, 14).padding(.vertical, 8)
        case .plan(let tank):
            PlanPreview(values: values, tank: tank)
        case .diagram:
            VStack(alignment: .leading, spacing: 6) {
                Text(spec.label).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                SketchView(sketch: Drawings.truss()).frame(maxWidth: 420)
            }
            .padding(14)
        default:
            row
        }
    }

    @ViewBuilder var row: some View {
        let filled = spec.isFilled(values)
        VStack(alignment: .leading, spacing: 8) {
            if !spec.label.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(spec.label).font(.sarabun(16, .medium, relativeTo: .callout)).foregroundStyle(Paper.ink)
                    if !spec.optional && spec.countable {
                        Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(filled ? Paper.tick : Theme.pending)
                    } else if spec.optional {
                        Text("ไม่บังคับ").font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted)
                    }
                    SourceChip(source: values.source(spec.id))
                }
            }
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    @ViewBuilder var control: some View {
        switch spec.kind {
        case .text(let ph):
            if spec.id == "date" {
                DateInput(text: textBinding)
            } else if spec.id == "gps" {
                GPSInput(text: textBinding)
            } else {
                HStack(spacing: 6) {
                    TextField(ph.isEmpty ? spec.label : ph, text: textBinding)
                        .textFieldStyle(OutlinedFieldStyle()).foregroundStyle(Paper.value)
                        .keyboardType(spec.id == "phone" ? .phonePad : .default)
                    if spec.id == "meterNo" {
                        NameplateScanButton(target: .meterNumber, apply: { values.set(spec.id, .text($0), source: .nameplate) }, compact: true)
                    }
                }
            }
        case .member(let component):
            MemberPicker(value: textBinding, component: component)
        case .pick(let list, let unit):
            HStack(spacing: 8) {
                Menu {
                    ForEach(list.groups, id: \.group) { g in
                        if list.groups.count == 1 { ForEach(g.items, id: \.self) { x in Button(x) { values[spec.id] = .text(x) } } }
                        else { Menu(g.group) { ForEach(g.items, id: \.self) { x in Button(x) { values[spec.id] = .text(x) } } } }
                    }
                    Divider()
                    Button("ล้างค่า") { values[spec.id] = nil }
                } label: {
                    HStack(spacing: 6) {
                        Text(values.text(spec.id).isEmpty ? "เลือก" : values.text(spec.id))
                            .foregroundStyle(values.text(spec.id).isEmpty ? Theme.inkMuted : Paper.value).font(.sarabun(16, .semibold, relativeTo: .callout))
                        Image(systemName: "chevron.up.chevron.down").font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                }
                TextField("หรือพิมพ์เอง", text: textBinding).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(maxWidth: 200)
                Text(unit).foregroundStyle(Theme.inkMuted)
            }
        case .number(let unit):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("0", text: numberBinding).keyboardType(.decimalPad).textFieldStyle(OutlinedFieldStyle(dense: true))
                        .foregroundStyle(Paper.value).frame(maxWidth: 200)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(badNumber ? Theme.danger : Color.clear, lineWidth: 1.5))
                    Text(unit).foregroundStyle(Theme.inkMuted)
                    if spec.id == "roofAngle" {
                        RoofSensorButton(reading: .pitch) { v, _ in values.set(spec.id, .text(v), source: .sensor) }
                    }
                }
                if badNumber {
                    HStack(spacing: 8) {
                        Text("อ่านเป็นตัวเลขไม่ได้").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
                        if !cleanedNumber.isEmpty {
                            Button("แก้เป็น \(cleanedNumber)") { values[spec.id] = .text(cleanedNumber) }.font(.sarabun(12, relativeTo: .caption))
                        }
                    }
                }
            }
        case .textarea:
            TextField(spec.label, text: textBinding, axis: .vertical).lineLimit(3...8).textFieldStyle(OutlinedFieldStyle()).foregroundStyle(Paper.value)
        case .choice(let options, let other):
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(options, id: \.self) { o in
                        TCChoiceChip(o, selected: values.choice(spec.id) == o) { choose(o) }
                    }
                }
                if other && values.choice(spec.id) == "อื่นๆ" {
                    TextField("ระบุ", text: otherBinding).textFieldStyle(OutlinedFieldStyle()).frame(maxWidth: 360)
                }
                if spec.id == "facing" {
                    RoofSensorButton(reading: .facing) { c, o in values.set(spec.id, .choice(c, other: o), source: .sensor) }
                }
            }
        case .checks(let options):
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(options, id: \.self) { o in
                    TCChoiceChip(o, selected: values.multi(spec.id).contains(o)) { toggle(o) }
                }
            }
        case .photo:
            PhotoField(photo: photoBinding, jobID: jobID, label: spec.label,
                       height: spec.id == "siteMap" ? 380 : 220,
                       mapGPS: Self.mapFields.contains(spec.id) ? gps : nil)
                .frame(maxWidth: spec.id == "siteMap" ? .infinity : 520)
                .photoShot(spec.id)
        case .photos(let max):
            PhotosField(photos: photosBinding, jobID: jobID, max: max)
        case .signature:
            SignatureField(photo: photoBinding, jobID: jobID)
        case .obstacles:
            ObstaclesEditor(items: Binding(get: { values.obstacles(spec.id) }, set: { values[spec.id] = $0.isEmpty ? nil : .obstacles($0) }))
        case .marks(let photoField):
            SiteMarksEditor(marks: Binding(get: { values.marks(spec.id) }, set: { values[spec.id] = $0.isEmpty ? nil : .marks($0) }),
                            photo: values.photo(photoField), trafos: values.transformers("trafos"), jobID: jobID,
                            shapes: values.shapes(SiteShapes.key), metersAcross: values.number(SiteShapes.scaleKey))
        case .transformers:
            VStack(alignment: .leading, spacing: 14) {
                TransformersEditor(items: Binding(get: { values.transformers(spec.id) }, set: { new in
                    let old = values.transformers(spec.id)
                    if new.count < old.count, let i = old.firstIndex(where: { o in !new.contains { $0.id == o.id } }) { values.shiftTransformerAnswers(removed: i) }
                    values[spec.id] = new.isEmpty ? nil : .transformers(new)
                }))
                TransformerPhotosView(values: $values, jobID: jobID)
            }
        default:
            EmptyView()
        }
    }

    var textBinding: Binding<String> {
        Binding(get: { values.text(spec.id) }, set: { values[spec.id] = $0.isEmpty ? nil : .text($0) })
    }
    /// Number fields keep only the number: commas, units and Thai digits are cleaned as they are typed.
    var numberBinding: Binding<String> {
        Binding(get: { values.text(spec.id) }, set: {
            let c = NumberInput.clean($0)
            values[spec.id] = c.isEmpty ? nil : .text(c)
        })
    }
    /// A stored value that isn't a number (typed before clean-up existed, or imported).
    var badNumber: Bool { !NumberInput.isValid(values.text(spec.id)) }
    var cleanedNumber: String { NumberInput.clean(values.text(spec.id)) }
    var otherBinding: Binding<String> {
        Binding(get: { values.other(spec.id) }, set: { values[spec.id] = .choice("อื่นๆ", other: $0) })
    }
    var photoBinding: Binding<Photo?> {
        Binding(get: { values.photo(spec.id) }, set: { values[spec.id] = $0.map { .photo($0) } })
    }
    var photosBinding: Binding<[Photo]> {
        Binding(get: { values.photos(spec.id) }, set: { values[spec.id] = $0.isEmpty ? nil : .photos($0) })
    }
    func choose(_ o: String) {
        if values.choice(spec.id) == o { values[spec.id] = nil }
        else { values[spec.id] = .choice(o, other: o == "อื่นๆ" ? values.other(spec.id) : "") }
    }
    func toggle(_ o: String) {
        var a = values.multi(spec.id)
        if let i = a.firstIndex(of: o) { a.remove(at: i) } else { a.append(o) }
        values[spec.id] = a.isEmpty ? nil : .multi(a)
    }
}

/// Auto-drawn plan from the spans entered in the same section.
struct PlanPreview: View {
    let values: Values
    let tank: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("แปลน (วาดอัตโนมัติจากระยะช่วงเสาและสิ่งกีดขวาง)").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                Spacer()
                if values.photo("planPhoto") != nil { Text("ใช้แบบร่างที่แนบแทน").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.pending) }
            }
            if let sk = Drawings.plan(values, tank: tank) {
                SketchView(sketch: sk).frame(maxWidth: .infinity).padding(8)
                    .background(Theme.paper).overlay(Rectangle().stroke(Theme.borderControl))
            } else {
                Text("— กรอกระยะช่วงเสาแนวนอนและแนวตั้ง เช่น 1.5,4,4,1.5 —").font(.sarabun(16, relativeTo: .callout)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 90).background(Theme.paper).overlay(Rectangle().stroke(Theme.borderControl))
            }
        }
        .padding(14)
    }
}

struct ObstaclesEditor: View {
    @Binding var items: [Obstacle]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                // Scrolls sideways when the five columns don't fit (iPhone).
                ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("ชื่อ").gridColumnAlignment(.leading)
                        Text("X (ม.)"); Text("Y (ม.)"); Text("กว้าง"); Text("ยาว"); Text("")
                    }
                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    ForEach(items) { o in
                        GridRow {
                            TextField("เช่น ช่องเซอร์วิส", text: bind(o.id, \.label)).frame(minWidth: 160)
                            TextField("0", text: bind(o.id, \.x)).keyboardType(.decimalPad).frame(width: 70)
                            TextField("0", text: bind(o.id, \.y)).keyboardType(.decimalPad).frame(width: 70)
                            TextField("0", text: bind(o.id, \.w)).keyboardType(.decimalPad).frame(width: 70)
                            TextField("0", text: bind(o.id, \.h)).keyboardType(.decimalPad).frame(width: 70)
                            Button(role: .destructive) { items.removeAll { $0.id == o.id } } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless)
                        }
                        .textFieldStyle(OutlinedFieldStyle())
                    }
                }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            Button { items.append(Obstacle()) } label: { Label("เพิ่มสิ่งกีดขวาง", systemImage: "plus") }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
    }
    func bind(_ id: UUID, _ kp: WritableKeyPath<Obstacle, String>) -> Binding<String> {
        Binding(get: { items.first { $0.id == id }?[keyPath: kp] ?? "" },
                set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i][keyPath: kp] = kp == \Obstacle.label ? v : NumberInput.clean(v) } })
    }
}

struct TransformersEditor: View {
    @Binding var items: [Transformer]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("หม้อแปลง TR\((items.firstIndex { $0.id == t.id } ?? 0) + 1)").font(.sarabun(16, .semibold, relativeTo: .callout))
                        TextField("kVA", text: kva(t.id)).keyboardType(.numberPad).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 110)
                        Text("kVA").foregroundStyle(Theme.inkMuted)
                        Spacer()
                        Button(role: .destructive) { items.removeAll { $0.id == t.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<6, id: \.self) { k in
                            VStack(spacing: 2) {
                                Text("MDB\(k + 1)").font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted)
                                TextField("A", text: mdb(t.id, k)).keyboardType(.numberPad).font(.sarabun(16, relativeTo: .callout).monospacedDigit()).textFieldStyle(OutlinedFieldStyle(dense: true)).multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .padding(10).background(Paper.band.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            if items.count < 5 {
                Button { items.append(Transformer()) } label: { Label("เพิ่มหม้อแปลง", systemImage: "plus") }.buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
        }
    }
    func kva(_ id: UUID) -> Binding<String> {
        Binding(get: { items.first { $0.id == id }?.kva ?? "" },
                set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i].kva = NumberInput.clean(v) } })
    }
    func mdb(_ id: UUID, _ k: Int) -> Binding<String> {
        Binding(get: {
            guard let t = items.first(where: { $0.id == id }), t.mdb.indices.contains(k) else { return "" }
            return t.mdb[k]
        }, set: { v in
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            while items[i].mdb.count <= k { items[i].mdb.append("") }
            items[i].mdb[k] = NumberInput.clean(v)
        })
    }
}
#endif
