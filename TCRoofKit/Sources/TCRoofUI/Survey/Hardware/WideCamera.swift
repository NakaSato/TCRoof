#if canImport(UIKit)
import SwiftUI
@preconcurrency import AVFoundation
import CoreMotion
import TCRoofCore

/// The camera for "มุมกว้าง" fields (docs/specs/hardware-assist-swift.md §H4.3). With an ultra-wide lens it opens at
/// 0.5× for one shot. Without one (iPad Air) it offers ถ่ายต่อกัน 3 ภาพ: left → centre → right, with the last shot's
/// right 30 % ghosted on the left edge and the gyroscope (`PanoramaGuide`) saying when the next one lines up. The
/// three are joined side by side into one picture, so the field, the report and Excel take it as before.
struct WideCamera: View {
    let done: (UIImage?) -> Void
    /// A joined strip is stored up to this long side, so each shot keeps about 1200 px.
    static let stripMaxSide: CGFloat = 3600

    @Environment(\.dismiss) private var dismiss
    @Environment(SurveyModel.self) private var model
    @State private var cam = WideCapture()
    @State private var sensors = CaptureContext()
    @State private var guide: PanoramaGuide?
    @State private var shots: [UIImage] = []
    @State private var stamp: PhotoStamp?
    @State private var busy = false
    @State private var result: UIImage?
    @State private var issues: [ImageQuality.Issue] = []

    private var multi: Bool { guide != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let result, !issues.isEmpty {
                PhotoReview(image: result, issues: issues, keep: { finish(result) }, retake: restart)
            } else {
                WidePreview(cam: cam).ignoresSafeArea()
                if multi { ghost }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if let guide { level(guide) }
                    bottomBar
                }
            }
        }
        .onAppear {
            if !cam.ultraWide { guide = PanoramaGuide(horizontalFOV: cam.fov(portrait: false)) }
            cam.onMotion = { rate, gravity, dt in guide?.turn(rate: rate, gravity: gravity, dt: dt) }
            cam.start()
            sensors.start()
        }
        .onDisappear { cam.stop(); sensors.stop() }
        .sensoryFeedback(.success, trigger: guide.map { $0.ready && $0.taken > 0 } ?? false) { _, now in now }
        .statusBarHidden()
    }

    // MARK: overlay

    private var topBar: some View {
        Text(multi ? guide?.cue ?? "" : cam.ultraWide ? "เลนส์มุมกว้าง 0.5×" : "ถ่ายภาพเดียว")
            .font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.onMedia).multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.top, 12).padding(.horizontal, 16)
    }

    /// The previous shot's right edge over the left of the preview, to line up the overlap.
    @ViewBuilder private var ghost: some View {
        if let last = shots.last {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height, k = PanoramaGuide.overlap
                Image(uiImage: last).resizable().scaledToFill()
                    .frame(width: w, height: h).offset(x: -(1 - k) * w)
                    .frame(width: k * w, height: h, alignment: .leading).clipped()
                    .opacity(0.4)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.onMedia.opacity(0.8)).frame(width: 2) }
            }
            .ignoresSafeArea().allowsHitTesting(false)
        }
    }

    /// A dot on a track: centred and green when the next shot lines up.
    private func level(_ g: PanoramaGuide) -> some View {
        let span = 30.0
        let x = g.taken == 0 || g.done ? 0 : min(max(g.offset / span, -1), 1)
        return ZStack {
            Capsule().fill(Theme.onMedia.opacity(0.3)).frame(width: 240, height: 6)
            Rectangle().fill(Theme.onMedia).frame(width: 2, height: 22)
            Circle().fill(g.ready ? Theme.success : Theme.pending).frame(width: 22, height: 22)
                .offset(x: x * 120)
        }
        .frame(height: 30).padding(.bottom, 12)
        .opacity(g.taken == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            Button("ยกเลิก") { done(nil); dismiss() }
                .font(.sarabunFixed(17, .semibold)).foregroundStyle(Theme.onMedia)
                .frame(minWidth: 90, minHeight: 44, alignment: .leading)
            Spacer()
            shutter
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(shots.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 28, height: 40).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if !cam.ultraWide && shots.isEmpty {
                    Button(multi ? "ภาพเดียว" : "3 ภาพ") { toggleMode() }
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onMedia)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Theme.onMedia.opacity(0.2), in: Capsule())
                }
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 12)
        .background(.black.opacity(0.35))
    }

    private var shutter: some View {
        let ready = !busy && (guide?.ready ?? true)
        return Button(action: shoot) {
            ZStack {
                Circle().stroke(Theme.onMedia, lineWidth: 4).frame(width: 72, height: 72)
                Circle().fill(ready ? Theme.onMedia : Theme.onMedia.opacity(0.35)).frame(width: 58, height: 58)
            }
            .frame(width: 80, height: 80)
        }
        .disabled(!ready)
        .accessibilityLabel("ถ่ายภาพ")
    }

    // MARK: flow

    private func toggleMode() {
        guide = multi ? nil : PanoramaGuide(horizontalFOV: cam.fov(portrait: false))
    }

    private func shoot() {
        busy = true
        if var g = guide, g.taken == 0 {
            // the field of view depends on how the device is held for the first shot
            g = PanoramaGuide(horizontalFOV: cam.fov(portrait: cam.portrait))
            guide = g
        }
        if guide == nil || guide?.taken == 1 { stamp = sensors.snapshot() }
        Task {
            let img = await cam.capture()
            busy = false
            guard let img else { return }
            guard var g = guide else { return check(img) }
            g.shot(); guide = g
            shots.append(img)
            if g.done { check(Self.strip(shots)) }
        }
    }

    private func check(_ img: UIImage) {
        busy = true
        Task {
            let found = await PhotoCheck.issues(img)
            busy = false
            if found.isEmpty { finish(img) } else { result = img; issues = found }
        }
    }

    private func restart() {
        result = nil; issues = []; shots = []
        if guide != nil { guide = PanoramaGuide(horizontalFOV: cam.fov(portrait: false)) }
    }

    private func finish(_ img: UIImage) {
        model.captureStamp = (stamp ?? sensors.snapshot(), Date(), shots.count > 1)
        done(img)
        dismiss()
    }

    /// The shots side by side at one height, with a thin white gap.
    static func strip(_ images: [UIImage], height: CGFloat = 1200) -> UIImage {
        let gap: CGFloat = 12
        let widths = images.map { $0.size.width / max($0.size.height, 1) * height }
        let size = CGSize(width: widths.reduce(0, +) + gap * CGFloat(max(images.count - 1, 0)), height: height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            var x: CGFloat = 0
            for (img, w) in zip(images, widths) {
                img.draw(in: CGRect(x: x, y: 0, width: w, height: height))
                x += w + gap
            }
        }
    }
}

