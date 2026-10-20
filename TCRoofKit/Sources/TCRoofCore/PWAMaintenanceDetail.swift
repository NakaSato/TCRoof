import Foundation

/// Detailed data for a handed-over maintenance station (reference/PhonePwaStation.dc.html).
public struct MaintenanceStationDetail: Identifiable, Hashable, Sendable {
    public var id: String { summary.id }
    public var summary: MaintenanceStationSummary
    public var handoverDate: String
    public var contractor: String
    public var contractorShort: String
    public var contractorPhone: String
    public var issueTitle: String?
    public var issueSubtitle: String?
    public var ctaText: String

    // Hourly generation (06:00 to 18:00, 13 hourly points)
    public var expectedHourly: [Double]
    public var actualHourly: [Double]
    public var hourlyMax: Double
    public var lastUpdated: String

    // KPIs
    public var prToday: Double
    public var prTarget: Double
    public var energyThisMonth: String
    public var energyExpectedThisMonth: String
    public var co2SavedThisMonth: String

    // Inverters
    public var inverters: [InverterItem]

    // Repairs
    public var tickets: [MaintenanceTicket]

    // PM
    public var nextPM: NextPMSummary?
    public var pmHistory: [PMHistoryItem]

    // Equipment
    public var equipmentGroups: [EquipmentGroup]

    public init(summary: MaintenanceStationSummary,
                handoverDate: String = "12/3/2569",
                contractor: String = "ผู้รับเหมา C",
                contractorShort: String = "ผู้รับเหมา C",
                contractorPhone: String = "0812345678",
                issueTitle: String? = nil,
                issueSubtitle: String? = nil,
                ctaText: String = "ใบงานซ่อม TK-0412",
                expectedHourly: [Double] = [4, 18, 42, 70, 92, 108, 114, 108, 92, 70, 42, 18, 4],
                actualHourly: [Double] = [2, 9, 22, 37, 48, 56, 60, 58, 52, 0, 0, 0, 0],
                hourlyMax: Double = 120,
                lastUpdated: String = "14:55",
                prToday: Double = 63,
                prTarget: Double = 80,
                energyThisMonth: String = "17.6 MWh",
                energyExpectedThisMonth: String = "คาด 21.4",
                co2SavedThisMonth: String = "8.8 t",
                inverters: [InverterItem] = [],
                tickets: [MaintenanceTicket] = [],
                nextPM: NextPMSummary? = nil,
                pmHistory: [PMHistoryItem] = [],
                equipmentGroups: [EquipmentGroup] = []) {
        self.summary = summary
        self.handoverDate = handoverDate
        self.contractor = contractor
        self.contractorShort = contractorShort
        self.contractorPhone = contractorPhone
        self.issueTitle = issueTitle
        self.issueSubtitle = issueSubtitle
        self.ctaText = ctaText
        self.expectedHourly = expectedHourly
        self.actualHourly = actualHourly
        self.hourlyMax = hourlyMax
        self.lastUpdated = lastUpdated
        self.prToday = prToday
        self.prTarget = prTarget
        self.energyThisMonth = energyThisMonth
        self.energyExpectedThisMonth = energyExpectedThisMonth
        self.co2SavedThisMonth = co2SavedThisMonth
        self.inverters = inverters
        self.tickets = tickets
        self.nextPM = nextPM
        self.pmHistory = pmHistory
        self.equipmentGroups = equipmentGroups
    }

    public var hasIssue: Bool { summary.status != .normal || issueTitle != nil }

