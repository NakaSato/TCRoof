import Foundation
import SwiftData
import TCRoofCore

/// One entry of `บันทึกการใช้เครื่องมือและรถ` (`ToolLog.Event`), kept as its JSON. One `toolEvents` document each, read
/// and written by the team (firestore.rules); a contractor's device has none.
@Model
final class ToolEvent {
    var eventJSON: String
    /// The event's time, for sorting without decoding.
    var at: Date
    var syncID: String?

    init(_ event: ToolLog.Event) {
        eventJSON = Self.encode(event)
        at = event.at
        syncID = event.id
    }

    var event: ToolLog.Event {
        get { (try? JSONDecoder().decode(ToolLog.Event.self, from: Data(eventJSON.utf8))) ?? ToolLog.Event(action: .remind, item: "", itemName: "", person: "", personEmail: "") }
        set { eventJSON = Self.encode(newValue); at = newValue.at }
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// A company vehicle (`ToolLog.Vehicle`), one `vehicles` document each, kept by the team.
@Model
final class CompanyVehicle {
    var vehicleJSON: String
    var syncID: String?

    init(_ vehicle: ToolLog.Vehicle) {
        vehicleJSON = ToolEvent.encode(vehicle)
        syncID = vehicle.id
    }

    var vehicle: ToolLog.Vehicle {
        get { (try? JSONDecoder().decode(ToolLog.Vehicle.self, from: Data(vehicleJSON.utf8))) ?? ToolLog.Vehicle(name: "", plate: "") }
        set { vehicleJSON = ToolEvent.encode(newValue) }
    }
}

extension ToolEvent: CloudSynced {
    struct Record: Codable {
        var event: String
        var at: Int64
    }

    static let collection = "toolEvents"
    var ownerJob: Job? { nil }
    var record: Record { Record(event: eventJSON, at: at.millis) }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        eventJSON = r.event
        at = Date(millis: r.at)
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> ToolEvent? {
        let decoded = (try? JSONDecoder().decode(ToolLog.Event.self, from: Data(r.event.utf8)))
        return decoded.map(ToolEvent.init)
    }
}

extension CompanyVehicle: CloudSynced {
    struct Record: Codable {
        var vehicle: String
    }

    static let collection = "vehicles"
    var ownerJob: Job? { nil }
    var record: Record { Record(vehicle: vehicleJSON) }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        vehicleJSON = r.vehicle
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> CompanyVehicle? {
        let decoded = (try? JSONDecoder().decode(ToolLog.Vehicle.self, from: Data(r.vehicle.utf8)))
        return decoded.map(CompanyVehicle.init)
    }
}

/// `-toolLogDemo YES` (DEBUG): the board's example log and vehicles, dated from now, shown in place of the stored ones;
/// the forms save nothing, so nothing reaches the team.
enum ToolLogDemo {
    static var on: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "toolLogDemo")
        #else
        false
        #endif
    }

    static let vehicles = [ToolLog.Vehicle(id: "v1", name: "Isuzu D-Max", plate: "1กข 1234", serviceAtKm: 88_000),
                           ToolLog.Vehicle(id: "v2", name: "Toyota Commuter", plate: "2กค 5678", serviceAtKm: 120_955),
                           ToolLog.Vehicle(id: "v3", name: "Toyota Revo", plate: "3กง 9012", serviceAtKm: 50_000)]

    static var events: [ToolLog.Event] {
        let cal = MasterSchedule.calendar, today = cal.startOfDay(for: .now)
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date { cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: day, to: today)!)! }
        func e(_ a: ToolLog.Action, _ item: String, _ name: String, _ who: String, _ job: String, _ t: Date, due: Date? = nil,
               odo: Int? = nil, fuel: Double? = nil, litres: Double? = nil, baht: Double? = nil, note: String = "") -> ToolLog.Event {
            ToolLog.Event(id: item + "-\(Int(t.timeIntervalSince1970))", action: a, item: item, itemName: name, person: who, personEmail: "", job: job, at: t, due: due,
                          odometer: odo, fuelLevel: fuel, litres: litres, baht: baht, note: note)
        }
        return [
            e(.borrow, "t376", "Fluke 376 FC แคลมป์มิเตอร์", "วิชัย", "NO.098", at(-4, 8, 15), due: at(-1, 17, 0)),
            e(.carOut, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "NO.212", at(-1, 7, 15), odo: 120_243),
            e(.giveBack, "hioki", "Hioki CM4375 แคลมป์มิเตอร์", "วิชัย", "NO.215", at(-1, 16, 5), note: "สภาพปกติ"),
            e(.fuel, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "", at(-1, 17, 30), litres: 45.2, baht: 1_450),
            e(.carIn, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "NO.212", at(-1, 18, 10), odo: 120_455, fuel: 0.3),
            e(.carOut, "v1", "Isuzu D-Max · 1กข 1234", "สมชาย", "NO.224", at(0, 7, 40), odo: 85_034),
            e(.borrow, "drone", "DJI Mavic 3 Thermal", "สมชาย", "NO.224", at(0, 9, 2), due: at(2, 17, 0)),
            e(.giveBack, "f1587", "Fluke 1587 FC เครื่องวัดฉนวน", "ธนพล", "NO.212", at(0, 10, 24), note: "สภาพปกติ"),
        ]
    }
}
