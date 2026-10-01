#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// B3 on iPad landscape (docs/ui/survey-b3): the water point on the A2 picture on the left; the water mode, the two photos
/// and the details on the right. The pin is A2's `.water` mark for this module (`WaterPoint`); field ids are unchanged.
/// iPad portrait and iPhone keep the schema form (`groupPage`).
struct WaterPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// "เปิด A2 →".
    var openSite: () -> Void = {}
    @Environment(SurveyModel.self) var model

    var rightWidth: CGFloat { min(500, max(380, width * 0.38)) }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var module: SurveyModule? { index.map { job.modules[$0] } }
    var values: Values { module?.values ?? Values() }
    var mode: WaterPoint.Mode? { WaterPoint.mode(values) }
    /// Texts that follow the mode; the design's default is "existing".
    var shownMode: WaterPoint.Mode { mode ?? .existing }

    func set(_ id: String, _ v: FieldValue?) { if let i = index { job.modules[i].values[id] = v } }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: "ตำแหน่งระบบน้ำล้างแผง")
            HStack(alignment: .top, spacing: 20) {
                pinCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 14) {
                    modeCard
                    photosCard
                    detailCard.frame(maxHeight: .infinity)
                }
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(Home.navy)
    }

    // MARK: card frame

    static let chipFill = Color(red: 0.890, green: 0.933, blue: 0.973)
    static let tileFill = Color(red: 0.961, green: 0.973, blue: 0.988)
    static let teal = Color(red: 0.153, green: 0.663, blue: 0.604)
    static let tealSoft = Color(red: 0.910, green: 0.969, blue: 0.953)
    static let line = Color(red: 0.788, green: 0.827, blue: 0.875)

    func header<Trailing: View>(_ n: Int, _ title: String, required: Bool = false, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 14, weight: .heavy)).foregroundStyle(Home.primary)
                .frame(width: 28, height: 28).background(Self.chipFill, in: RoundedRectangle(cornerRadius: 8))
            (Text(title) + (required ? Text(" *").foregroundColor(Home.danger) : Text(""))).font(.system(size: 17, weight: .bold)).lineLimit(1)
            trailing()
        }
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Home.navy.opacity(0.16)))
            .shadow(color: Home.navy.opacity(0.06), radius: 3, y: 2)
    }

    // MARK: 1 water point

    var pinCard: some View {
        card {
            header(1, "ตำแหน่งจุดจ่ายน้ำ", required: true) {
                Text("ภาพจากหน้า A2 · แตะบนภาพเพื่อย้ายจุด").font(.system(size: 12.5)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Self.tileFill, in: RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 8)
                Button(action: openSite) {
                    Text("เปิด A2 →").font(.system(size: 15, weight: .bold)).foregroundStyle(Home.primary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.primary.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            WaterPinStage(job: $job, moduleID: moduleID, mode: shownMode, openSite: openSite)
                .frame(maxHeight: .infinity)
            summaryStrip
        }
    }

    var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryTile("หลังคาที่ต้องล้าง", WaterPoint.roofNames(job))
            summaryTile("จำนวนแผง (จาก D1)", WaterPoint.panelSummary(job))
            summaryTile("แสดงผลใน", "ภาพ A2 · รายงาน")
        }
    }

    func summaryTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Home.muted)
            Text(value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.tileFill, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    // MARK: 2 water mode

    var modeCard: some View {
        card {
            header(2, "รูปแบบระบบน้ำ", required: true) { Spacer(minLength: 0) }
            HStack(spacing: 12) {
                ForEach(WaterPoint.Mode.allCases, id: \.self) { modeChoice($0) }
            }
            infoRow
        }
    }

    func modeChoice(_ m: WaterPoint.Mode) -> some View {
        let on = mode == m
        return Button { set(WaterPoint.modeKey, .choice(m.rawValue, other: "")) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(m.tag).font(.system(size: 12, weight: .bold)).foregroundStyle(on ? .white : Home.muted)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(on ? Self.teal : Self.tileFill, in: RoundedRectangle(cornerRadius: 5))
                Text(m.cardTitle).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                Text(m.cardSub).font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(on ? Self.tealSoft : Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Self.teal : Self.line, lineWidth: on ? 2 : 1))
            .background(RoundedRectangle(cornerRadius: 16).stroke(on ? Self.teal.opacity(0.14) : .clear, lineWidth: 6).padding(-1))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Self.teal, in: Circle()).padding(10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.cardTitle + " " + m.cardSub)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    var infoRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("i").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Home.primary, in: Circle())
            Text(shownMode.hint).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.tileFill, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 3 photos

    var photosCard: some View {
        let missing = WaterPoint.missingPhotos(values)
        return card {
            header(3, "ภาพประกอบ", required: true) {
                Spacer(minLength: 8)
                Text(missing == 0 ? "2/2 ภาพ ✓" : "\(2 - missing)/2 ภาพ · ขาดอีก \(missing) ภาพ")
                    .font(.system(size: 13, weight: missing == 0 ? .semibold : .bold))
                    .foregroundStyle(missing == 0 ? Home.ok : Home.danger).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 10) {
                photoTile("ภาพพื้นที่ติดตั้ง", key: "photoArea", caption: shownMode.areaCaption, hint: "ถ่ายภาพ" + shownMode.areaCaption)
                photoTile("ภาพมุมกว้าง", key: "photoWide", caption: wideCaption, hint: "ถ่ายภาพมุมกว้างของพื้นที่ติดตั้ง")
            }
        }
    }

    var wideCaption: String {
        let roofs = job.modules.filter { $0.type == .roof || $0.type == .tank }
        let name = roofs.first.map { $0.name.trimmingCharacters(in: .whitespaces).isEmpty ? $0.spec.short : $0.name }
        return (name.map { $0 + " · " } ?? "") + "จุดที่ต้องล้าง"
    }

    func photoTile(_ title: String, key: String, caption: String, hint: String) -> some View {
        let photo = values.photo(key)
        return VStack(alignment: .leading, spacing: 6) {
            (Text(title) + Text(" *").foregroundColor(Home.danger)).font(.system(size: 14, weight: .bold))
            PhotoSlot(photo: photo, jobID: job.id, hint: hint, required: true, title: title,
                      onPick: { img in if let p = model.addPhoto(img, to: job.id) { set(key, .photo(p)) } },
                      onClear: { set(key, nil) })
                .frame(height: 196)
                .overlay(alignment: .bottomLeading) {
                    if photo != nil {
                        Text(caption).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8).allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 4 details

    var detailCard: some View {
        card {
            header(4, "รายละเอียดเพิ่มเติม") { Spacer(minLength: 0) }
            TextEditor(text: Binding(get: { values.text("detail") }, set: { set("detail", $0.isEmpty ? nil : .text($0)) }))
                .font(.system(size: 16)).scrollContentBackground(.hidden).padding(8)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if values.text("detail").isEmpty {
                        Text(shownMode.placeholder).font(.system(size: 16)).foregroundStyle(Home.muted.opacity(0.8))
                            .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
                .accessibilityLabel("รายละเอียดเพิ่มเติม")
        }
    }
}
#endif
