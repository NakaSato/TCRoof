import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `นำเข้าไฟล์แผน Excel` as a sheet (docs/ui/install-tracking-iphone state 19): the picked file, its checks (station,
/// plan read, formulas the app can't work out), the task dates that change against the station's plan, and the choice
/// between the whole plan and its progress only. The same `MPWorkbookFlow` as the alert does the import.
struct MPImportSheet: View {
    let flow: MPWorkbookFlow
    let pending: MPWorkbookFlow.Pending
    @Bindable var job: Job
    /// The station the file names when it isn't this one, and the station it fits, if any.
    var otherStation: (file: String, fits: String?)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var progressOnly = false
    /// The file's project facts to take with the plan (`ProjectSetup`): those that fill an empty field start ticked.
    @State private var setupPicked: Set<ProjectSetup.Field> = []

    /// The facts the file has that the station doesn't, for a file of this station only.
    private var setupChanges: [ProjectSetup.Change] {
        otherStation == nil ? job.setupChanges(pending.imported.setup) : []
    }

    private struct Change: Identifiable {
        let id: String
        let code: String
        let title: String
        let what: String
        let old: String
        let new: String
    }

    /// The tasks whose start or end the file moves, against the station's plan now.
    private var changes: [Change] {
        guard let input = job.scheduleInput else { return [] }
        let now = Dictionary(MasterSchedule.plan(input).map { ($0.task, $0) }) { a, _ in a }
        let file = MasterSchedule.plan(pending.imported.input)
        // d/m, with the year when the file's plan is in another year than the station's
        let cal = MasterSchedule.calendar
        let otherYear = cal.component(.year, from: input.installStart) != cal.component(.year, from: pending.imported.input.installStart)
        func day(_ d: Date?) -> String { d.map((otherYear ? ThaiFormat.numericDate : ThaiFormat.dayMonth).string(from:)) ?? "–" }
        return file.flatMap { f -> [Change] in
            guard let o = now[f.task] else { return [] }
            var out: [Change] = []
            if day(o.start) != day(f.start) { out.append(.init(id: f.task.rawValue + "s", code: f.task.code, title: f.task.title, what: "เริ่ม", old: day(o.start), new: day(f.start))) }
            if day(o.end) != day(f.end) { out.append(.init(id: f.task.rawValue + "e", code: f.task.code, title: f.task.title, what: "เสร็จ", old: day(o.end), new: day(f.end))) }
            return out
        }
    }

    var body: some View {
        let r = pending.imported, c = changes
        let station = MPWorkbook.station(project: r.project, fileName: pending.name)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fileCard
                    if let other = otherStation {
                        check(false, "ไฟล์นี้อาจเป็นของสถานีอื่น", "ไฟล์: \(other.file) | สถานีนี้: \(job.stationName)"
                              + (other.fits.map { " | ไฟล์ตรงกับ \($0)" } ?? ""))
                    } else {
                        check(station.name != nil, station.name != nil ? "ชื่อสถานีในไฟล์ตรงกับงานนี้" : "ไฟล์ไม่ระบุชื่อสถานี",
                              [job.stationName, job.capacityKW > 0 ? job.capacityKW.formatted(.number.precision(.fractionLength(0...2))) + " kWp" : nil]
                                .compactMap { $0 }.joined(separator: " | "))
                    }
                    check(true, "อ่านแผนได้ครบ", "\(r.tasks.count) งาน | " + ThaiFormat.numericDate.string(from: r.input.installStart) + " – "
                          + ThaiFormat.numericDate.string(from: r.input.installEnd))
                    if let note = MPWorkbookFlow.formulaNote(r.formulas) { check(false, "สูตรที่แอปคำนวณเองไม่ได้", note) }
                    if job.scheduleInput != nil { changesCard(c) }
                    if !progressOnly, !setupChanges.isEmpty { setupCard }
                    if job.scheduleInput != nil {
                        mode(false, "นำเข้าแผนทั้งหมด", "แทนแผนในแอปด้วยไฟล์" + (r.actual.points.isEmpty ? " | ความก้าวหน้าที่บันทึกไว้ยังอยู่" : " | ใช้ความก้าวหน้าตามไฟล์"))
                        let n = MPWorkbookFlow.merged(r, into: job).changed
                        mode(true, "รับเฉพาะความก้าวหน้า", "แผนในแอปไม่เปลี่ยน | " + (n == 0 ? "ไม่มีช่องที่เปลี่ยนตามไฟล์" : "รับ % ที่แก้ใน Excel \(n) ช่อง"))
                    }
                }
                .padding(16)
            }
            .background(Theme.phonePage.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if otherStation?.fits != nil {
                        Button("เลือกสถานีอื่น…") { otherChoice() }
                            .buttonStyle(TCButtonStyle(.secondary, size: .page, fullWidth: true))
                    }
                    Button((progressOnly ? "รับเฉพาะความก้าวหน้า" : "นำเข้าแผน") + (otherStation == nil ? "" : "ที่สถานีนี้")) { run() }
                        .buttonStyle(TCButtonStyle(.primary, size: .page, fullWidth: true))
                        .accessibilityIdentifier("mpImport.run")
                }
                .padding(16)
                .background(Theme.phonePage)
            }
            .onAppear { setupPicked = ProjectSetup.defaultFields(setupChanges) }
            .navigationTitle("นำเข้าไฟล์แผน Excel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { flow.pending = nil; dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("ปิด")
                }
            }
        }
    }

    private var fileCard: some View {
        Button {
            flow.pending = nil
            dismiss()
            flow.startImport()
        } label: {
            HStack(spacing: 12) {
                Text("X").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44).background(Theme.success, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pending.name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(pending.data.count), countStyle: .file) + " | แตะเพื่อเลือกไฟล์อื่น")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func check(_ ok: Bool, _ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 12, weight: .heavy))
                .foregroundStyle(ok ? Theme.successInk : Theme.onPrimary)
                .frame(width: 28, height: 28).background(ok ? Theme.successSoft : Theme.warning, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(ok ? Theme.surface : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func changesCard(_ c: [Change]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("สิ่งที่เปลี่ยนจากแผนในแอป").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("\(c.count) จุด | \(Set(c.map(\.code)).count) งาน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 6)
            if c.isEmpty { Text("วันของทุกงานตรงกับแผนในแอป").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).padding(.vertical, 8) }
            ForEach(c) { x in
                HStack(spacing: 10) {
                    Text(x.code).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(x.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                        Text(x.what).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 4)
                    Text(x.old).font(.sarabunFixed(14)).strikethrough().foregroundStyle(Theme.inkMuted)
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    Text(x.new).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.warningInk)
                }
                .frame(minHeight: 48)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    /// `ตั้งค่าโครงการจากไฟล์`: the file's facts to take with the plan.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ตั้งค่าโครงการจากไฟล์").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("เลือก \(setupPicked.count) จาก \(setupChanges.count)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 6)
            ProjectSetupList(changes: setupChanges, picked: $setupPicked)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func mode(_ only: Bool, _ title: String, _ note: String) -> some View {
        let on = progressOnly == only
        return Button { progressOnly = only } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 22)).foregroundStyle(on ? Theme.success : Theme.chevron)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                    Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(on ? Theme.successSoft.opacity(0.5) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.success : Theme.borderSubtle, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(only ? "mpImport.progress" : "mpImport.all")
    }

    /// The alert's choices for a file of another station: closes the sheet, then asks there.
    private func otherChoice() {
        let p = pending
        flow.pending = nil
        flow.confirmsInSheet = false
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flow.pending = p }
    }

    private func run() {
        let p = pending
        flow.pending = nil
        if progressOnly && job.scheduleInput != nil {
            flow.takeProgress(p, on: job, context: context)
        } else {
            flow.apply(p, to: job, context: context, setup: otherStation == nil ? setupPicked : [])
        }
        dismiss()
    }
}
