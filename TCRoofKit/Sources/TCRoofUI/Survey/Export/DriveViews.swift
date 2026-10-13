#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import DriveSync

/// Lists survey-data files on Drive and downloads one into this iPad.
struct DriveOpenView: View {
    let opened: (Job) -> Void
    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var files: [DriveFile] = []
    @State private var loading = false
    @State private var error: String?
    @State private var opening: String?

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                if let error { PadSection { Text(error).foregroundStyle(Theme.dangerText) } }
                if files.isEmpty && !loading && error == nil {
                    PadSection { Text("ไม่พบไฟล์ข้อมูลงาน (survey-data) ใน Drive").foregroundStyle(Theme.inkMuted) }
                }
                if !files.isEmpty { PadSection { ForEach(files) { f in fileRow(f) } } }
            }
            .overlay { if loading { ProgressView("กำลังค้นหาใน Google Drive…") } }
            .navigationTitle("เปิดงานจาก Google Drive").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { load() } label: { Image(systemName: "arrow.clockwise") } }
            }
            .task { load() }
        }
    }

    func fileRow(_ f: DriveFile) -> some View {
        Button { open(f) } label: {
            HStack {
                Image(systemName: "doc.text").foregroundStyle(Theme.primary)
                VStack(alignment: .leading) {
                    Text(f.name).foregroundStyle(Theme.navy)
                    if let d = f.modified { Text(d.formatted(date: .abbreviated, time: .shortened)).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
                }
                Spacer()
                if opening == f.id { ProgressView() }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opening != nil)
    }

    func load() {
        loading = true; error = nil
        Task { @MainActor in
            do {
                if !model.google.isSignedIn { try await model.google.signIn() }
                files = try await model.drive.listSaves()
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    func open(_ f: DriveFile) {
        opening = f.id
        Task { @MainActor in
            do { let j = try await model.openFromDrive(f); opened(j) } catch { self.error = error.localizedDescription }
            opening = nil
        }
    }
}
#endif
