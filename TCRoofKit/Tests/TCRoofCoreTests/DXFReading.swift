import Foundation

/// Reading a written DXF back in tests. A protocol with a plain `DXFRead` beside it, so other test files don't create a
/// test case to borrow these (XCTest on Linux has no `XCTestCase()`).
protocol DXFReading {}

struct DXFRead: DXFReading {}

extension DXFReading {
    func lines(_ d: Data) -> [String] { String(data: d, encoding: .isoLatin1)!.components(separatedBy: "\r\n") }
    /// The entities as written (code, value pairs).
    func rawEntities(_ d: Data) -> [[(String, String)]] { records(d) }
    /// Every record of the ENTITIES section.
    func records(_ d: Data) -> [[(String, String)]] {
        let l = lines(d)
        let start = l.firstIndex(of: "ENTITIES")! + 1, end = l[start...].firstIndex(of: "ENDSEC")! - 1
        var out: [[(String, String)]] = []
        var i = start
        while i + 1 < end {
            if l[i] == "0" { out.append([]) }
            out[out.count - 1].append((l[i], l[i + 1])); i += 2
        }
        return out
    }
    /// The entities with each LWPOLYLINE as the LINEs it draws (its layer, linetype and colour on each), so geometry
    /// checks read every segment the same way.
    func entities(_ d: Data) -> [[(String, String)]] {
        var out: [[(String, String)]] = []
        for r in records(d) {
            guard r.first?.1 == "LWPOLYLINE" else { out.append(r); continue }
            let xs = r.filter { $0.0 == "10" }.map(\.1), ys = r.filter { $0.0 == "20" }.map(\.1), pts = Array(zip(xs, ys))
            let keep = r.filter { ["8", "6", "62"].contains($0.0) }, closed = (Int(value(r, "70") ?? "0") ?? 0) & 1 == 1
            let n = closed ? pts.count : pts.count - 1
            for k in 0..<max(0, n) {
                let a = pts[k], b = pts[(k + 1) % pts.count]
                out.append([("0", "LINE")] + keep + [("10", a.0), ("20", a.1), ("30", "0"), ("11", b.0), ("21", b.1), ("31", "0")])
            }
        }
        return out
    }
    /// The value of the first group `code` after line `i`.
    func after(_ l: [String], _ i: Int, _ code: String) -> String? {
        var k = i + 1
        while k + 1 < l.count { if l[k] == code { return l[k + 1] }; k += 2 }
        return nil
    }
    /// A table's record count.
    func tableCount(_ l: [String], _ name: String) -> Int? {
        guard let i = l.indices.first(where: { l[$0] == name && l[$0 - 1] == "2" && l[$0 - 2] == "TABLE" }) else { return nil }
        return after(l, i, "70").flatMap(Int.init)
    }
    func value(_ e: [(String, String)], _ code: String) -> String? { e.first { $0.0 == code }?.1 }
    func double(_ e: [(String, String)], _ code: String) -> Double { Double(value(e, code)!)! }
}
