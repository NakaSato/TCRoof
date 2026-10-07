import Foundation

/// The weekly-meeting page of an MP plan (docs/specs/master-schedule-swift.md §4): the Gantt of the 18 tasks on the
/// left and the Weekly Update, then the month's Monthly Update, on the right, on one A3 landscape page in points.
public enum MasterScheduleSheet {
    public static let width = 1190.55, height = 841.89
    static let margin = 28.0, panelW = 300.0, labelW = 250.0, gap = 16.0

    static let navy = RGBA(hex: 0x16325C), primary = RGBA(hex: 0x1F6FB5), muted = RGBA(hex: 0x7A8BA3)
    static let soft = RGBA(hex: 0xE3EEF8), line = RGBA(hex: 0xDDE4ED), red = RGBA(hex: 0xB42318), green = RGBA(hex: 0x2E7D32)

    /// "4/10/69" in the Thai Buddhist era.
    static func short(_ d: Date) -> String {
        let c = MasterSchedule.calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)/\(((c.year ?? 0) + 543) % 100)"
    }
    /// "52.75" → "52.8%".
    static func pct(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "%"
    }

    /// `title` heads the page (MP number and station). `week` is any day of the reported week.
    public static func page(input: MasterSchedule.Input, actual: MasterSchedule.Actual, week: Date, title: String) -> Sketch {
        let cal = MasterSchedule.calendar, wk = MasterSchedule.weekStart(week)
        let plan = MasterSchedule.plan(input), st = MasterSchedule.status(plan: plan, actual: actual, through: wk)
        let booked = actual.points.values.flatMap(\.keys).compactMap { MasterSchedule.date(fromKey: $0, calendar: cal) }
        let dates = plan.compactMap(\.start) + plan.compactMap(\.end) + booked + [wk]
        let weeks = MasterSchedule.weeks(from: dates.min() ?? wk, to: dates.max() ?? wk)
        var o: [DrawOp] = []

        // header
        o.append(.text("แผนงาน MP · " + title, at: Pt(margin, margin + 10), size: 16, bold: true, color: navy))
        let idx = weeks.firstIndex(of: wk).map { " · W\($0)" } ?? ""
        o.append(.text("ถึงสัปดาห์ \(short(wk))\(idx)   แผน \(pct(st.planned))   ทำได้ \(pct(st.actual))   " + variance(st.variance),
                       at: Pt(width - margin, margin + 10), size: 11, bold: true, color: st.variance < -0.05 ? red : navy, align: .right))
        let top = margin + 32

        o += gantt(plan: plan, actual: actual, weeks: weeks, chosen: wk,
                   in: Box(margin, top, width - 2 * margin - panelW - gap, height - top - margin - 18))
        o += weekly(st, plan: plan, in: Box(width - margin - panelW, top, panelW, 0))
        let monday = cal.date(byAdding: .day, value: 1, to: wk) ?? wk, mc = cal.dateComponents([.year, .month], from: monday)
        let m = MasterSchedule.month(plan: plan, actual: actual, year: mc.year ?? 0, month: mc.month ?? 0)
        o += monthly(m, title: "Monthly Update · เดือน \(mc.month ?? 0)/\((mc.year ?? 0) + 543)",
                     at: Pt(width - margin - panelW, top + 470))

        // legend and source
        let ly = height - margin - 4
        o.append(.rect(Box(margin, ly - 9, 18, 6), stroke: nil, fill: navy))
        o.append(.text("แผน", at: Pt(margin + 24, ly - 6), size: 8, color: navy))
        o.append(.rect(Box(margin + 60, ly - 9, 18, 6), stroke: nil, fill: primary))
        o.append(.text("ทำจริง (เข้มตามสัดส่วนของน้ำหนักงาน)", at: Pt(margin + 84, ly - 6), size: 8, color: navy))
        o.append(.line(Pt(margin + 260, ly - 12), Pt(margin + 260, ly), width: 1.5, color: red))
        o.append(.text("วันนี้", at: Pt(margin + 266, ly - 6), size: 8, color: navy))
        o.append(.text("สร้างจาก TCRoof · \(short(Date()))", at: Pt(width - margin, ly - 6), size: 8, color: muted, align: .right))
        return Sketch(width: width, height: height, ops: o)
    }

    static func variance(_ v: Double) -> String {
        v < -0.05 ? "ช้ากว่า \(pct(-v))" : v > 0.05 ? "เร็วกว่า \(pct(v))" : "ตามแผน"
    }

    // MARK: Gantt

    static func gantt(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, weeks: [Date], chosen: Date, in b: Box) -> [DrawOp] {
        let cal = MasterSchedule.calendar
        let rows: [(MasterSchedule.Part?, MasterSchedule.PlannedTask?)] = MasterSchedule.Part.allCases.flatMap { p in
            [(p, nil)] + plan.filter { $0.task.part == p }.map { (nil, $0) }
        }
        let headH = 24.0, rowH = (b.h - headH) / Double(rows.count)
        let gx = b.x + labelW, gw = b.w - labelW, cw = gw / Double(max(weeks.count, 1))
        let first = weeks.first ?? chosen
        func x(_ d: Date) -> Double { gx + Double(cal.dateComponents([.day], from: first, to: cal.startOfDay(for: d)).day ?? 0) / 7 * cw }
        var o: [DrawOp] = []

        if let i = weeks.firstIndex(of: chosen) { o.append(.rect(Box(gx + Double(i) * cw, b.y, cw, b.h), stroke: nil, fill: soft)) }
        // week labels, thinned to fit
        let every = max(1, Int((22 / cw).rounded(.up)))
        for (i, w) in weeks.enumerated() {
            let wx = gx + Double(i) * cw
            o.append(.line(Pt(wx, b.y), Pt(wx, b.maxY), width: 0.3, color: line))
            guard i % every == 0 else { continue }
            let c = cal.dateComponents([.day, .month], from: w)
            o.append(.text("\(c.day ?? 0)/\(c.month ?? 0)", at: Pt(wx + cw * Double(every) / 2, b.y + 7), size: 6.5, color: muted, align: .center))
            o.append(.text("W\(i)", at: Pt(wx + cw * Double(every) / 2, b.y + 17), size: 6.5, bold: true, color: muted, align: .center))
        }
        o.append(.text("งาน", at: Pt(b.x + 4, b.y + 12), size: 8, bold: true, color: muted))

        for (r, row) in rows.enumerated() {
            let y = b.y + headH + Double(r) * rowH
            o.append(.line(Pt(b.x, y + rowH), Pt(b.maxX, y + rowH), width: 0.3, color: line))
            if let part = row.0 {
                o.append(.rect(Box(b.x, y, b.w, rowH), stroke: nil, fill: soft))
                o.append(.text(part.reportTitle, at: Pt(b.x + 4, y + rowH / 2), size: 9, bold: true, color: navy))
                continue
            }
            guard let t = row.1 else { continue }
            let faded = t.weight == 0
            o.append(.text(t.task.code, at: Pt(b.x + 4, y + rowH / 2), size: 8, bold: true, color: faded ? muted : primary))
            o.append(.textBox(t.task.title, Box(b.x + 28, y + rowH / 2 - 5.5, labelW - 70, rowH), size: 7.5, color: faded ? muted : navy))
            o.append(.text(faded ? "ไม่ใช้" : pct(t.weight), at: Pt(gx - 6, y + rowH / 2), size: 7.5, color: muted, align: .right))
            if let s = t.start, let e = t.end {
                let x0 = x(s), x1 = max(x(e) + cw / 7, x0 + 2)
                o.append(.rect(Box(x0, y + rowH * 0.18, x1 - x0, rowH * 0.28), stroke: nil, fill: faded ? line : navy))
            }
            guard !faded else { continue }
            for (k, pts) in actual.points[t.task.rawValue] ?? [:] where pts > 0 {
                guard let d = MasterSchedule.date(fromKey: k, calendar: cal), let i = weeks.firstIndex(of: d) else { continue }
                let a = 0.3 + 0.7 * min(1, pts / t.weight)
                o.append(.rect(Box(gx + Double(i) * cw + 0.8, y + rowH * 0.56, max(cw - 1.6, 1), rowH * 0.28), stroke: nil,
                               fill: RGBA(primary.r, primary.g, primary.b, a)))
            }
        }
        let tx = x(Date())
        if tx >= gx && tx <= b.maxX { o.append(.line(Pt(tx, b.y), Pt(tx, b.maxY), width: 1.2, color: red)) }
        o.append(.rect(b, stroke: line, fill: nil, width: 0.6))
        o.append(.line(Pt(gx, b.y), Pt(gx, b.maxY), width: 0.6, color: line))
        return o
    }

    // MARK: Reports

    static func tableRow(_ title: String, _ p: Double, _ a: Double, at y: Double, x: Double, bold: Bool = false) -> [DrawOp] {
        let v = a - p
        return [
            .textBox(title, Box(x, y - 5.5, panelW - 140, 22), size: 8.5, bold: bold, color: navy),
            .text(pct(p), at: Pt(x + panelW - 92, y), size: 8.5, color: muted, align: .right),
            .text(pct(a), at: Pt(x + panelW - 46, y), size: 8.5, bold: true, color: navy, align: .right),
            .text(abs(v) < 0.05 ? "–" : (v > 0 ? "+" : "−") + String(pct(abs(v)).dropLast()), at: Pt(x + panelW, y), size: 8.5,
                  color: v < -0.05 ? red : v > 0.05 ? green : muted, align: .right),
        ]
    }

    static func heading(_ s: String, at p: Pt) -> [DrawOp] {
        [.text(s, at: p, size: 11, bold: true, color: navy),
         .text("แผน", at: Pt(p.x + panelW - 92, p.y + 16), size: 7.5, color: muted, align: .right),
         .text("จริง", at: Pt(p.x + panelW - 46, p.y + 16), size: 7.5, color: muted, align: .right),
         .text("ต่าง", at: Pt(p.x + panelW, p.y + 16), size: 7.5, color: muted, align: .right)]
    }

    static func weekly(_ st: MasterSchedule.Status, plan: [MasterSchedule.PlannedTask], in b: Box) -> [DrawOp] {
        var o = heading("Weekly Update (สะสม)", at: Pt(b.x, b.y + 6)), y = b.y + 38
        o += tableRow("รวมทั้งสถานี", st.planned, st.actual, at: y, x: b.x, bold: true); y += 20
        for p in MasterSchedule.Part.allCases {
            o += tableRow(p.reportTitle, st.plannedByPart[p] ?? 0, st.actualByPart[p] ?? 0, at: y, x: b.x); y += 20
        }
        o.append(.line(Pt(b.x, y - 6), Pt(b.x + panelW, y - 6), width: 0.5, color: line))
        o.append(.text("งานติดตั้ง (% ของแต่ละงาน)", at: Pt(b.x, y + 4), size: 8.5, bold: true, color: navy)); y += 22
        for t in plan where t.task.part == .construction && t.weight > 0 {
            o += tableRow("\(t.task.code) \(t.task.title)", st.plannedByTask[t.task] ?? 0, st.actualByTask[t.task] ?? 0, at: y, x: b.x)
            y += 30
        }
        return o
    }

    static func monthly(_ m: (planned: [MasterSchedule.Part: Double], actual: [MasterSchedule.Part: Double]), title: String, at p: Pt) -> [DrawOp] {
        var o = heading(title, at: p), y = p.y + 32
        o += tableRow("รวมเดือนนี้", m.planned.values.reduce(0, +), m.actual.values.reduce(0, +), at: y, x: p.x, bold: true); y += 20
        for part in MasterSchedule.Part.allCases {
            o += tableRow(part.reportTitle, m.planned[part] ?? 0, m.actual[part] ?? 0, at: y, x: p.x); y += 20
        }
        o.append(.text("% ของทั้งสถานีที่ทำในเดือนนี้", at: Pt(p.x, y), size: 7.5, color: muted))
        return o
    }
}
