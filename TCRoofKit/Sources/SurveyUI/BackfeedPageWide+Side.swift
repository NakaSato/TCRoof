#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// B4's right column: the SLD crop, the A2 crop and the equipment list.
extension BackfeedPageWide {
    func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary).lineLimit(1).fixedSize().frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    func title(_ t: String, sub: String) -> some View {
        let layout = phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(t).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
            Text(sub).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: SLD

    func sldCard(_ sl: SingleLine) -> some View {
        let drawing = SingleLineLayout.draw(sl)
        return card {
            HStack(alignment: .firstTextBaseline) {
                title("ส่วนที่เปลี่ยนใน SLD", sub: hv ? "CT/VT + รีเลย์หลังมิเตอร์ กฟภ." : "CT + รีเลย์ที่ตู้ \(ZeroExport.boardName(sl))")
                Spacer(minLength: 8)
                link("ดู SLD ทั้งหมด →", action: openDiagram)
            }
            .padding(.vertical, phone ? 0 : -10)
            Group {
                if let b = drawing.zeroExportBox, phone {
                    // too small to read when fitted to a phone's width: shown at 0.6 and scrolled sideways
                    ScrollView(.horizontal, showsIndicators: true) {
                        SLDCrop(drawing: drawing, box: b).frame(width: b.w * 0.6, height: b.h * 0.6)
                    }
                    .frame(height: b.h * 0.6)
                } else if let b = drawing.zeroExportBox {
                    SLDCrop(drawing: drawing, box: b, fill: true)
                } else {
                    Text("ยังไม่มีแผนภาพ · กรอกหม้อแปลงและ MDB ในหน้า A3 ก่อน").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: phone ? nil : .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.1)))
            .accessibilityLabel(hv ? "แผนภาพเส้นเดียวส่วนกันย้อนแรงสูง" : "แผนภาพเส้นเดียวส่วนกันย้อนแรงต่ำ")
        }
    }

    // MARK: A2

    /// "ตู้ MDP-1 · ห้องไฟฟ้า อาคารสูบน้ำ" (the board and its A3 location) or "ข้างมิเตอร์ PEA" with the symbol's name.
    func siteCaption(_ sl: SingleLine, _ mark: MapMark?) -> String {
        if hv {
            let name = mark?.label.trimmingCharacters(in: .whitespaces) ?? ""
            return "ข้างมิเตอร์ PEA" + (name.isEmpty ? "" : " · " + name)
        }
        let loc = sl.connectionBoard?.location.trimmingCharacters(in: .whitespaces) ?? ""
        return "ตู้ \(ZeroExport.boardName(sl))" + (loc.isEmpty ? "" : " · " + loc)
    }

    func siteCard(_ sl: SingleLine) -> some View {
        let mark = ZeroExport.mark(job, module: moduleID)
        return card {
            HStack(alignment: .firstTextBaseline) {
                title("ตำแหน่งบนภาพ A2", sub: "ภาพจากหน้า A2")
                Spacer(minLength: 8)
                link("เปิด A2 →", action: openSite)
            }
            .padding(.vertical, phone ? 0 : -10)
            SiteMarkCrop(job: job, mark: mark, caption: siteCaption(sl, mark), openSite: openSite)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: equipment

    func equipmentCard(_ sl: SingleLine) -> some View {
        let items = ZeroExport.equipment(job, values, sl)
        return card {
            title("อุปกรณ์ที่ต้องติดตั้ง", sub: "ตาม SLD").frame(minHeight: 24)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.teal)
                            .frame(width: 26, height: 26).background(Self.tealSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(item.sub).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The A2 site picture zoomed round one symbol (B4's กันย้อน), with A2's drawings, a ring on the symbol and a caption;
/// the whole picture with a hint when the symbol isn't placed. Read-only.
struct SiteMarkCrop: View {
    let job: Job
    let mark: MapMark?
    let caption: String
    var openSite: () -> Void = {}
    /// How far past "fill" the picture is zoomed round the symbol.
    var zoom: CGFloat = 1.5
    @Environment(SurveyModel.self) var model

    var body: some View {
        GeometryReader { geo in
            if let p = job.values.photo("siteMap"), let img = model.image(p, in: job.id) {
                stage(img, geo.size)
            } else {
                empty(noPicture: job.values.photo("siteMap") == nil).frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(PhotoSlot.stageColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func rect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        guard let m = mark else {
            let k = min(size.width / img.size.width, size.height / img.size.height)
            let w = img.size.width * k, h = img.size.height * k
            return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        }
        let k = max(size.width / img.size.width, size.height / img.size.height) * zoom
        let w = img.size.width * k, h = img.size.height * k
        let x = min(0, max(size.width - w, size.width / 2 - m.x * w)), y = min(0, max(size.height - h, size.height / 2 - m.y * h))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    func stage(_ img: UIImage, _ size: CGSize) -> some View {
        let r = rect(img, in: size)
        return ZStack(alignment: .topLeading) {
            Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            siteDrawing(job, in: r)
            if let m = mark {
                Circle().stroke(Theme.teal, lineWidth: 3).background(Circle().fill(Theme.teal.opacity(0.15)))
                    .frame(width: 46, height: 46)
                    .position(x: r.minX + m.x * r.width, y: r.minY + m.y * r.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            Text(mark == nil ? "ยังไม่มีสัญลักษณ์ กันย้อน · วางบนภาพในหน้า A2" : caption)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(mark == nil ? Theme.pending : Theme.navy)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mark == nil ? "ภาพ A2 ยังไม่มีตำแหน่งกันย้อน" : "ภาพ A2 ตำแหน่งกันย้อน " + caption)
    }

    func empty(noPicture: Bool) -> some View {
        VStack(spacing: 12) {
            if noPicture {
                Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(Theme.inkMuted)
                Text("ยังไม่มีภาพสถานที่ติดตั้งในหน้า A2").font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
                Button(action: openSite) {
                    Text("เปิด A2 เพื่อเลือกภาพ").font(.system(size: 15, weight: .bold)).padding(.horizontal, 16).frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                PhotoSlot.notDownloaded
            }
        }
        .padding(8)
    }
}

#if DEBUG
extension BackfeedPageWide {
    /// `-surveyB4 lv|lvdone|hv|hvdone` writes the states of docs/ui/survey-b4/states into the opened B4: the level, the
    /// pole (`เสาเดิม` for hvdone) and 2 or 4 generated placeholder photos, plus the example detail text.
    func openDebugState() {
        guard let state = UserDefaults.standard.string(forKey: "surveyB4"), let i = index else { return }
        let isHV = state.hasPrefix("hv"), count = state.hasSuffix("done") ? 4 : 2
        var v = job.modules[i].values
        v[ZeroExport.levelKey] = .choice(isHV ? ZeroExport.hv : ZeroExport.lv, other: "")
        v[ZeroExport.poleKey] = state == "hvdone" ? .choice("เสาเดิม", other: "") : nil
        for (k, key) in ZeroExport.photoKeys.enumerated() {
            v[key] = k < count ? model.addPhoto(Self.placeholder(k), to: job.id).map { .photo($0) } : nil
        }
        v["detail"] = .text(isHV ? "ระยะจากมิเตอร์ถึงเสาใหม่ประมาณ 8 ม. · ต้องขออนุญาต กฟภ." : "ติดตั้ง CT ที่บัสบาร์ขาออกเมน ACB · มีช่องว่างในตู้สำหรับรีเลย์")
        job.modules[i].values = v
    }

    static func placeholder(_ k: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 640, height: 400)).image { c in
            [UIColor(red: 0.35, green: 0.40, blue: 0.46, alpha: 1), UIColor(red: 0.72, green: 0.80, blue: 0.88, alpha: 1)][k % 2].setFill()
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
            UIColor(red: 0.153, green: 0.663, blue: 0.604, alpha: 1).setStroke()
            let p = UIBezierPath(rect: CGRect(x: 380, y: 140, width: 120, height: 140)); p.lineWidth = 6
            p.setLineDash([16, 10], count: 2, phase: 0); p.stroke()
        }
    }
}
#endif
#endif
