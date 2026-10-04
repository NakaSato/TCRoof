import SwiftUI
import SwiftData
import CoreLocation
import TCRoofCore

// MARK: - Survey job card

/// A survey queue card: job, appointment, draft progress, then `footer` (the survey button).
/// The body opens `JobDetailView`; the footer is a separate tap target.
struct SurveyJobCard<Footer: View>: View {
    let job: Job
    @ViewBuilder var footer: () -> Footer

    private var days: Int { RelativeDay.days(from: .now, to: job.surveyDate) }
    private var when: String { RelativeDay.label(days: days, time: ThaiFormat.time.string(from: job.surveyDate)) }
    private var progress: SurveyCardProgress {
        SurveyCardProgress(draft: job.surveyDraft.map(SurveyOptions.progress), hasSaved: !job.savedSurveys.isEmpty)
    }

    var body: some View {
        let p = progress
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { JobDetailView(job: job) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(job.projectName), \(when), \(p.key) \(p.value) \(p.percent)%")
            progressBox(p)
            footer()
        }
        .cardStyle()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            codeRow
            metaRow
            Divider().padding(.vertical, 4)
            whenRow
            Label(job.province, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(Theme.navy.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(job.projectName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.navy)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            DotPill(title: "ทีม \(job.team.rawValue)", color: job.team.color, dot: true)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var codeRow: some View {
        HStack(spacing: 8) {
            Text(job.code).font(.caption.bold()).foregroundStyle(Theme.inkMuted)
            DotPill(title: job.status.title, color: job.status.color)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            if job.customerName != job.projectName {
                Label(job.customerName, systemImage: "person").lineLimit(1)
            }
            Label(job.capacityKW.kw, systemImage: "bolt.fill")
        }
        .font(.footnote)
        .foregroundStyle(Theme.navy.opacity(0.85))
    }

    private var whenRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(when, systemImage: "calendar")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(days == 0 ? Theme.primary : days < 0 ? Theme.muted : Theme.navy)
            Text(job.surveyDate.thaiShort).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func progressBox(_ p: SurveyCardProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.key).font(.caption).foregroundStyle(Theme.inkMuted)
                Text(p.value).font(.subheadline.bold()).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(p.percent)%").font(.subheadline.bold()).monospacedDigit()
                    .foregroundStyle(p.percent == 0 ? Theme.progressZero : p.tone == .complete ? Theme.progressFull : Theme.primary)
            }
            HStack(spacing: 3) {
                ForEach(p.segments.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(color(p.segments[i])).frame(height: 6)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(p.tone == .draft ? Theme.progressBox : Theme.progressBoxIdle, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func color(_ segment: SurveyCardProgress.Segment) -> Color {
        switch segment {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .todo: Theme.borderSubtle
        }
    }
}
