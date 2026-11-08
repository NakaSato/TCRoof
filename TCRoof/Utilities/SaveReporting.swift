import Foundation
import SwiftData
import os

extension ModelContext {
    private static let saveLog = Logger(subsystem: "com.tcroof.internal", category: "save")

    /// Saves, and logs a failure with what was being saved instead of dropping it the way `try? save()` does.
    /// Returns the error so a caller the person is waiting on can say so.
    @discardableResult
    func saveOrReport(_ what: StaticString) -> Error? {
        do {
            try save()
            return nil
        } catch {
            Self.saveLog.error("\(what, privacy: .public): save failed: \(error.localizedDescription, privacy: .public)")
            return error
        }
    }
}
