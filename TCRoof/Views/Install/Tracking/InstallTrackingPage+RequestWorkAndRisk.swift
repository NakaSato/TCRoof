import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: 3 งานที่ขอเข้าปฏิบัติ

    func workCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let plan = job.scheduleInput.map { MasterSchedule.plan($0) }
        return reqCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    numbered(3, "งานที่ขอเข้าปฏิบัติ")
                    Text("\(r.work.count) งาน | \(r.work.count - r.linesWithoutDay) มีวัน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    if let at = reqPulledAt { chip("✓ ดึงจากแผน MP " + String(format: "%02d:%02d", RoutineReport.calendar.component(.hour, from: at), RoutineReport.calendar.component(.minute, from: at)), .ok).fixedSize() }
                    Spacer(minLength: 8)
                    legendSwatch(Theme.primary, "วันทำงาน", outlined: false)
                    legendSwatch(Theme.warning, "ยกมา", outlined: false)
                    legendSwatch(Theme.warning, "ยังไม่มีวัน", outlined: true)
                }
                VStack(spacing: 0) {
                    workRow {
                        Text("MP")
                    } title: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("งาน | ตำแหน่ง | ปริมาณ")
                            if editable { Text("แตะช่องวันเพื่อเลือก / ยกเลิก").font(.sarabunFixed(12)) }
                        }
                    } days: { d in Text(Self.dayTitle(r, d)) } tail: { EmptyView() }
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(height: 46)
                    ForEach(Array(r.work.enumerated()), id: \.element.id) { i, line in
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        workLine(r, line, index: i, late: lateDays(line, plan: plan, weekStart: r.weekStart), editable: editable)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    workRow { EmptyView() } title: { Text("งานต่อวัน").foregroundStyle(Theme.inkMuted) } days: { d in
                        let n = r.lines(on: d)
                        Text(n > 0 ? "\(n) งาน" : "–").bold().foregroundStyle(n > 0 ? Theme.navy : Theme.inkFaint).accessibilityIdentifier("workDay\(d)")
                    } tail: { EmptyView() }
                        .font(.sarabunFixed(14)).frame(height: 46)
                }
                .padding(.horizontal, 12)
                .background(Theme.phonePage.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if editable {
                    Button { reqSheet = .addLine } label: { Label("เพิ่มงานนอกแผน MP", systemImage: "plus").font(.sarabunFixed(15, .bold)) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).accessibilityIdentifier("requestAddLine")
                }
            }
        }
    }

    private func legendSwatch(_ c: Color, _ title: String, outlined: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(outlined ? Color.clear : c).frame(width: 12, height: 12)
                .overlay { if outlined { RoundedRectangle(cornerRadius: 3).strokeBorder(c, lineWidth: 1.5) } }
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func workRow<A: View, B: View, C: View, D: View>(@ViewBuilder _ code: () -> A, @ViewBuilder title: () -> B,
                                                              @ViewBuilder days: @escaping (Int) -> C, @ViewBuilder tail: () -> D) -> some View {
        HStack(spacing: 8) {
            code().frame(width: 52, alignment: .leading)
            title().frame(width: 300, alignment: .leading)
            ForEach(reqDays, id: \.self) { d in days(d).frame(maxWidth: .infinity) }
            tail().frame(width: 44)
        }
    }

    private func workLine(_ r: RoutineReport.WeeklyRequest, _ line: RoutineReport.PlanLine, index i: Int, late: Int?, editable: Bool) -> some View {
        let outside = r.work.prefix(i + 1).filter { $0.task == nil }.count
        let (tag, tone): (String, InstallPageData.Tone) = line.task == nil ? ("นอกแผน MP", .idle)
            : line.days.isEmpty ? ("ยังไม่มีวัน | รอนัด", .warn) : late.map { ("ยกมา | ช้า \($0) วัน", .warn) } ?? ("จากแผน MP", .info)
        let qty = line.qty > 0 ? (line.qty.formatted(.number.precision(.fractionLength(0...2))) + (line.unit.isEmpty ? "" : " " + line.unit)) : ""
        return workRow {
            Text(line.task?.code ?? "+\(outside)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).monospacedDigit()
        } title: {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.description.isEmpty ? (line.task?.title ?? "งานอื่น") : line.description)
                    .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                HStack(spacing: 6) {
                    chip(tag, tone).fixedSize()
                    Text([line.location, qty].filter { !$0.isEmpty }.joined(separator: " | ")).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
        } days: { d in
            workCell(r, line, day: d, carried: late != nil && line.days.first == d, editable: editable)
        } tail: {
            if editable {
                Button {
                    reqChange { $0.work.removeAll { $0.id == line.id } }
                    showToast("เอาออกจากคำขอแล้ว | ยังอยู่ในแผน MP")
                } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("เอางานออกจากคำขอ")
            }
        }
        .frame(minHeight: 64)
    }

    private func workCell(_ r: RoutineReport.WeeklyRequest, _ line: RoutineReport.PlanLine, day d: Int, carried: Bool, editable: Bool) -> some View {
        let on = line.days.contains(d), none = line.days.isEmpty
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button { if editable { reqChange { $0.toggleDay(line: line.id, day: d) } } } label: {
            ZStack {
                if on {
                    shape.fill(carried ? Theme.warning : Theme.primary)
                    if carried { Text("ยกมา").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary) }
                } else if none {
                    shape.strokeBorder(Theme.warning.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.fill(Theme.hairline)
                }
            }
            .frame(height: 30).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.dayTitle(r, d) + (on ? " มีงาน" : " ไม่มีงาน"))
        .accessibilityIdentifier("workCell\(line.task?.code ?? line.id.uuidString)-\(d)")
    }

    /// A line carried over: its task should have ended before this week; how many days late it is by Monday.
    func lateDays(_ line: RoutineReport.PlanLine, plan: [MasterSchedule.PlannedTask]?, weekStart: Date) -> Int? {
        #if DEBUG
        if Debug.demo { return line.task == .monitoring ? 1 : nil }
        #endif
        guard let t = line.task, let end = plan?.first(where: { $0.task == t })?.end, end < weekStart else { return nil }
        let monday = RoutineReport.add(weekStart, 1)
        return max(1, RoutineReport.calendar.dateComponents([.day], from: RoutineReport.day(end), to: monday).day ?? 1)
    }

    // MARK: 4 ประเมินความเสี่ยง

    func riskCard(_ r: RoutineReport.WeeklyRequest, editable: Bool) -> some View {
        let missing = RoutineReport.commonRisks.filter { c in !r.risks.contains { $0.description.contains(c) } }
        return reqCard {
            VStack(alignment: .leading, spacing: 12) {
                numbered(4, "ประเมินความเสี่ยง")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(r.risks) { risk in riskBox(risk, editable: editable) }
                }
                if editable && !missing.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(missing, id: \.self) { m in
                            Button("+ " + m) { reqChange { $0.risks.append(.init(description: m)) } }
                                .font(.sarabunFixed(14, .bold)).buttonStyle(TCButtonStyle(.secondary, size: .card))
                        }
                    }
                }
            }
        }
    }

    /// A text of one risk, found by its id when read and when written (and saved through `reqChange`).
    private func riskText(_ id: UUID, _ field: WritableKeyPath<RoutineReport.Risk, String>) -> Binding<String> {
        Binding(get: { request?.risks.first { $0.id == id }?[keyPath: field] ?? "" },
                set: { v in reqChange { $0.updateRisk(id) { $0[keyPath: field] = v } } })
    }

    private func riskBox(_ risk: RoutineReport.Risk, editable: Bool) -> some View {
        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if editable {
                    TextField("ความเสี่ยง", text: riskText(risk.id, \.description))
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                } else {
                    Text(risk.description).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                }
                Spacer(minLength: 4)
                if editable {
                    Button { reqChange { $0.risks.removeAll { $0.id == risk.id } } } label: { Image(systemName: "xmark").foregroundStyle(Theme.inkMuted).frame(width: 32, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel("ลบความเสี่ยง")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("ป้องกัน:").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                if editable {
                    TextField("แนวทางป้องกัน", text: riskText(risk.id, \.prevention), axis: .vertical)
                        .font(.sarabunFixed(13))
                } else {
                    Text(risk.prevention).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
            }
            HStack(spacing: 6) {
                ForEach(RoutineReport.RiskLevel.allCases, id: \.self) { l in
                    let on = risk.level == l
                    let (ink, fill): (Color, Color) = switch l {
                    case .low: (Theme.successInk, Theme.successSoft)
                    case .medium: (Theme.warningInk, Theme.warningSoft)
                    case .high: (Theme.dangerText, Theme.dangerSoft)
                    }
                    Button { if editable { reqChange { $0.updateRisk(risk.id) { $0.level = l } } } } label: {
                        Text(l.title).font(.sarabunFixed(13, .bold)).foregroundStyle(on ? ink : Theme.inkMuted)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(on ? fill : Theme.hairline, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
    }

    // MARK: toast

    func showToast(_ text: String) {
        reqToast = text
        Task { try? await Task.sleep(for: .seconds(2.2)); if reqToast == text { reqToast = nil } }
    }

    func toast(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.navySolid.opacity(0.9), in: Capsule())
            .padding(.bottom, 110)
            .transition(.opacity)
            .accessibilityIdentifier("requestToast")
    }
}
