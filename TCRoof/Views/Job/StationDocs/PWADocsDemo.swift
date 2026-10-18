#if DEBUG
import Foundation
import TCRoofCore

/// `-pwaDocsDemo YES`: the 12 stations of docs/ui/pwa-docs-iphone-v2 with papers set so each lands where the board
/// has it (late, ours, waiting for PWA or an office, ready), dated from `today`. Nothing is saved.
enum PWADocsDemo {
    /// MP, name, kWp, contractor, route, current package, the paper it waits on and its status, its due day and the
    /// handover, as days from today.
    private typealias Row = (mp: Int, name: String, kWp: Double, contractor: String, route: StationDocs.BuildingRoute,
                             current: StationDocs.Package, next: String, status: StationDocs.Status, due: Int, handover: Int)

    private static let rows: [Row] = [
        (189, "สถานีผลิตน้ำทุ่งน้อย · สาขาเมืองพล", 92.34, "A", .notify, .building, "building_exempt_notice", .draft, 0, 3),
        (120, "การประปาวัดชัย", 250, "B", .notify, .gridConnection, "owner_signoff", .requested, 6, 18),
        (98, "การประปาบ้านโป่ง", 90, "A", .notify, .handover, "punch_list", .missing, 8, 9),
        (154, "สถานีจ่ายน้ำแพรกหนามแดง", 209.76, "C", .notify, .pk2, "install_photo_report", .draft, 5, 12),
        (77, "สถานีผลิตน้ำโชคชัย", 171, "B", .notify, .handover, "asbuilt", .draft, -4, -4),
        (61, "สถานีผลิตน้ำแม่ข่ายชนบท", 145.2, "D", .permit, .building, "building_permit_o1", .requested, 12, 28),
        (133, "สถานีผลิตน้ำบางปะกง", 120.5, "A", .notify, .gridConnection, "outage_attachment", .requested, 7, 8),
        (142, "สถานีผลิตน้ำหนองแค", 180, "C", .notify, .building, "structural_plan", .draft, 3, 16),
        (88, "สถานีผลิตน้ำพนัสนิคม", 160.4, "B", .notify, .handover, "thermal_report", .missing, 2, 2),
        (171, "สถานีผลิตน้ำสามโคก", 98.2, "D", .notify, .building, "land_deed", .requested, 20, 44),
        (66, "สถานีผลิตน้ำบ้านบึง", 210, "C", .notify, .pk2, "pk_inspection_form", .draft, 9, 21),
        (109, "สถานีผลิตน้ำศรีราชา", 115, "A", .notify, .gridConnection, "", .signed, 10, 11),
    ]

    private static let order: [StationDocs.Package] = [.building, .gridConnection, .pk2, .handover]

    /// `recent`: some papers carry the time they changed and one waiting paper two reminders (the iPad page's
    /// `ความเคลื่อนไหว` and history).
    static func stations(today: Date, recent: Bool = false) -> [PWAPlan.Station] {
        let cal = MasterSchedule.calendar
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: today)) ?? today }
        return rows.map { r in
            var docs = StationDocs.Station(over200kVA: r.kWp >= 200, buildingRoute: r.route)
            let ctx = StationDocs.Context(docs, inverterKW: r.kWp)
            let at = order.firstIndex(of: r.current) ?? 0
            // packages before the current one are in; the current one is signed but for its paper; later ones not started,
            // with a draft or two
            for (i, p) in order.enumerated() where StationDocs.packages(ctx).contains(p) {
                for (j, kind) in StationDocs.papers(in: p, ctx).enumerated() where !kind.scope.isShared && docs.docs[kind.id] == nil {
                    let status: StationDocs.Status = i < at ? (j % 3 == 0 ? .submitted : .approved)
                        : i == at ? .signed : (j % 4 == 0 ? .draft : .missing)
                    docs.docs[kind.id] = StationDocs.DocState(status: status)
                }
            }
            if !r.next.isEmpty { docs.docs[r.next] = StationDocs.DocState(status: r.status) }
            if recent {
                // the current package's papers changed over the last days, the next paper an hour ago
                for (j, kind) in StationDocs.papers(in: r.current, ctx).enumerated() where docs.docs[kind.id] != nil {
                    docs.docs[kind.id]?.updatedAt = cal.date(byAdding: .hour, value: -(j + 1) * 20, to: today)
                }
                if !r.next.isEmpty {
                    docs.docs[r.next]?.updatedAt = cal.date(byAdding: .hour, value: -1, to: today)
                    if r.status == .requested {
                        docs.docs[r.next]?.reminders = [day(-3), cal.date(byAdding: .hour, value: -2, to: today) ?? today]
                    }
                }
            }
            docs.setDue(day(r.due), for: r.current)
            let input = MasterSchedule.Input(installStart: day(r.handover - 60), installEnd: day(r.handover),
                                             kickoff: day(r.handover - 90), engineeringStart: day(r.handover - 80),
                                             siteHandover: day(r.handover - 62), over200kVA: r.kWp >= 200)
            return PWAPlan.Station(id: "demo-\(r.mp)", mpNumber: r.mp, code: "MP\(r.mp)", name: r.name, kWp: r.kWp,
                                   contractor: r.contractor, input: input, docs: docs, docsContext: ctx)
        }
    }

    /// Every library paper approved, the electrical engineer's licence 20 days from running out.
    static func library(today: Date) -> StationDocs.Library {
        var lib = StationDocs.Library()
        for kind in PWADocs.libraryKinds { lib.docs[kind.id] = StationDocs.DocState(status: .approved) }
        lib.docs["engineer_license"] = StationDocs.DocState(
            status: .approved, expiresAt: MasterSchedule.calendar.date(byAdding: .day, value: 20, to: today))
        lib.docs["pwa_poa_order"] = StationDocs.DocState(
            status: .approved, expiresAt: MasterSchedule.calendar.date(byAdding: .day, value: 240, to: today))
        return lib
    }
}
#endif