    public var energyTodayFormatted: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: Int(summary.energy.rounded()))) ?? "\(Int(summary.energy))"
    }

    public var energyExpectedFormatted: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: Int(summary.expected.rounded()))) ?? "\(Int(summary.expected))"
    }

    public var generationPct: Int {
        summary.expected > 0 ? Int((summary.energy / summary.expected * 100).rounded()) : 0
    }

    /// Creates a detail instance filled with data matching `PhonePwaStation.dc.html` or derived from `summary`.
    public static func mock(for summary: MaintenanceStationSummary) -> MaintenanceStationDetail {
        let isAlarm = summary.status == .alarm
        let isOffline = summary.status == .offline

        let issueTitle: String? = isAlarm ? "INV 2 fault | 2 วัน" : (isOffline ? "สถานีออฟไลน์ | 6 ชม." : nil)
        let issueSub: String? = isAlarm ? "Error 31 | ผลิตได้ราวครึ่งเดียว" : (isOffline ? "ไม่มีสัญญาณสื่อสารจาก SmartLogger" : nil)

        let invs: [InverterItem]
        if isAlarm {
            invs = [
                InverterItem(id: "inv1", name: "INV 1", model: "Huawei SUN2000-110KTL | SN …4417", power: "58.2 kW", statusText: "ปกติ", isError: false),
                InverterItem(id: "inv2", name: "INV 2", model: "Huawei SUN2000-110KTL | SN …4452", power: "0 kW", statusText: "Error 31", isError: true),
            ]
        } else if isOffline {
            invs = [
                InverterItem(id: "inv1", name: "INV 1", model: "Huawei SUN2000-110KTL | SN …4417", power: "—", statusText: "ออฟไลน์", isError: true),
                InverterItem(id: "inv2", name: "INV 2", model: "Huawei SUN2000-110KTL | SN …4452", power: "—", statusText: "ออฟไลน์", isError: true),
            ]
        } else {
            invs = [
                InverterItem(id: "inv1", name: "INV 1", model: "Huawei SUN2000-110KTL | SN …4417", power: "58.2 kW", statusText: "ปกติ", isError: false),
                InverterItem(id: "inv2", name: "INV 2", model: "Huawei SUN2000-110KTL | SN …4452", power: "57.8 kW", statusText: "ปกติ", isError: false),
            ]
        }

        let tickets: [MaintenanceTicket]
        if summary.openRepairs > 0 || isAlarm || isOffline {
            tickets = [
                MaintenanceTicket(id: "TK-0412", status: "กำลังดำเนินการ", isClosed: false, dateText: "แจ้ง 11/10 09:20",
                                  title: isAlarm ? "INV 2 หยุดผลิต (Error 31)" : "ตรวจสอบอุปกรณ์สื่อสาร",
                                  subtitle: "ผู้รับเหมา C | นัดเข้าหน้างาน 14/10 10:00", currentStep: 2),
                MaintenanceTicket(id: "TK-0388", status: "ปิดแล้ว", isClosed: true, dateText: "2/9 → 4/9",
                                  title: "สาย DC string 7 หลวม", subtitle: "ผู้รับเหมา C | เปลี่ยนขั้วต่อ MC4 2 ชุด", currentStep: 4),
            ]
        } else {
            tickets = [
                MaintenanceTicket(id: "TK-0388", status: "ปิดแล้ว", isClosed: true, dateText: "2/9 → 4/9",
                                  title: "ตรวจเช็กขั้วต่อและสายไฟ", subtitle: "ทีม TC | เรียบร้อยทุกจุด", currentStep: 4),
            ]
        }

        let nextPM: NextPMSummary?
        if let pm = summary.nextPM {
            let c = Calendar.current.dateComponents([.day, .month], from: pm)
            let monthNames = ["", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]
            let mName = (c.month ?? 0) < monthNames.count ? monthNames[c.month ?? 0] : ""
            let daysAhead = max(0, Calendar.current.dateComponents([.day], from: .now, to: pm).day ?? 21)
            nextPM = NextPMSummary(dayText: "\(c.day ?? 3)", monthText: mName.isEmpty ? "พ.ย." : mName,
                                   countdownText: "PM ครั้งถัดไป | อีก \(daysAhead) วัน",
                                   title: "PM รอบ 6 เดือน",
                                   subtitle: "ทีม TC | ล้างแผง ตรวจขั้วต่อ IR scan")
        } else {
            nextPM = NextPMSummary(dayText: "3", monthText: "พ.ย.", countdownText: "PM ครั้งถัดไป | อีก 21 วัน",
                                   title: "PM รอบ 6 เดือน", subtitle: "ทีม TC | ล้างแผง ตรวจขั้วต่อ IR scan")
        }

        let pmHist = [
            PMHistoryItem(id: "pm1", title: "PM รอบ 6 เดือน", detail: "ทีม TC | ผ่าน 24/24 ข้อ", dateText: "3/5/2569"),
            PMHistoryItem(id: "pm2", title: "ล้างแผง", detail: "ผู้รับเหมา C | ผลิตเพิ่ม 6%", dateText: "15/7/2569"),
            PMHistoryItem(id: "pm3", title: "ตรวจรับหลังส่งมอบ", detail: "ทีม TC | IR scan ไม่พบจุดร้อน", dateText: "20/3/2569"),
        ]

        let eq = [
            EquipmentGroup(title: "แผง", rows: [
                EquipmentRow(key: "Longi Hi-MO 6 | 550 W", value: "400 แผง"),
                EquipmentRow(key: "String", value: "20 × 20"),
            ]),
            EquipmentGroup(title: "อินเวอร์เตอร์", rows: [
                EquipmentRow(key: "INV 1 | SUN2000-110KTL", value: isOffline ? "ออฟไลน์" : "ปกติ"),
                EquipmentRow(key: "INV 2 | SUN2000-110KTL", value: isAlarm ? "Error 31" : (isOffline ? "ออฟไลน์" : "ปกติ")),
            ]),
            EquipmentGroup(title: "มิเตอร์และสื่อสาร", rows: [
                EquipmentRow(key: "Smart meter DTSU666", value: isOffline ? "ขาดสัญญาณ" : "ออนไลน์"),
                EquipmentRow(key: "SmartLogger 3000", value: isOffline ? "ขาดสัญญาณ" : "ออนไลน์"),
                EquipmentRow(key: "ประกันระบบ", value: "ถึง 12/3/2571"),
            ]),
        ]

        let actualH: [Double]
        if isOffline {
            actualH = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        } else if isAlarm {
            actualH = [2, 9, 22, 37, 48, 56, 60, 58, 52, 0, 0, 0, 0]
        } else {
            actualH = [4, 17, 40, 68, 90, 105, 112, 106, 90, 0, 0, 0, 0]
        }

        return MaintenanceStationDetail(
            summary: summary,
            handoverDate: "12/3/2569",
            contractor: "ผู้รับเหมา C",
            contractorShort: "ผู้รับเหมา C",
            contractorPhone: "0812345678",
            issueTitle: issueTitle,
            issueSubtitle: issueSub,
            ctaText: (summary.openRepairs > 0 || isAlarm) ? "ใบงานซ่อม TK-0412" : "แจ้งซ่อม / ออกใบงาน",
            expectedHourly: [4, 18, 42, 70, 92, 108, 114, 108, 92, 70, 42, 18, 4],
            actualHourly: actualH,
            hourlyMax: 120,
            lastUpdated: "14:55",
            prToday: summary.pr > 0 ? summary.pr : 63,
            prTarget: 80,
            energyThisMonth: "17.6 MWh",
            energyExpectedThisMonth: "คาด 21.4",
            co2SavedThisMonth: "8.8 t",
            inverters: invs,
            tickets: tickets,
            nextPM: nextPM,
            pmHistory: pmHist,
            equipmentGroups: eq
        )
    }
}

