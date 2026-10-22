import Foundation

/// The roof mounting grid (docs/specs/cad-export-dxf, Roof mounting grid): on each face in use, a lower-case letter on
/// every line along the eave that carries L-feet (the rails along the purlins, or the purlins under rails that cross
/// them), and a number on every line up the slope through feet (1, 2, 3 … left to right on the plan). Letters run on from
/// face to face, so every foot has its own reference (`b-3`); lower case keeps them apart from the building's grid
/// (A, B … and 1, 2 …). Lines closer than 50 mm share a name.
public struct RoofMountGrid: Sendable {
    public struct Line: Sendable { public var at: Double; public var name: String }
    public struct Face: Sendable {
        public var face: RoofFace
        /// Lines along the eave (v) and up the slope (u), in the face's frame.
        public var letters: [Line]
        public var numbers: [Line]
        /// Every foot of the face, (u, v).
        public var feet: [Pt]
    }
    public let faces: [Face]

    public init(_ m: RoofMountLayout) {
        func merged(_ xs: [Double]) -> [Double] {
            xs.sorted().reduce(into: [Double]()) { out, x in if let last = out.last, abs(x - last) < 0.05 { return }; out.append(x) }
        }
        var out: [Face] = [], next = 0
        for f in m.faces where f.used {
            var feet: [Pt] = []
            for row in f.rows {
                for run in row.runs {
                    for (rail, xs) in zip([row.rails.0, row.rails.1], run.feet) { feet += xs.map { Pt($0, rail) } }
                }
            }
            for run in f.columnRuns {
                for (u, vs) in zip(run.railsAt, run.feet) { feet += vs.map { Pt(u, $0) } }
            }
            guard !feet.isEmpty else { continue }
            let vs = merged(feet.map(\.y)), us = merged(feet.map(\.x))
            let letters = vs.enumerated().map { Line(at: $1, name: Self.letter(next + $0)) }
            next += vs.count
            // numbered left to right on the plan (top to bottom when u runs up or down it)
            let a = f.face.plan(0, 0), b = f.face.plan(1, 0)
            let flip = abs(b.x - a.x) > 1e-6 ? b.x < a.x : b.y < a.y
            let order = flip ? Array(us.reversed()) : us
            out.append(Face(face: f.face, letters: letters, numbers: order.enumerated().map { Line(at: $1, name: "\($0 + 1)") }, feet: feet))
        }
        faces = out
    }

    /// a, b, … z, aa, ab, …
    static func letter(_ i: Int) -> String {
        let a = Array("abcdefghijklmnopqrstuvwxyz")
        return i < 26 ? String(a[i]) : String(a[i / 26 - 1]) + String(a[i % 26])
    }

    /// A foot's reference on its face (`b-3`).
    public func ref(_ f: Face, _ p: Pt) -> String? {
        guard let l = f.letters.first(where: { abs($0.at - p.y) < 0.05 }), let n = f.numbers.first(where: { abs($0.at - p.x) < 0.05 }) else { return nil }
        return l.name + "-" + n.name
    }
}

extension RoofDXF {
    /// The roof mounting grid on G-GRID, the plan's y flipped at `ly`: each letter line along its face past its feet
    /// with a bubble at both ends, each number line up the slope from past the eave to past its highest foot with its
    /// bubble beyond the eave, and each foot tagged with its reference (G-ANNO-TEXT).
    static func mountGrid(_ dxf: inout SketchDXF, _ g: RoofMountGrid, ly: Double) {
        let r = 0.2
        func bubble(_ c: (Double, Double), _ name: String) {
            dxf.circle(CADLayers.grid, c, r: r)
            dxf.text(CADLayers.grid, c, height: r * 0.9, name, align: .center, middle: true)
        }
        for f in g.faces {
            func at(_ u: Double, _ v: Double) -> (Double, Double) { let p = f.face.plan(u, v); return (p.x, ly - p.y) }
            let u0 = f.feet.map(\.x).min()!, u1 = f.feet.map(\.x).max()!
            for l in f.letters {
                dxf.line(CADLayers.grid, at(u0 - 0.45, l.at), at(u1 + 0.45, l.at))
                bubble(at(u0 - 0.45 - r, l.at), l.name)
                bubble(at(u1 + 0.45 + r, l.at), l.name)
            }
            for n in f.numbers {
                let top = f.feet.filter { abs($0.x - n.at) < 0.05 }.map(\.y).max() ?? 0
                dxf.line(CADLayers.grid, at(n.at, -0.6), at(n.at, top + 0.3))
                bubble(at(n.at, -0.6 - r), n.name)
            }
            for p in f.feet {
                guard let ref = g.ref(f, p) else { continue }
                let q = at(p.x, p.y)
                dxf.text(CADLayers.text, (q.0 + 0.06, q.1 + 0.06), height: 0.08, ref)
            }
        }
    }
}
