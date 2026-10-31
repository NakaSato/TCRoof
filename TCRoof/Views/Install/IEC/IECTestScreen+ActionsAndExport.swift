import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

extension IECTestScreen {
    // MARK: bottom bar

    func bottomBar(_ r: IECReport) -> some View {
        HStack(spacing: 12) {
            if let result = r.result {
                Text(result.passed ? "ผ่าน" : "ไม่ผ่าน").font(.sarabunFixed(15, .bold))
                    .foregroundStyle(result.passed ? Theme.successInk : Theme.dangerText)
                    .padding(.horizontal, 12).frame(height: 30).background(result.passed ? Theme.successSoft : Theme.dangerSoft, in: Capsule())
                VStack(alignment: .leading, spacing: 0) {
                    Text("ปิดการทดสอบแล้ว | แก้ไขไม่ได้").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text(Self.stamp(result.completedAt, result.by)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if permissions.can(.iecClose, on: job.access) {
                    Button { confirmReopen = true } label: { Label("แก้ไข", systemImage: "lock.open") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                }
            } else if let sent = r.submission {
                Text("รอปิด").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.warningInk)
                    .padding(.horizontal, 12).frame(height: 30).background(Theme.pendingSoft, in: Capsule())
                VStack(alignment: .leading, spacing: 0) {
                    Text("ส่งผลให้ทีมแล้ว | รอทีมภายในปิด").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text(Self.stamp(sent.submittedAt, sent.by)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            } else {
                IECRing(fraction: r.completion, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("บันทึกอัตโนมัติ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text("ครบ \(IECReport.Stage.allCases.filter { $0 != .review && r.isDone($0) }.count)/6 ขั้น | ความคืบหน้ารวม \(Int((r.completion * 100).rounded()))%")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            Button { startExport(.word) } label: {
                Label(makingWord ? "กำลังทำ Word…" : "ส่งออก Word ภาพถ่าย", systemImage: "doc.richtext")
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            .disabled(makingWord)
            Button { startExport(.excel) } label: { Label("ส่งออก Excel IEC 62446", systemImage: "tablecells") }
                .buttonStyle(TCButtonStyle(r.isLocked || !r.isDone(.review) ? .primary : .secondary, size: .card)).fixedSize()
            if !r.isLocked, permissions.can(.iecFillSubmit, on: job.access) {
                Button(action: submit) { Label("ส่งผลให้ทีม", systemImage: "paperplane") }
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                    .disabled(!r.isDone(.review))
                    .accessibilityHint(r.isDone(.review) ? "ส่งผลให้ทีมภายในตรวจและปิด" : "ทำขั้นที่ 1–6 ให้ครบก่อน")
            } else if r.isAwaitingClose, permissions.can(.iecClose, on: job.access) {
                Button { sendingBack = true } label: { Label("ส่งกลับให้แก้", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Button(action: complete) { Label("ปิดการทดสอบ", systemImage: "checkmark.seal") }
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                    .disabled(r.submissionIsStale)
                    .accessibilityHint(r.submissionIsStale ? "ข้อมูลเปลี่ยนหลังส่ง ส่งกลับให้แก้แล้วส่งใหม่" : "ทีมภายในสรุปผลและล็อกการทดสอบ")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// `ส่งผลให้ทีม`: the contractor hands the filled test over; it locks until the team closes it or sends it back.
    /// The MP plan doesn't count it yet.
    func submit() {
        job.updateIEC(context) { _ = $0.submit(by: job.iecActor) }
    }

    /// `ปิดการทดสอบ` (the internal team, like signing a daily report): closes and locks the sent test, and books the
    /// MP plan's `3.1 Pre-Commissioning Test` as done that week (a real test of a station with a plan; the sample
    /// never touches the plan). Reopening leaves the plan as it is.
    func complete() {
        job.updateIEC(context, evenWhenLocked: true) { _ = $0.complete(by: job.iecActor) }
        guard let r = job.iecReport, let result = r.result, r.sampleName == nil, let input = job.scheduleInput else { return }
        var a = job.scheduleActual
        a.setPercent(100, task: .preCommissioning, week: result.completedAt, weight: input.weight(.preCommissioning))
        if a.finished[MasterSchedule.Task.preCommissioning.rawValue] == nil { a.finished[MasterSchedule.Task.preCommissioning.rawValue] = result.completedAt }
        job.scheduleActual = a
        try? context.save()
    }

    /// `15 ต.ค. 2569 14:20 | ทีมทดสอบ`.
    static func stamp(_ at: Date, _ by: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH"); f.calendar = Calendar(identifier: .buddhist); f.dateFormat = "d MMM yyyy HH:mm"
        return f.string(from: at) + (by.isEmpty ? "" : " | " + by)
    }

    /// A closed test says so above everything; a result whose values changed since (a sync) says that too.
    @ViewBuilder func resultNotice(_ r: IECReport) -> some View {
        if r.resultIsStale {
            notice("exclamationmark.triangle.fill", Theme.warningInk, Theme.pendingSoft,
                   "ข้อมูลเปลี่ยนหลังปิดการทดสอบ", "อาจมาจากเครื่องอื่น | กด แก้ไข แล้วส่งผลและปิดอีกครั้งเพื่อสรุปผลใหม่") { EmptyView() }
        } else if r.result != nil {
            notice("lock.fill", Theme.successInk, Theme.successSoft,
                   "ปิดการทดสอบแล้ว", "ค่าทั้งหมดถูกล็อก | กด แก้ไข เพื่อเปิดให้แก้") { EmptyView() }
        } else if r.submissionIsStale {
            notice("exclamationmark.triangle.fill", Theme.warningInk, Theme.pendingSoft,
                   "ข้อมูลเปลี่ยนหลังส่งผล", "อาจมาจากเครื่องอื่น | ทีมภายในกด ส่งกลับให้แก้ แล้วให้ผู้รับเหมาส่งใหม่") { EmptyView() }
        } else if r.isAwaitingClose {
            notice("paperplane.fill", Theme.primary, Theme.primarySoft,
                   "ส่งผลให้ทีมแล้ว | รอทีมภายในปิด", "ค่าทั้งหมดถูกล็อก | ทีมภายในตรวจแล้วกด ปิดการทดสอบ หรือ ส่งกลับให้แก้") { EmptyView() }
        } else if let back = r.sentBack {
            notice("arrow.uturn.backward.circle.fill", Theme.warningInk, Theme.pendingSoft,
                   "ทีมส่งกลับให้แก้" + (back.note.isEmpty ? "" : ": " + back.note),
                   Self.stamp(back.at, back.by) + " | แก้แล้วกด ส่งผลให้ทีม อีกครั้ง") { EmptyView() }
        }
    }

    // MARK: station line

    /// A sample's banner, or a warning when the sheet's station line doesn't name this job (renamed since, or edited).
    @ViewBuilder func stationNotice(_ r: IECReport) -> some View {
        if let sample = r.sampleName {
            notice("info.circle", Theme.primary, Theme.primarySoft,
                   "ข้อมูลตัวอย่างจากสถานี\(sample) ไม่ใช่ผลทดสอบของงานนี้", "แฟ้มที่ส่งออกจะตั้งชื่อว่าตัวอย่าง") { EmptyView() }
        } else if r.namesAnotherStation(than: job.stationName) {
            notice("exclamationmark.triangle.fill", Theme.warningInk, Theme.pendingSoft,
                   "บรรทัดสถานีในแผ่นงานไม่ตรงกับชื่องาน", "แผ่นงานเขียนว่า “\(r.stationLine)” | งานนี้คือ “\(job.stationName)”") {
                Button("ใช้ชื่อของงาน", action: useJobName).buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            }
        }
    }

    private func notice<Action: View>(_ symbol: String, _ ink: Color, _ fill: Color, _ title: String, _ detail: String,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text(detail).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Rewrites the sheet's station line from the job, as a new test would have it.
    func useJobName() {
        let line = job.newIECReport.stationLine
        job.updateIEC(context) { $0.stationLine = line }
    }

    // MARK: export

    func startExport(_ kind: IECReport.ExportRecord.Kind = .excel) {
        exportKind = kind
        if job.iecReport?.namesAnotherStation(than: job.stationName) == true { confirmExport = true } else { export(kind) }
    }

    func export(_ kind: IECReport.ExportRecord.Kind) {
        switch kind {
        case .excel: exportExcel()
        case .word: exportWord()
        }
    }

    /// Keeps a made file in the job's documents under `IEC 62446` (so it goes to Drive with them), records it on the
    /// test, and offers it to the share sheet; both are the same bytes.
    private func file(_ data: Data, name: String, kind: IECReport.ExportRecord.Kind) throws {
        for old in job.documents where old.name == name { context.delete(old) }
        let doc = DocumentAsset(name: name, data: data)
        doc.folderPath = "IEC 62446"
        context.insert(doc)
        doc.job = job
        job.updateIEC(context, evenWhenLocked: true) { $0.recordExport(kind, name: name) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        exported = ExportedFile(url: url)
    }

    /// The photo appendix (`IECWord`): every photo the test uses, shrunk to 1600 px off the main thread first.
    private func exportWord() {
        guard let r = job.iecReport else { return }
        // the installation photos have their own report (9, `IECInstallPhotosPage`)
        let install = Set(r.installPhotoFileNames().keys)
        let originals = Dictionary(uniqueKeysWithValues: r.photoFileNames().keys.filter { !install.contains($0) }.compactMap { id in
            job.iecPhoto(id).map { (id, $0.data) }
        })
        let name = IECWord.fileName(station: r.sampleName.map { "ตัวอย่าง " + $0 } ?? job.stationName, date: r.testDate ?? .now)
        makingWord = true
        Task {
            defer { makingWord = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try IECWord.export(r, photos: originals.mapValues { ImageUtil.compressed($0) })
                }.value
                try file(data, name: name, kind: .word)
            } catch IECWord.Failure.noStrings {
                exportError = "ยังไม่มีสตริงให้ทำภาคผนวกภาพถ่าย"
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    /// The PWA's own workbook with this test typed in (`IECExcel`): kept in the job's documents under `IEC 62446`
    /// (so it goes to Drive with them), then offered to the share sheet; both are the same file.
    private func exportExcel() {
        guard let r = job.iecReport else { return }
        do {
            let data = try IECExcel.export(r)
            // example data is named as such, never as this job
            let name = IECExcel.fileName(station: r.sampleName.map { "ตัวอย่าง " + $0 } ?? job.stationName, date: r.testDate ?? .now)
            try file(data, name: name, kind: .excel)
        } catch let f as IECExcel.Failure {
            exportError = f.message
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: DEBUG

    /// `-iecDemo YES` seeds the sample (`reset` replaces the test with it), `-iecStationLine <text>` writes the
    /// sheet's station line, `-iecSetup YES` opens the set-up, `-iecInverter n -iecPhase before|after`
    /// opens a string table (`-iecPage performance|conditions|photos` another page of it), `-iecSlot n` selects its
    /// slot and `-iecEntry YES` opens that string in `กรอกทีละสตริง`.
    enum Debug {
        #if DEBUG
        static let demo = UserDefaults.standard.bool(forKey: "iecDemo") || demoReset || demoFull || UserDefaults.standard.string(forKey: "iecDemo") == "praek"
        static let demoReset = UserDefaults.standard.string(forKey: "iecDemo") == "reset"
        /// `-iecDemo full`: the sample with everything filled in (each step done, none confirmed), replacing the test.
        static let demoFull = UserDefaults.standard.string(forKey: "iecDemo") == "full"
        static let clear = UserDefaults.standard.bool(forKey: "iecClear")
        static let stationLine = UserDefaults.standard.string(forKey: "iecStationLine")
        static let setup = UserDefaults.standard.bool(forKey: "iecSetup")
        static let inverter: Int? = UserDefaults.standard.object(forKey: "iecInverter") == nil ? nil : UserDefaults.standard.integer(forKey: "iecInverter")
        static let phase = UserDefaults.standard.string(forKey: "iecPhase").flatMap(IECReport.Phase.init) ?? .before
        static let slot: Int? = UserDefaults.standard.object(forKey: "iecSlot") == nil ? nil : UserDefaults.standard.integer(forKey: "iecSlot")
        static let page: IECStringGrid.Page = switch UserDefaults.standard.string(forKey: "iecPage") {
        case "performance": .performance
        case "conditions": .conditions
        case "photos": .photos
        case "install": .install
        default: .table
        }
        static let entry = UserDefaults.standard.bool(forKey: "iecEntry")
        /// `-iecStep2 YES`: step 2's page on the sample with a photo for every reading (`-iecStep2State` its states).
        static let step2 = UserDefaults.standard.bool(forKey: "iecStep2")
        /// `-iecStep4 YES`: step 4's page on the sample (`-iecStep4State` its states).
        static let step4 = UserDefaults.standard.bool(forKey: "iecStep4")
        /// `-iecStep 1`: step 1's page; `-iecDemo praek` the sample with the board's models, MPPTs and a drawn SLD.
        static let step1 = UserDefaults.standard.integer(forKey: "iecStep") == 1
        static let praek = UserDefaults.standard.string(forKey: "iecDemo") == "praek"
        /// `-iecSheet INV01-before|INV02-after|…`: the sheet preview on that sheet (`-iecSheetSource off` hides the
        /// sources). Step 1's `-iecSheet add|delete|sn` are its own.
        static let sheet: SheetTarget? = UserDefaults.standard.string(forKey: "iecSheet").flatMap { v in
            guard v.hasPrefix("INV"), let n = Int(v.dropFirst(3).prefix(2)) else { return nil }
            return SheetTarget(inverter: n - 1, phase: v.hasSuffix("after") ? .after : .before)
        }
        #else
        static let entry = false
        static let setup = false
        static let slot: Int? = nil
        #endif
    }
}
