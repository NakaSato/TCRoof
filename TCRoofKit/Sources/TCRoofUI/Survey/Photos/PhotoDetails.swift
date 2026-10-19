#if canImport(UIKit)
import SwiftUI
import MapKit
import TCRoofCore

/// Where a page wants `ภาพที่เลือก` (docs/specs/tank-drawing-swift.md, sub-step 4) instead of the plain viewer: a tap
/// on a photo opens its details, and `tags` (D1's openings) offers a tag; `normalise` checks a typed one.
struct PhotoDetailsContext {
    var tags: [String] = []
    var normalise: (String) -> String? = { _ in nil }
}

private struct PhotoDetailsKey: EnvironmentKey { static let defaultValue: PhotoDetailsContext? = nil }
extension EnvironmentValues {
    var photoDetails: PhotoDetailsContext? {
        get { self[PhotoDetailsKey.self] }
        set { self[PhotoDetailsKey.self] = newValue }
    }
}

/// `ภาพที่เลือก`: the photo, when and where it was taken, a note, the opening it shows (when the page offers tags),
/// where it was taken on a small map, and retake / delete.
struct PhotoDetailSheet: View {
    @Binding var photo: Photo?
    let image: UIImage
    let title: String
    let context: PhotoDetailsContext
    let retake: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var typed = ""
    @State private var typedBad = false
    @State private var zoom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 320)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { zoom = true }
                        .accessibilityLabel("ภาพ แตะเพื่อขยาย")
                    if let p = photo { info(p) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("หมายเหตุ").font(.sarabunFixed(14, .bold))
                        TextField("เช่น ฝาปล่องแตก", text: $note, axis: .vertical)
                            .font(.sarabunFixed(15)).lineLimit(1...4)
                            .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl))
                            .onChange(of: note) { _, t in edit { $0.note = t.isEmpty ? nil : t } }
                    }
                    if !context.tags.isEmpty { tagPicker }
                    if let p = photo, let lat = p.lat, let lon = p.lon { where_(lat, lon) }
                    HStack(spacing: 10) {
                        Button { dismiss(); retake() } label: { Label("ถ่ายใหม่", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card))
                        Button(role: .destructive) { photo = nil; dismiss() } label: {
                            Label("ลบภาพ", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    }
                }
                .padding(16)
            }
            .navigationTitle(title.isEmpty ? "ภาพที่เลือก" : title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
            .sheet(isPresented: $zoom) { PhotoViewer(image: image, title: title) }
        }
        .foregroundStyle(Theme.navy)
        .onAppear { note = photo?.note ?? "" }
    }

    func edit(_ f: (inout Photo) -> Void) {
        guard var p = photo else { return }
        f(&p)
        if p != photo { photo = p }
    }

    func info(_ p: Photo) -> some View {
        let c = Calendar(identifier: .buddhist).dateComponents([.day, .month, .year, .hour, .minute], from: p.takenAt)
        let when = String(format: "%d/%d/%d %02d:%02d", c.day ?? 0, c.month ?? 0, c.year ?? 0, c.hour ?? 0, c.minute ?? 0)
        let rows: [(String, String)] = [("ถ่ายเมื่อ", when),
                                       ("พิกัด", p.lat.flatMap { lat in p.lon.map { String(format: "%.5f, %.5f", lat, $0) } } ?? "ไม่มีพิกัด (ภาพจากคลังภาพ)"),
                                       ("ทิศกล้อง", p.heading.map { "\(Int($0.rounded()) % 360)°" } ?? "-")]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    Text(r.0).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 8)
                    Text(r.1).font(.sarabunFixed(14, .bold)).monospacedDigit()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The opening the photo shows: a menu of the tank's points, or a range typed (`V1–V10`).
    var tagPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ผูกกับจุด").font(.sarabunFixed(14, .bold))
            HStack(spacing: 8) {
                Menu {
                    Button("ไม่ผูก") { edit { $0.tag = nil } }
                    ForEach(context.tags, id: \.self) { t in Button(t) { edit { $0.tag = t } } }
                } label: {
                    Label(photo?.tag ?? "เลือกจุด", systemImage: "chevron.down").font(.sarabunFixed(15, .bold))
                        .frame(minWidth: 110, minHeight: 44)
                        .padding(.horizontal, 10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl))
                }
                TextField("หรือพิมพ์ช่วง เช่น V1–V10", text: $typed)
                    .font(.sarabunFixed(15)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(10).frame(minHeight: 44).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(typedBad ? Theme.danger : Theme.borderControl))
                    .onSubmit {
                        if let t = context.normalise(typed) { edit { $0.tag = t }; typed = ""; typedBad = false } else { typedBad = true }
                    }
            }
            if typedBad { Text("ไม่พบจุดนี้บนถัง").font(.sarabunFixed(12.5)).foregroundStyle(Theme.dangerText) }
        }
    }

    /// `จุดถ่ายภาพ`: where the camera stood.
    func where_(_ lat: Double, _ lon: Double) -> some View {
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return VStack(alignment: .leading, spacing: 6) {
            Text("จุดถ่ายภาพ").font(.sarabunFixed(14, .bold))
            Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 250, longitudinalMeters: 250))) {
                Marker("ถ่ายที่นี่", coordinate: c)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}
#endif
