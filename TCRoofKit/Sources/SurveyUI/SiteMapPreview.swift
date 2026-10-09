#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreLocation
import TCRoofCore

/// The picture's own proportions on iPad; a fixed 170 pt on iPhone.
private struct MapShape: ViewModifier {
    let phone: Bool
    func body(content: Content) -> some View {
        if phone { content.frame(height: 170) } else { content.aspectRatio(1 / SiteMapPreview.aspect, contentMode: .fit) }
    }
}

/// Satellite preview of the job's GPS on A1: pick a zoom level for the report's site picture, frame the part the report
/// uses (`MapCrop`), and long-press the pin to move the GPS.
/// The view has the picture's own proportions, so a frame in % of the view is the same % of the picture.
struct SiteMapPreview: View {
    @Binding var gps: String
    @Binding var zoom: Int
    @Binding var crop: MapCrop
    let keys: MapImage.Keys
    /// iPhone A1 (docs/ui/survey-a1-iphone): 170 pt high, smaller zoom chips, a hint label, no report frame
    /// (the frame is in percent of the picture's own proportions, which this height doesn't keep).
    var phone = false

    @State private var image: UIImage?
    @State private var loading = false
    @State private var failure: String?
    @State private var drag: CGSize = .zero
    @State private var pinLifted = false
    @State private var frameSize: CGSize = .zero
    /// The frame while a finger moves it; written to the job when the finger lifts.
    @State private var liveCrop: MapCrop?

