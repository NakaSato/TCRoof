#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import TCRoofCore

/// คลังแบบมาตรฐาน (docs/specs/standard-designs.md §2): the supplied sheets and the designs the team saved, with their
/// revision and where they came from. The team (`design.library`) renames, archives and imports; anyone exports a
/// `.tcdesign` file. Designs reach the other devices through Firestore (the app's CloudSync).
struct DesignLibraryView: View {
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    /// Bumped after each change, as the library isn't observable.
    @State private var version = 0
    @State private var renaming: TankDesign?
    @State private var newName = ""
    @State private var importing = false
    /// `แนบแบบ`: the design a picked PDF / image goes to; the sheet opened.
    @State private var attaching: TankDesign?
    @State private var viewing: TankDesign?
    @State private var share: URL?
    @State private var error: String?

    var canEdit: Bool { permissions.can(.designLibrary) }

    var body: some View {
        NavigationStack {
            List {
                Section("แบบ กปภ. ที่ทีมส่งมา") {
                    ForEach(TankDesign.seeds) { d in row(d) }
                }
                Section {
                    let saved = DesignLibrary.shared.tanks
                    if saved.isEmpty {
                        Text("ยังไม่มีแบบที่บันทึก · ตรวจถังครบทุกจุดแล้วกด บันทึกเป็นแบบมาตรฐาน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    }
                    ForEach(saved) { d in row(d) }
                } header: {
                    Text("แบบที่ทีมบันทึก")
                } footer: {
                    Text(canEdit ? "งานที่ใช้แบบไปแล้วเก็บสำเนาของแบบไว้ แก้แบบในคลังไม่กระทบงานเดิม"
                                 : "ผู้รับเหมาใช้แบบได้ แต่บันทึก แก้ไข หรือนำเข้าแบบไม่ได้").font(.sarabunFixed(12))
                }
            }
            .id(version)
            .navigationTitle("คลังแบบมาตรฐาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button { importing = true } label: { Label("นำเข้า", systemImage: "square.and.arrow.down") }
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
                do {
                    let url = try result.get()
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    try DesignLibrary.shared.importFile(Data(contentsOf: url))
                    version += 1
                } catch { self.error = "นำเข้าไม่ได้: " + error.localizedDescription }
            }
            .fileImporter(isPresented: Binding(get: { attaching != nil }, set: { if !$0 { attaching = nil } }),
                          allowedContentTypes: [.pdf, .image]) { result in
                guard let d = attaching else { return }
                attaching = nil
                do {
                    let url = try result.get()
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    let pages = DesignSheetViewer.pages(from: url).compactMap { DesignLibrary.shared.storeSheetPage($0.0, width: $0.1, height: $0.2) }
                    guard !pages.isEmpty else { return error = "อ่านไฟล์แบบไม่ได้" }
                    DesignLibrary.shared.setSheet(d.id, pages)
                    version += 1
                } catch { self.error = "แนบไม่ได้: " + error.localizedDescription }
            }
            .sheet(item: $viewing) { d in DesignSheetViewer(design: d) }
            .alert("แก้ชื่อแบบ", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("ชื่อแบบ", text: $newName)
                Button("บันทึก") {
                    if let d = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty { DesignLibrary.shared.rename(d.id, to: newName); version += 1 }
                    renaming = nil
                }
                Button("ยกเลิก", role: .cancel) { renaming = nil }
            }
            .sheet(item: Binding(get: { share.map(SharedFile.init) }, set: { share = $0?.url })) { f in
                ShareSheet(items: [f.url]).presentationDetents([.medium, .large])
            }
            .errorAlert($error)
        }
        .foregroundStyle(Theme.navy)
    }

    struct SharedFile: Identifiable { let url: URL; var id: String { url.path } }

    func counts(_ d: TankDesign) -> String {
        "ช่องระบาย \(d.vents.count) · ช่องลงถัง \(d.hatches.count) · บันได \(d.ladders.count)" + (d.pipes.isEmpty ? "" : " · ท่อ \(d.pipes.count)")
    }

    func row(_ d: TankDesign) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.name).font(.sarabunFixed(15, .bold))
                    if d.archived {
                        Text("เก็บเข้าคลัง").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.inkMuted)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.hairline, in: Capsule())
                    }
                }
                Text(d.size + " · " + counts(d)).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                Text((d.isSeed ? "" : "rev \(d.revision) · ") + d.source).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 6)
            Menu {
                if !d.sheet.isEmpty { Button { viewing = d } label: { Label("ดูแบบ (\(d.sheet.count) หน้า)", systemImage: "doc.richtext") } }
                Button { export(d) } label: { Label("ส่งออก .tcdesign", systemImage: "square.and.arrow.up") }
                if canEdit && !d.isSeed {
                    Button { newName = d.name; renaming = d } label: { Label("แก้ชื่อ", systemImage: "pencil") }
                    Button { attaching = d } label: { Label(d.sheet.isEmpty ? "แนบแบบ (PDF / รูป)" : "แนบแบบใหม่แทนของเดิม", systemImage: "paperclip") }
                    Button { DesignLibrary.shared.archive(d.id, !d.archived); version += 1 } label: {
                        Label(d.archived ? "นำกลับมาใช้" : "เก็บเข้าคลัง", systemImage: d.archived ? "tray.and.arrow.up" : "archivebox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("ตัวเลือกของ \(d.name)")
        }
        .opacity(d.archived ? 0.6 : 1)
    }

    func export(_ d: TankDesign) {
        let safe = d.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe + ".tcdesign")
        do { try d.exported().write(to: url, options: .atomic); share = url } catch { self.error = error.localizedDescription }
    }
}
#endif
