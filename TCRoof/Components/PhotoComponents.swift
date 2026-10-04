import SwiftUI
import TCRoofUI
import PhotosUI
import PencilKit

/// Pick from the library or shoot with the camera; shows thumbnails with delete buttons.
struct PhotoPickerSection: View {
    let images: [Data]
    let onAdd: (Data) -> Void
    let onDelete: ((Int) -> Void)?

    @State private var items: [PhotosPickerItem] = []
    @State private var showCamera = false

    init(images: [Data], onAdd: @escaping (Data) -> Void, onDelete: ((Int) -> Void)? = nil) {
        self.images = images
        self.onAdd = onAdd
        self.onDelete = onDelete
    }

    init(images: Binding<[Data]>) {
        self.init(images: images.wrappedValue,
                  onAdd: { images.wrappedValue.append($0) },
                  onDelete: { images.wrappedValue.remove(at: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) {
                    Label("เลือกจากคลังภาพ", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        Label("ถ่ายรูป", systemImage: "camera")
                    }
                }
                Spacer()
                if !images.isEmpty {
                    Text("\(images.count) รูป").font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.bordered)

            if images.isEmpty {
                Text("ยังไม่มีรูปภาพ")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6])))
            } else {
                PhotoGrid(images: images, onDelete: onDelete)
            }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        onAdd(ImageUtil.compressed(data))
                    }
                }
                items = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in onAdd(ImageUtil.compressed(image)) }
                .ignoresSafeArea()
        }
    }
}

struct PhotoGrid: View {
    let images: [Data]
    var onDelete: ((Int) -> Void)? = nil
    var minSize: CGFloat = 120

    @State private var viewerIndex: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minSize), spacing: 12)], spacing: 12) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                ZStack(alignment: .topTrailing) {
                    Button { viewerIndex = index } label: {
                        Thumbnail(data: data)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    if let onDelete {
                        Button { onDelete(index) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(4)
                        .accessibilityLabel("ลบรูป")
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(get: { viewerIndex.map(IndexBox.init) }, set: { viewerIndex = $0?.id })) { box in
            PhotoViewer(images: images, start: box.id)
        }
    }
}

private struct IndexBox: Identifiable { let id: Int }

struct Thumbnail: View {
    let data: Data

    var body: some View {
        Color.gray.opacity(0.15)
            .overlay {
                if let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.3)))
    }
}

struct PhotoViewer: View {
    let images: [Data]
    @State var start: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $start) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().tag(index)
                    }
                }
            }
            .tabViewStyle(.page)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .padding(24)
            .accessibilityLabel("ปิด")
        }
    }
}

// MARK: - UIKit bridges

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Apple Pencil / finger signature pad. Writes a PNG into `signature`; setting it to nil clears the pad.
struct SignaturePad: UIViewRepresentable {
    @Binding var signature: Data?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(Theme.navy), width: 4)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if signature == nil && !canvas.drawing.strokes.isEmpty {
            canvas.drawing = PKDrawing()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: SignaturePad
        init(_ parent: SignaturePad) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            if canvas.drawing.strokes.isEmpty {
                if parent.signature != nil { parent.signature = nil }
                return
            }
            let bounds = canvas.drawing.bounds.insetBy(dx: -20, dy: -20)
            let image = canvas.drawing.image(from: bounds, scale: 2)
            parent.signature = image.pngData()
        }
    }
}
