#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// B4 on iPad landscape (docs/ui/survey-b4): the level (and the pole for HV), four photos and the details on the left;
/// the zero-export part of the single line diagram, the กันย้อน symbol on the A2 picture and what to install on the
/// right. `level` is the same answer the SLD page and B2's card toggle; the photos follow `ZeroExport.photoKeys`.
/// iPad portrait and iPhone get the same cards in one scrolling column (`stacked`).
struct BackfeedPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    var openSite: () -> Void = {}
    var openDiagram: () -> Void = {}
    /// One scrolling column (iPad portrait, iPhone).
    var stacked = false
    @Environment(SurveyModel.self) var model

    /// iPhone width: card titles put their sub line underneath and the SLD crop scrolls sideways.
    var phone: Bool { width < 500 }

    var leftWidth: CGFloat { min(560, max(420, width * 0.42)) }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func set(_ id: String, _ v: FieldValue?) {
        guard let i = index else { return }
        let before = job
        job.modules[i].values[id] = v
        // the A2 กันย้อน symbol shows the level as MV / LV
        if id == ZeroExport.levelKey { SiteSync.pull(&job, since: before) }
    }

    var hv: Bool { ZeroExport.isHV(values) }
    var line: SingleLine { SingleLine.build(job) }

    static let tealSoft = Color(red: 0.910, green: 0.969, blue: 0.953)
    static let line = Color(red: 0.788, green: 0.827, blue: 0.875)
    static let tagGrey = Color(red: 0.902, green: 0.918, blue: 0.937)

    var body: some View {
        let sl = line
        return Group {
            if stacked { stackedColumn(sl) } else { sideBySide(sl) }
        }
        .foregroundStyle(Home.navy)
        #if DEBUG
        .task { openDebugState() }
        #endif
    }

    func stackedColumn(_ sl: SingleLine) -> some View {
        ScrollView { stackedCards(sl).padding(.vertical, 16) }
            .scrollDismissesKeyboard(.interactively)
    }

    func stackedCards(_ sl: SingleLine) -> some View {
        VStack(spacing: 14) {
            PageStepBar(job: job, here: .module(moduleID), title: "ตำแหน่งติดตั้งระบบกันย้อน")
            levelCard(sl)
            photosCard(sl)
            sldCard(sl).frame(height: phone ? nil : 392)
            siteCard(sl).frame(height: phone ? 300 : 360)
            equipmentCard(sl).fixedSize(horizontal: false, vertical: true)
            detailCard.frame(height: 180)
        }
    }

    func sideBySide(_ sl: SingleLine) -> some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: "ตำแหน่งติดตั้งระบบกันย้อน")
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    levelCard(sl)
                    photosCard(sl)
                    detailCard.frame(maxHeight: .infinity)
                }
                .frame(width: leftWidth).frame(maxHeight: .infinity)
                VStack(spacing: 14) {
                    sldCard(sl).frame(height: 392)
                    HStack(alignment: .top, spacing: 14) {
                        siteCard(sl).frame(maxWidth: .infinity, maxHeight: .infinity)
                        equipmentCard(sl).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Home.navy.opacity(0.16)))
            .shadow(color: Home.navy.opacity(0.06), radius: 3, y: 2)
    }

    func header<Trailing: View>(_ n: Int, _ title: String, required: Bool = false, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 14, weight: .heavy)).foregroundStyle(Home.primary)
                .frame(width: 28, height: 28).background(WaterPageWide.chipFill, in: RoundedRectangle(cornerRadius: 8))
            (Text(title) + (required ? Text(" *").foregroundColor(Home.danger) : Text(""))).font(.system(size: 17, weight: .bold)).lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
    }

    func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.7)
    }

    // MARK: 1 level

    func levelCard(_ sl: SingleLine) -> some View {
        let board = ZeroExport.boardName(sl), kv = ZeroExport.kv(job)
        return card {
            header(1, "ตำแหน่งกันย้อน", required: true) { hint("ใช้ค่าเดียวกับ B2 และ SLD") }
            HStack(spacing: 12) {
                levelChoice(ZeroExport.lv, tag: "LV · 400 V", title: "กันย้อนที่แรงต่ำ", sub: "CT ที่เมนตู้ \(board) (400 V)")
                levelChoice(ZeroExport.hv, tag: "HV · \(kv) kV", title: "กันย้อนที่แรงสูง", sub: "CT/VT หลังมิเตอร์ กฟภ. (\(kv) kV)")
            }
            if hv { poleRow }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func levelChoice(_ value: String, tag: String, title: String, sub: String) -> some View {
        let on = values.choice(ZeroExport.levelKey) == value
        return Button { set(ZeroExport.levelKey, .choice(value, other: "")) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tag).font(.system(size: 12, weight: .bold)).foregroundStyle(on ? .white : Home.muted)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(on ? Home.teal : Self.tagGrey, in: RoundedRectangle(cornerRadius: 5))
                Text(title).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                Text(sub).font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(2).minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(on ? Self.tealSoft : Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Home.teal : Self.line, lineWidth: on ? 2 : 1))
            .background(RoundedRectangle(cornerRadius: 16).stroke(on ? Home.teal.opacity(0.18) : .clear, lineWidth: 6).padding(-1))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Home.teal, in: Circle()).padding(10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " " + sub)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    var poleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text("เสา") + Text(" *").foregroundColor(Home.danger)).font(.system(size: 16, weight: .bold))
                Spacer(minLength: 8)
                hint("สำหรับติดตั้ง CT/VT แรงสูง")
            }
            HStack(spacing: 12) {
                ForEach(ZeroExport.poles, id: \.self) { p in
                    let on = values.choice(ZeroExport.poleKey) == p
                    Button { set(ZeroExport.poleKey, .choice(p, other: "")) } label: {
                        Text(p).font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.teal : Home.navy.opacity(0.5), lineWidth: on ? 1.5 : 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: 2 photos

    func photosCard(_ sl: SingleLine) -> some View {
        let n = ZeroExport.photoCount(values), missing = ZeroExport.missingPhotos(values), board = ZeroExport.boardName(sl)
        let keys = ZeroExport.photoKeys
        return card {
            header(2, "ภาพประกอบ", required: true) {
                Text(missing == 0 ? "\(n) ภาพ · ครบขั้นต่ำ \(ZeroExport.minPhotos) ภาพ ✓" : "\(n)/\(ZeroExport.minPhotos) ภาพ · ขาดอีก \(missing) ภาพ")
                    .font(.system(size: 13, weight: missing == 0 ? .semibold : .bold))
                    .foregroundStyle(missing == 0 ? Home.ok : Home.danger).lineLimit(1).minimumScaleFactor(0.7)
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    BackfeedPhotoTile(job: job, photo: values.photo(keys[0]), label: ZeroExport.photoLabel(0, hv: hv, board: board), set: { set(keys[0], $0) })
                    BackfeedPhotoTile(job: job, photo: values.photo(keys[1]), label: ZeroExport.photoLabel(1, hv: hv, board: board), set: { set(keys[1], $0) })
                }
                GridRow {
                    BackfeedPhotoTile(job: job, photo: values.photo(keys[2]), label: ZeroExport.photoLabel(2, hv: hv, board: board), set: { set(keys[2], $0) })
                    BackfeedPhotoTile(job: job, photo: values.photo(keys[3]), label: ZeroExport.photoLabel(3, hv: hv, board: board), set: { set(keys[3], $0) })
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 3 details

    var detailCard: some View {
        card {
            header(3, "รายละเอียดเพิ่มเติม") { hint("ไม่บังคับ") }
            TextEditor(text: Binding(get: { values.text("detail") }, set: { set("detail", $0.isEmpty ? nil : .text($0)) }))
                .font(.system(size: 16)).scrollContentBackground(.hidden).padding(8)
                .frame(minHeight: 60, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if values.text("detail").isEmpty {
                        Text(hv ? "เช่น ระยะจากมิเตอร์ถึงเสา · การขออนุญาต กฟภ." : "เช่น ตำแหน่ง CT · ช่องว่างในตู้สำหรับรีเลย์")
                            .font(.system(size: 16)).foregroundStyle(Home.muted.opacity(0.8))
                            .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
                .accessibilityLabel("รายละเอียดเพิ่มเติม")
        }
    }
}

/// One of B4's four photos: 128 high; filled shows the photo with its label pill, empty is a red dashed slot that opens
/// the photo library or the camera.
struct BackfeedPhotoTile: View {
    let job: Job
    let photo: Photo?
    let label: String
    let set: (FieldValue?) -> Void
    @Environment(SurveyModel.self) var model
    @State var choosing = false
    @State var showPicker = false
    @State var showCamera = false

    var body: some View {
        Group {
            if let p = photo { filled(p) } else { empty }
        }
        .frame(maxWidth: .infinity).frame(height: 128)
    }

    func pick(_ img: UIImage) { if let p = model.addPhoto(img, to: job.id) { set(.photo(p)) } }

    func filled(_ p: Photo) -> some View {
        PhotoSlot(photo: p, jobID: job.id, hint: label, required: true, title: label, dense: true, fill: true, onPick: pick, onClear: { set(nil) })
            .overlay(alignment: .bottomLeading) {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Home.navy).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8).allowsHitTesting(false)
            }
    }

    var empty: some View {
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) { choosing = true } else { showPicker = true }
        } label: {
            VStack(spacing: 6) {
                A2Icon(name: "ui-camera", fallback: "camera", size: 26).foregroundStyle(Home.primary)
                Text("ถ่ายภาพ / อัปโหลด").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.primary)
                Text(label).font(.system(size: 12)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.danger, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ถ่ายภาพหรืออัปโหลด " + label)
        .confirmationDialog(label, isPresented: $choosing) {
            Button("ถ่ายภาพ") { showCamera = true }
            Button("อัปโหลดจากคลังภาพ") { showPicker = true }
        }
        .photoSources(picker: $showPicker, camera: $showCamera, onPick: pick)
    }
}
#endif
