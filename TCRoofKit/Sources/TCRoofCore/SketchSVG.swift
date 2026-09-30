import Foundation

public extension Sketch {
    /// SVG of the drawing (used for previews in tests and for debugging layouts off-device).
    func svg(photoHref: (Photo) -> String? = { _ in nil }) -> String {
        func c(_ v: RGBA?) -> String {
            guard let v else { return "none" }
            // see-through fills (A2's panel area) keep their alpha
            if v.a < 1 { return "rgba(\(Int(v.r * 255)),\(Int(v.g * 255)),\(Int(v.b * 255)),\(fmt(v.a)))" }
            return String(format: "#%02X%02X%02X", Int(v.r * 255), Int(v.g * 255), Int(v.b * 255))
        }
        func e(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        func n(_ d: Double) -> String { fmt(d) }
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(n(width))\" height=\"\(n(height))\" viewBox=\"0 0 \(n(width)) \(n(height))\" font-family=\"Sarabun, Tahoma, sans-serif\">"
        var clip = 0
        for op in ops {
            switch op {
            case let .line(a, b, w, col, dash):
                s += "<line x1=\"\(n(a.x))\" y1=\"\(n(a.y))\" x2=\"\(n(b.x))\" y2=\"\(n(b.y))\" stroke=\"\(c(col))\" stroke-width=\"\(n(w))\"\(dash.isEmpty ? "" : " stroke-dasharray=\"\(dash.map(n).joined(separator: " "))\"")/>"
            case let .rect(r, st, f, w):
                s += "<rect x=\"\(n(r.x))\" y=\"\(n(r.y))\" width=\"\(n(r.w))\" height=\"\(n(r.h))\" fill=\"\(c(f))\" stroke=\"\(c(st))\" stroke-width=\"\(n(w))\"/>"
            case let .hatch(r, col, sp):
                clip += 1
                s += "<clipPath id=\"h\(clip)\"><rect x=\"\(n(r.x))\" y=\"\(n(r.y))\" width=\"\(n(r.w))\" height=\"\(n(r.h))\"/></clipPath><g clip-path=\"url(#h\(clip))\">"
                var t = -r.h; while t < r.w { s += "<line x1=\"\(n(r.x + t))\" y1=\"\(n(r.maxY))\" x2=\"\(n(r.x + t + r.h))\" y2=\"\(n(r.y))\" stroke=\"\(c(col))\" stroke-width=\"1.4\"/>"; t += sp }
                s += "</g>"
            case let .circle(p, r, st, f, w):
                s += "<circle cx=\"\(n(p.x))\" cy=\"\(n(p.y))\" r=\"\(n(r))\" fill=\"\(c(f))\" stroke=\"\(c(st))\" stroke-width=\"\(n(w))\"/>"
            case let .polygon(ps, st, f, w):
                s += "<polygon points=\"\(ps.map { "\(n($0.x)),\(n($0.y))" }.joined(separator: " "))\" fill=\"\(c(f))\" stroke=\"\(c(st))\" stroke-width=\"\(n(w))\"/>"
            case let .text(t, at, size, bold, col, al, ang):
                let anchor = al == .left ? "start" : al == .center ? "middle" : "end"
                s += "<text x=\"\(n(at.x))\" y=\"\(n(at.y + size * 0.35))\" font-size=\"\(n(size))\" fill=\"\(c(col))\" text-anchor=\"\(anchor)\"\(bold ? " font-weight=\"bold\"" : "")\(ang != 0 ? " transform=\"rotate(\(n(ang)) \(n(at.x)) \(n(at.y)))\"" : "")>\(e(t))</text>"
            case let .textBox(t, r, size, bold, col, al):
                let lines = ApproxText.wrap(t, width: r.w, size: size)
                let anchor = al == .left ? "start" : al == .center ? "middle" : "end"
                let x = al == .left ? r.x : al == .center ? r.x + r.w / 2 : r.maxX
                for (i, l) in lines.enumerated() where Double(i + 1) * size * 1.3 <= r.h + 1 {
                    s += "<text x=\"\(n(x))\" y=\"\(n(r.y + size * (1.0 + 1.3 * Double(i))))\" font-size=\"\(n(size))\" fill=\"\(c(col))\" text-anchor=\"\(anchor)\"\(bold ? " font-weight=\"bold\"" : "")>\(e(l))</text>"
                }
            case let .photo(p, r):
                let f = r.fit(Double(p.width), Double(p.height))
                if let href = photoHref(p) { s += "<image x=\"\(n(f.x))\" y=\"\(n(f.y))\" width=\"\(n(f.w))\" height=\"\(n(f.h))\" xlink:href=\"\(href)\" preserveAspectRatio=\"xMidYMid meet\"/>" }
                else { s += "<rect x=\"\(n(f.x))\" y=\"\(n(f.y))\" width=\"\(n(f.w))\" height=\"\(n(f.h))\" fill=\"#cfd8dc\"/>" }
            case let .checkbox(r, on):
                s += "<rect x=\"\(n(r.x))\" y=\"\(n(r.y))\" width=\"\(n(r.w))\" height=\"\(n(r.h))\" fill=\"\(on ? c(.tick) : "#FFFFFF")\" stroke=\"#000000\" stroke-width=\"0.7\"/>"
                if on { s += "<polyline points=\"\(n(r.x + r.w * 0.2)),\(n(r.y + r.h * 0.5)) \(n(r.x + r.w * 0.42)),\(n(r.y + r.h * 0.75)) \(n(r.x + r.w * 0.82)),\(n(r.y + r.h * 0.25))\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"1.3\"/>" }
            }
        }
        return s + "</svg>"
    }
}

/// Text size estimate used where no font metrics are available (Linux tests, first-pass layout).
public enum ApproxText {
    /// Width of one line; Thai vowel/tone marks above and below take no advance.
    public static func width(_ s: String, size: Double, bold: Bool = false) -> Double {
        var w = 0.0
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0E31, 0x0E34...0x0E3A, 0x0E47...0x0E4E: continue
            case 0x0E00...0x0E7F: w += 0.54
            case 0x20: w += 0.25
            case 0x30...0x39: w += 0.55
            case 0x41...0x5A: w += 0.62
            default: w += 0.5
            }
        }
        return w * size * (bold ? 1.06 : 1)
    }
    public static func wrap(_ text: String, width: Double, size: Double, bold: Bool = false) -> [String] {
        var out: [String] = []
        for para in text.components(separatedBy: "\n") {
            var line = ""
            // break at spaces; very long runs (Thai has no spaces) break by characters
            for word in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let cand = line.isEmpty ? word : line + " " + word
                if self.width(cand, size: size, bold: bold) <= width { line = cand; continue }
                if !line.isEmpty { out.append(line); line = "" }
                var chunk = ""
                for ch in word {
                    if self.width(chunk + String(ch), size: size, bold: bold) > width, !chunk.isEmpty { out.append(chunk); chunk = "" }
                    chunk.append(ch)
                }
                line = chunk
            }
            out.append(line)
        }
        return out
    }
    public static func height(_ text: String, width: Double, size: Double, bold: Bool = false) -> Double {
        Double(wrap(text, width: width, size: size, bold: bold).count) * size * 1.3
    }
}
