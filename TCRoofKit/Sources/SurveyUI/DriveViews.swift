#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import DriveSync
import TCRoofUI

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
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if files.isEmpty && !loading && error == nil { Text("ไม่พบไฟล์ข้อมูลงาน (survey-data) ใน Drive").foregroundStyle(.secondary) }
                ForEach(files) { f in
                    Button { open(f) } label: {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(f.name).foregroundStyle(.primary)
                                if let d = f.modified { Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if opening == f.id { ProgressView() }
                        }
                    }
                    .disabled(opening != nil)
                }
            }
            .tcFormStyle()
            .overlay { if loading { ProgressView("กำลังค้นหาใน Google Drive…") } }
            .navigationTitle("เปิดงานจาก Google Drive").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { load() } label: { Image(systemName: "arrow.clockwise") } }
            }
            .task { load() }
        }
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