    static let cropBlue = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)
    static let aspect = MapImage.size.height / MapImage.size.width

    /// Named levels; each is the zoom whose picture is closest to that width at the site's latitude.
    static let levels: [(name: String, meters: Double)] = [("พื้นที่", 500), ("สถานี", 200), ("อาคาร", 50)]
    static let zoomRange = 3...21

    static func zoom(across meters: Double, lat: Double) -> Int {
        let z = log2(MapImage.metersAcross(lat: lat, zoom: 0) / meters)
        return min(max(Int(z.rounded()), zoomRange.lowerBound), zoomRange.upperBound)
    }

    var coordinate: CLLocationCoordinate2D? { MapImage.coordinate(from: gps) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(red: 0.91, green: 0.933, blue: 0.961)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                } else if loading {
                    ProgressView()
                } else {
                    Text(failure ?? "ใส่พิกัดด้านล่างเพื่อดูแผนที่").font(.footnote).foregroundStyle(Home.muted)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                if coordinate != nil { if !phone { cropLayer(size) }; pin }
            }
            .overlay(alignment: .topLeading) { levelPicker.padding(phone ? 8 : 10) }
            .overlay(alignment: .topTrailing) { zoomButtons.padding(phone ? 8 : 10) }
            .overlay(alignment: .bottomLeading) { if phone { tag(Text("ลากหมุดเพื่อปรับ · ระดับซูมนี้ใช้ในรายงาน").font(.system(size: 11)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8)).padding(8) } }
            .overlay(alignment: .bottomTrailing) { if coordinate != nil { scaleBar(size).padding(phone ? 8 : 10) } }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { frameSize = $0 }
        .modifier(MapShape(phone: phone))
        .clipShape(RoundedRectangle(cornerRadius: phone ? 12 : 10))
        .overlay(RoundedRectangle(cornerRadius: phone ? 12 : 10).stroke(phone ? Home.hairline : Home.navy.opacity(0.2)))
        .task(id: "\(gps)|\(zoom)") { await load() }
    }

    // MARK: pin

    /// The fetched picture has its own marker at the centre; this one sits on it. Long-press, then drag, to move it
    /// (a plain drag belongs to the report frame underneath). The frame stays where it is.
    var pin: some View {
        // a1-map-pin is 48 × 50 with its accuracy halo centred 1 pt below the middle; the halo's centre is the site
        A2Icon(name: "a1-map-pin", fallback: "mappin", size: nil).frame(width: 48, height: 50).offset(y: -1)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .scaleEffect(pinLifted ? 1.15 : 1)
            .frame(width: 60, height: 60).contentShape(Rectangle())
            .offset(drag)
            .gesture(LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { v in
                    guard case .second(true, let d) = v else { return }
                    pinLifted = true
                    drag = d?.translation ?? .zero
                }
                .onEnded { v in
                    if case .second(true, let d?) = v { move(by: d.translation) }
                    drag = .zero; pinLifted = false
                })
            .animation(.easeOut(duration: 0.15), value: pinLifted)
            .accessibilityLabel("หมุดตำแหน่ง")
            .accessibilityHint("แตะค้างแล้วลากเพื่อย้าย")
    }

    // MARK: report frame

    /// Blue frame with four corner handles; outside it the map is dimmed.
    func cropLayer(_ size: CGSize) -> some View {
        let c = liveCrop ?? crop
        let r = c.rect(in: size)
        let across = MapImage.metersAcross(lat: coordinate?.latitude ?? 15, zoom: zoom)
        return ZStack(alignment: .topLeading) {
            Path { p in p.addRect(CGRect(origin: .zero, size: size)); p.addRect(r) }
                .fill(Color(red: 22 / 255, green: 50 / 255, blue: 92 / 255).opacity(0.32), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Rectangle().fill(Color.white.opacity(0.001))
                .overlay(Rectangle().stroke(Self.cropBlue, lineWidth: 2))
                .frame(width: r.width, height: r.height)
                .gesture(cropDrag(size) { $0.moved(dx: $1.width, dy: $1.height) })
                .offset(x: r.minX, y: r.minY)
            Text(c.label(across: across, aspect: Self.aspect))
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Self.cropBlue, in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
                .offset(x: r.minX + 6, y: r.minY + 6)
                .allowsHitTesting(false)
            ForEach(MapCrop.Corner.allCases, id: \.self) { k in
                handle.gesture(cropDrag(size) { $0.resized(k, dx: $1.width, dy: $1.height) })
                    .offset(x: (k == .nw || k == .sw ? r.minX : r.maxX) - 22, y: (k == .nw || k == .ne ? r.minY : r.maxY) - 22)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.label(across: across, aspect: Self.aspect))
    }

    /// 16-pt white square, blue border, in a 44-pt hit area centred on the corner.
    var handle: some View {
        RoundedRectangle(cornerRadius: 3).fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Self.cropBlue, lineWidth: 2.5))
            .frame(width: 16, height: 16)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    /// Applies `change` (translation in % of the map) to the frame as it was when the finger went down.
    func cropDrag(_ size: CGSize, change: @escaping (MapCrop, CGSize) -> MapCrop) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let d = CGSize(width: g.translation.width / size.width * 100, height: g.translation.height / size.height * 100)
                liveCrop = change(crop, d)
            }
            .onEnded { _ in
                if let liveCrop { crop = liveCrop }
                liveCrop = nil
            }
    }

    /// Metres per point of the preview: the 640-pt picture is scaled to fill the frame.
    func metersPerPoint(_ size: CGSize, lat: Double) -> Double {
        let k = max(size.width / MapImage.size.width, size.height / MapImage.size.height)
        return MapImage.metersAcross(lat: lat, zoom: zoom) / (MapImage.size.width * k)
    }

    func move(by t: CGSize) {
        guard let c = coordinate, t != .zero, frameSize != .zero else { return }
        let m = metersPerPoint(frameSize, lat: c.latitude)
        let lat = c.latitude - t.height * m / 111_320
        let lon = c.longitude + t.width * m / (111_320 * cos(c.latitude * .pi / 180))
        gps = GPS.format(lat, lon)
    }

    // MARK: controls

    var levelPicker: some View {
        let lat = coordinate?.latitude ?? 15
        return HStack(spacing: 2) {
            ForEach(Self.levels, id: \.name) { l in
                let z = Self.zoom(across: l.meters, lat: lat)
                let on = z == zoom
                Button { zoom = z } label: {
                    levelLabel(l, on: on)
                    .padding(.horizontal, phone ? 8 : 10).frame(minHeight: phone ? 28 : 44)
                    .background(on ? Home.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
                    // the 28-pt chip keeps a 44-pt tap area
                    .contentShape(Rectangle().inset(by: phone ? -8 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .foregroundStyle(Home.navy)
        .padding(3)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: Home.navy.opacity(0.2), radius: 2, y: 1)
    }

    /// Two lines on iPad ("สถานี" over "200 ม."); one line on iPhone ("สถานี 200 ม.").
    @ViewBuilder func levelLabel(_ l: (name: String, meters: Double), on: Bool) -> some View {
        if phone {
            HStack(spacing: 3) {
                Text(l.name).font(.system(size: 12, weight: on ? .bold : .regular))
                Text("\(Int(l.meters)) ม.").font(.system(size: 11, weight: on ? .bold : .regular)).foregroundStyle(on ? Home.navy : Home.muted)
            }
            .lineLimit(1).fixedSize()
        } else {
            VStack(spacing: 0) {
                Text(l.name).font(.system(size: 13, weight: on ? .bold : .regular))
                Text("\(Int(l.meters)) ม.").font(.system(size: 11)).foregroundStyle(on ? Home.navy : Home.muted)
            }
        }
    }

    var zoomButtons: some View {
        VStack(spacing: 0) {
            zoomButton("ui-plus", "plus", "ซูมเข้า", +1).disabled(zoom >= Self.zoomRange.upperBound)
            Rectangle().fill(Home.navy.opacity(0.12)).frame(width: 44, height: 1)
            zoomButton("ui-minus", "minus", "ซูมออก", -1).disabled(zoom <= Self.zoomRange.lowerBound)
        }
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: Home.navy.opacity(0.2), radius: 2, y: 1)
    }

    func zoomButton(_ icon: String, _ symbol: String, _ label: String, _ step: Int) -> some View {
        Button { zoom += step } label: {
            A2Icon(name: icon, fallback: symbol, size: 20).foregroundStyle(Home.primary)
                .frame(width: 44, height: phone ? 40 : 44).contentShape(Rectangle().inset(by: phone ? -2 : 0))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    @ViewBuilder func scaleBar(_ size: CGSize) -> some View {
        let lat = coordinate?.latitude ?? 15
        let across = metersPerPoint(size, lat: lat) * size.width
        let length = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000].last { $0 <= across * 0.2 } ?? 1
        tag(HStack(spacing: 6) {
            let w = length / across * size.width
            Path { p in p.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 5), CGPoint(x: w, y: 5), CGPoint(x: w, y: 0)]) }
                .stroke(Home.navy, lineWidth: 1.5).frame(width: w, height: 5)
            Text(length >= 1000 ? "\(Int(length / 1000)) กม." : "\(Int(length)) ม.").font(.system(size: 11))
        })
    }

    func tag<V: View>(_ v: V) -> some View {
        v.padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: loading

    func load() async {
        guard coordinate != nil else { image = nil; failure = nil; return }
        // wait for typing to settle before asking for a new picture
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            let img = try await MapImage.fetch(gps: gps, zoom: zoom, keys: keys)
            guard !Task.isCancelled else { return }
            image = img; failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            image = nil; failure = error.localizedDescription
        }
    }
}
#endif
