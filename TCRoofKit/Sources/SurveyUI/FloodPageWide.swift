#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore
import PDFReport

/// A4 on iPad (docs/ui/survey-a4): a live water-level cross-section, the equipment height check and flood photos on the left;
/// the flood questions, the GISTDA lookup and the note on the right. Landscape puts them side by side, portrait stacks them and scrolls.
/// Field ids are unchanged; the new answers are optional, so completion is too. iPhone keeps the schema form (`groupPage`).
struct FloodPageWide: View {
    @Binding var job: Job
    /// Width of the page's content.
    let width: CGFloat
    /// Portrait: one scrolling column.
    var stacked = false
    @Environment(SurveyModel.self) var model
    @State var fetching = false
    @State var failure: String?
    @State var attempt = 0
    @State var dragging = false
    @State var editHeights = false
    @State var pickPhoto: PhotosPickerItem?
    @State var showPicker = false
    @State var showCamera = false
    @State var viewing: Photo?

    var rightWidth: CGFloat { min(740, max(460, (width - 28) * 0.55)) }
    var values: Values { job.values }
    var state: FloodCheck.State { FloodCheck.state(values) }
    var check: FloodCheck.Result { job.floodCheck }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .flood)
            if stacked {
                ScrollView {
                    VStack(spacing: 20) { leftColumn; rightColumn }.padding(.bottom, 8)
                }
                .scrollIndicators(.hidden).frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 28) {
                    ScrollView { leftColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(maxWidth: .infinity)
                    ScrollView { rightColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(width: rightWidth)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(Home.navy)
        // the recommended install height is what the report summary quotes
        .onChange(of: check.minCm) { _, n in if state == .flooded { job.values["equipHeight"] = .text(String(n)) } }
        .photosPicker(isPresented: $showPicker, selection: $pickPhoto, matching: .images)
        .onChange(of: pickPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { addPhoto(img) }
                pickPhoto = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { img in if let img { addPhoto(img) } }.ignoresSafeArea() }
        .sheet(item: $viewing) { p in if let img = model.image(p, in: job.id) { PhotoViewer(image: img, title: "หลักฐานน้ำท่วม") } }
    }

    // MARK: bindings

    func text(_ id: String) -> Binding<String> {
        Binding(get: { job.values.text(id) }, set: { job.values[id] = .text($0) })
    }
    func choose(_ id: String, _ option: String) { job.values[id] = .choice(option, other: option == "อื่นๆ" ? job.values.other(id) : "") }

    // MARK: left column

    var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            A1Card(title: "ภาพตัดระดับน้ำ", trailing: "อัปเดตตามข้อมูลด้านขวา · ใช้ในรายงาน PDF", spacing: 10) {
                sectionDrawing
                checkTable
            }
            photosBlock
        }
    }

    var sectionDrawing: some View {
        let sketch = FloodSection.sketch(job), k = FloodSection.scale(job)
        let jobID = job.id
        return GeometryReader { geo in
            let s = geo.size.width / CGFloat(FloodSection.width)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.withCGContext { cg in
                        cg.scaleBy(x: s, y: s)
                        PDFRenderer.draw(sketch.ops, in: cg, photo: { model.image($0, in: jobID) })
                    }
                }
                .accessibilityElement().accessibilityLabel(FloodSection.accessibilityLabel(job))
                if state == .flooded {
                    let wy = (FloodSection.groundY - check.level * k) * s
                    Label("ลากเส้นน้ำเพื่อปรับระดับ", systemImage: "arrow.up.and.down")
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Home.primary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white).overlay(Rectangle().stroke(Home.primary))
                        .position(x: 375 * s, y: min(wy + 26 * s, (FloodSection.groundY - 14) * s))
                        .allowsHitTesting(false)
                }
                if state == .unknownEmpty { fetchOverlay }
                if state == .unknownFetched, let g = values.gistda {
                    Text(g.banner).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Home.pending)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white).overlay(RoundedRectangle(cornerRadius: 3).stroke(Home.orange))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { d in
                guard state == .flooded else { return }
                let wy = (FloodSection.groundY - check.level * k) * s
                if !dragging { guard abs(d.startLocation.y - wy) < 36 else { return }; dragging = true }
                let cm = FloodSection.cm(atY: d.location.y / s, scale: k)
                let stepped = Int((min(max(cm, 0), 300) / 10).rounded()) * 10
                if Double(stepped) != check.level { job.values["floodDepth"] = .text(String(stepped)) }
            }.onEnded { _ in dragging = false })
        }
        .aspectRatio(CGFloat(FloodSection.width / FloodSection.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var fetchOverlay: some View {
        VStack(spacing: 10) {
            Text("ยังไม่มีข้อมูลระดับน้ำ").font(.system(size: 15, weight: .bold))
            Text("ดึงประวัติน้ำท่วมจาก GISTDA ตามพิกัด A1").font(.system(size: 13)).foregroundStyle(Home.muted).multilineTextAlignment(.center)
            fetchButton
            if let failure { Text(failure).font(.system(size: 12.5)).foregroundStyle(Home.danger).multilineTextAlignment(.center); estimateButton }
        }
        .padding(.vertical, 14).padding(.horizontal, 16).frame(width: 320)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.borderControl))
        .shadow(color: Home.navy.opacity(0.12), radius: 6, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).offset(y: -12)
    }

    // MARK: equipment height check

    var checkTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("ตรวจความสูงอุปกรณ์").font(.system(size: 16, weight: .bold))
                Text(FloodCheck.requirement(values)).font(.system(size: 12.5)).foregroundStyle(Home.muted)
                Spacer()
                Button { editHeights = true } label: {
                    Label("ปรับความสูง", systemImage: "slider.horizontal.3").font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
                }
                .popover(isPresented: $editHeights) { heightEditor }
            }
            if check.rows.isEmpty {
                Text("ยังไม่มีหัวข้อ Inverter / SMDB / Emergency ในงานนี้").font(.system(size: 13)).foregroundStyle(Home.muted).padding(.vertical, 6)
            }
            ForEach(check.rows) { r in
                HStack(spacing: 6) {
                    Text(r.name).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(r.tag).font(.system(size: 12.5)).foregroundStyle(Home.muted)
                    Spacer(minLength: 6)
                    Text(r.height).font(.system(size: 14)).monospacedDigit().foregroundStyle(Home.navy)
                    pill(r.status).frame(width: 130, alignment: .trailing)
                }
                .frame(minHeight: 30)
                Divider()
            }
        }
    }

    func pill(_ s: FloodCheck.Status) -> some View {
        let c: (Color, Color) = s.tone == .good ? (Color(red: 0.886, green: 0.937, blue: 0.855), Color(red: 0.231, green: 0.455, blue: 0.125))
            : s.tone == .bad ? (Color(red: 0.992, green: 0.925, blue: 0.918), Color(red: 0.706, green: 0.137, blue: 0.094))
            : (Color(red: 1, green: 0.957, blue: 0.898), Home.pending)
        return Text(s.text).font(.system(size: 12.5, weight: .bold)).foregroundStyle(c.1).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2).background(c.0, in: RoundedRectangle(cornerRadius: 6))
    }

    var heightEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ความสูงอุปกรณ์ (ซม.)").font(.headline)
            heightField("พื้นห้อง Inverter จากพื้นดิน", "invFloorCm", placeholder: Int(FloodCheck.defaultFloorCm))
            heightField("ติดตั้ง Inverter / SMDB สูงจากพื้นห้อง", "invMountCm", placeholder: Int(FloodCheck.defaultMountCm))
            heightField("ปุ่ม Emergency จากพื้นดิน", "emgMountCm", placeholder: Int(FloodCheck.defaultEmergencyCm))
            Text("เว้นว่างเพื่อใช้ค่าเริ่มต้น").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 360)
    }
    func heightField(_ label: String, _ id: String, placeholder: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 14)).foregroundStyle(Home.muted)
            TextField(String(placeholder), text: text(id)).keyboardType(.decimalPad).inputBox()
        }
    }

    // MARK: photos

    var photos: [Photo] { ([values.photo("floodPhoto")] + values.photos("floodPhotos").map { Optional($0) }).compactMap { $0 } }

    func setPhotos(_ list: [Photo]) {
        job.values["floodPhoto"] = list.first.map { .photo($0) }
        job.values["floodPhotos"] = list.count > 1 ? .photos(Array(list.dropFirst())) : nil
    }
    func addPhoto(_ img: UIImage) { if let p = model.addPhoto(img, to: job.id) { setPhotos(photos + [p]) } }

    var photosBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ภาพคราบระดับน้ำ / หลักฐานน้ำท่วม").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("ไม่บังคับ · แนะนำถ่ายคู่ตลับเมตร").font(.footnote).foregroundStyle(Home.muted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photos) { p in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let img = model.image(p, in: job.id) { Image(uiImage: img).resizable().scaledToFill() }
                                else { Color(uiColor: .tertiarySystemFill).overlay(Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary)) }
                            }
                            .frame(width: 92, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { viewing = p }
                            Button { setPhotos(photos.filter { $0.id != p.id }) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(Color.black.opacity(0.6), in: Circle())
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .offset(x: 12, y: -12).accessibilityLabel("ลบภาพ")
                        }
                    }
                    photoButton("อัปโหลด", "photo.on.rectangle") { showPicker = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { photoButton("กล้อง", "camera") { showCamera = true } }
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
    func photoButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 96, minHeight: 60).padding(.horizontal, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    // MARK: right column

    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            label("พื้นที่เคยมีน้ำท่วมหรือไม่", required: true)
            choiceRow(Schema.flood.fields[0].choiceOptions, id: "floodHistory")
            switch state {
            case .flooded: floodedForm
            case .unknownEmpty, .unknownFetched: gistdaCard
            case .never: neverNote
            }
            VStack(alignment: .leading, spacing: 6) {
                label("หมายเหตุ")
                TextEditor(text: text("floodNote"))
                    .font(.system(size: 17)).scrollContentBackground(.hidden).padding(8)
                    .frame(minHeight: 140).frame(maxHeight: stacked ? 200 : .infinity)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
            }
            .frame(maxHeight: stacked ? nil : .infinity)
        }
    }

    func label(_ t: String, required: Bool = false, aside: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(t) + (required ? Text(" *").foregroundColor(Home.danger) : Text(""))).font(.system(size: 17, weight: .bold))
            Spacer(minLength: 8)
            if let aside { Text(aside).font(.footnote).foregroundStyle(Home.muted) }
        }
    }

    /// Large choice buttons in a row; wraps to more rows when there are more than `perRow`.
    func choiceRow(_ options: [String], id: String, perRow: Int = 3, height: CGFloat = 52) -> some View {
        let rows = stride(from: 0, to: options.count, by: perRow).map { Array(options[$0..<min($0 + perRow, options.count)]) }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { o in choiceButton(o, id: id, height: height) }
                    if row.count < perRow { ForEach(0..<(perRow - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 1) } }
                }
            }
        }
    }
    func choiceButton(_ o: String, id: String, height: CGFloat) -> some View {
        let on = values.choice(id) == o
        return Button { choose(id, o) } label: {
            Text(o).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.teal : Home.navy.opacity(0.5), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    func numberBox(_ title: String, id: String, unit: String, required: Bool = false, keyboard: UIKeyboardType = .numberPad) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title, required: required)
            HStack(spacing: 6) {
                TextField("", text: text(id)).keyboardType(keyboard).font(.system(size: 20, weight: .bold))
                if !unit.isEmpty { Text(unit).font(.system(size: 15)).foregroundStyle(Home.muted) }
            }
            .inputBox(minHeight: 52)
        }
    }

    var floodedForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            RatioRow(weights: [1, 1, 1]) {
                numberBox("ปีล่าสุด (พ.ศ.)", id: "floodYear", unit: "", required: true)
                numberBox("ระดับน้ำสูงสุด", id: "floodDepth", unit: "ซม.", required: true, keyboard: .decimalPad)
                numberBox("ท่วมขัง", id: "floodDays", unit: "วัน")
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) { label("วัดความสูงจาก", required: true); choiceRow(Schema.floodRefs, id: "floodRef", height: 44) }
                VStack(alignment: .leading, spacing: 6) {
                    label("ที่มาข้อมูล", required: true)
                    choiceRow(Schema.floodInfoSources, id: "floodInfoSource", height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 6) { label("ความถี่"); choiceRow(["ทุกปี", "2–5 ปีครั้ง", "นานกว่า 5 ปี"], id: "floodFreq") }
            VStack(alignment: .leading, spacing: 6) {
                label("สาเหตุ", aside: "เลือกได้ 1")
                choiceRow(Schema.floodSources, id: "floodSource", height: 48)
                if values.choice("floodSource") == "อื่นๆ" {
                    TextField("ระบุสาเหตุ", text: Binding(get: { values.other("floodSource") },
                                                         set: { job.values["floodSource"] = .choice("อื่นๆ", other: $0) })).inputBox()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                label("จุดที่เคยได้รับผลกระทบ", aside: "แสดงบนภาพ A2")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3), alignment: .leading, spacing: 4) {
                    ForEach(Schema.floodHits, id: \.self) { h in hitBox(h) }
                }
            }
        }
    }
    func hitBox(_ h: String) -> some View {
        let on = values.multi("floodHit").contains(h)
        return Button {
            var a = values.multi("floodHit")
            if on { a.removeAll { $0 == h } } else { a.append(h) }
            job.values["floodHit"] = .multi(a)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(on ? Home.primary : Home.navy.opacity(0.5))
                Text(h).font(.system(size: 14)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    var neverNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("ไม่เคยท่วม · ข้ามรายละเอียดได้", systemImage: "checkmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Home.ok)
            Text("ระดับติดตั้งอุปกรณ์ใช้แค่ระยะเผื่อจากพื้น").font(.system(size: 14)).foregroundStyle(Home.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.886, green: 0.937, blue: 0.855).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.ok.opacity(0.4)))
    }

    // MARK: GISTDA

    var gistdaCard: some View {
        let gps = GPS.parse(values.text("gps"))
        return A1Card(title: "ข้อมูลน้ำท่วมจาก GISTDA", trailing: gps.map { "ตามพิกัด A1 · " + String(format: "%.4f, %.4f", $0.lat, $0.lon) } ?? "ยังไม่มีพิกัด A1", spacing: 10) {
            if let g = values.gistda {
                VStack(spacing: 0) {
                    ForEach(g.rows, id: \.label) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(r.label).font(.system(size: 14)).foregroundStyle(Home.muted).frame(width: 110, alignment: .leading)
                            Text(r.value).font(.system(size: 15, weight: .bold)).foregroundStyle(tone(r.tone)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                Text(g.footnote).font(.system(size: 12)).foregroundStyle(Home.muted)
                HStack { fetchButton(again: true); Spacer() }
            } else {
                Text("ยังไม่มีข้อมูลจากหน้างาน ดึงประวัติพื้นที่น้ำท่วมซ้ำซากจากภาพดาวเทียม GISTDA ได้ทันที").font(.system(size: 15)).foregroundStyle(Home.muted)
                fetchButton
            }
            if failure != nil { estimateButton }
            if let failure { Text(failure).font(.system(size: 14, weight: .semibold)).foregroundStyle(Home.danger) }
            else if gps == nil { Text("ใส่พิกัด GPS ในหน้า A1 ก่อน (เช่น 17.0062, 99.8235)").font(.system(size: 13)).foregroundStyle(Home.pending) }
            else if gistdaKey.isEmpty { Text(FloodLookup.Failure.noKey.message + " · ตั้งค่าได้ในหน้าตั้งค่า").font(.system(size: 13)).foregroundStyle(Home.pending) }
        }
    }
    func tone(_ t: FloodGistda.Tone) -> Color { t == .good ? Color(red: 0.231, green: 0.455, blue: 0.125) : t == .warn ? Home.pending : t == .bad ? Color(red: 0.706, green: 0.137, blue: 0.094) : Home.navy }

    var gistdaKey: String {
        let k = model.settings.gistdaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty ? FloodLookup.bundledKey : k
    }
    var fetchButton: some View { fetchButton(again: false) }
    func fetchButton(again: Bool) -> some View {
        let ready = GPS.parse(values.text("gps")) != nil
        return Button(action: fetchGistda) {
            HStack(spacing: 8) {
                if fetching { ProgressView().tint(.white) } else { Image(systemName: "arrow.down.circle") }
                Text(fetching ? (attempt > 1 ? "กำลังลองใหม่ครั้งที่ \(attempt)/3…" : "กำลังดึงข้อมูล… (อาจใช้เวลาถึง 1 นาที)") : again ? "ดึงข้อมูลใหม่" : failure != nil ? "ลองใหม่" : "ดึงข้อมูลจาก GISTDA")
            }
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(minHeight: 48)
            .background(ready && !fetching ? Home.primary : Home.disabledText, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!ready || fetching)
    }

    /// GISTDA is slow or down: carry on with the default estimate instead of waiting.
    var estimateButton: some View {
        Button { failure = nil; job.values.setGistda(.estimate()) } label: {
            Text("ใช้ค่าประเมิน \(FloodGistda.defaultDepthCm) ซม. ไปก่อน").font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.primary)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.primary))
        }
        .buttonStyle(.plain)
    }

    func fetchGistda() {
        failure = nil
        guard let p = GPS.parse(values.text("gps")) else { failure = FloodLookup.Failure.badCoordinates.message; return }
        let key = gistdaKey
        guard !key.isEmpty else { failure = FloodLookup.Failure.noKey.message; return }
        fetching = true
        Task { @MainActor in
            attempt = 1
            do { job.values.setGistda(try await FloodLookup(apiKey: key).fetch(lat: p.lat, lon: p.lon, progress: { n in Task { @MainActor in attempt = n } })) }
            catch let e as FloodLookup.Failure { failure = e.message }
            catch { failure = FloodLookup.Failure.badResponse.message }
            fetching = false
        }
    }
}

extension FieldSpec {
    /// The options of a choice field (empty for other kinds).
    var choiceOptions: [String] { if case .choice(let o, _) = kind { return o }; return [] }
}
#endif
