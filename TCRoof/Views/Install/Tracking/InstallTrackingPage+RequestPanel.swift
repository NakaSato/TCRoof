import SwiftUI
import PDFKit
import TCRoofUI
import TCRoofCore

/// `คำขอรายสัปดาห์`'s right panel (docs/ui/install-tracking-ipad-weekly-request §4.6): the approval flow, the checks
/// before sending, the requester's signature and name, the action; and the tab's sheets.
extension InstallTrackingPage {
    func requestPanel(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("สัปดาห์ที่ \(Self.weekNumber(r))").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                requestStatusChip(r)
            }
            approvalFlow(r)
            if r.status != .approved { checksList(r) }
            Spacer(minLength: 0)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            signatureBlock(r, editable: editable)
            actionButtons(r)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
        // beside the dock, the panel runs down to the screen's edge
        .padding(.bottom, 18)
    }

    // MARK: flow

    private func approvalFlow(_ r: RoutineReport.WeeklyRequest) -> some View {
        let inspector = reqSettings.inspector.isEmpty ? "กฟภ." : reqSettings.inspector
        let sent = r.status != .draft, approved = r.status == .approved
        let signed = sent || reqSignature != nil
        let steps: [(String, String, Bool)] = [
            ("ร่างคำขอ", "Site Engineer | " + (signed ? "ลงนามแล้ว" : "ยังไม่ลงนาม"), sent),
            ("ส่งขออนุมัติ (PDF)", "ส่งถึงผู้ตรวจ " + inspector, sent),
            ("อนุมัติ", "ผู้ตรวจ " + inspector, approved)]
        let current = steps.firstIndex { !$0.2 }
        return HStack(alignment: .top, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(s.2 ? Theme.success : i == current ? Theme.primary : Theme.track).frame(width: 26, height: 26)
                        if s.2 { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
                        else { Text("\(i + 1)").font(.sarabunFixed(13, .bold)).foregroundStyle(i == current ? Theme.onPrimary : Theme.inkMuted) }
                    }
                    Text(s.0).font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.navy).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(s.1).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityValue(s.2 ? "เสร็จแล้ว" : i == current ? "ขั้นปัจจุบัน" : "ยังไม่ถึง")
            }
        }
        .padding(12)
        .background(Theme.phonePage.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: checks

    /// The checks before sending: warnings, except the signature and the name, which hold the send.
    func requestChecks(_ r: RoutineReport.WeeklyRequest) -> [(ok: Bool, title: String, why: String?)] {
        #if DEBUG
        let draft = Debug.demo ? Self.demoRequest(week: r.weekStart, back: 0) : WeeklyRequestStore.draft(job, r.weekStart)
        #else
        let draft = WeeklyRequestStore.draft(job, r.weekStart)
        #endif
        let missing = Set(draft.work.compactMap(\.task)).subtracting(r.work.compactMap(\.task)).count
        let noDay = r.linesWithoutDay, noPlace = r.work.filter { $0.location.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let height = r.risks.contains { $0.description.contains(RoutineReport.commonRisks[0]) || $0.description.contains("ที่สูง") }
        let live = r.risks.contains { $0.description.contains(RoutineReport.commonRisks[2]) || $0.description.contains("ไฟฟ้า") }
        let signed = r.status != .draft || reqSignature != nil, named = !reqName.trimmingCharacters(in: .whitespaces).isEmpty
        var why: [String] = []
        if noDay > 0 { why.append("\(noDay) งานยังไม่มีวัน | แตะช่องวันเพื่อเลือก") }
        if noPlace > 0 { why.append("\(noPlace) งานยังไม่มีตำแหน่ง") }
        return [
            (missing == 0, "แผนงานตรงกับแผน MP สัปดาห์ที่ \(Self.weekNumber(r))", missing == 0 ? nil : "ขาด \(missing) งานจากแผน | แตะ ดึงจากแผน MP"),
            (why.isEmpty, "ทุกงานมีตำแหน่งและวัน", why.isEmpty ? nil : why.joined(separator: " | ")),
            (height && live, "ประเมินความเสี่ยงงานบนที่สูงและงานไฟฟ้า", height && live ? nil : "ยังไม่มี" + (height ? "งานไฟฟ้า" : live ? "งานบนที่สูง" : "ทั้งสองข้อ")),
            (r.perDay > 0, "มีกำลังคนในคำขอ", r.perDay > 0 ? nil : "ยังไม่มีคนในตำแหน่งใด"),
            (signed && named, "ผู้ส่งคำขอลงนาม", !signed ? "ยังไม่ได้เซ็น | เซ็นด้านล่าง" : named ? nil : "ใส่ชื่อผู้ส่งคำขอ"),
        ]
    }

    private func checksList(_ r: RoutineReport.WeeklyRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ตรวจก่อนส่ง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
            ForEach(Array(requestChecks(r).enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(c.ok ? Theme.successSoft : Theme.warningSoft).frame(width: 24, height: 24)
                        Image(systemName: c.ok ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(c.ok ? Theme.successInk : Theme.warningInk)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                        if let w = c.why { Text(w).font(.sarabunFixed(13)).foregroundStyle(Theme.warningInk) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: signature

    private func signatureBlock(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let draft = r.status == .draft
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                let star = Text("*").foregroundStyle(Theme.danger)
                Text("ลายเซ็นผู้ส่งคำขอ \(star)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("SITE ENGINEER").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted)
            }
            if let png = reqSignature, let img = UIImage(data: png) {
                VStack(alignment: .leading, spacing: 2) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 46)
                    Text("ลงนาม " + Self.signedLine(reqSignedAt ?? .now)).font(.sarabunFixed(12)).foregroundStyle(Theme.successInk)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(Theme.successSoft.opacity(0.5), in: frame)
                .overlay(frame.strokeBorder(Theme.success.opacity(0.6)))
                .overlay(alignment: .topTrailing) {
                    if draft && editable {
                        Button { setSignature(nil) } label: { Image(systemName: "xmark").foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("ล้างลายเซ็น")
                    }
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("requestSigned")
            } else if !draft, let at = r.engineerSignedAt ?? r.sentAt {
                Text("ลงนาม " + Self.signedLine(at)).font(.sarabunFixed(13)).foregroundStyle(Theme.successInk)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(.horizontal, 12)
                    .background(Theme.successSoft.opacity(0.5), in: frame)
            } else {
                Button { reqSheet = .sign } label: {
                    Label("เซ็นชื่อ", systemImage: "signature").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.warningInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.warningSoft.opacity(0.4), in: frame)
                        .overlay(frame.strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                }
                .buttonStyle(.plain).disabled(!editable).accessibilityIdentifier("requestSign")
            }
            if draft && editable {
                TextField("ชื่อผู้ส่งคำขอ", text: $reqName).font(.sarabunFixed(15)).textFieldStyle(OutlinedFieldStyle())
                    .accessibilityIdentifier("requestName")
            } else {
                let name = r.sentBy.isEmpty ? reqName : (TeamDirectory.shared.person(r.sentBy)?.name ?? reqName)
                if !name.isEmpty { Text(name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy) }
            }
        }
    }

    static func signedLine(_ d: Date) -> String {
        let cal = RoutineReport.calendar
        let day = cal.isDateInToday(d) ? "วันนี้" : RoutineReport.thaiDate(d)
        return day + String(format: " %02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
    }

    // MARK: actions

    @ViewBuilder private func actionButtons(_ r: RoutineReport.WeeklyRequest) -> some View {
        if !reqMayAct {
            note("ดูอย่างเดียว")
        } else {
            switch r.status {
            case .draft:
                let ready = reqSignature != nil && !reqName.trimmingCharacters(in: .whitespaces).isEmpty
                Button { sendRequest() } label: { Text("ส่งขออนุมัติ (PDF)").frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                    .disabled(!ready).accessibilityIdentifier("requestSend")
            case .sent where reqExternal:
                note("ส่งแล้ว | รอทีมอนุมัติ")
            case .sent:
                VStack(spacing: 8) {
                    Button { reqSheet = .approve } label: { Text("บันทึกอนุมัติแล้ว").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true)).accessibilityIdentifier("requestApprove")
                    Button { reqChange { $0.sendBack() }; setSignature(nil) } label: { Text("ส่งกลับให้แก้").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true)).accessibilityIdentifier("requestSendBack")
                }
            case .approved:
                VStack(spacing: 8) {
                    Label("อนุมัติแล้ว", systemImage: "checkmark.circle.fill").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.successInk)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if !reqExternal {
                        Button { reqChange { $0.reopen() } } label: { Text("เปิดแก้อีกครั้ง").frame(maxWidth: .infinity) }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true)).accessibilityIdentifier("requestReopen")
                    }
                }
            }
        }
    }

    /// Keeps the drawn signature on the job for this week (it syncs and prints on R1), or removes it; the board's example
    /// keeps it in memory only.
    func setSignature(_ png: Data?) {
        reqSignature = png
        reqSignedAt = png == nil ? nil : .now
        #if DEBUG
        if Debug.demo { return }
        #endif
        if let r = request { job.setRequestSignature(png, for: r, context: context) }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityIdentifier("requestNote")
    }

    /// `ส่งขออนุมัติ (PDF)`: sends it (our engineer's send signs it, as `WeeklyRequestScreen`), files the PDF and shows it.
    private func sendRequest() {
        reqChange { $0.send(by: permissions.email, signs: !reqExternal) }
        #if DEBUG
        if Debug.demo { reqSheet = .pdf; return }
        #endif
        if let r = request { WeeklyRequestStore.save(r, job: job, external: reqExternal, file: true, context: context) }
        reqSheet = .pdf
    }

    // MARK: sheets

    @ViewBuilder func requestSheet(_ s: RequestSheet, _ r: RoutineReport.WeeklyRequest) -> some View {
        switch s {
        case .sign:
            RequestSignSheet(name: reqName) { png, name in
                setSignature(png)
                if !name.isEmpty { reqName = name }
            }
        case .pdf:
            RequestPDFSheet(job: job, request: r, week: Self.weekNumber(r), demo: Self.isDemo) { url in shared = Shared(url: url) }
        case .approve:
            InspectorAckSheet(title: "บันทึกอนุมัติแล้ว", name: r.approvedBy.isEmpty ? reqSettings.inspector : r.approvedBy, date: r.approvedAt ?? .now) { name, when, _ in
                reqChange { $0.approve(by: name, at: when) }
                #if DEBUG
                if Debug.demo { return }
                #endif
                if let r = request { WeeklyRequestStore.save(r, job: job, external: reqExternal, file: true, context: context) }
            }
        case .addLine:
            AddOutsideLineSheet(locations: reqSettings.locations) { line in reqChange { $0.work.append(line) } }
        }
    }

    static var isDemo: Bool {
        #if DEBUG
        Debug.demo
        #else
        false
        #endif
    }

    // MARK: demo

    #if DEBUG
    /// The board's example (`assets/sample-data.json`), dated from the week given; nothing is kept. `back` 1 and 2 are
    /// the approved weeks before.
    static func demoRequest(week: Date, back: Int) -> RoutineReport.WeeklyRequest {
        var r = RoutineReport.WeeklyRequest(weekStart: week)
        r.crew = [("ผู้ควบคุมงาน", 1), ("หัวหน้างาน", 1), ("ช่างไฟฟ้า", 2), ("ผู้ปฏิบัติงาน", 4)].map { .init(name: $0.0, count: $0.1) }
        r.tools = [("เครื่องวัดฉนวน (Megger)", 1), ("แคลมป์มิเตอร์ DC", 1), ("สว่านไร้สาย", 2), ("รถกระเช้า", 1)].map { .init(name: $0.0, count: $0.1) }
        func task(_ code: String) -> MasterSchedule.Task? { MasterSchedule.Task.allCases.first { $0.code == code } }
        let lines: [(String, String, String, Double, String, [Int])] = [
            ("3.1", "ตรวจร่วม Punch list กับเจ้าของงาน", "ทั้งสถานี", 1, "ครั้ง", [0]),
            ("2.8", "แก้ไขรายการ Punch list", "ตามรายการ", 0, "", [0, 1]),
            ("2.9", "Data Logger | Monitoring (ต่อจากสัปดาห์นี้)", "ห้อง MDB", 1, "ชุด", [0]),
            ("1.7", "การไฟฟ้าตรวจขนานไฟ (รอนัด)", "ตู้ AC | มิเตอร์", 1, "ครั้ง", []),
            ("3.2", "ส่งมอบงาน | อบรมผู้ใช้", "อาคารสำนักงาน", 1, "ครั้ง", [1]),
            ("2.7", "แบบ As-built | เอกสารส่งมอบ", "สำนักงาน", 1, "ชุด", [1, 2])]
        r.work = lines.map { .init(task: task($0.0), description: $0.1, location: $0.2, qty: $0.3, unit: $0.4, days: $0.5) }
        r.risks = [.init(description: "งานบนที่สูง (หลังคา)", level: .high, prevention: "สายรัดตัวนิรภัย | ราวกันตก | จป. ตรวจก่อนขึ้น"),
                   .init(description: "งานไฟฟ้ามีแรงดัน (ขนานไฟ)", level: .high, prevention: "LOTO | ถุงมือฉนวน | ช่างไฟฟ้ามีใบอนุญาตคุมงาน"),
                   .init(description: "ฝนตก | ฟ้าผ่า", level: .medium, prevention: "หยุดงานบนหลังคาเมื่อฝนตก | ปิดเบรกเกอร์ DC")]
        if back > 0 {
            let at = RoutineReport.add(r.weekStart, -2)
            r.sentAt = at; r.engineerSignedAt = at
            r.approve(by: "ผู้ตรวจ กฟภ.", at: at)
        }
        return r
    }

    static var demoInstruments: [Instrument] {
        [Instrument(id: "d1", name: "เครื่องวัดฉนวน (Megger)", code: "", kind: "", calibrationDue: Date.now.adding(days: 150)),
         Instrument(id: "d2", name: "แคลมป์มิเตอร์ DC", code: "", kind: "", calibrationDue: Date.now.adding(days: 18)),
         Instrument(id: "d3", name: "สว่านไร้สาย", code: "", kind: "", calibrationDue: nil)]
    }

    /// A drawn signature for `-installRequestState signed`.
    static var demoSignature: Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 70)).image { ctx in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 10, y: 50))
            for i in 1...10 { p.addQuadCurve(to: CGPoint(x: 10 + i * 22, y: i % 2 == 0 ? 50 : 30), controlPoint: CGPoint(x: i * 22, y: i % 2 == 0 ? 10 : 70)) }
            UIColor(Theme.navy).setStroke(); p.lineWidth = 3; p.stroke()
        }.pngData()
    }
    #endif
}