/// The capture session: the ultra-wide lens when there is one, else the wide one; motion samples for the guide.
@MainActor
final class WideCapture: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let ultraWide: Bool
    var onMotion: ((SIMD3<Double>, SIMD3<Double>, Double) -> Void)?
    private(set) var portrait = false
    private let device: AVCaptureDevice?
    private let output = AVCapturePhotoOutput()
    private let motion = CMMotionManager()
    private var lastSample: TimeInterval?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var pending: CheckedContinuation<UIImage?, Never>?
    fileprivate weak var preview: AVCaptureVideoPreviewLayer? { didSet { attachRotation() } }
    private var rotationWatch: NSKeyValueObservation?

    override init() {
        let uw = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        ultraWide = uw != nil
        device = uw ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        super.init()
    }

    /// The lens's horizontal field of view as held, in degrees.
    func fov(portrait: Bool) -> Double {
        PanoramaGuide.horizontalFOV(sensorFOV: Double(device?.activeFormat.videoFieldOfView ?? 65), portrait: portrait)
    }

    func start() {
        if let device, let input = try? AVCaptureDeviceInput(device: device) {
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            output.maxPhotoQualityPrioritization = .balanced
            session.commitConfiguration()
            attachRotation()
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
                guard let m else { return }
                MainActor.assumeIsolated { self?.sample(m) }
            }
        }
    }

    private func sample(_ m: CMDeviceMotion) {
        let g = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
        portrait = abs(g.y) > abs(g.x)
        let dt = lastSample.map { m.timestamp - $0 } ?? 0
        lastSample = m.timestamp
        onMotion?(SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z), g, dt)
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        rotationWatch = nil
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    private func attachRotation() {
        guard let device, let preview else { return }
        let r = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotation = r
        preview.connection?.videoRotationAngle = r.videoRotationAngleForHorizonLevelPreview
        rotationWatch = r.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] r, _ in
            let angle = r.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.preview?.connection?.videoRotationAngle = angle }
        }
    }

    func capture() async -> UIImage? {
        guard session.isRunning, pending == nil else { return nil }
        if let r = rotation, let c = output.connection(with: .video), c.isVideoRotationAngleSupported(r.videoRotationAngleForHorizonLevelCapture) {
            c.videoRotationAngle = r.videoRotationAngleForHorizonLevelCapture
        }
        return await withCheckedContinuation { c in
            pending = c
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            pending?.resume(returning: img)
            pending = nil
        }
    }
}

private struct WidePreview: UIViewRepresentable {
    let cam: WideCapture

    final class Host: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Host {
        let v = Host()
        v.preview.session = cam.session
        v.preview.videoGravity = .resizeAspectFill
        cam.preview = v.preview
        return v
    }
    func updateUIView(_ v: Host, context: Context) {}
}
#endif
