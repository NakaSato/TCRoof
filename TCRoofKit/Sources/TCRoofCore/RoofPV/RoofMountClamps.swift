import Foundation

/// What the module installation rules read off a laid-out roof (docs/specs/module-install-rules.md §7.2): where the
/// rails hold the modules and on which side.
extension RoofMountLayout {
    /// The clamps hold the modules' long side when the rails cross it: portrait on rails along the eave, or landscape on
    /// rails across the purlins.
    public var clampsLongSide: Bool { options.landscape == options.acrossPurlins }

    /// Every offset A the layout uses (module end → rail, mm, to the millimetre), over the faces in use; sorted, no repeats.
    public var clampOffsetsMm: [Double] {
        var out = Set<Double>()
        func mm(_ m: Double) -> Double { (m * 1000).rounded() }
        let up = moduleUp, along = moduleAlong
        for f in faces where f.used {
            if options.acrossPurlins {
                for run in f.columnRuns {
                    guard let c = run.columns.first, let r = run.rows.first, f.rows[r].slots.indices.contains(c),
                          run.railsAt.count == 2 else { continue }
                    let u = f.rows[r].slots[c].u
                    out.insert(mm(run.railsAt[0] - u)); out.insert(mm(u + along - run.railsAt[1]))
                }
            } else {
                for row in f.rows where row.slots.contains(where: \.isModule) {
                    out.insert(mm(row.rails.0 - row.v)); out.insert(mm(row.v + up - row.rails.1))
                }
            }
        }
        return out.sorted()
    }

    /// The faces in use: their tilt (°) and azimuth (°).
    public var usedFaceAngles: [(tilt: Double, azimuth: Double)] {
        faces.filter(\.used).map { ($0.face.tilt * 180 / .pi, $0.face.azimuth) }
    }
}
