import SwiftUI
import Observation
import TCRoofUI
import TCRoofCore
import CoreLocation
import MapKit

// The parts of `PhoneSurveyList` (docs/ui/tcroof-survey-home-iphone): section label, week card, status chips,
// job list and dock.

/// Pressed: 3 % smaller and a little darker; nothing with Reduce Motion.
struct SurveyHomePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        configuration.label
            .brightness(pressed ? -0.04 : 0)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// `สัปดาห์นี้ … 30 ก.ย. – 6 ต.ค.` over a card.
struct SurveyHomeSectionLabel: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack {
            Text(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(trailing).monospacedDigit()
        }
        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        .padding(.horizontal, 4)
    }
}

struct SurveyHomeChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
            .accessibilityHidden(true)
    }
}

extension Job {
    var cardProgress: SurveyCardProgress {
        SurveyCardProgress(draft: surveyDraft.map(SurveyOptions.progress), hasSaved: !savedSurveys.isEmpty)
    }

    /// "วันนี้ 09:30 น."
    func surveyWhen(now: Date) -> String {
        RelativeDay.label(days: RelativeDay.days(from: now, to: surveyDate), time: ThaiFormat.time.string(from: surveyDate))
    }
}

// MARK: - Week card

/// The week strip, then `นัดถัดไป` when the selected day is that appointment's day, then the day's other appointments.
struct SurveyWeekCard: View {
    let week: [SurveyDayHome.Day]
    @Binding var selectedDay: Int
    let next: Job?
    let agenda: [Job]
    let now: Date
    /// `12 กม. - ขับ 25 นาที`; nil hides the item.
    let driveText: String?
    let open: (Job) -> Void
    let call: (Job) -> Void
    let navigate: (Job) -> Void

