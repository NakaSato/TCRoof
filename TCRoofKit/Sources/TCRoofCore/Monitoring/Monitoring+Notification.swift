import Foundation

/// A paired station that went into alarm or offline since the last reading (issue #259 §7, CHA-21), announced on the
/// device that read it: `สถานีมีปัญหา` with its first alarm, or `สถานีออฟไลน์` with how long nothing came. A tap opens
/// the dock's `Monitor` tab. Only a change is announced: not a station's first reading after launch, not a station that
/// stays in the same state, and not an unpaired one.
public enum MonitoringNotification {
    public static func plans(previous: [String: Monitoring.Health], stations: [Monitoring.Station], now: Date,
                             offlineAfter minutes: Int) -> [NotificationPlan] {
        stations.compactMap { s in
            guard s.paired, let before = previous[s.id] else { return nil }
            let health = s.health(now: now, offlineAfter: minutes)
            guard health != .normal, health != before else { return nil }
            return plan(s, health: health, now: now, offlineAfter: minutes)
        }
    }

    static func plan(_ s: Monitoring.Station, health: Monitoring.Health, now: Date, offlineAfter minutes: Int) -> NotificationPlan {
        let name = [s.mpNumber.map { "MP \($0)" }, s.name.isEmpty ? nil : s.name].compactMap { $0 }.joined(separator: " ")
        let title = health == .offline ? "สถานีออฟไลน์" : "สถานีมีปัญหา"
        let sub: String
        if health == .offline {
            sub = "ไม่ได้รับข้อมูลเกิน \(minutes) นาที"
        } else if let a = s.alarms.first(where: { $0.source != .tcroof }) {
            sub = [a.part, a.source == .growatt && !a.code.isEmpty ? "Error \(a.code)" : nil, a.detail]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | ")
        } else if let online = s.invertersOnline {
            sub = "อินเวอร์เตอร์ทำงาน \(online)/\(s.inverters)"
        } else {
            sub = ""
        }
        return NotificationPlan(id: "monitor-\(s.id)-\(health.rawValue)-\(Int(now.timeIntervalSince1970))", type: .monitor,
                                title: title, body: name, sub: sub, fire: .after(1))
    }
}
