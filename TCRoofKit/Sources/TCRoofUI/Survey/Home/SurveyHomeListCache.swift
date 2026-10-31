#if canImport(UIKit)
import Foundation
import TCRoofCore

/// A sheet, geometry update or download-progress change does not change the project list's inputs.
@MainActor
final class SurveyHomeListCache {
    let stations = ProjectStationListCache()
    struct Key: Equatable {
        let model: ObjectIdentifier
        let revision: Int
        let search: String
        let stage: JobStage
        let filter: SurveyHomeView.Filter
        let sort: SurveyHomeView.Sort
        let mine: Set<String>?
        let pending: Set<UUID>?
    }
    struct Result {
        let searched: [Job]
        let shown: [Job]
    }
    private var key: Key?
    private var value: Result?

    func result(for key: Key, build: () -> Result) -> Result {
        if self.key == key, let value { return value }
        let value = build()
        self.key = key
        self.value = value
        return value
    }
}
#endif
