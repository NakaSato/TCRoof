#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore

/// The survey's one photo slot (docs/ui/photo-picker): empty is a dashed frame (red when required) with a hint and
/// "อัปโหลด" / "กล้อง"; filled shows the photo with a done badge and a clear button, and opens full screen on tap.
/// It owns the photo library and camera; the page saves the picked image (`model.addPhoto`) in `onPick`.
struct PhotoSlot: View {
    let photo: Photo?
    let jobID: UUID
    var hint: String
    var required = false
    /// The full-screen viewer's title.
    var title = ""
    /// Extra content under the buttons of an empty slot (B2's "ใช้ภาพพื้นที่").
    var extra: AnyView? = nil
    var clearLabel = "ลบภาพ"
    /// Small tiles (A3): badges sit closer to the corners and a missing photo shows only its icon.
    var dense = false
    /// The photo fills the slot, cropped (B4's 2 × 2 grid); otherwise it fits.
    var fill = false
    var onPick: (UIImage) -> Void
    var onClear: () -> Void
    /// nil opens the built-in viewer.
    var onOpen: ((Photo) -> Void)? = nil
    @Environment(SurveyModel.self) private var model
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var viewing: Photo?

    var body: some View {
        Group {
            if let p = photo { filled(p) } else { empty }
        }
        .photoSources(picker: $showPicker, camera: $showCamera, onPick: onPick)
        .sheet(item: $viewing) { p in if let img = model.image(p, in: jobID) { PhotoViewer(image: img, title: title) } }
    }

    var empty: some View {
        ViewThatFits {
            VStack(spacing: 14) {
                Text(hint).font(.system(size: 15)).foregroundStyle(Home.muted).multilineTextAlignment(.center)
                PhotoSourceButtons(onUpload: { showPicker = true }, onCamera: { showCamera = true })
                extra
            }
            .padding()
            .frame(minWidth: 330, minHeight: 120)
            VStack(spacing: 4) {
                // a small ideal width so ViewThatFits keeps the hint and lets it shrink
                Text(hint).font(.system(size: 12, weight: .bold)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 0, idealWidth: 60, maxWidth: .infinity)
                PhotoSourceButtons(compact: true, onUpload: { showPicker = true }, onCamera: { showCamera = true })
                extra
            }
            .padding(4)
            PhotoSourceButtons(compact: true, onUpload: { showPicker = true }, onCamera: { showCamera = true })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(required ? Home.danger : Home.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    func filled(_ p: Photo) -> some View {
        ZStack {
            PhotoSlot.stageColor
            if let img = model.image(p, in: jobID) {
                Button { if let onOpen { onOpen(p) } else { viewing = p } } label: {
                    if fill {
                        // in an overlay, so the cropped photo never sizes the slot
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay { Image(uiImage: img).resizable().scaledToFill() }.clipped()
                    } else {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .buttonStyle(.plain).accessibilityLabel(title.isEmpty ? "ดูภาพเต็มจอ" : "\(title) แตะเพื่อดูเต็มจอ")
            } else {
                if dense {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 20)).foregroundStyle(Home.muted)
                        .accessibilityLabel("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด")
                } else {
                    PhotoSlot.notDownloaded
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
        .overlay(alignment: .topLeading) { PhotoDoneBadge(inset: dense ? 4 : 10) }
        .overlay(alignment: .topTrailing) { PhotoClearButton(label: clearLabel, inset: dense ? -4 : 4, action: onClear) }
    }

    /// The grey-blue behind a photo scaled to fit.
    static let stageColor = Color(red: 0.91, green: 0.933, blue: 0.961)

    /// A photo saved in the job but taken on another device.
    static var notDownloaded: some View {
        Label("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด", systemImage: "icloud.and.arrow.down")
            .font(.callout).foregroundStyle(Home.muted).multilineTextAlignment(.center).padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "อัปโหลด" and "กล้อง" alone (the camera only where the device has one); `compact` makes them 44 pt icon buttons.
struct PhotoSourceButtons: View {
    var compact = false
    /// The labelled buttons' height (A4's photo strip uses 60).
    var height: CGFloat = 46
    var onUpload: () -> Void
    var onCamera: () -> Void

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            button("อัปโหลด", icon: "ui-upload-photo", fallback: "photo", action: onUpload)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                button("กล้อง", icon: "ui-camera", fallback: "camera", action: onCamera)
            }
        }
    }

    func button(_ title: String, icon: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if compact {
                    A2Icon(name: icon, fallback: fallback, size: 20).foregroundStyle(Home.primary)
                        .frame(width: 44, height: 44)
                } else {
                    HStack(spacing: 8) {
                        A2Icon(name: icon, fallback: fallback, size: 18).foregroundStyle(Home.primary)
                        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Home.navy)
                    }
                    .frame(width: 150, height: height)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The green tick on a filled photo.
struct PhotoDoneBadge: View {
    var inset: CGFloat = 10
    var body: some View {
        A2Icon(name: "b1-photo-done", fallback: "checkmark.circle.fill", size: 28).foregroundStyle(Home.ok)
            .padding(inset).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The dark ✕ on a filled photo: 28 pt inside a 44 pt hit area.
struct PhotoClearButton: View {
    var label = "ลบภาพ"
    /// The hit area's distance from the corner; negative lets it overhang a small tile's 8 pt margin.
    var inset: CGFloat = 4
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            A2Icon(name: "b1-photo-clear", fallback: "xmark.circle.fill", size: 28)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(inset)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Presents the photo library and the camera and hands the chosen image to `onPick`.
    func photoSources(picker: Binding<Bool>, camera: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoSources(showPicker: picker, showCamera: camera, onPick: onPick))
    }
}

extension View {
    /// How the camera checks shots taken for `field` (`PhotoShot.of`): a nameplate warns when tilted.
    func photoShot(_ field: String) -> some View { environment(\.photoShot, PhotoShot.of(field)) }
}

private struct PhotoShotKey: EnvironmentKey { static let defaultValue = PhotoShot.any }

extension EnvironmentValues {
    var photoShot: PhotoShot {
        get { self[PhotoShotKey.self] }
        set { self[PhotoShotKey.self] = newValue }
    }
}

private struct PhotoSources: ViewModifier {
    @Binding var showPicker: Bool
    @Binding var showCamera: Bool
    let onPick: (UIImage) -> Void
    @Environment(\.photoShot) private var shot
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPicker, selection: $item, matching: .images)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let img = UIImage(data: data) { onPick(img) }
                    item = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) { CheckedCamera(shot: shot) { img in if let img { onPick(img) } } }
    }
}
#endif
