import Foundation
import SwiftData
import TCRoofCore

// The travel and expense log (docs/specs/calendar-travel-expenses-swift.md part B). Each record belongs to the person
// who made it (`ownerEmail`): it syncs to their other devices and managers may read it (firestore.rules), nobody else.
// Receipts and odometer photos stay on the device until the month is submitted, when they go up to the person's Drive
// with the claim (`ClaimExport`); their Drive ids then travel on the record so the person's other devices can show them.

/// One working day of travel by one person.
@Model
final class Trip {
    var date: Date
    var ownerEmail: String
    var person: String
    var vehicleRaw: String
    var plate: String
    var startPlace: String
    /// Encoded `[TravelClaim.Stop]`.
    var stopsJSON: String
    /// The way back from the last stop to the start place; nil while not worked out, 0 when the day doesn't go back.
    var backKm: Double?
    /// Baht per km for a private car, kept from the settings when the trip was made so a later change doesn't move it.
    var rate: Double
    var odoStart: Int?
    var odoEnd: Int?
    var odoReason: String
    @Attribute(.externalStorage) var odoStartPhoto: Data?
    @Attribute(.externalStorage) var odoEndPhoto: Data?
    var odoStartDriveID: String?
    var odoEndDriveID: String?
    var syncID: String?

    init(date: Date, ownerEmail: String, person: String, vehicle: TravelClaim.Vehicle, plate: String, startPlace: String, rate: Double) {
        self.date = TravelClaim.calendar.startOfDay(for: date)
        self.ownerEmail = ownerEmail
        self.person = person
        self.vehicleRaw = vehicle.rawValue
        self.plate = plate
        self.startPlace = startPlace
        self.stopsJSON = "[]"
        self.rate = rate
        self.odoReason = ""
        self.syncID = UUID().uuidString
    }

    var vehicle: TravelClaim.Vehicle {
        get { TravelClaim.Vehicle(rawValue: vehicleRaw) ?? .company }
        set { vehicleRaw = newValue.rawValue }
    }

    var stops: [TravelClaim.Stop] {
        get { (try? JSONDecoder().decode([TravelClaim.Stop].self, from: Data(stopsJSON.utf8))) ?? [] }
        set { stopsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }

    var monthKey: String { TravelClaim.monthKey(date) }

    var day: TravelClaim.Day {
        TravelClaim.Day(id: syncID ?? "", date: date, vehicle: vehicle, plate: plate, startPlace: startPlace, stops: stops,
                        backKm: backKm, rate: rate, odoStart: odoStart, odoEnd: odoEnd, odoReason: odoReason,
                        hasOdoPhotos: odoStartPhoto != nil || odoEndPhoto != nil)
    }
}

/// One expense, usually one receipt.
@Model
final class Expense {
    var date: Date
    var ownerEmail: String
    var person: String
    var categoryRaw: String
    /// Satang.
    var amount: Int
    var vendor: String
    var taxID: String
    var note: String
    /// The job it is allocated to (its sync id); nil for the day in general.
    var jobID: String?
    @Attribute(.externalStorage) var receipt: Data?
    var receiptDriveID: String?
    /// "receipt" once the values were read from the photo (`ReceiptParser`), else "typed".
    var fillSource: String
    var createdAt: Date
    var syncID: String?

    init(date: Date, ownerEmail: String, person: String, category: TravelClaim.Category, amount: Int = 0) {
        self.date = date
        self.ownerEmail = ownerEmail
        self.person = person
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.vendor = ""
        self.taxID = ""
        self.note = ""
        self.fillSource = "typed"
        self.createdAt = .now
        self.syncID = UUID().uuidString
    }

