#if canImport(UIKit)
import SwiftUI
import UIKit
import SurveyCore

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
}

struct JobCard: View {
    let job: Job
    var pendingSync = false
    var synced = false
    var recent = false
    @Environment(SurveyModel.self) private var model

    var body: some View {
        let c = job.completion
        let steps = job.stepStatuses
        let next = job.nextStep
        let nextIndex = next.flatMap { n in steps.firstIndex { $0.step.page == n.page } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("NO.\(job.docNo.isEmpty ? " —" : job.docNo)").font(.subheadline.weight(.heavy)).foregroundStyle(Home.muted)
                        badge
                    }
                    if job.projectName.isEmpty {
                        Text("ยังไม่ได้ตั้งชื่อโครงการ").font(.system(size: 17, weight: .bold)).italic().foregroundStyle(Home.muted)
                    } else {
                        Text(job.projectName).font(.system(size: 17, weight: .bold)).foregroundStyle(Home.navy)
                    }
                    Text(detailLine).font(.caption).foregroundStyle(Home.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                PercentRing(percent: c.percent)
            }
            HStack(spacing: 4) {
                ForEach(steps, id: \.step.id) { s in Capsule().fill(color(s.status)).frame(height: 5) }
            }
            continueRow(next: next, index: nextIndex.map { $0 + 1 }, total: steps.count)
            if let id = job.jobSyncID, let label = model.linkedJobLabel?(id) {
                Label(label, systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Home.primary).lineLimit(1)
            }
            if !job.sectionsByCategory.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(job.sectionsByCategory) { g in
                        Text("\(g.category.rawValue) \(g.category.title) ×\(g.sections.count)").font(.caption.weight(.bold)).foregroundStyle(Home.navy)
                            .padding(.horizontal, 9).padding(.vertical, 4).background(Home.mint.opacity(0.45), in: Capsule())
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(recent ? Home.primary.opacity(0.55) : Home.border, lineWidth: recent ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    var badge: some View {
        let missing = job.missingItems.count
        let (text, fg, bg): (String, Color, Color) = job.projectName.isEmpty ? ("ร่าง", Home.muted, Color.secondary.opacity(0.14))
            : missing > 0 ? ("ขาด \(missing) รายการ", Home.red, Home.redSoft.opacity(0.3))
            : ("ข้อมูลครบ", Home.teal, Home.mint.opacity(0.45))
        return Text(text).font(.caption2.weight(.bold)).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2).background(bg, in: Capsule())
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
        case .complete: return Home.mint
        case .current: return Home.primary
        case .missing: return Home.redSoft
        case .notStarted: return Color.secondary.opacity(0.2)
        }
    }

    func continueRow(next: SurveyStep?, index: Int?, total: Int) -> some View {
        let last = index == total
        return HStack(spacing: 8) {
            if let next, let index {
                Text("ทำต่อ \(index)/\(total)").font(.caption).foregroundStyle(Home.muted).monospacedDigit()
                Text(next.code).font(.subheadline.weight(.heavy)).foregroundStyle(Home.navy)
                Text(next.title).font(.subheadline.weight(.bold)).foregroundStyle(Home.navy).lineLimit(1)
            } else {
                Label("กรอกครบทุกขั้นแล้ว", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.bold)).foregroundStyle(Home.teal)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Home.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(next == nil || last ? Home.mint.opacity(0.25) : Home.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder var syncMark: some View {
        if pendingSync {
            Label("รอซิงก์", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Home.orange).fontWeight(.bold)
        } else if synced {
            Label("ซิงก์แล้ว", systemImage: "icloud.fill").foregroundStyle(Home.primary).fontWeight(.bold)
        }
    }
}

/// The card's percent ring: blue, teal from 80%.
struct PercentRing: View {
    let percent: Int
    var size: CGFloat = 52
    var body: some View {
        let tint = percent >= 80 ? Home.teal : Home.primary
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: Double(percent) / 100).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Home.navy)
        }
        .frame(width: size, height: size)
    }
}
#endif
