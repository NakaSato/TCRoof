#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import PencilKit
import TCRoofCore
import TCRoofUI

/// One photo frame: take with the camera or pick from the library; tap to view, menu to replace or remove.
struct PhotoField: View {
    @Binding var photo: Photo?
    let jobID: UUID
    var label: String = ""
    var height: CGFloat = 220
    /// When set, offers "แผนที่ดาวเทียม" to fill the frame with a satellite picture of this location.
    var mapGPS: String? = nil
    @Environment(SurveyModel.self) private var model
    @State private var fetchingMap = false
    @State private var mapError: String?
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showFull = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .tertiarySystemFill))
            if let p = photo, let img = model.image(p, in: jobID) {
                Image(uiImage: img).resizable().scaledToFit()
                    .onTapGesture { showFull = true }
            } else if photo != nil {
                // taken on another iPad and not downloaded yet — don't offer to fill the frame again
                PhotoSlot.notDownloaded
            } else {
                ViewThatFits {
                    VStack(spacing: 12) {
                        PhotoSourceButtons(onUpload: { showPicker = true }, onCamera: { showCamera = true })
                        mapButton
                    }
                    HStack(spacing: 8) {
                        PhotoSourceButtons(compact: true, onUpload: { showPicker = true }, onCamera: { showCamera = true })
                        mapButton
                    }
                }
                .padding(8)
            }
            if fetchingMap { Color.black.opacity(0.35); ProgressView("กำลังดึงภาพแผนที่…").tint(.white).foregroundStyle(.white) }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [5, 4] : [])))
        .overlay(alignment: .topTrailing) {
            if photo != nil {
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { showCamera = true } label: { Label("ถ่ายใหม่", systemImage: "camera") } }
                    Button { showPicker = true } label: { Label("เลือกจากคลังภาพ", systemImage: "photo") }
                    if mapGPS != nil { Button { fetchMap() } label: { Label("ดึงใหม่จากแผนที่ดาวเทียม", systemImage: "map") } }
                    Button(role: .destructive) { photo = nil } label: { Label("ลบภาพ", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55)).padding(8)
                }
            }
        }
        .photoSources(picker: $showPicker, camera: $showCamera) { img in photo = model.addPhoto(img, to: jobID) }
        .sheet(isPresented: $showFull) {
            if let p = photo, let img = model.image(p, in: jobID) { PhotoViewer(image: img, title: label) }
        }
        .errorAlert($mapError)
    }

    @ViewBuilder var mapButton: some View {
        if mapGPS != nil {
            Button { fetchMap() } label: { Label("แผนที่ดาวเทียม", systemImage: "map.fill").frame(minHeight: 44) }.buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
    }

    func fetchMap() {
        guard let gps = mapGPS else { return }
        fetchingMap = true
        Task { @MainActor in
            do { photo = try await model.mapPhoto(gps: gps, for: jobID) } catch { mapError = error.localizedDescription }
            fetchingMap = false
        }
    }
}

/// Several photos (up to `max`) in a grid.
struct PhotosField: View {
    @Binding var photos: [Photo]
    let jobID: UUID
    let max: Int
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                PhotoField(photo: Binding(get: { p }, set: { new in
                    if let new { photos[i] = new } else { photos.removeAll { $0.id == p.id } }
                }), jobID: jobID, height: 180)
                .overlay(alignment: .topLeading) {
                    Text("\(i + 1)").font(.caption.bold()).padding(6).background(.thinMaterial, in: Circle()).padding(6)
                }
            }
            if photos.count < max {
                PhotoField(photo: Binding(get: { nil }, set: { if let p = $0 { photos.append(p) } }), jobID: jobID, height: 180)
            }
        }
        Text("\(photos.count) / \(max) ภาพ").font(.caption).foregroundStyle(Theme.inkMuted)
    }
}

struct PhotoViewer: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    var body: some View {
        NavigationStack {
            Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale)
                .gesture(MagnificationGesture().onChanged { scale = Swift.max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } } }
        }
    }
}

/// System camera.
struct CameraPicker: UIViewControllerRepresentable {
    /// Off when `CheckedCamera` hosts it and decides when the cover closes.
    var dismissOnFinish = true
    /// Flash on: a retake after "มืดเกินไป".
    var flash = false
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        if flash { c.cameraFlashMode = .on }
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.done(info[.originalImage] as? UIImage)
            if parent.dismissOnFinish { parent.dismiss() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.done(nil)
            if parent.dismissOnFinish { parent.dismiss() }
        }
    }
}