    var category: TravelClaim.Category {
        get { TravelClaim.Category(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var monthKey: String { TravelClaim.monthKey(date) }
    /// On this device, or on Drive waiting to come down.
    var hasReceipt: Bool { receipt != nil || receiptDriveID != nil }

    var item: TravelClaim.Item {
        TravelClaim.Item(id: syncID ?? "", date: date, category: category, amount: amount, vendor: vendor, taxID: taxID, note: note,
                         jobID: jobID, hasReceipt: hasReceipt, fromReceipt: fillSource == "receipt")
    }
}

/// A person's claim for one month: submitted (which locks the month's trips and expenses), withdrawn, and where its files
/// went on Drive.
@Model
final class ClaimMonth {
    var ownerEmail: String
    /// "2026-10".
    var month: String
    var submittedAt: Date?
    /// Every submit and withdrawal, one line each ("ยื่นเบิก 31 ต.ค. 2569 18:02"), the logged undo of §B5.
    var log: String
    @Attribute(.externalStorage) var signature: Data?
    var pdfDriveID: String?
    var excelDriveID: String?
    var driveFolderURL: String?
    var syncID: String?

    init(ownerEmail: String, month: String) {
        self.ownerEmail = ownerEmail
        self.month = month
        self.log = ""
        self.syncID = UUID().uuidString
    }

    var isSubmitted: Bool { submittedAt != nil }

    func addLog(_ line: String) {
        log = log.isEmpty ? line : log + "\n" + line
    }
}

// MARK: - Sync

/// A record that belongs to one person: only their devices push it (`CloudSync` skips another account's left on a
/// shared iPad), and the listeners ask for theirs only.
protocol OwnedRecord {
    var ownerEmail: String { get }
}
extension Trip: OwnedRecord {}
extension Expense: OwnedRecord {}
extension ClaimMonth: OwnedRecord {}

extension Trip: CloudSynced {
    struct Record: Codable, Sendable {
        var date: Int64
        var ownerEmail, person, vehicle, plate, startPlace, stops: String
        var backKm: Double?
        var rate: Double
        var odoStart, odoEnd: Int?
        var odoReason: String
        var odoStartDrive, odoEndDrive: String?
    }

    static let collection = "trips"
    var ownerJob: Job? { nil }

    var record: Record {
        Record(date: date.millis, ownerEmail: ownerEmail, person: person, vehicle: vehicleRaw, plate: plate, startPlace: startPlace,
               stops: stopsJSON, backKm: backKm, rate: rate, odoStart: odoStart, odoEnd: odoEnd, odoReason: odoReason,
               odoStartDrive: odoStartDriveID, odoEndDrive: odoEndDriveID)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        date = Date(millis: r.date); ownerEmail = r.ownerEmail; person = r.person; vehicleRaw = r.vehicle; plate = r.plate
        startPlace = r.startPlace; stopsJSON = r.stops; backKm = r.backKm; rate = r.rate
        odoStart = r.odoStart; odoEnd = r.odoEnd; odoReason = r.odoReason
        // a photo uploaded elsewhere replaces this device's copy, which downloads when the day is opened
        if r.odoStartDrive != odoStartDriveID { odoStartDriveID = r.odoStartDrive; if r.odoStartDrive != nil { odoStartPhoto = nil } }
        if r.odoEndDrive != odoEndDriveID { odoEndDriveID = r.odoEndDrive; if r.odoEndDrive != nil { odoEndPhoto = nil } }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> Trip? {
        Trip(date: Date(millis: r.date), ownerEmail: r.ownerEmail, person: r.person,
             vehicle: TravelClaim.Vehicle(rawValue: r.vehicle) ?? .company, plate: r.plate, startPlace: r.startPlace, rate: r.rate)
    }
}

extension Expense: CloudSynced {
    struct Record: Codable, Sendable {
        var date, createdAt: Int64
        var ownerEmail, person, category: String
        var amount: Int
        var vendor, taxID, note, fillSource: String
        var jobID, receiptDrive: String?
    }

    static let collection = "expenses"
    var ownerJob: Job? { nil }

    var record: Record {
        Record(date: date.millis, createdAt: createdAt.millis, ownerEmail: ownerEmail, person: person, category: categoryRaw,
               amount: amount, vendor: vendor, taxID: taxID, note: note, fillSource: fillSource, jobID: jobID, receiptDrive: receiptDriveID)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        date = Date(millis: r.date); createdAt = Date(millis: r.createdAt); ownerEmail = r.ownerEmail; person = r.person
        categoryRaw = r.category; amount = r.amount; vendor = r.vendor; taxID = r.taxID; note = r.note; fillSource = r.fillSource
        jobID = r.jobID
        if r.receiptDrive != receiptDriveID { receiptDriveID = r.receiptDrive; if r.receiptDrive != nil { receipt = nil } }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> Expense? {
        Expense(date: Date(millis: r.date), ownerEmail: r.ownerEmail, person: r.person,
                category: TravelClaim.Category(rawValue: r.category) ?? .other, amount: r.amount)
    }
}

extension ClaimMonth: CloudSynced {
    struct Record: Codable, Sendable {
        var ownerEmail, month, log: String
        var submittedAt: Int64?
        var pdfDrive, excelDrive, driveFolderURL: String?
    }

    static let collection = "claims"
    var ownerJob: Job? { nil }

    var record: Record {
        Record(ownerEmail: ownerEmail, month: month, log: log, submittedAt: submittedAt?.millis, pdfDrive: pdfDriveID,
               excelDrive: excelDriveID, driveFolderURL: driveFolderURL)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        ownerEmail = r.ownerEmail; month = r.month; log = r.log; submittedAt = r.submittedAt.map(Date.init(millis:))
        pdfDriveID = r.pdfDrive; excelDriveID = r.excelDrive; driveFolderURL = r.driveFolderURL
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> ClaimMonth? {
        ClaimMonth(ownerEmail: r.ownerEmail, month: r.month)
    }
}