public struct InverterItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var power: String
    public var statusText: String
    public var isError: Bool

    public init(id: String, name: String, model: String, power: String, statusText: String, isError: Bool = false) {
        self.id = id
        self.name = name
        self.model = model
        self.power = power
        self.statusText = statusText
        self.isError = isError
    }
}

public struct MaintenanceTicket: Identifiable, Hashable, Sendable {
    public var id: String
    public var status: String
    public var isClosed: Bool
    public var dateText: String
    public var title: String
    public var subtitle: String
    public var currentStep: Int

    public init(id: String, status: String, isClosed: Bool = false, dateText: String, title: String, subtitle: String, currentStep: Int) {
        self.id = id
        self.status = status
        self.isClosed = isClosed
        self.dateText = dateText
        self.title = title
        self.subtitle = subtitle
        self.currentStep = currentStep
    }
}

public struct NextPMSummary: Hashable, Sendable {
    public var dayText: String
    public var monthText: String
    public var countdownText: String
    public var title: String
    public var subtitle: String

    public init(dayText: String, monthText: String, countdownText: String, title: String, subtitle: String) {
        self.dayText = dayText
        self.monthText = monthText
        self.countdownText = countdownText
        self.title = title
        self.subtitle = subtitle
    }
}

public struct PMHistoryItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var dateText: String

    public init(id: String, title: String, detail: String, dateText: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.dateText = dateText
    }
}

public struct EquipmentGroup: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    public var rows: [EquipmentRow]

    public init(title: String, rows: [EquipmentRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct EquipmentRow: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
