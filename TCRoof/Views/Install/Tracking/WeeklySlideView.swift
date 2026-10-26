import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// One slide of the customer's `Weekly Report Template` (docs/ui/install-tracking-ipad-weekly-report §4.3), drawn at the
/// board's 1920 × 1080 from the same `WeeklySlides.Content` the .pptx is written from, and scaled to the width it is
/// given. The rail, the viewer and the .pptx sheet show it. The colours are the template's (a document, like the PDF),
/// not the app's `Theme`.
struct WeeklySlideView: View {
    /// The slide: its kind, number and (a photo slide) page.
    let slide: WeeklySlides.Outline
    let data: WeeklySlides.Content
    /// The week's photos by id.
    var photos: [UUID: UIImage] = [:]

    static let size = CGSize(width: 1920, height: 1080)

    var body: some View {
        GeometryReader { g in
            let k = g.size.width / Self.size.width
            canvas
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("สไลด์ \(slide.number) \(slide.label)")
    }

    private var kind: WeeklySlides.Kind { slide.kind }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Tpl.paper
            if kind == .cover { cover } else { frame }
            switch kind {
            case .cover: EmptyView()
            case .agenda: agenda
            case .progress: progress
            case .daily: daily
            case .photos: photoRow(slide.page)
            case .weather: weather
            case .problems: problems
            }
            text("\(slide.number)", 1386, 1003, 432, 58, size: 12.6, color: Tpl.pageInk, align: .trailing)
        }
    }

    // MARK: pieces

    /// A box at (x, y) on the 1920 × 1080 slide.
    private func at<V: View>(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ v: V) -> some View {
        v.frame(width: w, height: h).offset(x: x, y: y)
    }

    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, size: CGFloat, bold: Bool = false,
                      color: Color = Tpl.ink, align: TextAlignment = .leading, italic: Bool = false) -> some View {
        let frameAlign: Alignment = align == .center ? .center : align == .trailing ? .trailing : .leading
        return at(x, y, w, h, Text(s).font(.sarabunFixed(size, bold ? .bold : .regular)).italic(italic).foregroundStyle(color)
            .multilineTextAlignment(align).lineLimit(nil).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign))
    }

    private func picture(_ name: String) -> Image? { Tpl.picture(name).map(Image.init(uiImage:)) }

    // MARK: slides

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            at(0, 80, 1920, 110, Tpl.band)
            if let seal = picture("logo-pea-seal") { at(1608, 28, 228, 214, seal.resizable().scaledToFit()) }
            text("Weekly Report", 160, 283, 1600, 146, size: 75.6, bold: true, color: Tpl.title, align: .center)
            text((data.project + [data.station]).joined(separator: "\n"), 170, 486, 1580, 305, size: 53.2, bold: true, color: Tpl.coverInk, align: .center)
            text(data.range, 99, 887, 1700, 102, size: 50.4, bold: true, color: Tpl.coverInk, align: .center)
        }
    }

    /// The band with its yellow title and the template's mark at its left.
    private var frame: some View {
        ZStack(alignment: .topLeading) {
            at(0, 49, 1920, 92, Tpl.band)
            text(kind.bandTitle, 0, 42, 1920, 92, size: kind == .agenda || kind == .weather ? 56 : 50.4, color: Tpl.bandTitle, align: .center)
            at(35, 6, 60, 156, Rectangle().fill(Tpl.markGrey).overlay(Rectangle().strokeBorder(Tpl.markGreyLine, lineWidth: 10)))
            at(76, 15, 63, 83, Rectangle().fill(Tpl.markYellow).overlay(Rectangle().strokeBorder(Tpl.markYellowLine, lineWidth: 10)))
            at(126, 49, 43, 56, Arrow().fill(Tpl.markArrow).overlay(Arrow().stroke(Tpl.markArrowLine, lineWidth: 8)))
        }
    }

    private var agenda: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(["CONSTRUCTION PROGRESS", "Weather Report", "ปัญหาและอุปสรรค"].enumerated()), id: \.offset) { i, item in
                let y = 205 + 150 * CGFloat(i)
                if let hex = picture("agenda-hex-\(i + 1)") { at(118, y, 140, 120, hex.resizable().scaledToFit()) }
                text(item, 300, y + 26, 1400, 68, size: 39.2)
                at(258, y + 110, 1500, 4, Line().stroke(Tpl.dots, style: StrokeStyle(lineWidth: 4, dash: [4, 8])))
                at(1752, y + 109, 10, 10, Circle().fill(Tpl.dot))
            }
        }
    }

    private var progress: some View {
        ZStack(alignment: .topLeading) {
            text("ความก้าวหน้าของงาน", 64, 168, 1000, 68, size: 39.2, bold: true)
            at(64, 262, 1300, 668, Rectangle().fill(Tpl.chartBack).overlay(Rectangle().strokeBorder(Tpl.chartLine, lineWidth: 2)))
            at(1050, 300, 22, 22, Tpl.planBar)
            text("แผน", 1078, 290, 80, 40, size: 24)
            at(1170, 300, 22, 22, Tpl.band)
            text("จริง", 1198, 290, 80, 40, size: 24)
            if data.bars.isEmpty {
                text("ยังไม่มีแผน MP", 140, 560, 1180, 60, size: 33.6, color: Tpl.pageInk, align: .center)
            } else {
                bars
            }
            at(1366, 443, 478, 286, Tpl.boxGrey)
            text(["% WORK PROGRESS", "PLAN : \(Self.pct(data.planned)) %", "ACTUAL : \(Self.pct(data.actual)) %",
                  "STATUS : \(data.status ?? "0") %"].joined(separator: "\n"), 1394, 443, 450, 286, size: 39.2, color: Tpl.paper)
            at(554, 960, 812, 58, Rectangle().strokeBorder(Tpl.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            text(data.period, 554, 960, 812, 58, size: 25.2, align: .center)
        }
    }

    static func pct(_ x: Double?) -> String { String(Int((x ?? 0).rounded())) }

    /// Six weeks, plan and actual side by side; 60 % fills the chart until a week goes past it.
    private var bars: some View {
        let list = data.bars, top = max(60, list.map { max($0.planned, $0.actual) }.max() ?? 0)
        let gap: CGFloat = 40, groupW = (1180 - gap * CGFloat(list.count - 1)) / CGFloat(list.count)
        let full: CGFloat = 476, base: CGFloat = 860, barW = (groupW - 8) / 2
        return ZStack(alignment: .topLeading) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, b in
                let x = 140 + CGFloat(i) * (groupW + gap)
                let ph = full * b.planned / top, ah = full * b.actual / top
                at(x, base - ph, barW, max(ph, 0.5), Tpl.planBar)
                at(x + barW + 8, base - ah, barW, max(ah, 0.5), b.current ? Tpl.band : Tpl.actualBar)
                text(Self.pct(b.actual) + "%", x, base - full - 48, groupW, 44, size: 28, bold: true, align: .center)
                text(b.label, x, 870, groupW, 44, size: 28, bold: b.current, align: .center)
            }
            at(140, base - 1.5, 1180, 3, Tpl.axis)
        }
    }

    private var daily: some View {
        let widths: [CGFloat] = [95, 126, 186, 1281]
        return ZStack(alignment: .topLeading) {
            text(data.tableLine, 109, 141, 1499, 69, size: 33.6, bold: true, color: Tpl.coverInk)
            VStack(spacing: 0) {
                tableRow(["ลำดับ", "สัปดาห์ที่", "วันที่", "การดำเนินงาน"], widths: widths, height: 50, header: true, waiting: false)
                ForEach(data.rows, id: \.number) { r in
                    tableRow([String(r.number), String(data.weekNumber), r.dateText, r.lines.joined(separator: "\n")],
                             widths: widths, height: 80, header: false, waiting: r.state == .waiting)
                }
            }
            .offset(x: 116, y: 216)
        }
    }

    private func tableRow(_ cells: [String], widths: [CGFloat], height: CGFloat, header: Bool, waiting: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { c in
                let last = c == cells.count - 1
                ZStack(alignment: header || !last ? .center : .topLeading) {
                    header ? Tpl.band : Tpl.paper
                    if waiting && last {
                        Rectangle().fill(Tpl.waitFill)
                            .overlay(Rectangle().strokeBorder(Tpl.waitInk, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                            .padding(6)
                    }
                    Text(cells[c]).font(.sarabunFixed(header ? 25.2 : 22.4)).italic(waiting && last)
                        .foregroundStyle(header ? Tpl.paper : waiting && last ? Tpl.waitInk : Tpl.ink)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: header || !last ? .center : .leading)
                        .frame(maxHeight: .infinity, alignment: header ? .center : .top)
                }
                .frame(width: widths[c], height: height)
                .overlay(Rectangle().strokeBorder(Tpl.tableLine, lineWidth: 1))
            }
        }
    }

    /// Two photos side by side over their dashed captions; a last single photo centred.
    private func photoRow(_ page: Int) -> some View {
        let list = data.photos(page: page)
        return ZStack(alignment: .topLeading) {
            text("PROGRESS FOR THIS WEEK", 69, 165, 1200, 82, size: 39.2)
            ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                let x: CGFloat = list.count == 1 ? 504 : 40 + CGFloat(i) * 936
                at(x, 274, 911, 576, Tpl.photoBack)
                if let img = photos[p.id] { at(x, 274, 911, 576, Image(uiImage: img).resizable().scaledToFit()) }
                at(x, 886, 911, 58, Rectangle().strokeBorder(Tpl.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                text(p.caption, x, 886, 911, 58, size: 25.2, align: .center)
            }
            if list.isEmpty { text("ไม่มีรูปในรายงานประจำวัน", 40, 540, 1840, 60, size: 33.6, color: Tpl.pageInk, align: .center) }
        }
    }

    /// The customer's weather grid: a blue strip of day names, the icon, the words and the date, a column a day.
    private var weather: some View {
        let w: CGFloat = 1320 / 7
        return ZStack(alignment: .topLeading) {
            at(353, 239, 1320, 110, LinearGradient(colors: [Tpl.paper, Tpl.wxTop], startPoint: .top, endPoint: .bottom)
                .overlay(Rectangle().strokeBorder(Tpl.wxLine, lineWidth: 2)))
            ForEach(Array(data.weather.enumerated()), id: \.offset) { i, d in
                let x = 357 + CGFloat(i) * w
                text(d.name, x, 258, w, 82, size: 39.2, bold: true, color: Tpl.color(d.colour), align: .center)
                at(x, 367, w, 241, Rectangle().fill(Tpl.wxIcon).overlay(Rectangle().strokeBorder(Tpl.wxIconLine, lineWidth: 3)))
                if let icon = d.icon, let img = picture(icon.rawValue) { at(x + (w - 150) / 2, 412, 150, 150, img.resizable().scaledToFit()) }
                at(x, 608, w, 215, LinearGradient(colors: [Tpl.wxTextTop, Tpl.wxTextBottom], startPoint: .top, endPoint: .bottom)
                    .overlay(Rectangle().strokeBorder(Tpl.ink, lineWidth: 3)))
                text(d.text, x, 608, w, 215, size: 33.6, align: .center)
                at(x, 823, w, 108, LinearGradient(colors: [Tpl.dateTop, Tpl.dateBottom], startPoint: .top, endPoint: .bottom)
                    .overlay(Rectangle().strokeBorder(Tpl.ink, lineWidth: 3)))
                text(d.date, x, 823, w, 108, size: 44.8, color: Tpl.dateInk, align: .center)
            }
        }
    }

    private var problems: some View {
        let bullets: ([String]) -> [String] = { $0.isEmpty ? ["• ไม่มี"] : $0.map { "• " + $0 } }
        let body = Text("ปัญหาและอุปสรรคระหว่างปฏิบัติงาน\n").bold() + Text(bullets(data.problems).joined(separator: "\n") + "\n")
            + Text("แนวทางแก้ไข\n").bold() + Text(bullets(data.fixes).joined(separator: "\n"))
        return at(195, 260, 1593, 720, body.font(.sarabunFixed(37.1)).foregroundStyle(Tpl.ink).lineSpacing(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }

    private struct Arrow: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
            }
        }
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// The customer's template colours and pictures.
private enum Tpl {
    static func color(_ hex: String) -> Color {
        let v = UInt32(hex, radix: 16) ?? 0
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let paper = Theme.paper, ink = color("000000"), pageInk = color("898989"), coverInk = color("6E747A")
    static let band = color("4472C4"), bandTitle = color("FFFF00"), title = color("002060")
    static let markGrey = color("808080"), markGreyLine = color("A6A6A6"), markYellow = color("FFC000"), markYellowLine = color("FFFF00")
    static let markArrow = color("F4B183"), markArrowLine = color("C55A11")
    static let dots = color("C0C0C0"), dot = color("A6A6A6")
    static let chartBack = color("FAFBFD"), chartLine = color("D0D7E2"), planBar = color("BFC9D9"), actualBar = color("8FAADC")
    static let axis = color("333333"), boxGrey = color("808080")
    static let tableLine = color("1F4E79"), waitFill = color("FFF3E6"), waitInk = color("C55A11"), photoBack = color("F2F4F7")
    static let wxTop = color("0070C0"), wxMid = color("DCE6F4"), wxLine = color("2F5597"), wxIcon = color("5B9BD5"), wxIconLine = color("002060")
    static let wxTextTop = color("D9E2F3"), wxTextBottom = color("A9C7EA"), dateInk = color("FFC000"), dateTop = color("1F4E79"), dateBottom = color("002060")

    /// The template's pictures, decoded once.
    @MainActor static var pictures: [String: UIImage] = [:]
    @MainActor static func picture(_ name: String) -> UIImage? {
        if let p = pictures[name] { return p }
        let p = WeeklySlides.templatePicture(name).flatMap(UIImage.init(data:))
        pictures[name] = p
        return p
    }
}
