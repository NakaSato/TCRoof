import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

// อัปโหลดผัง (docs/ui/daily-report-ipad-v2 §3): the station's own key plan from the document camera, the photo
// library or a PDF (a page, then cropped), or back to the survey's A2 picture. It is the station's, so it is saved
// at once, not with the day's report; the locations keep their points on the new picture.

extension DailyOnePage {
    /// The compact white key-plan button: 28 pt to see, 44 pt to tap.
    func planChip<L: View>(_ label: L) -> some View {
        label
            .font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 8).frame(minWidth: 28).frame(height: 28)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.borderSubtle))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    var uploadButton: some View {
        Button { showUpload = true } label: {
            planChip(Label("อัปโหลดผัง", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keyPlanUpload")
        .popover(isPresented: $showUpload, arrowEdge: .top) {
            uploadMenu.presentationCompactAdaptation(.popover)
        }
        .fullScreenCover(isPresented: $showScan) {
            DocumentCamera { pdf in
                showScan = false
                if let pdf, let img = KeyPlanFile.page(of: pdf, at: 0) { useKeyPlan(img) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { useKeyPlan(img) }
                libraryItem = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: KeyPlanFile.types) { result in
            guard case .success(let url) = result else { return }
            let open = url.startAccessingSecurityScopedResource()
            defer { if open { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            if url.pathExtension.lowercased() == "dwg" {
                actions.toast("ยังเปิดไฟล์ DWG ไม่ได้ | ส่งออกเป็น PDF ก่อน แล้วเลือกอีกครั้ง")
            } else if KeyPlanFile.isPDF(data) {
                pdfPick = KeyPlanFile.PDFPick(data: data)
            } else if let img = UIImage(data: data) {
                cropPick = KeyPlanFile.CropPick(image: img)
            }
        }
        .sheet(item: $pdfPick) { pick in
            KeyPlanPDFSheet(data: pick.data) { img in useKeyPlan(img) }
        }
        .sheet(item: $cropPick) { pick in
            KeyPlanCropSheet(image: pick.image) { img in useKeyPlan(img) }
        }
    }

    private var uploadMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ผังตำแหน่งงาน (Key Plan) ของสถานีนี้ | ใช้ทุกวัน และในหน้า 2 ของ DAILY REPORT")
                .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6).padding(.bottom, 4)
            uploadRow("camera", "ถ่ายรูปผัง", "กล้อง | ปรับมุมกระดาษอัตโนมัติ", enabled: DocumentCamera.isAvailable) { showScan = true }
            uploadRow("photo", "เลือกจากคลังภาพ", "JPG | PNG") { showLibrary = true }
            uploadRow("doc.badge.arrow.up", "ไฟล์แบบ PDF / DWG", "เลือกหน้าและครอปเฉพาะผัง") { showFiles = true }
            uploadRow("map", "ใช้ภาพ A2 จากรายงานสำรวจ", "ภาพผังหน้างานที่ลงนามแล้ว", enabled: job.uploadedKeyPlan != nil) {
                job.clearKeyPlan(context: context)
                keyPlanVersion += 1
                actions.toast("ใช้ภาพ A2 เป็นผังของสถานีนี้แล้ว | ตำแหน่งงานเดิมยังอยู่")
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(Theme.surface)
    }

    private func uploadRow(_ icon: String, _ title: String, _ sub: String, enabled: Bool = true,
                           _ action: @escaping () -> Void) -> some View {
        Button {
            showUpload = false
            // the menu's popover closes before a sheet or a picker opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text(sub).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// Saves the picture as the station's key plan.
    func useKeyPlan(_ image: UIImage) {
        job.setKeyPlan(ImageUtil.compressed(image, maxDimension: 2400), context: context)
        keyPlanVersion += 1
        actions.toast("อัปโหลดผังแล้ว | ลากหมุดงานไปวางบนผังใหม่")
    }
}

/// Reading a key plan file: a PDF page drawn as a picture, and cropping.
enum KeyPlanFile {
    struct PDFPick: Identifiable { let id = UUID(); let data: Data }
    struct CropPick: Identifiable { let id = UUID(); let image: UIImage }

    static var types: [UTType] { [.pdf, .png, .jpeg, .image] + (UTType(filenameExtension: "dwg").map { [$0] } ?? []) }

    static func isPDF(_ data: Data) -> Bool { data.prefix(4) == Data("%PDF".utf8) }

    /// Page `index` of a PDF, about 2400 pt on its long side, on white.
    static func page(of data: Data, at index: Int, longSide: CGFloat = 2400) -> UIImage? {
        guard let page = PDFDocument(data: data)?.page(at: index) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let scale = longSide / max(box.width, box.height, 1)
        return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
    }

    /// `rect` in fractions of the picture.
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage {
        let size = image.size
        let r = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        return UIGraphicsImageRenderer(size: r.size).image { _ in
            image.draw(at: CGPoint(x: -r.minX, y: -r.minY))
        }
    }
}

/// A PDF's pages to pick from (skipped for one page), then the crop.
struct KeyPlanPDFSheet: View {
    let data: Data
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: UIImage?

    private var count: Int { PDFDocument(data: data)?.pageCount ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                if let picked {
                    KeyPlanCropper(image: picked) { done($0); dismiss() }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            ForEach(0..<count, id: \.self) { i in
                                Button { picked = KeyPlanFile.page(of: data, at: i) } label: {
                                    VStack(spacing: 6) {
                                        if let thumb = KeyPlanFile.page(of: data, at: i, longSide: 360) {
                                            Image(uiImage: thumb).resizable().scaledToFit().frame(height: 180)
                                                .background(Theme.paper)
                                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderSubtle))
                                        }
                                        Text("หน้า \(i + 1)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                                    }
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Theme.pageGradient.ignoresSafeArea())
            .navigationTitle(picked == nil ? "เลือกหน้าที่เป็นผัง" : "ครอปเฉพาะผัง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } } }
        }
        .onAppear { if count == 1 { picked = KeyPlanFile.page(of: data, at: 0) } }
    }
}

/// A picture file: the crop only.
struct KeyPlanCropSheet: View {
    let image: UIImage
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KeyPlanCropper(image: image) { done($0); dismiss() }
                .background(Theme.pageGradient.ignoresSafeArea())
                .navigationTitle("ครอปเฉพาะผัง")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } } }
        }
    }
}

/// The picture with a frame dragged by its corners; `ใช้ผังนี้` crops to it.
struct KeyPlanCropper: View {
    let image: UIImage
    let done: (UIImage) -> Void
    /// In fractions of the picture.
    @State private var rect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    @State private var start: CGRect?

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit()
                .overlay { GeometryReader { g in frame(in: g.size) } }
                .padding(24)
            HStack(spacing: 12) {
                Button("ทั้งหน้า") { rect = CGRect(x: 0, y: 0, width: 1, height: 1) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Button("ใช้ผังนี้") { done(KeyPlanFile.crop(image, to: rect)) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
            }
            .padding(.bottom, 24)
        }
    }

    private func frame(in size: CGSize) -> some View {
        let r = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { p in p.addRect(CGRect(origin: .zero, size: size)); p.addRect(r) }
                .fill(Theme.navySolid.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Rectangle().strokeBorder(Theme.primary, lineWidth: 2).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
            ForEach(0..<4, id: \.self) { corner in
                handle(corner, at: CGPoint(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY), size: size)
            }
        }
    }

    /// Corners 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
    private func handle(_ corner: Int, at p: CGPoint, size: CGSize) -> some View {
        Circle().fill(Theme.primary).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 3))
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(p)
            .gesture(DragGesture().onChanged { g in
                let s = start ?? rect
                if start == nil { start = rect }
                let dx = g.translation.width / max(size.width, 1), dy = g.translation.height / max(size.height, 1)
                var minX = s.minX, minY = s.minY, maxX = s.maxX, maxY = s.maxY
                if corner % 2 == 0 { minX = min(max(s.minX + dx, 0), maxX - 0.1) } else { maxX = max(min(s.maxX + dx, 1), minX + 0.1) }
                if corner < 2 { minY = min(max(s.minY + dy, 0), maxY - 0.1) } else { maxY = max(min(s.maxY + dy, 1), minY + 0.1) }
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }.onEnded { _ in start = nil })
            .accessibilityLabel(["มุมซ้ายบน", "มุมขวาบน", "มุมซ้ายล่าง", "มุมขวาล่าง"][corner])
    }
}
