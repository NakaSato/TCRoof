import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

/// Slot 4's photo pages, drawn as the filed requests show them: A4, the project header centred on every page, two
/// titled sections a page, each with one photo or two (stacked when landscape, side by side when upright).
enum PhotoReportRenderer {
    static var size: CGSize { CGSize(width: PhotoReport.pageSize[0], height: PhotoReport.pageSize[1]) }

    typealias Loader = (String) -> UIImage?

    static func pdf(_ report: PhotoReport, kWp: Double?, load: Loader) -> Data? {
        let pages = report.pages
        guard !pages.isEmpty else { return nil }
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { r in
            for page in pages {
                r.beginPage()
                draw(page, header: report.header(kWp: kWp), load: load, in: r.cgContext)
            }
        }
    }

    static func image(_ report: PhotoReport, page: Int, kWp: Double?, load: Loader) -> UIImage? {
        let pages = report.pages
        guard pages.indices.contains(page) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            draw(pages[page], header: report.header(kWp: kWp), load: load, in: r.cgContext)
        }
    }

    private static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "Sarabun-Bold" : "Sarabun-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    private static func centred(_ text: String, font: UIFont, in box: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: PermitRenderer.paper(Theme.paperInk),
                                                       .paragraphStyle: style])
            .draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    static func draw(_ sections: [PhotoReport.Section], header: [String], load: Loader, in ctx: CGContext) {
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        for (i, line) in header.enumerated() {
            let y = PhotoReport.headerTop + Double(i) * PhotoReport.headerLineHeight
            centred(line, font: font(12, bold: i == 0), in: CGRect(x: 48, y: y, width: size.width - 96, height: 20))
        }
        for (slot, section) in sections.prefix(2).enumerated() {
            let frame = PhotoReport.frame(slot: slot)
            let title = PermitRenderer.rect(frame.title)
            PermitRenderer.paper(Theme.primarySoft).setFill()
            ctx.fill(title)
            centred(section.title, font: font(PhotoReport.titleFontSize, bold: true), in: title.insetBy(dx: 6, dy: 2))

            let images = section.photos.prefix(PhotoReport.maxPhotos).compactMap(load)
            let rects = PhotoReport.photoRects(slot: slot, aspects: images.map { Double($0.size.width / max($0.size.height, 1)) })
            for (image, r) in zip(images, rects) {
                let box = PermitRenderer.rect(r)
                image.draw(in: box)
                let border = UIBezierPath(rect: box)
                border.lineWidth = 0.75
                PermitRenderer.paper(Theme.borderControl).setStroke()
                border.stroke()
            }
        }
    }
}

/// The photo set for PPIM slot 4: a photo or two under each standard heading, the header lines, and a preview of
/// the pages that go into the slot's file.
struct PhotoReportView: View {
    let job: Job
    @Binding var home: HomeJob

    @State private var target: String?
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var previewPage = 0

    private var store: PermitStore { PermitStore(job: job) }
    private var kWp: Double? { HomeJob.number(home.pvKWp) ?? home.ppim.panelKWp }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "ภาพถ่ายระบบ", trail: ["งานบ้าน", job.code], current: "PPIM ช่อง 4") {}
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    headerCard
                    sectionsCard
                    previewCard
                }
                .padding(isPhone ? Space.l : Space.xl)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if home.photoReport.address.isEmpty { home.photoReport.address = job.address }
        }
        .photosPicker(isPresented: $showPicker, selection: $picks, maxSelectionCount: PhotoReport.maxPhotos, matching: .images)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty, let id = target else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        home.photoReport.add(store.addPhoto(ImageUtil.compressed(data)), to: id)
                    }
                }
                picks = []
            }
        }
    }

    private var headerCard: some View {
        PermitSection(title: "หัวกระดาษทุกหน้า", subtitle: "บรรทัดที่ 3 คำนวณจากขนาดแผง (kWp)") {
            PermitField("ชื่อโครงการ", text: $home.photoReport.projectTitle)
            PermitField("ที่อยู่ติดตั้ง", text: $home.photoReport.address)
            Text(kWp.map { "ขนาดกำลังการผลิตติดตั้ง " + String(format: "%.2f", $0) + " กิโลวัตต์" } ?? "กรอกขนาดแผง (kWp) ในหน้างานบ้าน")
                .font(.sarabun(14, relativeTo: .body)).foregroundStyle(kWp == nil ? Theme.dangerText : Theme.navy)
        }
    }

    private var sectionsCard: some View {
        let r = home.photoReport
        return PermitSection(title: "รูปตามหัวข้อ",
                             subtitle: r.missing.isEmpty ? "ครบ 9 หัวข้อมาตรฐาน · \(r.pages.count) หน้า"
                                                         : "ยังขาด \(r.missing.count) หัวข้อ · หัวข้อละไม่เกิน 2 รูป") {
            ForEach(r.sections) { sectionRow($0) }
        }
    }

    private func sectionRow(_ s: PhotoReport.Section) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top) {
                Image(systemName: s.photos.isEmpty ? (s.required ? "circle" : "circle.dashed") : "checkmark.circle.fill")
                    .foregroundStyle(s.photos.isEmpty ? Theme.borderControl : Theme.okTick)
                Text(s.title).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                if !s.required { TCStatusChip("ถ้ามี", fill: Theme.disabledFill, text: Theme.inkMuted) }
            }
            HStack(spacing: Space.s) {
                ForEach(s.photos, id: \.self) { thumb($0) }
                if s.photos.count < PhotoReport.maxPhotos {
                    Button { target = s.id; showPicker = true } label: {
                        Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                            .frame(width: 72, height: 72)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("เพิ่มรูป \(s.title)")
                }
            }
        }
        .padding(Space.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func thumb(_ name: String) -> some View {
        let image = store.photo(name).flatMap(UIImage.init(data:))
        return ZStack(alignment: .topTrailing) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Theme.disabledFill }
            }
            .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            Button {
                home.photoReport.remove(name)
                store.deletePhoto(name)
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.surface, Theme.dangerText)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .buttonStyle(.plain)
            .offset(x: 10, y: -10)
            .accessibilityLabel("ลบรูป")
        }
    }

    @ViewBuilder private var previewCard: some View {
        let count = home.photoReport.pages.count
        PermitSection(title: "ตัวอย่างหน้า", subtitle: count == 0 ? "ยังไม่มีรูป" : "หน้า \(min(previewPage, count - 1) + 1) / \(count)") {
            if count > 0 {
                let page = min(previewPage, count - 1)
                if let image = PhotoReportRenderer.image(home.photoReport, page: page, kWp: kWp,
                                                          load: { store.photo($0).flatMap(UIImage.init(data:)) }) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: 520)
                        .overlay(Rectangle().strokeBorder(Theme.borderSubtle))
                        .frame(maxWidth: .infinity)
                }
                HStack {
                    TCButton("ก่อนหน้า", systemImage: "chevron.left", kind: .secondary, size: .card) { previewPage = page - 1 }
                        .disabled(page == 0)
                    Spacer()
                    TCButton("ถัดไป", systemImage: "chevron.right", kind: .secondary, size: .card) { previewPage = page + 1 }
                        .disabled(page >= count - 1)
                }
            }
        }
    }
}
