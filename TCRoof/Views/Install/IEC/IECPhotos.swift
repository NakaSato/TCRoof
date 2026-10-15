import SwiftUI
import SwiftData
import PhotosUI
import TCRoofUI
import TCRoofCore

/// The IEC test's photos are `PhotoAsset`s on the job (`Job.iecPhotos`), tagged with a new id that the report keeps
/// per string and kind. They stay on the device and go to Drive with the job's documents (`ProjectDriveUpload`, under
/// `IEC 62446/รูปถ่าย`); Firestore carries only the ids.
extension Job {
    func iecPhoto(_ id: String?) -> PhotoAsset? {
        guard let id else { return nil }
        return iecPhotos.first { $0.tag == id }
    }

    /// Keeps a photo, removing the one it replaces; returns its id for the report. A closed test keeps its photos
    /// (the old id comes back, and `updateIEC` refuses the change anyway).
    func storeIECPhoto(_ data: Data, replacing old: String?, context: ModelContext) -> String {
        if iecReport?.isLocked == true { return old ?? "" }
        if let o = iecPhoto(old) { context.delete(o) }
        let id = UUID().uuidString
        let asset = PhotoAsset(data: data, tag: id)
        context.insert(asset)
        asset.iecJob = self
        return id
    }

    func removeIECPhoto(_ id: String?, context: ModelContext) {
        guard iecReport?.isLocked != true else { return }
        if let o = iecPhoto(id) { context.delete(o) }
    }
}

enum IECCamera {
    /// `-iecCameraStub YES` (UI tests and screenshots; the simulator has no camera): a drawn photo instead.
    static var stub: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "iecCameraStub")
        #else
        false
        #endif
    }

    /// A meter's screen showing `reading`, for the stub.
    static func stubPhoto(_ reading: String) -> Data {
        let size = CGSize(width: 800, height: 600)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.86, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.3, blue: 0.27, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 260, y: 90, width: 280, height: 420), cornerRadius: 40).fill()
            UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 300, y: 150, width: 200, height: 100), cornerRadius: 8).fill()
            let text = NSAttributedString(string: reading, attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 54, weight: .bold),
                                                                        .foregroundColor: UIColor.black])
            let r = text.boundingRect(with: size, options: [], context: nil)
            text.draw(at: CGPoint(x: 400 - r.width / 2, y: 200 - r.height / 2))
        }
        return img.jpegData(compressionQuality: 0.7) ?? Data()
    }
}

/// One photo slot: the picture with its caption and time, or a dashed `ถ่ายรูป` tile. Tapped, it opens the camera
/// (or the library on a device without one); a menu replaces or removes a taken photo.
struct IECPhotoTile: View {
    let caption: String
    let asset: PhotoAsset?
    var height: CGFloat = 170
    /// What the stub photo shows.
    var stubReading = "0.0"
    let store: (Data) -> Void
    let remove: () -> Void

    @State private var camera = false
    @State private var library = false
    @State private var picked: PhotosPickerItem?

    var body: some View {
        Group {
            // empty: a tap takes the photo (the menu on a long press); taken: a tap offers retake, library or delete
            if asset == nil {
                Menu { menuItems } label: { tile } primaryAction: { take() }
            } else {
                Menu { menuItems } label: { tile }
            }
        }
        .fullScreenCover(isPresented: $camera) { StampedCamera { store($0) } }
        .photosPicker(isPresented: $library, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { store(ImageUtil.compressed(data)) }
                picked = nil
            }
        }
        .accessibilityLabel(caption)
        .accessibilityValue(asset == nil ? "ยังไม่มีรูป" : "มีรูปแล้ว")
    }

    @ViewBuilder private var menuItems: some View {
        Button { take() } label: { Label(asset == nil ? "ถ่ายรูป" : "ถ่ายใหม่", systemImage: "camera") }
        Button { library = true } label: { Label("เลือกจากคลังภาพ", systemImage: "photo.on.rectangle") }
        if asset != nil { Button(role: .destructive, action: remove) { Label("ลบรูป", systemImage: "trash") } }
    }

    private func take() {
        if IECCamera.stub { store(IECCamera.stubPhoto(stubReading)) }
        else if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
        else { library = true }
    }

    @ViewBuilder private var tile: some View {
        if let asset, let img = UIImage(data: asset.data) {
            // the tile's size first, the photo filling it: a photo wider than a narrow tile (IR, 150 pt) would
            // otherwise widen the frame and spill out of its card
            Color.clear.frame(maxWidth: .infinity).frame(height: height)
                .overlay { Image(uiImage: img).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text("\(caption) · \(ThaiFormat.time.string(from: asset.createdAt))").font(.sarabunFixed(13, .bold))
                        .foregroundStyle(Theme.successInk).padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.successSoft, in: Capsule()).padding(10)
                }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "camera").font(.system(size: 22))
                Text("ถ่าย" + caption).font(.sarabunFixed(14))
            }
            .foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.inkMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(Rectangle())
        }
    }
}

/// The number pad of screen 3: digits, `.`, delete, and `ค่าก่อนหน้า` / `ถัดไป ›`.
struct IECKeypad: View {
    let press: (String) -> Void
    let back: () -> Void
    let next: () -> Void

    private let keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "⌫"]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(keys, id: \.self) { k in
                    Button { press(k) } label: {
                        Group {
                            if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                        }
                        .font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(k == "⌫" ? "ลบ" : k == "." ? "จุด" : k)
                }
            }
            HStack(spacing: 10) {
                Button("ค่าก่อนหน้า", action: back).buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                Button("ถัดไป ›", action: next).buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
            }
        }
    }
}
