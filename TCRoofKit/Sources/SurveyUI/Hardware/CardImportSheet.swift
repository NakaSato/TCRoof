#if canImport(UIKit)
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import TCRoofCore
import TCRoofUI

/// นำเข้ารูปจากการ์ด / USB (docs/specs/hardware-assist-swift.md §H6): pick photos from an SD card reader, a drone's
/// USB connection or Files. Each is copied (the card keeps its originals), and offered where it fits (`CardImport`):
/// the highest as the A2 site picture, one taken next to a site symbol for that symbol's section, the rest in a tray
/// with every empty photo slot of the job.
struct CardImportSheet: View {
    @Binding var job: Job
    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var reading = false
    @State private var items: [Item] = []
    /// Shot id → where it went.
    @State private var placed: [UUID: String] = [:]
    @State private var replaceSite: Item?

    struct Item: Identifiable {
        let shot: CardImport.Shot
        let url: URL
        let thumb: UIImage?
        var id: UUID { shot.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty { empty } else { list }
            }
            .navigationTitle("นำเข้ารูปจากการ์ด / USB").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("เสร็จ") { dismiss() } }
                if !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) { Button { picking = true } label: { Label("เพิ่มรูป", systemImage: "plus") } }
                }
            }
            .overlay { if reading { ProgressView("กำลังอ่านรูป…").padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)) } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { load(urls) }
        }
        .confirmationDialog("แทนภาพสถานที่ติดตั้งเดิม?", isPresented: Binding(get: { replaceSite != nil }, set: { if !$0 { replaceSite = nil } }),
                            titleVisibility: .visible, presenting: replaceSite) { item in
            Button("ใช้ภาพนี้แทน") { useAsSite(item) }
        } message: { _ in Text("สัญลักษณ์และเส้นที่วาดไว้บน A2 จะอยู่ตำแหน่งเดิมบนภาพใหม่") }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "surveyCardImport") { return load(Self.demoFiles()) }
            #endif
            if items.isEmpty { picking = true }
        }
    }

    #if DEBUG
    /// `-surveyCardImport YES`: a drone shot 80 m up and two ground shots, as files with GPS EXIF.
    static func demoFiles() -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CardImportDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shots: [(String, UIColor, Double, String)] = [("DJI_0001", .systemGreen, 92, "FC3582"), ("IMG_2201", .systemOrange, 12, "iPhone 15 Pro"),
                                                         ("IMG_2202", .systemBlue, 11, "iPhone 15 Pro")]
        return shots.compactMap { name, color, alt, model in
            let img = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { c in color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 400, height: 300)) }
            guard let cg = img.cgImage else { return nil }
            let url = dir.appendingPathComponent(name + ".jpg")
            guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            let props: [CFString: Any] = [
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 17.0062, kCGImagePropertyGPSLatitudeRef: "N",
                                                kCGImagePropertyGPSLongitude: 99.8235, kCGImagePropertyGPSLongitudeRef: "E",
                                                kCGImagePropertyGPSAltitude: alt],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:07 10:4\(Int(alt) % 10):00"],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model]]
            CGImageDestinationAddImage(d, cg, props as CFDictionary)
            return CGImageDestinationFinalize(d) ? url : nil
        }
    }
    #endif

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "sdcard").font(.system(size: 44)).foregroundStyle(Theme.primary)
            Text("เสียบการ์ด SD หรือต่อโดรนผ่าน USB-C แล้วเลือกรูป").font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            Button { picking = true } label: { Text("เลือกรูป").bold().frame(minWidth: 160, minHeight: 44) }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
            Text("รูปถูกคัดลอกเข้างาน รูปต้นฉบับยังอยู่ในการ์ด").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
        .padding(24)
    }

    // MARK: list

    private var geo: SiteGeo? {
        MapImage.coordinate(from: job.values.text("gps")).flatMap { SiteGeo(values: job.values, lat: $0.latitude, lon: $0.longitude) }
    }

    private var list: some View {
        let open = items.filter { placed[$0.id] == nil }
        let aerial = CardImport.aerial(open.map(\.shot))
        let geo = geo, marks = job.values.marks("siteMarks")
        var near: [(mark: MapMark, items: [(Item, Double)])] = []
        var tray: [Item] = []
        for item in open where item.id != aerial?.id {
            if let geo, let hit = CardImport.nearest(item.shot, marks: marks, geo: geo), !job.photoTargets(for: hit.mark).isEmpty {
                if let k = near.firstIndex(where: { $0.mark.id == hit.mark.id }) { near[k].items.append((item, hit.meters)) }
                else { near.append((hit.mark, [(item, hit.meters)])) }
            } else { tray.append(item) }
        }
        let targets = job.emptyPhotoTargets
        return PadForm(maxWidth: 900) {
            if let aerial, let item = open.first(where: { $0.id == aerial.id }) {
                PadSection("ภาพมุมสูงจากโดรน") {
                    row(item) {
                        Button(job.values.photo("siteMap") == nil ? "ใช้เป็นภาพ A2" : "แทนภาพ A2") {
                            if job.values.photo("siteMap") == nil { useAsSite(item) } else { replaceSite = item }
                        }
                        .buttonStyle(TCButtonStyle(.primary, size: .card))
                    }
                } footer: {
                    Text(item.shot.altitude.map { "สูงจากระดับน้ำทะเล \(Int($0.rounded())) ม. ใช้เป็นภาพสถานที่ติดตั้งได้ (ต้องวัดมาตราส่วนในหน้า A2)" } ?? "")
                }
            }
            ForEach(near, id: \.mark.id) { group in
                let slots = job.photoTargets(for: group.mark)
                PadSection("ใกล้ \(markName(group.mark))") {
                    ForEach(group.items, id: \.0.id) { item, meters in
                        row(item, detail: "ห่าง \(Int(meters.rounded())) ม.") {
                            if let first = slots.first {
                                Button("ใส่ " + first.label) { place(item, first) }.buttonStyle(TCButtonStyle(.primary, size: .card))
                            }
                            slotMenu(item, slots: slots)
                        }
                    }
                }
            }
            if !tray.isEmpty {
                PadSection("ภาพอื่น (\(tray.count))") {
                    ForEach(tray) { item in row(item) { slotMenu(item, slots: targets) } }
                } footer: {
                    if geo == nil, !marks.isEmpty {
                        Text("ภาพ A2 ไม่ใช่ภาพดาวเทียมที่ดึงจากพิกัด จึงจับคู่รูปกับสัญลักษณ์ตามตำแหน่งที่ถ่ายไม่ได้")
                    }
                }
            }
            let done = items.filter { placed[$0.id] != nil }
            if !done.isEmpty {
                PadSection("ใส่แล้ว (\(done.count))") {
                    ForEach(done) { item in
                        row(item, detail: placed[item.id]) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }
                    }
                }
            }
        }
    }

    private func row<Actions: View>(_ item: Item, detail: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { info(item, detail); Spacer(minLength: 8); actions() }
            VStack(alignment: .leading, spacing: 8) { info(item, detail); HStack(spacing: 8) { actions() } }
        }
        .padding(.vertical, 4)
    }

    private func info(_ item: Item, _ detail: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let t = item.thumb { Image(uiImage: t).resizable().scaledToFill() } else { Theme.track }
            }
            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.shot.date.map { $0.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "th_TH"))) } ?? "ไม่มีวันที่")
                    .font(.sarabunFixed(15, .semibold)).foregroundStyle(Theme.navy)
                Text([item.shot.camera, item.shot.lat == nil ? "ไม่มีพิกัด" : nil, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
        }
    }

    private func slotMenu(_ item: Item, slots: [PhotoTarget]) -> some View {
        Menu {
            ForEach(Array(Dictionary(grouping: slots, by: \.section).sorted { a, b in
                (slots.firstIndex { $0.section == a.key } ?? 0) < (slots.firstIndex { $0.section == b.key } ?? 0)
            }), id: \.key) { section, list in
                Section(section) { ForEach(list) { t in Button(t.label) { place(item, t) } } }
            }
        } label: {
            Text("ใส่ในช่อง…").frame(minHeight: 44)
        }
        .disabled(slots.isEmpty)
    }

    private func markName(_ m: MapMark) -> String { m.label.isEmpty ? m.kind.paletteTitle : m.label }

    // MARK: actions

    private func photo(_ item: Item, maxSide: CGFloat = 1600) -> Photo? {
        guard let img = UIImage(contentsOfFile: item.url.path), var p = model.addPhoto(img, to: job.id, maxSide: maxSide) else { return nil }
        p.apply(item.shot.stamp)
        if let d = item.shot.date { p.takenAt = d }
        return p
    }

    private func place(_ item: Item, _ t: PhotoTarget) {
        guard let p = photo(item) else { return }
        if let m = t.module {
            guard let k = job.modules.firstIndex(where: { $0.id == m }) else { return }
            job.modules[k].values[t.field] = .photo(p)
        } else {
            job.values[t.field] = .photo(p)
        }
        placed[item.id] = "\(t.section.split(separator: " ").first ?? "") \(t.label)"
    }

    private func useAsSite(_ item: Item) {
        guard let p = photo(item, maxSide: 2400) else { return }
        job.values["siteMap"] = .photo(p)
        job.values[SiteShapes.sourceKey] = .text("drone")
        // a drone photo's scale is unknown until it is measured on A2
        job.values[SiteShapes.scaleKey] = nil
        placed[item.id] = "A2 ภาพสถานที่ติดตั้ง"
    }

    // MARK: reading

    private func load(_ urls: [URL]) {
        reading = true
        Task {
            let new = await Task.detached(priority: .userInitiated) { urls.compactMap(Self.read) }.value
            items = (items + new).sorted { ($0.shot.date ?? .distantFuture) < ($1.shot.date ?? .distantFuture) }
            reading = false
        }
    }

    /// Copies the file out of the card and reads its EXIF and a small thumbnail.
    nonisolated static func read(_ url: URL) -> Item? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CardImport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil,
              let src = CGImageSourceCreateWithURL(copy as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                  kCGImageSourceThumbnailMaxPixelSize: 200,
                                                                  kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        return Item(shot: shot(props), url: copy, thumb: thumb.map { UIImage(cgImage: $0) })
    }

    nonisolated static func shot(_ props: [CFString: Any]) -> CardImport.Shot {
        var s = CardImport.Shot()
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            s.lat = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
            s.lon = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
        }
        if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
            s.altitude = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1 ? -alt : alt
        }
        s.heading = gps[kCGImagePropertyGPSImgDirection] as? Double
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if let t = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            s.date = f.date(from: t)
        }
        s.camera = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String
        return s
    }
}
#endif