#if DEBUG
extension InstallTrackingPage {
    /// `-installRequestState`: the board's states 02–08 on the opened week (in memory with `-installDemo YES`).
    func applyRequestState() {
        guard let state = Debug.requestState else { return }
        switch state {
        case "sign": reqSheet = .sign
        case "signed": reqSignature = Self.demoSignature; reqSignedAt = .now
        case "sent": reqSignature = Self.demoSignature; reqChange { $0.send(by: permissions.email, signs: !reqExternal) }
        case "approved":
            reqChange { $0.send(by: permissions.email, signs: true); $0.approve(by: reqSettings.inspector.isEmpty ? "ผู้ตรวจ กฟภ." : reqSettings.inspector, at: .now) }
        case "pdf": reqSheet = .pdf
        case "edited":
            reqChange { r in
                if let i = r.crew.indices.last { r.crew[i].count += 1 }
                if !r.crew.isEmpty, let d = r.work.flatMap(\.days).first { r.toggleOff(role: 0, day: d) }
                if let i = r.work.firstIndex(where: \.days.isEmpty) { r.work[i].days = [2] }
                if r.work.count > 1 { r.work.remove(at: 1) }
                r.work.append(.init(task: nil, description: "ล้างแผงก่อนตรวจขนานไฟ", location: "หลังคา 1", qty: 1, unit: "ครั้ง", days: [3]))
            }
        default: break
        }
    }
}
#endif
