import Foundation

/// Thai public holidays, which no working-day count includes: the ERC flow's utility deadlines (`ERCFlow.isWorking`)
/// and the routine reports' working days (`RoutineReport.isWorkingDay`), on top of each station's own extra days off
/// (`RoutineReport.Settings.holidays`). From the team plan workbook's `สมมติฐาน` sheet, written to
/// `public-holidays.json` by `tools/plan-template/holidays.py`; run it again when the workbook gets next year's.
public enum PublicHolidays {
    public struct Day: Codable, Equatable, Sendable {
        /// `yyyy-MM-dd`, as `RoutineReport.dayKey` and `ERCFlow.day` write a day.
        public let date: String
        public let name: String
        /// The workbook still asks for the cabinet's announcement to confirm it (Buddhist holidays, substitute days).
        public let toConfirm: Bool
    }

    private struct File: Decodable { let days: [Day] }

    public static let all: [Day] = {
        guard let url = Bundle.module.url(forResource: "public-holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.days
    }()

    /// Every holiday's day key.
    public static let days: Set<String> = Set(all.map(\.date))

    /// The holiday on that day key, if any.
    public static func day(_ key: String) -> Day? { all.first { $0.date == key } }

    /// The last day the list covers: counts past it have no public holidays to skip.
    public static var coveredUntil: String? { all.last?.date }
}
