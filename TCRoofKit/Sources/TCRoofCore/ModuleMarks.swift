import Foundation

/// A section's own point on A2's site picture: one `siteMarks` entry of `kind`, linked to its module by `MapMark.module`
/// (B3's water point, B5's FTS switch). A2, the section's page and the report all draw the same mark; no separate
/// coordinate field is stored.
public enum ModuleMarks {
    public static let key = "siteMarks"

    /// The index in `siteMarks` of this module's mark: the one linked to it, else (marks placed before the link) the
    /// unlinked mark of `kind` in the same position as the module among the `type` modules without a linked mark.
    static func index(in marks: [MapMark], kind: MarkKind, type: ModuleType, module: UUID, job: Job) -> Int? {
        if let i = marks.firstIndex(where: { $0.kind == kind && $0.module == module }) { return i }
        let linked = Set(marks.compactMap { $0.kind == kind ? $0.module : nil })
        let unlinkedModules = job.modules.filter { $0.type == type && !linked.contains($0.id) }.map(\.id)
        let unlinkedMarks = marks.indices.filter { marks[$0].kind == kind && marks[$0].module == nil }
        guard let k = unlinkedModules.firstIndex(of: module) else { return nil }
        return unlinkedMarks[safe: k]
    }

    /// This module's mark, or nil when none has been placed.
    public static func mark(_ job: Job, _ kind: MarkKind, of type: ModuleType, module: UUID) -> MapMark? {
        let marks = job.values.marks(key)
        return index(in: marks, kind: kind, type: type, module: module, job: job).map { marks[$0] }
    }

    /// Moves this module's mark to (x, y) in fractions of the A2 picture, creating it if there is none, and links it.
    public static func place(_ job: inout Job, _ kind: MarkKind, of type: ModuleType, module: UUID, x: Double, y: Double) {
        var marks = job.values.marks(key)
        if let i = index(in: marks, kind: kind, type: type, module: module, job: job) {
            marks[i].x = min(max(x, 0), 1); marks[i].y = min(max(y, 0), 1); marks[i].module = module
        } else {
            marks.append(MapMark(kind: kind, x: x, y: y, module: module))
        }
        job.values[key] = .marks(marks)
    }

    /// Drops the mark of a module being removed (call before removing it).
    public static func remove(_ job: inout Job, _ kind: MarkKind, of type: ModuleType, module: UUID) {
        var marks = job.values.marks(key)
        guard let i = index(in: marks, kind: kind, type: type, module: module, job: job) else { return }
        marks.remove(at: i)
        job.values[key] = marks.isEmpty ? nil : .marks(marks)
    }

    /// Drops the marks belonging to `m`, if its type has one.
    public static func removeAll(_ job: inout Job, for m: SurveyModule) {
        switch m.type {
        case .water: remove(&job, .water, of: .water, module: m.id)
        case .fts: remove(&job, .emergency, of: .fts, module: m.id)
        default: break
        }
    }
}
