#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// Icon and title close together, for small badges.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}

struct JobCard: View {
    /// A survey in progress, a survey moved to installation (read-only), or the installation job itself.
    enum Mode { case survey, locked, install }
    let job: Job
    var mode = Mode.survey
    var pendingSync = false
    var synced = false
    var recent = false
    @Environment(SurveyModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the denser card of docs/ui/pwa-solar-survey-iphone.
    var compact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: compact ? 10 : 12) {
                VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                    HStack(spacing: compact ? 6 : 8) {
                        Text("NO.\(job.docNo.isEmpty ? " —" : job.docNo)").font(compact ? .system(size: 12, weight: .bold) : .subheadline.weight(.heavy)).foregroundStyle(Theme.inkMuted)
                        if mode == .install { installBadge }
                        else if mode == .locked {
                            // the lock matters more than the answer count once the survey is closed
                            ViewThatFits(in: .horizontal) { HStack(spacing: 8) { badge; lockBadge }; lockBadge }
                        } else { badge }
                    }
                    if job.projectName.isEmpty {
                        Text("ยังไม่ได้ตั้งชื่อโครงการ").font(.system(size: compact ? 16 : 17, weight: .bold)).italic().foregroundStyle(Theme.inkMuted)
                    } else {
                        Text(job.projectName).font(.system(size: compact ? 16 : 17, weight: .bold)).foregroundStyle(Theme.navy)
                    }
                    Text(detailLine).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                PercentRing(percent: mode == .install ? install.percent : job.completion.percent, style: compact ? .cardSmall : .card)
            }
            if mode == .install { installProgress } else { surveyProgress }
            if mode != .install, let id = job.jobSyncID, let label = model.linkedJobLabel?(id) {
                Label(label, systemImage: "link").font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.primary).lineLimit(1)
            }
            if mode == .install {
                HStack(spacing: 6) {
                    chip(install.team.isEmpty ? "ยังไม่กำหนดทีม" : "ทีม " + install.team)
                    chip("ส่งมอบ " + (install.dueDate.map { ISODate.thai(ISODate.string($0)) } ?? "ยังไม่กำหนด"))
                }
            } else if !job.sectionsByCategory.isEmpty {
                FlowLayout(spacing: compact ? 4 : 6, lineSpacing: compact ? 4 : 6) {
                    ForEach(job.sectionsByCategory) { g in
                        Text("\(g.category.rawValue) \(g.category.title) ×\(g.sections.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.navy)
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
        .padding(.horizontal, compact ? 14 : 16).padding(.top, compact ? 12 : 14).padding(.bottom, compact ? 10 : 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(mode == .locked ? Theme.background : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(recent ? Theme.primary.opacity(compact ? 1 : 0.55) : Theme.borderSubtle, lineWidth: recent && !compact ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder var surveyProgress: some View {
        let steps = job.stepStatuses
        let next = job.nextStep
        let nextIndex = next.flatMap { n in steps.firstIndex { $0.step.page == n.page } }
        HStack(spacing: compact ? 2 : 3) {
            ForEach(steps, id: \.step.id) { s in Capsule().fill(color(s.status)).frame(height: 6) }
        }
        if mode == .locked {
            actionRow(Text("งดแก้ไข · ดูได้อย่างเดียว"), Text("ดูรายงานสำรวจ"), background: Theme.rowSelected)
        } else {
            continueRow(next: next, index: nextIndex.map { $0 + 1 }, total: steps.count)
        }
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

    var lockBadge: some View {
        Label("ล็อก · อยู่ในงานติดตั้ง", systemImage: "lock").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.navy)
            .labelStyle(TightLabel()).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.borderSubtle, in: Capsule())
    }

    func chip(_ text: String) -> some View {
        Text(text).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
    }

    func actionRow(_ lead: Text, _ title: Text, background: Color) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            lead.font(compact ? .system(size: 11) : .caption).foregroundStyle(Theme.inkMuted)
            title.font(compact ? .system(size: 13, weight: .bold) : .subheadline.weight(.bold)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
        }
        .stripFrame(compact: compact)
        .background(background, in: RoundedRectangle(cornerRadius: compact ? 9 : 10))
    }

    var badge: some View {
        let missing = job.missingItems.count
        let (text, fg, bg): (String, Color, Color) = job.projectName.isEmpty ? ("ร่าง", Theme.inkMuted, Theme.primarySoft)
            : missing > 0 ? ("ยังขาด \(missing) ช่อง", Theme.pending, Theme.pendingSoft)
            : ("ครบ", Theme.okTick, Theme.okSoft)
        return Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(fg)
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
        let last = index == total
        let font: Font = compact ? .system(size: 13, weight: .bold) : .subheadline.weight(.bold)
        return HStack(spacing: compact ? 6 : 8) {
            if let next, let index {
                Text("ทำต่อ \(index)/\(total)").font(compact ? .system(size: 11) : .caption).foregroundStyle(Theme.inkMuted).monospacedDigit()
                if compact {
                    // code and title on one line, cut at the end
                    Text(next.code + " " + next.title).font(font).foregroundStyle(Theme.navy).lineLimit(1)
                } else {
                    Text(next.code).font(.sarabun(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                    Text(next.title).font(font).foregroundStyle(Theme.navy).lineLimit(1)
                }
            } else {
                Label("กรอกครบทุกขั้นแล้ว", systemImage: "checkmark.circle.fill").font(font).foregroundStyle(Theme.teal)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
        }
        .stripFrame(compact: compact)
        .background(compact ? Theme.primarySoft : next == nil || last ? Theme.mint.opacity(0.25) : Theme.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: compact ? 9 : 10))
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
    /// The continue / action strip: 34 pt high on iPhone, 10 pt padding on iPad.
    @ViewBuilder func stripFrame(compact: Bool) -> some View {
        if compact { padding(.horizontal, 10).frame(minHeight: 34) } else { padding(.horizontal, 10).padding(.vertical, 10) }
    }
}

/// The percent ring. `.card` is the home card's 58 pt ring (icons/progress-ring-*.svg): light track, blue arc,
/// green at 100 %, value over a small "%". `.cardSmall` is the iPhone card's 44 pt ring
/// (docs/ui/pwa-solar-survey-iphone/icons/progress-ring-44-*.svg). `.compact` is the editor sidebar's: blue, teal from 80 %.
struct PercentRing: View {
    enum Style { case compact, card, cardSmall }
    let percent: Int
    var size: CGFloat = 52
    var style = Style.compact

    var body: some View {
        switch style {
        case .compact:
            let tint = percent >= 80 ? Theme.teal : Theme.primary
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            }
            .frame(width: size, height: size)
        case .card:
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 4)
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(percent >= 100 ? Theme.stepDone : Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                (Text("\(percent)").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.navy)
                    + Text("%").font(.system(size: 10)).foregroundColor(Theme.inkMuted))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityElement().accessibilityLabel("\(percent)%")
        case .cardSmall:
            ZStack {
                Circle().stroke(Theme.borderSubtle, lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(percent >= 100 ? Theme.stepDone : Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            }
            // the svg's 22 pt radius in a 52 box, scaled to 44: the stroke sits inside the frame
            .padding(2.5)
            .frame(width: 44, height: 44)
            .accessibilityElement().accessibilityLabel("\(percent)%")
        }
    }
}
#endif
