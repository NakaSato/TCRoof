import Foundation
import Observation

/// Builds diagrams away from the UI actor. Reading result never builds a diagram.
@MainActor @Observable
public final class SingleLineRender {
    public struct Result: Sendable {
        public let line: SingleLine
        public let drawing: SingleLineDrawing
    }

    public private(set) var result: Result?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var key: (job: Job, hv: Bool?)?
    @ObservationIgnored private let build: @Sendable (Job, Bool?) async throws -> Result

    public init() { build = { try await Self.makeResult($0, hv: $1) } }

    // Injection keeps scheduling/cancellation tests independent of diagram complexity.
    init(build: @escaping @Sendable (Job, Bool?) async throws -> Result) { self.build = build }

    deinit { task?.cancel() }

    /// Keep the last result visible while a changed job is debounced and rebuilt.
    public func update(_ job: Job, hv: Bool? = nil, now: Bool = false) {
        if let key, key.job == job, key.hv == hv, task != nil || result != nil { return }
        key = (job, hv)
        let previous = task, build = build
        previous?.cancel()
        task = Task { [weak self] in
            if !now { try? await Task.sleep(for: .milliseconds(250)) }
            // A cancelled synchronous stage finishes before its replacement starts.
            await previous?.value
            guard !Task.isCancelled else { return }
            guard let made = try? await build(job, hv), !Task.isCancelled else { return }
            self?.result = made
        }
    }

    public func cancel() {
        task?.cancel()
        key = nil
    }

    func waitForUpdate() async { await task?.value }

    private nonisolated static func makeResult(_ job: Job, hv: Bool?) async throws -> Result {
        try await BackgroundWork.value {
            let line = SingleLine.build(job, hvOverride: hv)
            try Task.checkCancellation()
            let drawing = SingleLineLayout.draw(line)
            return Result(line: line, drawing: drawing)
        }
    }
}
