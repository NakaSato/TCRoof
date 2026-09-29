#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SurveyCore
import DriveSync

/// Entry point of the survey-report feature. Put it inside a NavigationStack
/// (TCRoof pushes it from "สำรวจหน้างาน"; a standalone app wraps it in `SolarSurveyScene`).
public struct SolarSurveyReportView: View {
    @State private var model = SurveyModel.shared
    let title: String
    let subtitle: String
    /// - Parameters:
    ///   - title: heading of the job list, e.g. the client group "การประปาส่วนภูมิภาค".
    public init(title: String = "PWA Solar Survey",
                subtitle: String = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)") {
        self.title = title; self.subtitle = subtitle
    }
    public var body: some View { SurveyHomeView(title: title, subtitle: subtitle).environment(model) }
}

public extension SurveyModel {
    @MainActor static let shared = SurveyModel()
}

struct SurveyHomeView: View {
    var title = "PWA Solar Survey"
    var subtitle = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
    @Environment(SurveyModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var search = ""
    @State private var showNew = false
    @State private var open: Job?
    @State private var importing = false
    @State private var showSettings = false
    @State private var showDriveOpen = false
    @State private var share: SurveyModel.ExportFile?
    @State private var toDelete: Job?
    @State private var message: String?
    @State private var error: String?

    var filtered: [Job] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.jobs }
        return model.jobs.filter { j in
            [j.docNo, j.projectName, j.values.text("address"), j.values.text("coordinator"), j.values.text("engineer")].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let compact = sizeClass == .compact
                let header = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                header {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(compact ? .title2.bold() : .largeTitle.bold())
                        Text(subtitle).font(compact ? .subheadline : .body).foregroundStyle(.secondary)
                    }
                    if !compact { Spacer() }
                    Button { showNew = true } label: {
                        Label("งานสำรวจใหม่", systemImage: "plus").frame(maxWidth: compact ? .infinity : nil)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(Paper.tick) }
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.jobs.isEmpty ? "ยังไม่มีงานสำรวจ" : "ไม่พบงานที่ค้นหา", systemImage: "list.clipboard")
                    } description: {
                        Text(model.jobs.isEmpty ? "เริ่มงานใหม่ หรือเปิดงานที่บันทึกไว้จาก Google Drive / ไฟล์สำรอง" : "ลองคำค้นอื่น")
                    } actions: {
                        if model.jobs.isEmpty { Button("งานสำรวจใหม่") { showNew = true }.buttonStyle(.borderedProminent) }
                    }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { j in
                            Button { open = j } label: { JobCard(job: j) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { model.duplicate(j.id) } label: { Label("ทำสำเนา", systemImage: "plus.square.on.square") }
                                    Button { do { share = try model.exportBackup([j.id]) } catch { self.error = error.localizedDescription } } label: { Label("ส่งออกข้อมูลงาน", systemImage: "square.and.arrow.up") }
                                    Button(role: .destructive) { toDelete = j } label: { Label("ลบงาน", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .padding(sizeClass == .compact ? 16 : 24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Paper.page)
        .searchable(text: $search, prompt: "ค้นหาเลขที่ ชื่อโครงการ ที่อยู่")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $open) { j in JobEditorView(job: model.job(j.id) ?? j).environment(model) }
        #if DEBUG
        // `-surveyDemo YES` opens a job right away for simulator checks; add `-surveyDemoSection YES` to open its first section.
        .task {
            guard UserDefaults.standard.bool(forKey: "surveyDemo"), open == nil else { return }
            open = model.jobs.first ?? model.create(JobTemplate.all[0], engineer: model.settings.engineer)
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showDriveOpen = true } label: { Label("เปิดจาก Google Drive", systemImage: "icloud.and.arrow.down") }
                Menu {
                    Button { importing = true } label: { Label("นำเข้าไฟล์ข้อมูล (.json)", systemImage: "square.and.arrow.down") }
                    Button { do { share = try model.exportBackup() } catch { self.error = error.localizedDescription } } label: { Label("สำรองข้อมูลทุกงาน", systemImage: "externaldrive") }
                        .disabled(model.jobs.isEmpty)
                    Divider()
                    Button { showSettings = true } label: { Label("ตั้งค่า", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showNew) {
            NewJobSheet { t in let j = model.create(t, engineer: model.settings.engineer); showNew = false; open = j }
        }
        .sheet(isPresented: $showSettings) { SurveySettingsView().environment(model) }
        .sheet(isPresented: $showDriveOpen) { DriveOpenView { j in showDriveOpen = false; open = j }.environment(model) }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { r in
            do {
                guard let url = try r.get().first else { return }
                let n = try model.importFile(url)
                message = "นำเข้า \(n) งานแล้ว"
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("ลบงานนี้?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { j in
            Button("ลบ \(j.projectName)", role: .destructive) { model.delete(j.id); toDelete = nil }
        } message: { _ in Text("ข้อมูลและรูปทั้งหมดของงานนี้ในเครื่องจะถูกลบ (ไฟล์ใน Google Drive ไม่ถูกลบ)") }
        .errorAlert($error)
        .onAppear { model.reload() }
    }
}

struct JobCard: View {
    let job: Job
    @Environment(SurveyModel.self) private var model
    var body: some View {
        let c = job.completion
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(job.projectName.isEmpty ? "(ยังไม่ได้ตั้งชื่อโครงการ)" : job.projectName).font(.headline).lineLimit(2)
                }
                Spacer()
                ProgressRing(value: c.fraction, size: 42)
            }
            Text(job.values.text("address").isEmpty ? "—" : job.values.text("address")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            if let id = job.jobSyncID, let label = model.linkedJobLabel?(id) {
                Label(label, systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).lineLimit(1)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(job.sectionsByCategory) { g in
                    Text("\(g.category.rawValue) \(g.category.title) ×\(g.sections.count)").font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Paper.band, in: Capsule())
                }
            }
            Divider()
            HStack {
                Label(ISODate.thai(job.values.text("date")), systemImage: "calendar")
                Spacer()
                Label("\(job.photoCount)", systemImage: "photo")
                if job.drive?.folderID != nil { Image(systemName: "icloud.fill").foregroundStyle(.blue) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct NewJobSheet: View {
    let create: (JobTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(JobTemplate.all) { t in
                        Button { create(t) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.label).font(.headline).foregroundStyle(.primary)
                                Text(t.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } footer: { Text("เพิ่มหรือลบหัวข้อสำรวจภายหลังได้ในหน้าแก้ไขงาน") }
            }
            .navigationTitle("เริ่มงานสำรวจใหม่").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct SurveySettingsView: View {
    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var s = SurveySettings()
    @State private var error: String?
    @State private var signedIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("รายงาน") {
                    TextField("ชื่อบริษัท (หัวรายงาน PDF)", text: $s.company)
                    TextField("ชื่อวิศวกรผู้สำรวจ (ใส่ให้งานใหม่อัตโนมัติ)", text: $s.engineer)
                }
                Section {
                    SecureField("Google Maps API key (Maps Static API)", text: $s.googleMapsKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Stepper(value: $s.mapZoom, in: 15...21) {
                        LabeledContent("ระดับซูม", value: "\(s.mapZoom)  (กว้างประมาณ \(Int(MapImage.metersAcross(lat: 15, zoom: s.mapZoom).rounded())) ม.)")
                    }
                } header: { Text("ภาพสถานที่ติดตั้งจากแผนที่") } footer: {
                    Text("ปุ่ม \"Google Maps\" ในกรอบภาพสถานที่ติดตั้ง / ภาพมุมสูง ดึงภาพดาวเทียมตรงพิกัด GPS ของงาน ใส่ key ของ Maps Static API เพื่อใช้ภาพ Google ถ้าเว้นว่างจะใช้ภาพดาวเทียมของ Apple Maps แทน")
                }
                Section {
                    TextField("xxxxxxxx.apps.googleusercontent.com", text: $s.googleClientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("โฟลเดอร์หลักใน Drive", text: $s.driveRoot)
                    Toggle("อัปรูปขึ้น Drive อัตโนมัติ", isOn: $s.autoUploadPhotos)
                    if signedIn {
                        LabeledContent("บัญชี", value: model.google.email ?? "ลงชื่อเข้าใช้แล้ว")
                        Button("ออกจากระบบ Google", role: .destructive) { if let out = model.signOutHandler { out() } else { model.google.signOut(); signedIn = false } }
                    } else {
                        Button("ลงชื่อเข้าใช้ Google") {
                            apply()
                            Task { do { try await model.google.signIn(); signedIn = true } catch { self.error = error.localizedDescription } }
                        }
                    }
                } header: { Text("Google Drive") } footer: {
                    Text("สร้าง OAuth client ชนิด iOS ใน Google Cloud Console (เปิด Google Drive API) ใส่ Bundle ID ของแอป แล้วคัดลอก Client ID มาวางที่นี่ แอปจะเห็นเฉพาะไฟล์ที่แอปสร้างเอง (สิทธิ์ drive.file)\n\nอัปรูปอัตโนมัติ: รูปใหม่จะถูกส่งเข้าโฟลเดอร์งานใน Drive ภายในไม่กี่วินาที เพื่อให้ iPad เครื่องอื่นที่เปิดงานเดียวกันดึงรูปไปได้")
                }
            }
            .navigationTitle("ตั้งค่าแบบสำรวจ").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { apply(); dismiss() } }
            }
            .onAppear { s = model.settings; signedIn = model.google.isSignedIn }
            .errorAlert($error)
        }
    }

    func apply() {
        s.googleClientID = s.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings = s
        model.google.clientID = s.googleClientID
    }
}
#endif
