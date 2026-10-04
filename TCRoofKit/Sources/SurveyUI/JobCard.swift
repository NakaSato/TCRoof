#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Colours of the home screen (docs/ui/pwa-solar-survey, after grf.css).
enum Home {
    static let navy = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .label : UIColor(red: 0.086, green: 0.196, blue: 0.361, alpha: 1) })
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red: 0.357, green: 0.420, blue: 0.510, alpha: 1) })
    static let primary = Color(red: 0.122, green: 0.435, blue: 0.710)
    static let primaryLight = Color(red: 0.180, green: 0.561, blue: 0.859)
    static let teal = Color(red: 0.153, green: 0.663, blue: 0.604)
    static let mint = Color(red: 0.620, green: 0.902, blue: 0.839)
    static let red = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let redSoft = Color(red: 0.949, green: 0.627, blue: 0.604)
    static let orange = Color(red: 0.769, green: 0.416, blue: 0.0)
    static let border = navy.opacity(0.15)
    // design system "TCRoof Survey" (docs/ui/survey-a1), as in the host app's Theme.swift
    static let danger = Color(red: 0.851, green: 0.271, blue: 0.231)
    static let primarySoft = Color(red: 0.890, green: 0.933, blue: 0.973)
    static let borderControl = Color(red: 0.467, green: 0.533, blue: 0.620)
    static let pending = Color(red: 0.706, green: 0.325, blue: 0.035)
    static let sun = Color(red: 1.0, green: 0.773, blue: 0.239)
    static let ok = Color(red: 0.180, green: 0.620, blue: 0.357)
    /// Warning orange #F08C00: the A2 lock, selected building models and the bottom bar's "!" badge (docs/ui/survey-a2 v2).
    static let warn = Color(red: 0.941, green: 0.549, blue: 0.0)
    // surveys moved to installation (docs/ui/pwa-solar-survey, 30/9/2569)
    static let lockedCard = Color(red: 0.961, green: 0.969, blue: 0.980)
    static let lockedAction = Color(red: 0.918, green: 0.945, blue: 0.973)
    static let lockBadge = Color(red: 0.867, green: 0.894, blue: 0.929)
    static let disabledFill = Color(red: 0.933, green: 0.949, blue: 0.969)
    static let disabledText = Color(red: 0.561, green: 0.639, blue: 0.737)
    // home board v2 (docs/ui/pwa-solar-survey, 2/10/2569)
    /// Progress ring track #E6ECF3.
    static let ringTrack = Color(red: 0.902, green: 0.925, blue: 0.953)
    /// Finished step and full ring #70AD47.
    static let stepDone = Color(red: 0.439, green: 0.678, blue: 0.278)
    /// "✓ ซิงก์แล้ว" #2E7D32.
    static let synced = Color(red: 0.180, green: 0.490, blue: 0.196)
    /// The footer's synced cloud #3B7420 (docs/ui/pwa-solar-survey-iphone/icons/cloud-synced.svg).
    static let syncedIcon = Color(red: 0.231, green: 0.455, blue: 0.125)
    // card tokens of the iPhone and iPad boards (docs/ui/pwa-solar-survey-iphone/icons/README.md, 3/10/2569)
    /// Hairline #DDE4ED: steps not started, the 44 pt ring's track, filter pill borders.
    static let hairline = Color(red: 0.867, green: 0.894, blue: 0.929)
    /// "ยังขาด n ช่อง" badge background #FFF4E5 (text `pending`).
    static let badgeWarnBg = Color(red: 1.0, green: 0.957, blue: 0.898)
    /// "ครบ" badge #E2EFDA / #3B7420.
    static let badgeOkBg = Color(red: 0.886, green: 0.937, blue: 0.855)
    static let badgeOkText = Color(red: 0.231, green: 0.455, blue: 0.125)
    /// "ร่าง" badge text #5B6B82 on `primarySoft`, the same in dark mode.
    static let badgeDraftText = Color(red: 0.357, green: 0.420, blue: 0.510)
    /// Selected filter pill #16325C, the same in dark mode.
    static let pillOn = Color(red: 0.086, green: 0.196, blue: 0.361)
    /// Count chip of an unselected filter pill #EEF2F7.
    static let pillCount = Color(red: 0.933, green: 0.949, blue: 0.969)
    // iPhone bottom bar (docs/ui/components/iphone-bottom-bar, 4/10/2569)
    /// "✓ บันทึกแล้ว" text and border #3B7420.
    static let okTick = Color(red: 0.231, green: 0.455, blue: 0.125)
    /// "✓ บันทึกแล้ว" background #F1F8EC.
    static let okSoftBG = Color(red: 0.945, green: 0.973, blue: 0.925)
    /// "กำลังบันทึก…" background #F3F6FA.
    static let savingBG = Color(red: 0.953, green: 0.965, blue: 0.980)
    /// Disabled ‹ / › rgba(142,142,147,0.4).
    static let navOff = Color(red: 0.557, green: 0.557, blue: 0.576).opacity(0.4)
    // D1 สิ่งกีดขวาง on iPhone (docs/ui/survey-d1-obstacles-iphone/svg/README.md, 4/10/2569)
    /// The selected point and its halo #E8851A.
    static let pointSelected = Color(red: 0.910, green: 0.522, blue: 0.102)
    /// D1 จัดแผง: a panel on the plan #2B4FD8 (docs/ui/survey-d1-layout-iphone/svg/README.md).
    static let panelBlue = Color(red: 0.169, green: 0.310, blue: 0.847)
    /// End of the teal gradient #4DB6E0 (from `teal`).
    static let tealLight = Color(red: 0.302, green: 0.714, blue: 0.878)
}

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
                        Text("NO.\(job.docNo.isEmpty ? " —" : job.docNo)").font(compact ? .system(size: 12, weight: .bold) : .subheadline.weight(.heavy)).foregroundStyle(Home.muted)
                        if mode == .install { installBadge }
                        else if mode == .locked {
                            // the lock matters more than the answer count once the survey is closed
                            ViewThatFits(in: .horizontal) { HStack(spacing: 8) { badge; lockBadge }; lockBadge }
                        } else { badge }
                    }
                    if job.projectName.isEmpty {
                        Text("ยังไม่ได้ตั้งชื่อโครงการ").font(.system(size: compact ? 16 : 17, weight: .bold)).italic().foregroundStyle(Home.muted)
                    } else {
                        Text(job.projectName).font(.system(size: compact ? 16 : 17, weight: .bold)).foregroundStyle(Home.navy)
                    }
                    Text(detailLine).font(.caption).foregroundStyle(Home.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                PercentRing(percent: mode == .install ? install.percent : job.completion.percent, style: compact ? .cardSmall : .card)
            }
            if mode == .install { installProgress } else { surveyProgress }
            if mode != .install, let id = job.jobSyncID, let label = model.linkedJobLabel?(id) {
                Label(label, systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Home.primary).lineLimit(1)
            }
            if mode == .install {
                HStack(spacing: 6) {
                    chip(install.team.isEmpty ? "ยังไม่กำหนดทีม" : "ทีม " + install.team)
                    chip("ส่งมอบ " + (install.dueDate.map { ISODate.thai(ISODate.string($0)) } ?? "ยังไม่กำหนด"))
                }
            } else if !job.sectionsByCategory.isEmpty {
                FlowLayout(spacing: compact ? 4 : 6, lineSpacing: compact ? 4 : 6) {
                    ForEach(job.sectionsByCategory) { g in
                        Text("\(g.category.rawValue) \(g.category.title) ×\(g.sections.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Home.navy)
                            .padding(.horizontal, 8).padding(.vertical, 1).background(Home.primarySoft, in: Capsule())
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
            .font(.caption).foregroundStyle(Home.muted).monospacedDigit()
        }
        .padding(.horizontal, compact ? 14 : 16).padding(.top, compact ? 12 : 14).padding(.bottom, compact ? 10 : 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(mode == .locked ? Home.lockedCard : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(recent ? Home.primary.opacity(compact ? 1 : 0.55) : Home.border, lineWidth: recent && !compact ? 1.5 : 1))
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
            actionRow(Text("งดแก้ไข · ดูได้อย่างเดียว"), Text("ดูรายงานสำรวจ"), background: Home.lockedAction)
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
                Capsule().fill(i < install.doneSteps ? Home.mint : i == install.doneSteps ? Home.primary : Color.secondary.opacity(0.2)).frame(height: 5)
            }
        }
        actionRow(Text("ขั้น \(min(install.doneSteps + 1, n))/\(n)").monospacedDigit(), Text(install.currentStep ?? "ส่งมอบแล้ว"),
                  background: install.isDone ? Home.mint.opacity(0.25) : Home.primary.opacity(0.08))
    }

    var installBadge: some View {
        Text(install.doneSteps > 0 ? "กำลังติดตั้ง" : "รอเริ่มงาน").font(.caption2.weight(.bold)).foregroundStyle(Home.primary)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Home.primarySoft, in: Capsule())
    }

    var lockBadge: some View {
        Label("ล็อก · อยู่ในงานติดตั้ง", systemImage: "lock").font(.caption2.weight(.bold)).foregroundStyle(Home.navy)
            .labelStyle(TightLabel()).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 2).background(Home.lockBadge, in: Capsule())
    }

    func chip(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(Home.navy)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Home.primarySoft, in: Capsule())
    }

    func actionRow(_ lead: Text, _ title: Text, background: Color) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            lead.font(compact ? .system(size: 11) : .caption).foregroundStyle(Home.muted)
            title.font(compact ? .system(size: 13, weight: .bold) : .subheadline.weight(.bold)).foregroundStyle(Home.navy).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Home.primary)
        }
        .stripFrame(compact: compact)
        .background(background, in: RoundedRectangle(cornerRadius: compact ? 9 : 10))
    }

    var badge: some View {
        let missing = job.missingItems.count
        let (text, fg, bg): (String, Color, Color) = job.projectName.isEmpty ? ("ร่าง", Home.badgeDraftText, Home.primarySoft)
            : missing > 0 ? ("ยังขาด \(missing) ช่อง", Home.pending, Home.badgeWarnBg)
            : ("ครบ", Home.badgeOkText, Home.badgeOkBg)
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
        case .complete: return Home.stepDone
        case .current: return Home.primary
        case .missing: return Home.pending
        case .notStarted: return Home.hairline
        }
    }

    func continueRow(next: SurveyStep?, index: Int?, total: Int) -> some View {
        let last = index == total
        let font: Font = compact ? .system(size: 13, weight: .bold) : .subheadline.weight(.bold)
        return HStack(spacing: compact ? 6 : 8) {
            if let next, let index {
                Text("ทำต่อ \(index)/\(total)").font(compact ? .system(size: 11) : .caption).foregroundStyle(Home.muted).monospacedDigit()
                if compact {
                    // code and title on one line, cut at the end
                    Text(next.code + " " + next.title).font(font).foregroundStyle(Home.navy).lineLimit(1)
                } else {
                    Text(next.code).font(.subheadline.weight(.heavy)).foregroundStyle(Home.navy)
                    Text(next.title).font(font).foregroundStyle(Home.navy).lineLimit(1)
                }
            } else {
                Label("กรอกครบทุกขั้นแล้ว", systemImage: "checkmark.circle.fill").font(font).foregroundStyle(Home.teal)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Home.primary)
        }
        .stripFrame(compact: compact)
        .background(compact ? Home.primarySoft : next == nil || last ? Home.mint.opacity(0.25) : Home.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: compact ? 9 : 10))
    }

    /// Sync state as a 20 pt icon only (owner, 3 ต.ค.): waiting / synced; VoiceOver keeps the words.
    @ViewBuilder var syncMark: some View {
        if pendingSync {
            Image(systemName: "icloud.and.arrow.up").font(.system(size: 20)).foregroundStyle(Home.pending)
                .accessibilityLabel("รอซิงก์")
        } else if synced {
            Image(systemName: "checkmark.icloud").font(.system(size: 20)).foregroundStyle(Home.syncedIcon)
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
            let tint = percent >= 80 ? Home.teal : Home.primary
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Home.navy)
            }
            .frame(width: size, height: size)
        case .card:
            ZStack {
                Circle().stroke(Home.ringTrack, lineWidth: 4)
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(percent >= 100 ? Home.stepDone : Home.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                (Text("\(percent)").font(.system(size: 16, weight: .bold)).foregroundColor(Home.navy)
                    + Text("%").font(.system(size: 10)).foregroundColor(Home.muted))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityElement().accessibilityLabel("\(percent)%")
        case .cardSmall:
            ZStack {
                Circle().stroke(Home.hairline, lineWidth: 5)
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(percent >= 100 ? Home.stepDone : Home.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Home.navy)
            }
            // the svg's 22 pt radius in a 52 box, scaled to 44: the stroke sits inside the frame
            .padding(2.5)
            .frame(width: 44, height: 44)
            .accessibilityElement().accessibilityLabel("\(percent)%")
        }
    }
}
#endif
