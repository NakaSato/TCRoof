#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Icon and title close together, for small badges.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}

/// The project card of docs/ui/pwa-solar-survey-iphone: one size, in one column on iPhone and three on iPad.
struct JobCard: View {
    /// A survey (also once moved to installation), or the installation job itself.
    enum Mode { case survey, install }
    let job: Job
    var mode = Mode.survey
    var pendingSync = false
    var synced = false
    var recent = false
    /// The job's station in the install overview, once it has moved to installation: the card then shows the
    /// install phase (docs/ui/pwa-solar-survey-iphone-v3 §4).
    var station: InstallStationSummary?
    @Environment(SurveyModel.self) private var model
    var phase: InstallStationSummary? { station }

    @ViewBuilder var body: some View {
        if let phase {
            card.accessibilityElement(children: .ignore).accessibilityLabel(phaseLabel(phase)).accessibilityAddTraits(.isButton)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("NO.\(job.docNo.isEmpty ? " —" : job.docNo)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        if phase != nil { phaseBadge }
                        else if mode == .install || job.stage != .survey { installBadge }
                        else { surveyBadge }
                    }
                    if job.projectName.isEmpty {
                        Text("ยังไม่ได้ตั้งชื่อโครงการ").font(.sarabunFixed(16, .bold)).italic().foregroundStyle(Theme.inkMuted)
                    } else {
                        Text(job.projectName).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                    }
                    Text(detailLine).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let phase {
                    PercentRing(percent: Int(phase.actual.rounded()), style: .cardSmall, tint: late(phase) ? Theme.danger : Theme.primary)
                } else {
                    PercentRing(percent: mode == .install ? install.percent : job.completion.percent, style: .cardSmall)
                }
            }
            if let phase { phaseProgress(phase) } else if mode == .install { installProgress } else { surveyProgress }
            if phase == nil, mode != .install, let id = job.jobSyncID, let label = model.linkedJobLabel?(id) {
                Label(label, systemImage: "link").font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.primary).lineLimit(1)
            }
            if let phase {
                phaseChips(phase)
            } else if mode == .install {
                HStack(spacing: 6) {
                    chip(install.team.isEmpty ? "ยังไม่กำหนดทีม" : "ทีม " + install.team)
                    chip("ส่งมอบ " + (install.dueDate.map { ISODate.thai(ISODate.string($0)) } ?? "ยังไม่กำหนด"))
                }
            } else if !job.sectionsByCategory.isEmpty {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(job.sectionsByCategory) { g in
                        Text("\(g.category.rawValue) \(g.category.title) ×\(g.sections.count)").font(.sarabunFixed(11, .semibold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 8).padding(.vertical, 1).background(Theme.primarySoft, in: Capsule())
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Label(dateLine, systemImage: "calendar")
                Spacer()
                Label("\(job.photoCount)", systemImage: "photo")
                syncMark
            }
            .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(recent ? Theme.primary : Theme.borderSubtle, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder var surveyProgress: some View {
        let steps = job.stepStatuses
        let next = job.nextStep
        let nextIndex = next.flatMap { n in steps.firstIndex { $0.step.page == n.page } }
        HStack(spacing: 2) {
            ForEach(steps, id: \.step.id) { s in Capsule().fill(color(s.status)).frame(height: 6) }
        }
        continueRow(next: next, index: nextIndex.map { $0 + 1 }, total: steps.count)
    }

    var install: InstallInfo { job.install ?? InstallInfo(movedAt: job.updated) }

    /// Seven installation steps: done, in progress, not yet.
    @ViewBuilder var installProgress: some View {
        let n = InstallInfo.steps.count
        HStack(spacing: 4) {
            ForEach(0..<n, id: \.self) { i in
                Capsule().fill(i < install.doneSteps ? Theme.mint : i == install.doneSteps ? Theme.primary : Theme.track).frame(height: 5)
            }
        }
        actionRow(Text("ขั้น \(min(install.doneSteps + 1, n))/\(n)").monospacedDigit(), Text(install.currentStep ?? "ส่งมอบแล้ว"),
                  background: install.isDone ? Theme.mint.opacity(0.25) : Theme.primary.opacity(0.08))
    }

    var installBadge: some View {
        Text(install.doneSteps > 0 ? "กำลังติดตั้ง" : "รอเริ่มงาน").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.primarySoft, in: Capsule())
    }

    var surveyBadge: some View {
        Text("สำรวจ").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 8).frame(height: 18).background(Theme.primarySoft, in: Capsule())
    }

    // MARK: install phase

    private func late(_ s: InstallStationSummary) -> Bool {
        InstallOverview.pace(s, threshold: model.settings.behindThreshold) == .behind
    }

    /// `ช้ากว่าแผน n%` or `ตามแผน`; nothing for a station with no MP plan.
    private func paceText(_ s: InstallStationSummary) -> String? {
        guard let v = s.variance else { return nil }
        return late(s) ? "ช้ากว่าแผน \(-v)%" : "ตามแผน"
    }

    /// What VoiceOver reads for the install-phase card.
    private func phaseLabel(_ s: InstallStationSummary) -> String {
        [job.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : job.projectName, "ติดตั้ง",
         taskText(s), paceText(s) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `กำลังทำ <task>`, or `ยังไม่มีแผน MP` for a station with no plan and no task yet, such as a survey just moved.
    private func taskText(_ s: InstallStationSummary) -> String {
        if !s.currentTask.isEmpty { return "กำลังทำ " + s.currentTask }
        return s.plan == nil ? "ยังไม่มีแผน MP" : ""
    }

    var phaseBadge: some View {
        HStack(spacing: 3) {
            HardHat().stroke(Theme.okTick, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 13)
            Text("ติดตั้ง").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.okTick)
        }
        .padding(.horizontal, 8).frame(height: 18).background(Theme.okSoft, in: Capsule())
    }

    /// Ten segments over the MP plan's 0–100 %, then `กำลังทำ <task>` with the pace.
    @ViewBuilder private func phaseProgress(_ s: InstallStationSummary) -> some View {
        let isLate = late(s)
        HStack(spacing: 2) {
            ForEach(Array(InstallOverview.bar(s, threshold: model.settings.behindThreshold).enumerated()), id: \.offset) { _, segment in
                Capsule().fill(color(segment, late: isLate)).frame(height: 6)
            }
        }
        HStack(spacing: 6) {
            if s.currentTask.isEmpty, s.plan == nil {
                Text("ยังไม่มีแผน MP").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            } else {
                Text("กำลังทำ").font(.system(size: 11)).foregroundStyle(Theme.inkMuted).fixedSize()
                Text(s.currentTask.isEmpty ? "—" : s.currentTask).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let pace = paceText(s) { Text(pace).font(.sarabunFixed(11.5, .bold)).fixedSize() }
            Text("›").font(.sarabunFixed(17))
        }
        .foregroundStyle(isLate ? Theme.dangerText : Theme.primary)
        .stripFrame()
        .background(isLate ? Theme.dangerSoft : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
    }

    private func color(_ segment: InstallOverview.BarSegment, late: Bool) -> Color {
        switch segment {
        case .done: Theme.stepDone
        case .current: late ? Theme.danger : Theme.primary
        case .overdue: Theme.dangerPale
        case .ahead: Theme.borderSubtle
        }
    }

    /// `แผน p% · จริง a%`, `ส่งมอบ dd/mm` and the contractor.
    private func phaseChips(_ s: InstallStationSummary) -> some View {
        let actual = "จริง \(Int(s.actual.rounded()))%"
        let due = s.dueDate.map { d -> String in
            let c = Calendar.current.dateComponents([.day, .month], from: d)
            return String(format: "ส่งมอบ %02d/%02d", c.day ?? 0, c.month ?? 0)
        }
        return FlowLayout(spacing: 4, lineSpacing: 4) {
            phaseChip(s.plan.map { "แผน \(Int($0.rounded()))% · " + actual } ?? actual, ink: Theme.navy)
            if let due { phaseChip(due, ink: Theme.inkMuted) }
            if !s.contractor.isEmpty { phaseChip(s.contractor, ink: Theme.inkMuted) }
        }
    }

    private func phaseChip(_ text: String, ink: Color) -> some View {
        Text(text).font(.sarabunFixed(11, .semibold)).foregroundStyle(ink).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 1).background(Theme.background, in: Capsule())
    }

    func chip(_ text: String) -> some View {
        Text(text).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
    }

    func actionRow(_ lead: Text, _ title: Text, background: Color) -> some View {
        HStack(spacing: 6) {
            lead.font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
            title.font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
        }
        .stripFrame()
        .background(background, in: RoundedRectangle(cornerRadius: 9))
    }

    var badge: some View {
        let missing = job.missingItems.count
        let (text, fg, bg): (String, Color, Color) = job.projectName.isEmpty ? ("ร่าง", Theme.inkMuted, Theme.primarySoft)
            : missing > 0 ? ("ยังขาด \(missing) ช่อง", Theme.pending, Theme.pendingSoft)
            : ("ครบ", Theme.okTick, Theme.okSoft)
        return Text(text).font(.sarabunFixed(11, .bold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2).background(bg, in: Capsule())
    }

    var detailLine: String {
        guard !job.projectName.isEmpty else { return "แตะเพื่อกรอกข้อมูลโครงการใน A1" }
        let kw = job.values.text("capacity").trimmingCharacters(in: .whitespaces)
        let parts = [job.values.text("address").trimmingCharacters(in: .whitespacesAndNewlines), kw.isEmpty ? "" : kw + " kWp"].filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var dateLine: String {
        let d = job.values.text("date")
        let time = job.updated.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return d.isEmpty ? time : ISODate.thai(d) + " · " + time
    }

    func color(_ s: SurveyStep.Status) -> Color {
        switch s {
        case .complete: return Theme.stepDone
        case .current: return Theme.primary
        case .missing: return Theme.pending
        case .notStarted: return Theme.borderSubtle
        }
    }

    func continueRow(next: SurveyStep?, index: Int?, total: Int) -> some View {
        let font = Font.system(size: 13, weight: .bold)
        return HStack(spacing: 6) {
            if let next, let index {
                Text("ทำต่อ \(index)/\(total)").font(.system(size: 11)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                // code and title on one line, cut at the end
                Text(next.code + " " + next.title).font(font).foregroundStyle(Theme.navy).lineLimit(1)
            } else if job.canMoveToInstall {
                // a tap asks to move it to installation (SurveyHomeView)
                Label("ครบแล้ว", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.teal)
                    .labelStyle(TightLabel()).fixedSize()
                Text("ย้ายไปงานติดตั้ง").font(font).foregroundStyle(Theme.navy).lineLimit(1)
            } else {
                Label("กรอกครบทุกขั้นแล้ว", systemImage: "checkmark.circle.fill").font(font).foregroundStyle(Theme.teal)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
        }
        .stripFrame()
        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
    }

    /// Sync state as a 20 pt icon only (owner, 3 ต.ค.): waiting / synced; VoiceOver keeps the words.
    @ViewBuilder var syncMark: some View {
        if pendingSync {
            Image(systemName: "icloud.and.arrow.up").font(.system(size: 20)).foregroundStyle(Theme.pending)
                .accessibilityLabel("รอซิงก์")
        } else if synced {
            Image(systemName: "checkmark.icloud").font(.system(size: 20)).foregroundStyle(Theme.okTick)
                .accessibilityLabel("ซิงก์แล้ว")
        }
    }
}

private extension View {
    /// The continue / action strip: 34 pt high.
    func stripFrame() -> some View { padding(.horizontal, 10).frame(minHeight: 34) }
}

/// The hard hat of the `ติดตั้ง` badge (docs/ui/pwa-solar-survey-iphone-v3/icons/badge-install-hardhat.svg), drawn on
/// the svg's 24 pt grid.
struct HardHat: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // brim, then the shell over it
        p.move(to: CGPoint(x: 3, y: 18)); p.addLine(to: CGPoint(x: 21, y: 18))
        p.move(to: CGPoint(x: 4.5, y: 18)); p.addLine(to: CGPoint(x: 4.5, y: 16))
        p.addArc(center: CGPoint(x: 12, y: 16), radius: 7.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 19.5, y: 18))
        // the ridge and the two ribs
        p.move(to: CGPoint(x: 10, y: 8.7)); p.addLine(to: CGPoint(x: 10, y: 6.5))
        p.addLine(to: CGPoint(x: 14, y: 6.5)); p.addLine(to: CGPoint(x: 14, y: 8.7))
        p.move(to: CGPoint(x: 9.5, y: 11.5)); p.addLine(to: CGPoint(x: 9.5, y: 14.5))
        p.move(to: CGPoint(x: 14.5, y: 11.5)); p.addLine(to: CGPoint(x: 14.5, y: 14.5))
        let scale = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// The percent ring. `.cardSmall` is the project card's 44 pt ring
/// (docs/ui/pwa-solar-survey-iphone/icons/progress-ring-44-*.svg): light track, blue arc, green at 100 %.
/// `.compact` is the editor sidebar's: blue, teal from 80 %.
struct PercentRing: View {
    enum Style { case compact, cardSmall }
    let percent: Int
    var size: CGFloat = 52
    var style = Style.compact
    /// `.cardSmall` only: the arc's colour in place of blue, then green at 100 %.
    var tint: Color?

    var body: some View {
        switch style {
        case .compact:
            let tint = percent >= 80 ? Theme.teal : Theme.primary
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.sarabunFixed(13, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            }
            .frame(width: size, height: size)
        case .cardSmall:
            ZStack {
                Circle().stroke(Theme.borderSubtle, lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(tint ?? (percent >= 100 ? Theme.stepDone : Theme.primary), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.sarabunFixed(13, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            }
            // the svg's 22 pt radius in a 52 box, scaled to 44: the stroke sits inside the frame
            .padding(2.5)
            .frame(width: 44, height: 44)
            .accessibilityElement().accessibilityLabel("\(percent)%")
        }
    }
}
#endif
