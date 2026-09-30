#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreLocation
import SurveyCore

/// Satellite preview of the job's GPS on A1: pick a zoom level for the report's site picture and drag the pin to move the GPS.
struct SiteMapPreview: View {
    @Binding var gps: String
    @Binding var zoom: Int
    let googleKey: String
    var height: CGFloat = 280

    @State private var image: UIImage?
    @State private var loading = false
    @State private var failure: String?
    @State private var drag: CGSize = .zero
    @State private var frameSize: CGSize = .zero

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
                if coordinate != nil { pin }
            }
            .overlay(alignment: .topLeading) { levelPicker.padding(10) }
            .overlay(alignment: .topTrailing) { zoomButtons.padding(10) }
            .overlay(alignment: .bottomLeading) {
                if coordinate != nil { tag(Text("ลากหมุดเพื่อปรับตำแหน่ง").font(.system(size: 12)).foregroundStyle(Home.muted)).padding(10) }
            }
            .overlay(alignment: .bottomTrailing) { if coordinate != nil { scaleBar(size).padding(10) } }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { frameSize = $0 }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.2)))
        .task(id: "\(gps)|\(zoom)") { await load() }
    }

    // MARK: pin

    /// The fetched picture has its own marker at the centre; this one sits on it and follows the finger.
    var pin: some View {
        ZStack {
            Circle().fill(Home.primary.opacity(0.18)).frame(width: 44, height: 44)
            Image(systemName: "mappin").font(.system(size: 30, weight: .bold)).foregroundStyle(Home.danger).offset(y: -12)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 60, height: 60).contentShape(Rectangle())
        .offset(drag)
        .gesture(DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in move(by: g.translation); drag = .zero })
        .accessibilityLabel("หมุดตำแหน่ง")
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
                    VStack(spacing: 0) {
                        Text(l.name).font(.system(size: 13, weight: on ? .bold : .regular))
                        Text("\(Int(l.meters)) ม.").font(.system(size: 11)).foregroundStyle(on ? Home.navy : Home.muted)
                    }
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(on ? Home.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
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

    var zoomButtons: some View {
        VStack(spacing: 0) {
            zoomButton("plus", "ซูมเข้า", +1).disabled(zoom >= Self.zoomRange.upperBound)
            Rectangle().fill(Home.navy.opacity(0.12)).frame(width: 44, height: 1)
            zoomButton("minus", "ซูมออก", -1).disabled(zoom <= Self.zoomRange.lowerBound)
        }
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: Home.navy.opacity(0.2), radius: 2, y: 1)
    }

    func zoomButton(_ symbol: String, _ label: String, _ step: Int) -> some View {
        Button { zoom += step } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Home.primary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
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
            let img = try await MapImage.fetch(gps: gps, zoom: zoom, googleKey: googleKey)
            guard !Task.isCancelled else { return }
            image = img; failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            image = nil; failure = error.localizedDescription
        }
    }
}
#endif
