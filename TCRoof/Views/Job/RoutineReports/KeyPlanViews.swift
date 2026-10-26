import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import PDFReport

/// The key plan (docs/specs/routine-reports-swift.md §2.1): the A2 site picture of the station's survey report, with a
/// point per location placed in the report settings.
extension Job {
    /// The tag of the station's uploaded key plan: a `PhotoAsset` on the job (`iecPhotos`, the job's own photos), so it
    /// syncs and goes to Drive as the IEC photos do (docs/ui/daily-report-ipad-v2 rules).
    static let keyPlanTag = "keyplan"

    /// The key plan uploaded for this station, once its picture is on this device.
    var uploadedKeyPlan: PhotoAsset? { iecPhotos.first { $0.tag == Self.keyPlanTag } }

    /// Replaces the uploaded key plan with `data` (a JPEG); the locations keep their points.
    @MainActor func setKeyPlan(_ data: Data, context: ModelContext) {
        for p in iecPhotos where p.tag == Self.keyPlanTag { context.delete(p) }
        let asset = PhotoAsset(data: data, tag: Self.keyPlanTag)
        context.insert(asset)
        asset.iecJob = self
        try? context.save()
    }

    /// Back to the survey's A2 picture.
    @MainActor func clearKeyPlan(context: ModelContext) {
        for p in iecPhotos where p.tag == Self.keyPlanTag { context.delete(p) }
        try? context.save()
    }

    /// The key plan: the one uploaded for the station, else the newest linked survey report's site picture, when this
    /// device has it.
    @MainActor var keyPlanPicture: (photo: Photo, image: UIImage)? {
        if let p = uploadedKeyPlan, !p.data.isEmpty, let img = UIImage(data: p.data) {
            return (Photo(fileName: "keyplan.jpg", width: Int(img.size.width), height: Int(img.size.height)), img)
        }
        return surveyKeyPlan
    }

    /// The newest linked survey report's site picture (A2), when it has one on this device.
    @MainActor var surveyKeyPlan: (photo: Photo, image: UIImage)? {
        let survey = SurveyModel.shared
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "routineKeyPlan") { return Self.demoPicture }
        #endif
        guard let id = syncID, let report = survey.jobs(linkedTo: id).max(by: { $0.updated < $1.updated }),
              let p = report.values.photo("siteMap"), let img = survey.image(p, in: report.id) else { return nil }
        return (p, img)
    }

    #if DEBUG
    /// `-routineKeyPlan YES`: a drawn stand-in for the A2 picture (roofs, a tank, the inverter room).
    static let demoPicture: (photo: Photo, image: UIImage) = {
        let size = CGSize(width: 1600, height: 1000)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.62, green: 0.72, blue: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.55, alpha: 1).setFill()
            for r in [CGRect(x: 350, y: 220, width: 260, height: 180), CGRect(x: 760, y: 180, width: 260, height: 160),
                      CGRect(x: 1000, y: 460, width: 300, height: 180), CGRect(x: 700, y: 650, width: 200, height: 130)] { ctx.fill(r) }
            UIColor(red: 0.45, green: 0.6, blue: 0.8, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 300, y: 600, width: 200, height: 200))
        }
        return (Photo(fileName: "demo-site.jpg", width: 1600, height: 1000), img)
    }()
    #endif

    /// The key plan for the PDF, with the image data it draws; nil without a picture or any placed point.
    @MainActor func reportKeyPlan() -> (plan: RoutineReportPages.KeyPlan, image: Data)? {
        guard let (p, img) = keyPlanPicture, img.size.height > 0, let data = img.jpegData(compressionQuality: 0.8) else { return nil }
        let s = routineSettings
        let points = s.locations.compactMap { l in s.keyPoint(l).map { (name: l, x: $0.x, y: $0.y) } }
        guard !points.isEmpty else { return nil }
        return (.init(photo: p, aspect: img.size.width / img.size.height, points: points), data)
    }
}