/// Signature box: sign with Apple Pencil or a finger, saved as a transparent PNG.
struct SignatureField: View {
    @Binding var photo: Photo?
    let jobID: UUID
    @Environment(SurveyModel.self) private var model
    @State private var signing = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle().fill(Theme.paper)
                if let p = photo, let img = model.image(p, in: jobID) { Image(uiImage: img).resizable().scaledToFit().padding(6) }
                else { Text(photo == nil ? "แตะเพื่อเซ็นชื่อ" : "ลายเซ็นอยู่บนเครื่องอื่น").foregroundStyle(Theme.inkMuted) }
            }
            .frame(maxWidth: 320).frame(height: 110)
            .overlay(Rectangle().stroke(Theme.borderControl))
            .onTapGesture { signing = true }
            if photo != nil { Button("ลบลายเซ็น", role: .destructive) { photo = nil } }
        }
        .signaturePad(isPresented: $signing) { img in if let img { photo = model.addPhoto(img, to: jobID, maxSide: 900, png: true) } }
    }
}

extension View {
    /// The signature pad: full screen over a dimmed page on iPad (docs/ui/survey-e1 states/05), a sheet on iPhone.
    func signaturePad(isPresented: Binding<Bool>, who: String? = nil, done: @escaping (UIImage?) -> Void) -> some View {
        modifier(SignaturePadPresenter(isPresented: isPresented, who: who, done: done))
    }
}

private struct SignaturePadPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let who: String?
    let done: (UIImage?) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content.sheet(isPresented: $isPresented) { SignaturePad(who: who, done: done) }
        } else {
            content.fullScreenCover(isPresented: $isPresented) {
                SignaturePad(who: who, done: done).presentationBackground(.clear)
            }
        }
    }
}

/// Sign with Apple Pencil or a finger. On iPad it is a card inset 32 pt over a dimmed page; on iPhone it fills its sheet.
/// The PNG is the drawing's bounds plus 12 pt, at scale 2, drawn in the light trait so the ink stays black.
struct SignaturePad: View {
    /// "วิศวกรผู้สำรวจ · <name>" under the title.
    var who: String? = nil
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var canvas = PKCanvasView()

    static let fill = Color(red: 0.988, green: 0.992, blue: 0.996)
    static let line = Color(red: 0.357, green: 0.420, blue: 0.510)
    static let save = Color(red: 0.122, green: 0.435, blue: 0.710)

    var body: some View {
        let phone = sizeClass == .compact
        ZStack {
            if !phone { Color(red: 0.055, green: 0.102, blue: 0.169).opacity(0.55).ignoresSafeArea() }
            VStack(spacing: 12) {
                topBar(phone: phone)
                pad(phone: phone)
                Text("เซ็นชื่อเหนือเส้นด้วย Apple Pencil หรือนิ้ว").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, phone ? 16 : 20).padding(.top, 14).padding(.bottom, 18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: phone ? 0 : 20))
            .shadow(color: .black.opacity(phone ? 0 : 0.3), radius: 24, y: 16)
            .padding(phone ? 0 : 32)
        }
        .environment(\.colorScheme, .light)
    }

    func topBar(phone: Bool) -> some View {
        HStack(spacing: 10) {
            outline("ยกเลิก", width: phone ? 80 : 110) { dismiss() }
            VStack(spacing: 0) {
                Text("ลายเซ็น").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.navy)
                if let who { Text(who).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity)
            outline("ล้าง", width: phone ? 64 : 96) { canvas.drawing = PKDrawing() }
            Button {
                let d = canvas.drawing
                if !d.bounds.isEmpty {
                    let r = d.bounds.insetBy(dx: -12, dy: -12)
                    var img: UIImage?
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent { img = d.image(from: r, scale: 2) }
                    done(img)
                }
                dismiss()
            } label: {
                Text("บันทึก").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(minWidth: phone ? 80 : 130, minHeight: 48)
                    .background(Self.save, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    func outline(_ title: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(minWidth: width, minHeight: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    func pad(phone: Bool) -> some View {
        let inset: CGFloat = phone ? 32 : 80
        return GeometryReader { geo in
            let y = geo.size.height * 0.74
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Self.line.opacity(0.5)).frame(width: max(0, geo.size.width - 2 * inset), height: 1.5)
                    .offset(x: inset, y: y)
                Text("×").font(.system(size: 28)).foregroundStyle(Self.line.opacity(0.55))
                    .offset(x: inset, y: y - 44)
                CanvasRepresentable(canvas: canvas)
            }
        }
        .background(Self.fill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Self.line.opacity(0.35)))
        .frame(minHeight: 240)
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        return canvas
    }
    func updateUIView(_ v: PKCanvasView, context: Context) {}
}
#endif
