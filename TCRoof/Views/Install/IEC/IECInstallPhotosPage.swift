import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import PDFReport
import ExcelExport

/// `9 ภาพถ่ายติดตั้งระบบ` (design canvas `iPad · IEC 62446 · 9`): the roofs, then one card per page of the report with its
/// photo slots, and `PDF รายงาน 9`, which makes every page (cover, contents, one page each) from what is taken. The
/// pages follow the station's roofs and inverters (`IECReport.installPages`); an inverter's two photos are step 1's.
/// On iPhone (compact width, `IECInstallPhotosScreen`) it is one column: the button under the count, the photos stacked.
struct IECInstallPhotosPage: View {
    @Bindable var job: Job
    /// A sent or closed test: the roofs and photos can't change, the PDF can still be made.
    var readOnly = false
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.permissions) private var permissions
    @State private var newRoof = ""
    @State private var making = false
    @State private var share: ReportShare?
    @State private var failure: String?

    private var compact: Bool { sizeClass == .compact }
    private var cardPadding: CGFloat { compact ? 14 : 18 }

    var body: some View {
        let r = job.iecReport ?? job.newIECReport
        let pages = r.installPages
        VStack(alignment: .leading, spacing: 14) {
            summary(r, pages: pages.count)
            roofs(r).disabled(readOnly)
            ForEach(Array(pages.enumerated()), id: \.element.id) { n, page in
                pageCard(r, page, number: n + 1).disabled(readOnly)
            }
        }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .alert("ทำ PDF ไม่สำเร็จ", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private func summary(_ r: IECReport, pages: Int) -> some View {
        let t = r.installTally, left = t.total - t.done
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(left == 0 ? "ครบ \(t.total) รูปแล้ว" : "ถ่ายแล้ว \(t.done)/\(t.total) รูป · เหลือ \(left)")
                    .font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(left == 0 ? "พร้อมทำรายงาน 9 (\(pages) หน้า + ปก)" : "ช่องที่ยังไม่มีรูปจะว่างในรายงาน · \(pages) หน้า + ปก")
                    .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            if !compact { Spacer(minLength: 8) }
            TCButton(making ? "กำลังทำ PDF…" : "PDF รายงาน 9", systemImage: "doc.richtext", kind: .primary, fullWidth: compact) { makePDF() }
                .disabled(making)
                .accessibilityIdentifier("iecInstallPDF")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The roofs: each has two pages; renaming keeps its photos, removing one deletes them.
    private func roofs(_ r: IECReport) -> some View {
        let list = r.installPhotos.effectiveRoofs
        return VStack(alignment: .leading, spacing: 10) {
            Text("หลังคา · \(list.count) หลัง (หลังละ 2 หน้า)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
            ForEach(list) { roof in
                HStack(spacing: 10) {
                    IECRoofNameField(name: roof.name) { name in
                        job.updateIEC(context) { $0.installPhotos.renameRoof(roof.id, to: name) }
                    }
                    if list.count > 1 {
                        Button(role: .destructive) { remove(roof) } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.dangerText)
                        .accessibilityLabel("ลบ " + roof.name)
                    }
                }
            }
            let add = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            add {
                TextField("ชื่อหลังคาที่เพิ่ม เช่น หลังคาอาคารถังน้ำใส 2", text: $newRoof)
                    .font(.sarabunFixed(15)).textFieldStyle(OutlinedFieldStyle(dense: true))
                    .onSubmit(addRoof)
                TCButton("เพิ่มหลังคา", systemImage: "plus", kind: .secondary, fullWidth: compact, action: addRoof)
                    .disabled(newRoof.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pageCard(_ r: IECReport, _ page: IECReport.InstallPage, number: Int) -> some View {
        let taken = page.slots.filter { r.installPhoto($0) != nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("9.\(number)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    Text(page.slots.contains { if case .inverter = $0.source { true } else { false } }
                         ? "รูปเดียวกับขั้น 1/7 · " + page.subtitle : page.subtitle)
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                Text("\(taken)/\(page.slots.count)").font(.sarabunFixed(14, .bold)).monospacedDigit()
                    .foregroundStyle(taken == page.slots.count ? Theme.successInk : Theme.inkMuted)
            }
            // two side by side on iPad, as the printed page; one under the other on iPhone
            let slots = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            slots {
                ForEach(page.slots) { slot in
                    VStack(alignment: .leading, spacing: 6) {
                        IECPhotoTile(caption: Self.short(slot.caption), asset: job.iecPhoto(r.installPhoto(slot)), height: compact ? 220 : 200,
                                     stubReading: "9.\(number)") { data in
                            let old = (job.iecReport ?? job.newIECReport).installPhoto(slot)
                            let id = job.storeIECPhoto(data, replacing: old, context: context)
                            job.updateIEC(context) { $0.setInstallPhoto(id, for: slot) }
                        } remove: {
                            job.removeIECPhoto(r.installPhoto(slot), context: context)
                            job.updateIEC(context) { $0.setInstallPhoto(nil, for: slot) }
                        }
                        Text(slot.caption).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                        Text(slot.tip).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // a one-photo page keeps the card's two columns
                if page.slots.count == 1, !compact { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
        }
        .padding(cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The tile's own label: the report's heading without its `ภาพถ่าย`.
    static func short(_ caption: String) -> String {
        caption.hasPrefix("ภาพถ่าย") ? String(caption.dropFirst("ภาพถ่าย".count)) : caption
    }

    private func addRoof() {
        let name = newRoof.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        job.updateIEC(context) { $0.installPhotos.addRoof(name) }
        newRoof = ""
    }

    private func remove(_ roof: IECReport.InstallPhotos.Roof) {
        var r = job.iecReport ?? job.newIECReport
        guard !r.isLocked else { return }
        let gone = r.installPhotos.removeRoof(roof.id)
        gone.forEach { job.removeIECPhoto($0, context: context) }
        job.updateIEC(context) { _ = $0.installPhotos.removeRoof(roof.id) }
    }

    // MARK: PDF

    /// Every page of the report, kept in the job's documents under `IEC 62446` (so it goes to Drive) and offered to
    /// the share sheet. Photos are shrunk to 1600 px off the main thread first.
    private func makePDF() {
        let r = job.iecReport ?? job.newIECReport
        let pages = r.installPages
        let originals = Dictionary(uniqueKeysWithValues: pages.flatMap(\.slots).compactMap { slot in
            r.installPhoto(slot).flatMap { id in job.iecPhoto(id).map { (id, $0.data) } }
        })
        let logos = (try? IECWord.formLogos()) ?? []
        let station = r.sampleName.map { "ตัวอย่าง " + $0 } ?? job.stationName
        let capacity = (r.installedKWp > 0 ? r.installedKWp : job.capacityKW)
            .formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
        making = true
        Task {
            defer { making = false }
            let small = await Task.detached(priority: .userInitiated) { originals.mapValues { ImageUtil.compressed($0) } }.value
            var images: [UUID: Data] = [:]
            func photo(_ data: Data, _ name: String) -> Photo {
                let p = Photo(fileName: name, width: 0, height: 0)
                images[p.id] = data
                return p
            }
            let report = InstallPhotoPages(
                station: station, capacity: capacity, month: Self.month.string(from: .now),
                pages: pages.map { page in
                    .init(title: page.title, group: page.group, slots: page.slots.map { slot in
                        .init(caption: slot.caption, photo: r.installPhoto(slot).flatMap { small[$0] }.map { photo($0, "install.jpg") })
                    })
                },
                logos: logos.enumerated().map { i, d in photo(d, i == 0 ? "pwa.jpg" : "pea.png") },
                measure: PDFRenderer.Measure())
            let data = PDFRenderer.pdf(pages: report.render(), title: "ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า") { p in
                images[p.id].flatMap(UIImage.init(data:))
            }
            let name = "ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า \(station).pdf"
            for old in job.documents where old.name == name { context.delete(old) }
            let doc = DocumentAsset(name: name, data: data)
            doc.folderPath = "IEC 62446"
            context.insert(doc)
            doc.job = job
            // a real station's report is its paper in เอกสารสถานี, so the Drive upload files it in the hand-over folders
            // (the team's: a contractor's device never sends station papers)
            if r.sampleName == nil, permissions.can(.stationDocsDrafts) { fileAsPaper(name) }
            try? context.save()
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                share = ReportShare(url: url)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// The station paper this report is (`StationDocs` `install_photo_report`: ขนานไฟ, พค.2 and ส่งมอบ, and พค.2 check
    /// line 23). The paper takes the new file; one missing becomes `ร่างแล้ว`, one further along keeps its status. A file
    /// attached there by hand stays in the job's documents.
    static let paperID = "install_photo_report"

    private func fileAsPaper(_ name: String) {
        var station = job.stationDocs
        var paper = station.docs[Self.paperID] ?? StationDocs.DocState()
        paper.fileName = name
        if paper.status == .missing { paper.status = .draft }
        paper.updatedAt = .now
        station.docs[Self.paperID] = paper
        job.stationDocs = station
    }

    /// `ตุลาคม 2569`, the cover's foot.
    static let month: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.calendar = Calendar(identifier: .buddhist)
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}

/// The page on its own, pushed from the job screen's `ภาพถ่ายติดตั้งระบบ` row: the iPhone's way to it (the iPad also
/// has it in the string table's side list). A closed or sent test is read only here too.
struct IECInstallPhotosScreen: View {
    @Bindable var job: Job

    var body: some View {
        let locked = job.iecReport?.isLocked == true
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if locked {
                    Label("ผลทดสอบส่งหรือปิดแล้ว · ทีมต้องเปิด “แก้ไข” ในหน้าทดสอบ IEC ก่อนจึงแก้รูปได้ · ทำ PDF ได้", systemImage: "lock")
                        .font(.sarabunFixed(14)).foregroundStyle(Theme.warningInk)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                IECInstallPhotosPage(job: job, readOnly: locked)
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.phonePage.ignoresSafeArea())
        .navigationTitle("9 ภาพถ่ายติดตั้งระบบ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A roof's name, saved when typing ends.
private struct IECRoofNameField: View {
    let name: String
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("ชื่อหลังคา", text: $text)
            .font(.sarabunFixed(15)).textFieldStyle(OutlinedFieldStyle(dense: true))
            .focused($focused)
            .onAppear { text = name }
            .onChange(of: name) { _, n in if !focused { text = n } }
            .onChange(of: focused) { _, on in if !on { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { text = name } else if t != name { save(t) }
    }
}
