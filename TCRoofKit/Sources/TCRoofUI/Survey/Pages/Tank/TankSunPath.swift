#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// `เส้นทางดวงอาทิตย์`: a polar sun-path diagram, north up and east right, the horizon on the rim and the zenith in the
/// middle. The chosen month's path in orange with the moment's sun, 21 มี.ค. / มิ.ย. / ธ.ค. dotted, and each object's
/// skyline seen from the tank's centre as a wedge in its kind's colour.
struct TankSunPath: View {
    let latitude: Double
    let month: Int
    let time: Double
    let scene: TankShadeScene

    var body: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in draw(&ctx, size) }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityElement()
                .accessibilityLabel("เส้นทางดวงอาทิตย์ เดือน " + RoutineReport.thaiMonthsShort[month])
            legend
        }
    }

    var legend: some View {
        let items: [(Color, String, Bool)] = [(Theme.warning, "เดือนที่เลือก", true), (Theme.inkFaint, "21 มี.ค. | มิ.ย. | ธ.ค.", true),
                                              (TankShadeScene.color(.tree), "ต้นไม้", false), (TankShadeScene.color(.building), "อาคาร", false),
                                              (TankShadeScene.color(.tower), "หอถัง", false)]
        return FlowLayout(spacing: 10) {
            ForEach(items, id: \.1) { c, t, dot in
                HStack(spacing: 4) {
                    if dot { Circle().fill(c).frame(width: 8, height: 8) } else { RoundedRectangle(cornerRadius: 2).fill(c.opacity(0.6)).frame(width: 10, height: 10) }
                    Text(t).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    func point(_ alt: Double, _ compass: Double, _ c: CGPoint, _ R: Double) -> CGPoint {
        let r = (90 - alt) / 90 * R, a = compass * .pi / 180
        return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let R = min(size.width, size.height) / 2 - 18, c = CGPoint(x: size.width / 2, y: size.height / 2)
        // the horizon and the altitude rings
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)), with: .color(Theme.inkMuted), lineWidth: 1.2)
        for alt in [30.0, 60.0] {
            let r = (90 - alt) / 90 * R
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.borderOutdoor),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        for (t, a) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
            let p = point(-14, a, c, R)
            ctx.draw(Text(t).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.navy), at: p)
        }
        // the objects' skylines
        for i in scene.items {
            let s = TankShade.skyline(i, size: (scene.w, scene.h), planAzimuth: scene.planAzimuth, exposed: scene.exposed)
            guard s.altitude > 0.5 else { continue }
            let rIn = (90 - min(s.altitude, 89)) / 90 * R
            var wedge = Path()
            let a0 = Angle(degrees: s.from - 90), a1 = Angle(degrees: s.to - 90)
            wedge.addArc(center: c, radius: R, startAngle: a0, endAngle: a1, clockwise: false)
            wedge.addArc(center: c, radius: rIn, startAngle: a1, endAngle: a0, clockwise: true)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(TankShadeScene.color(i.kind).opacity(0.55)))
        }
        // the solstices and equinox, dotted
        for m in [2, 5, 11] where m != month {
            for s in TankShade.sunPath(latitude: latitude, month: m) {
                let p = point(s.altitude, s.azimuth + 180, c, R)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)), with: .color(Theme.inkFaint))
            }
        }
        // the month's path and the moment's sun
        for s in TankShade.sunPath(latitude: latitude, month: month) {
            let p = point(s.altitude, s.azimuth + 180, c, R)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Theme.warning))
        }
        if let s = TankShade.sun(latitude: latitude, month: month, time: time) {
            let p = point(s.altitude, s.azimuth + 180, c, R)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(Theme.warning))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)), with: .color(Theme.warning.opacity(0.5)), lineWidth: 2)
        }
    }
}

#endif
