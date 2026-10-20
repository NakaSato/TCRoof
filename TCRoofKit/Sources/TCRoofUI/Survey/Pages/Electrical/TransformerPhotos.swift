#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// Every transformer must be photographed from all sides plus its nameplate, and must name the MDB it feeds.
struct TransformerPhotosView: View {
    @Binding var values: Values
    let jobID: UUID

    var body: some View {
        let trs = values.transformers("trafos")
        ForEach(Array(trs.enumerated()), id: \.element.id) { i, t in
            if Schema.transformerPresent(values, i) { card(i, t) }
        }
    }

    func card(_ i: Int, _ t: Transformer) -> some View {
        let missing = Schema.transformerAngles.filter { values.photo("tr\(i)_\($0.key)") == nil }
        let mdbs = t.mdb.enumerated().filter { !$0.element.isEmpty }.map { "MDB\($0.offset + 1)" }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ภาพหม้อแปลง TR\(i + 1)" + (t.kva.isEmpty ? "" : " | \(t.kva) kVA")).font(.sarabun(17, .semibold, relativeTo: .headline))
                Spacer()
                if missing.isEmpty { Label("ครบทุกมุม", systemImage: "checkmark.seal.fill").foregroundStyle(Paper.tick).font(.sarabun(16, relativeTo: .callout)) }
                else { Label("ขาด \(missing.count) ภาพ", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.dangerText).font(.sarabun(16, relativeTo: .callout)) }
            }
            Text("บังคับถ่าย: ด้านหน้า ด้านหลัง ด้านซ้าย ด้านขวา ป้ายพิกัด และมุมกว้าง").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(Schema.transformerAngles, id: \.key) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(a.label).font(.sarabun(12, .semibold, relativeTo: .caption))
                            Image(systemName: values.photo("tr\(i)_\(a.key)") == nil ? "asterisk" : "checkmark.circle.fill")
                                .font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(values.photo("tr\(i)_\(a.key)") == nil ? Theme.danger : Paper.tick)
                        }
                        PhotoField(photo: photoBinding("tr\(i)_\(a.key)"), jobID: jobID, label: "TR\(i + 1) " + a.label, height: 150)
                            .photoShot("tr\(i)_\(a.key)")
                    }
                }
            }
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ตู้ MDB ปลายสาย").font(.sarabun(16, .medium, relativeTo: .callout))
                Menu {
                    ForEach(mdbs.isEmpty ? (1...6).map { "MDB\($0)" } : mdbs, id: \.self) { m in Button(m) { values["tr\(i)_feed"] = .text(m) } }
                } label: {
                    HStack {
                        Text(values.text("tr\(i)_feed").isEmpty ? "เลือกตู้" : values.text("tr\(i)_feed"))
                            .foregroundStyle(values.text("tr\(i)_feed").isEmpty ? Theme.danger : Paper.value)
                        Image(systemName: "chevron.up.chevron.down").font(.sarabun(11, relativeTo: .caption2))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                }
                TextField("หรือพิมพ์ชื่อตู้", text: textBinding("tr\(i)_feed")).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(maxWidth: 160)
            }
            TextField("ตำแหน่งตู้ MDB ปลายสาย เช่น ห้องไฟฟ้า อาคารสูบน้ำ 1", text: textBinding("tr\(i)_feedLoc")).textFieldStyle(OutlinedFieldStyle())
            PhotoField(photo: photoBinding("tr\(i)_feedPhoto"), jobID: jobID, label: "ภาพตู้ MDB ปลายสาย", height: 150).frame(maxWidth: 360)
        }
        .padding(12)
        .background(Paper.band.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(missing.isEmpty ? Paper.tick : Theme.dangerLine))
    }

    func photoBinding(_ id: String) -> Binding<Photo?> {
        Binding(get: { values.photo(id) }, set: { values[id] = $0.map { .photo($0) } })
    }
    func textBinding(_ id: String) -> Binding<String> {
        Binding(get: { values.text(id) }, set: { values[id] = $0.isEmpty ? nil : .text($0) })
    }
}
#endif