    /// The next appointment, when it is on the selected day.
    private var shownNext: Job? {
        next.flatMap { RelativeDay.days(from: now, to: $0.surveyDate) == selectedDay ? $0 : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
            divider.padding(.top, 4)
            if let job = shownNext {
                nextBlock(job)
                if !agenda.isEmpty { divider }
            }
            ForEach(agenda) { agendaRow($0) }
            if shownNext == nil && agenda.isEmpty {
                Text("ไม่มีนัดสำรวจในวันนี้").font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
        }
        .padding(.top, 8).padding(.horizontal, 6).padding(.bottom, 4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.horizontal, 10)
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.offset) { dayButton($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("เลือกวัน")
    }

    private func dayButton(_ day: SurveyDayHome.Day) -> some View {
        let selected = day.offset == selectedDay
        return Button { selectedDay = day.offset } label: {
            VStack(spacing: 3) {
                Text(day.label).font(.sarabun(11.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Text("\(day.number)").font(.sarabun(16, selected || day.isToday ? .bold : .regular, relativeTo: .body)).monospacedDigit()
                    .foregroundStyle(selected ? Theme.surface : day.isToday ? Theme.primary : Theme.navy)
                    .frame(width: 34, height: 34)
                    .background(selected ? Theme.navy : .clear, in: Circle())
                // the space stays when the day has no appointment
                Circle().fill(day.hasAppointments ? (selected ? Theme.primary : Theme.survey) : .clear).frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel((day.isToday ? "วันนี้ " : "") + ThaiFormat.dayMonthShort.string(from: day.date)
                            + (day.hasAppointments ? " นัด \(day.count)" : " ไม่มีนัด"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: next appointment

    private func nextBlock(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("นัดถัดไป").font(.sarabun(12.5, .semibold, relativeTo: .caption)).foregroundStyle(Theme.primary)
                .padding(.top, 10).padding(.horizontal, 10).padding(.bottom, 2)
            HStack(spacing: 8) {
                Button { open(job) } label: { nextText(job) }
                    .buttonStyle(SurveyHomePressStyle())
                    .accessibilityLabel("รายละเอียดงาน \(job.projectName)")
                if job.phone.contains(where: \.isNumber) {
                    circleButton("phone", label: "โทรหาลูกค้า") { call(job) }
                }
                circleButton("location", label: "นำทางไปหน้างาน") { navigate(job) }
            }
            .padding(.top, 2).padding(.trailing, 6).padding(.bottom, 8).padding(.leading, 10)
            metaLine(job).padding(.horizontal, 10).padding(.bottom, 12)
        }
    }

    private func nextText(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(job.projectName).font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy).lineLimit(1)
            (Text(job.surveyWhen(now: now)).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
             + Text(" | \(job.province)").font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44).background(Theme.background, in: Circle())
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel(label)
    }

    private func metaLine(_ job: Job) -> some View {
        HStack(spacing: 14) {
            metaItem("clock") {
                Text(SurveyDayHome.until(now: now, date: job.surveyDate)).font(.sarabun(13.5, .bold, relativeTo: .footnote))
                    .foregroundStyle(Theme.navy)
            }
            if let driveText {
                metaItem("car") { Text(driveText).font(.sarabun(13.5, relativeTo: .footnote)) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkTab).monospacedDigit().lineLimit(1)
    }

    private func metaItem(_ symbol: String, @ViewBuilder text: () -> some View) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
            text()
        }
    }

    // MARK: agenda

    private func agendaRow(_ job: Job) -> some View {
        let time = ThaiFormat.time.string(from: job.surveyDate)
        return Button { open(job) } label: {
            HStack(spacing: 12) {
                Text(time).font(.sarabun(15, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.navy)
                    .frame(width: 48, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(job.team.color).frame(width: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.projectName).font(.sarabun(15.5, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text("ทีม \(job.team.rawValue) | \(job.province) | \(job.capacityKW.kw)")
                        .font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                SurveyHomeChevron()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 56)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel("นัดสำรวจ \(job.projectName) \(time) น.")
    }
}

// MARK: - Status chips

/// `ทั้งหมด 9 | สนใจ 4 | ยืนยันแล้ว 3 …`: nil is `ทั้งหมด`.
struct SurveyStatusChips: View {
    @Binding var selection: JobStatus?
    let total: Int
    let counts: [JobStatus: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, title: "ทั้งหมด", count: total)
                ForEach(JobStatus.allCases) { chip($0, title: $0.shortTitle, count: counts[$0] ?? 0) }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("กรองสถานะ")
    }

    private func chip(_ status: JobStatus?, title: String, count: Int) -> some View {
        let selected = status == selection
        return Button { selection = status } label: {
            HStack(spacing: 6) {
                if let status { Circle().fill(status.color).frame(width: 8, height: 8) }
                Text(title)
                Text("\(count)").monospacedDigit().opacity(0.7)
            }
            .font(.sarabun(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(selected ? Theme.surface : Theme.inkTab)
            .lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(selected ? Theme.navy : Theme.surface, in: Capsule())
            .overlay { if !selected { Capsule().strokeBorder(Theme.borderSubtle) } }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel("\(title) \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Job list

/// One card with a row per job; each row opens the job.
struct SurveyHomeList: View {
    let jobs: [Job]
    let empty: String
    let open: (Job) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            if jobs.isEmpty {
                Text(empty).font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            ForEach(jobs) { job in
                Button { open(job) } label: { SurveyHomeRow(job: job, separator: job !== jobs.last) }
                    .buttonStyle(SurveyHomePressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(job.projectName) \(job.status.title)")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SurveyHomeRow: View {
    let job: Job
    let separator: Bool

    var body: some View {
        let progress = job.cardProgress
        HStack(spacing: 12) {
            Text(SurveyDayHome.initial(of: job.projectName)).font(.sarabun(16, .bold, relativeTo: .body)).foregroundStyle(job.team.color)
                .frame(width: 40, height: 40).background(job.team.color.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(job.projectName).font(.sarabun(15.5, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text("\(job.code) | \(job.capacityKW.kw) | \(job.province)")
                    .font(.sarabun(12.5, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.inkMuted)
                if progress.tone == .draft { draftLine(progress).padding(.top, 4) }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(job.status.shortTitle).font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(job.status.color)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(job.status.color.opacity(0.12), in: Capsule())
            SurveyHomeChevron()
        }
        .padding(.top, 8).padding(.trailing, 14).padding(.bottom, 8).padding(.leading, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if separator { Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.leading, 68) }
        }
    }

    private func draftLine(_ p: SurveyCardProgress) -> some View {
        HStack(spacing: 8) {
            // the bar gives way before the text is cut
            SurveyDraftBar(percent: p.percent).frame(minWidth: 24, maxWidth: 96)
            Text("ทำต่อ \(p.shortValue) | \(p.percent)%").font(.sarabun(12, .bold, relativeTo: .caption)).monospacedDigit()
                .foregroundStyle(Theme.primary).fixedSize().layoutPriority(1)
        }
    }
}

/// The draft's progress, filling from the left when it first appears.
private struct SurveyDraftBar: View {
    let percent: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Theme.primary)
                .frame(width: geo.size.width * (shown || reduceMotion ? CGFloat(percent) / 100 : 0))
        }
        .frame(height: 4)
        .background(Theme.borderSubtle, in: Capsule())
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { shown = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dock

/// The glass bar over the tab bar: the next appointment's survey (`ทำแบบสำรวจต่อ | ค่าไฟ` or `เริ่มสำรวจ`) and
/// the add-customer button. With no appointment ahead only the add button is left, trailing.
struct SurveyHomeDock: View {
    let next: Job?
    let now: Date
    let open: (Job) -> Void
    /// nil hides `เพิ่มลูกค้าใหม่` (a contractor can't create jobs: `job.edit`).
    let add: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 8) {
            if let next { primary(next) }
            if let add { addButton(add) }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(Theme.surface.opacity(0.7)))
        .shadow(color: Theme.navy.opacity(0.18), radius: 15, y: 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func primary(_ job: Job) -> some View {
        let progress = job.cardProgress
        let title = progress.tone == .draft ? "ทำแบบสำรวจต่อ | \(progress.shortValue)" : "เริ่มสำรวจ"
        return Button { open(job) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(15.5, .bold, relativeTo: .headline))
                Text("\(job.projectName) | \(job.surveyWhen(now: now)) | \(progress.percent)%")
                    .font(.sarabun(12, relativeTo: .caption)).monospacedDigit().opacity(0.88)
            }
            .foregroundStyle(Theme.onPrimary).lineLimit(1)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: Theme.primary.opacity(0.3), radius: 7, y: 6)
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel("\(title) \(job.projectName)")
    }

    private func addButton(_ add: @escaping () -> Void) -> some View {
        Button(action: add) {
            Image(systemName: "person.badge.plus").font(.system(size: 23, weight: .medium)).foregroundStyle(Theme.dockTeal)
                .frame(width: 52, height: 52)
                .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(SurveyHomePressStyle())
        .accessibilityLabel("เพิ่มลูกค้าใหม่")
    }
}

// MARK: - Drive estimate

/// Distance and drive time from here to the next appointment's address. It never asks for location access:
/// without it, or without a route, `text` stays nil and the item is hidden.
@MainActor
@Observable
final class DriveEstimate {
    private(set) var text: String?
    @ObservationIgnored private var fetcher: LocationFetcher?

    func load(address: String) async {
        text = nil
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let fetcher = LocationFetcher()
        self.fetcher = fetcher
        let here: CLLocation? = await withCheckedContinuation { done in
            fetcher.request { done.resume(returning: try? $0.get()) }
        }
        // `Job` keeps an address, not coordinates
        guard let here, let there = try? await CLGeocoder().geocodeAddressString(address).first?.location else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: there.coordinate))
        request.transportType = .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA(), !Task.isCancelled else { return }
        text = SurveyDayHome.drive(meters: eta.distance, seconds: eta.expectedTravelTime)
    }
}
