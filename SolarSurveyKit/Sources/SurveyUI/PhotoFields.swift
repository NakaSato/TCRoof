#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import PencilKit
import TCRoofCore

/// One photo frame: take with the camera or pick from the library; tap to view, menu to replace or remove.
struct PhotoField: View {
    @Binding var photo: Photo?
    let jobID: UUID
    var label: String = ""
    var height: CGFloat = 220
    /// When set, offers "Google Maps" to fill the frame with a satellite picture of this location.
    var mapGPS: String? = nil
    @Environment(SurveyModel.self) private var model
    @State private var fetchingMap = false
    @State private var mapError: String?
    @State private var pick: PhotosPickerItem?
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
                VStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("รูปนี้ถ่ายจากเครื่องอื่น ยังไม่อยู่ในเครื่องนี้").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 30)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("ถ่ายภาพ", systemImage: "camera.fill") }.buttonStyle(.borderedProminent)
                        }
                        Button { showPicker = true } label: { Label("คลังภาพ", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered)
                        if mapGPS != nil {
                            Button { fetchMap() } label: { Label("Google Maps", systemImage: "map.fill") }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            if fetchingMap { Color.black.opacity(0.35); ProgressView("กำลังดึงภาพแผนที่…").tint(.white).foregroundStyle(.white) }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [5, 4] : [])))
        .overlay(alignment: .topTrailing) {
            if photo != nil {
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { showCamera = true } label: { Label("ถ่ายใหม่", systemImage: "camera") } }
                    Button { showPicker = true } label: { Label("เลือกจากคลังภาพ", systemImage: "photo") }
                    if mapGPS != nil { Button { fetchMap() } label: { Label("ดึงใหม่จาก Google Maps", systemImage: "map") } }
                    Button(role: .destructive) { photo = nil } label: { Label("ลบภาพ", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55)).padding(8)
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    photo = model.addPhoto(img, to: jobID)
                }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in if let img { photo = model.addPhoto(img, to: jobID) } }.ignoresSafeArea()
        }
        .sheet(isPresented: $showFull) {
            if let p = photo, let img = model.image(p, in: jobID) { PhotoViewer(image: img, title: label) }
        }
        .errorAlert($mapError)
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
        Text("\(photos.count) / \(max) ภาพ").font(.caption).foregroundStyle(.secondary)
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
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
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
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.done(nil)
            parent.dismiss()
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
                Rectangle().fill(Color.white)
                if let p = photo, let img = model.image(p, in: jobID) { Image(uiImage: img).resizable().scaledToFit().padding(6) }
                else { Text(photo == nil ? "แตะเพื่อเซ็นชื่อ" : "ลายเซ็นอยู่บนเครื่องอื่น").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 320).frame(height: 110)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
            .onTapGesture { signing = true }
            if photo != nil { Button("ลบลายเซ็น", role: .destructive) { photo = nil } }
        }
        .sheet(isPresented: $signing) {
            SignaturePad { img in if let img { photo = model.addPhoto(img, to: jobID, maxSide: 900, png: true) } }
        }
    }
}

struct SignaturePad: View {
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    var body: some View {
        NavigationStack {
            VStack {
                CanvasRepresentable(canvas: canvas)
                    .frame(height: 280).background(Color.white)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1).padding(.horizontal, 40).padding(.bottom, 60) }
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
                Text("เซ็นชื่อด้วย Apple Pencil หรือนิ้ว").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("ลายเซ็น").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .principal) { Button("ล้าง") { canvas.drawing = PKDrawing() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        let d = canvas.drawing
                        if !d.bounds.isEmpty {
                            let r = d.bounds.insetBy(dx: -12, dy: -12)
                            var img: UIImage?
                            UITraitCollection(userInterfaceStyle: .light).performAsCurrent { img = d.image(from: r, scale: 2) }
                            done(img)
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
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