/// The picture with its location markers; `highlight` ones are filled red. Tapping reports the point as fractions.
struct KeyPlanImage: View {
    let image: UIImage
    let points: [(name: String, x: Double, y: Double)]
    var highlight: Set<String> = []
    var selected: String?
    var onTap: ((Double, Double) -> Void)?

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .overlay {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { at in
                                onTap?(min(max(at.x / g.size.width, 0), 1), min(max(at.y / g.size.height, 0), 1))
                            }
                        ForEach(points, id: \.name) { p in marker(p).position(x: p.x * g.size.width, y: p.y * g.size.height) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func marker(_ p: (name: String, x: Double, y: Double)) -> some View {
        let on = highlight.contains(p.name), sel = selected == p.name
        return Circle().fill(on ? Theme.danger : Theme.paper).frame(width: 14, height: 14)
            .overlay(Circle().stroke(sel ? Theme.primary : on ? Theme.paper : Theme.navy, lineWidth: sel ? 3 : 1.5))
            // the label hangs to the right without moving the circle off the point
            .overlay(alignment: .leading) {
                Text(p.name).font(.sarabun(11, on || sel ? .bold : .regular, relativeTo: .caption2)).foregroundStyle(on ? Theme.dangerText : Theme.navy)
                    .padding(.horizontal, 4).background(Theme.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize().offset(x: 18)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(p.name + (on ? " มีงานวันนี้" : ""))
    }
}

/// The daily screen's key plan card: today's locations in red.
struct KeyPlanCard: View {
    let job: Job
    let today: Set<String>
    @State private var picture: UIImage?
    @State private var showSettings = false
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        let s = job.routineSettings
        let points = s.locations.compactMap { l in s.keyPoint(l).map { (name: l, x: $0.x, y: $0.y) } }
        ReportCard("ผังตำแหน่ง (Key plan)") {
            if let picture, !points.isEmpty {
                KeyPlanImage(image: picture, points: points, highlight: today)
                Text("จุดสีแดง = มีงานวันนี้").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            } else {
                Text(picture == nil ? "ยังไม่มีภาพสถานที่ (A2) ในแบบสำรวจของงานนี้" : "ยังไม่ได้วางตำแหน่งบนภาพ")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                if picture != nil {
                    Button("วางตำแหน่งบนภาพ") { showSettings = true }.font(.sarabun(15, .semibold, relativeTo: .subheadline)).frame(minHeight: touchMin)
                }
            }
        }
        .task { picture = job.keyPlanPicture?.image }
        .sheet(isPresented: $showSettings, onDismiss: { refresh += 1 }) { KeyPlanSheet(job: job) }
    }
}

/// Places each station location on the picture: pick a location, then tap where it is. Edits `settings`; the caller saves.
struct KeyPlanEditor: View {
    let job: Job
    @Binding var settings: RoutineReport.Settings
    @State private var selected: String?
    @State private var picture: UIImage?

    var body: some View {
        let points = settings.locations.compactMap { l in settings.keyPoint(l).map { (name: l, x: $0.x, y: $0.y) } }
        PadForm(maxWidth: 900) {
            PadSection {
                if let picture {
                    KeyPlanImage(image: picture, points: points, selected: selected) { x, y in
                        guard let sel = selected else { return }
                        settings.keyPoints[sel] = [x, y]
                        // move on to the next location still without a point
                        selected = settings.locations.first { settings.keyPoint($0) == nil } ?? sel
                    }
                } else {
                    Text("ยังไม่มีภาพสถานที่ (A2) ในแบบสำรวจของงานนี้ ถ่ายหรือนำเข้าภาพในหน้า A2 ก่อน").foregroundStyle(Theme.muted)
                }
            } footer: {
                Text(selected.map { "แตะบนภาพเพื่อวาง \($0)" } ?? "เพิ่มตำแหน่งในสถานีก่อน")
            }
            PadSection("ตำแหน่ง") {
                ForEach(settings.locations, id: \.self) { l in
                    HStack(spacing: 8) {
                        Button { selected = l } label: {
                            HStack {
                                Image(systemName: selected == l ? "largecircle.fill.circle" : "circle").foregroundStyle(Theme.primary)
                                Text(l).foregroundStyle(Theme.navy)
                                Spacer()
                                Text(settings.keyPoint(l) == nil ? "ยังไม่วาง" : "วางแล้ว").font(.sarabun(12, relativeTo: .caption))
                                    .foregroundStyle(settings.keyPoint(l) == nil ? Theme.muted : Theme.okText)
                            }
                            .frame(minHeight: touchMin).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if settings.keyPoint(l) != nil {
                            PadRowButton("ลบจุด \(l)", systemImage: "mappin.slash", destructive: true) { settings.keyPoints[l] = nil }
                        }
                    }
                }
            }
        }
        .navigationTitle("ผังตำแหน่ง (Key plan)")
        .navigationBarTitleDisplayMode(.inline)
        .tcPadNavBar("ผังตำแหน่ง (Key plan)", trail: ["หน้าหลัก", job.code])
        .task {
            picture = job.keyPlanPicture?.image
            if selected == nil { selected = settings.locations.first { settings.keyPoint($0) == nil } ?? settings.locations.first }
        }
    }
}

/// The editor on its own, saving into the job (from the daily screen's key plan card).
struct KeyPlanSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @State private var settings: RoutineReport.Settings

    init(job: Job) {
        self.job = job
        _settings = State(initialValue: job.routineSettings)
    }

    var body: some View {
        NavigationStack {
            KeyPlanEditor(job: job, settings: $settings)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("บันทึก") { job.routineSettings = settings; dismiss() }.bold()
                    }
                }
        }
    }
}
