import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore
import SurveyUI

struct PlanJobRow: View {
    let job: Job
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TeamTag(team: job.team)
                Text(job.code).font(.sarabun(15, .bold, relativeTo: .subheadline))
                Spacer()
                if let day = job.installDay(on: date) {
                    Text("Day \(day)/\(job.installDays)").font(.sarabun(12, .bold, relativeTo: .caption))
                }
            }
            Text("\(job.capacityKW.kw) | \(job.province)").font(.sarabun(12, relativeTo: .caption))
            Label(job.customerName, systemImage: "person").font(.sarabun(12, relativeTo: .caption))
            Text("โครงการ : \(job.projectName)").font(.sarabun(12, relativeTo: .caption))
        }
        .foregroundStyle(Theme.navy)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(job.team.color)
                .frame(width: 5)
        }
    }
}

struct PlanListView: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var search = ""
    @FocusState private var searching: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var grouped: [(month: Date, jobs: [Job])] {
        let filtered = jobs.filter { $0.matches(search) }
        let dict = Dictionary(grouping: filtered) { $0.installStart.startOfMonth }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    var body: some View {
        if sizeClass == .compact { phoneList } else { padList }
    }

    /// iPad: the months as headings over `JobCard`s, like the scan and install queues.
    private var padList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if grouped.isEmpty {
                    TCEmptyState("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนคำค้นหา"))
                }
                ForEach(grouped, id: \.month) { group in
                    Text(group.month.thaiMonthYear).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.navy)
                    LazyVGrid(columns: cardColumns, spacing: 16) {
                        ForEach(group.jobs) { job in
                            JobCard(job: job, dateLabel: "วันเริ่มติดตั้ง", date: job.installStart) {
                                JobDetailView(job: job)
                            } footer: {
                                JobCardStrip(key: "ช่วงติดตั้ง",
                                             value: "\(job.installStart.thaiShort) – \(job.installEnd.thaiShort) · \(job.installDays) วัน")
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .tcPadNavBar("รายการแผนก่อสร้าง", trail: ["หน้าหลัก", "แผนก่อสร้างและเอกสาร"]) {
            TCBarSearchField(text: $search, prompt: "ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ")
        }
    }

    private var phoneList: some View {
        PadForm {
            PhoneSearchField(text: $search, focused: $searching, prompt: "ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ")
            ForEach(grouped, id: \.month) { group in
                PadSection(group.month.thaiMonthYear) {
                    ForEach(group.jobs) { job in
                        PadLink { JobDetailView(job: job) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(job.team.color).frame(width: 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(job.code).bold().lineLimit(1).fixedSize()
                                        TeamTag(team: job.team).fixedSize()
                                    }
                                    // the status sits on the name's line: beside the whole text it squeezed the code onto two lines
                                    HStack {
                                        Text(job.projectName).font(.sarabun(15, relativeTo: .subheadline)).lineLimit(1)
                                        Spacer(minLength: 4)
                                        TCStatusChip(job.status.title, fill: job.status.color.opacity(0.12), text: job.status.color).fixedSize()
                                    }
                                    Text("\(job.installStart.thaiShort) – \(job.installEnd.thaiShort) · \(job.installDays) วัน · \(job.capacityKW.kw)")
                                        .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                                }
                            }
                            .foregroundStyle(Theme.navy)
                        }
                    }
                }
            }
        }
        .overlay {
            if grouped.isEmpty {
                TCEmptyState("ไม่พบรายการ", systemImage: "tray", description: Text("ลองเปลี่ยนคำค้นหา"))
            }
        }
        .navigationTitle("รายการแผนก่อสร้าง")
    }
}
