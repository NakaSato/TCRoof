#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The single line diagram built off the main thread (docs/specs/single-line-diagram.md): a change of the job waits
/// 250 ms for the next one, then `SingleLine.build` and `SingleLineLayout.draw` run detached; the last diagram stays
/// on screen meanwhile, so typing in A3, B4 or B5 never waits for a big station's redraw. The first diagram is built
/// at once.
@MainActor
final class SingleLineRender: ObservableObject {
    struct Result { let line: SingleLine; let drawing: SingleLineDrawing }
    @Published private(set) var result: Result?
    private var task: Task<Void, Never>?
    private var key: (job: Job, hv: Bool?)?

    /// The diagram for `job`, now when there is none yet (then kept), else the last one while a new one is made.
    func current(_ job: Job, hv: Bool? = nil) -> Result {
        if let result { return result }
        let line = SingleLine.build(job, hvOverride: hv)
        return Result(line: line, drawing: SingleLineLayout.draw(line))
    }

    /// Rebuilds for a changed job (or HV choice), debounced; nothing when they are the same as last time.
    func update(_ job: Job, hv: Bool? = nil, now: Bool = false) {
        if let key, key.job == job, key.hv == hv, result != nil { return }
        key = (job, hv)
        task?.cancel()
        task = Task { [weak self] in
            if !now { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            let made = await Task.detached(priority: .userInitiated) { () -> Result in
                let line = SingleLine.build(job, hvOverride: hv)
                return Result(line: line, drawing: SingleLineLayout.draw(line))
            }.value
            guard !Task.isCancelled else { return }
            self?.result = made
        }
    }
}
#endif
