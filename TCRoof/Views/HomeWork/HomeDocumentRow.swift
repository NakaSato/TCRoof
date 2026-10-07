import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import TCRoofUI
import TCRoofCore

/// One document of a home job: status, who brings it, its PPIM slot, files, and the screen that makes it.
struct HomeDocumentRow<Destination: View>: View {
    let spec: HomeDocSpec
    @Binding var document: HomeDocument
    let store: PermitStore
    @ViewBuilder var destination: () -> Destination

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var preview: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                statusMark
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.title).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    tags
                    if let note = spec.note {
                        Text(note).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                statusMenu
            }
            actions
            if !document.files.isEmpty { fileList }
        }
        .padding(Space.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        add(ImageUtil.compressed(data), ext: "jpg")
                    }
                }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { add(data, ext: url.pathExtension) }
            }
        }
        .quickLookPreview($preview)
    }

    private var statusMark: some View {
        let done = document.status.isDone
        return Image(systemName: done ? "checkmark.circle.fill" : (spec.optional ? "circle.dashed" : "circle"))
            .font(.system(size: 22)).foregroundStyle(done ? Theme.okTick : Theme.borderControl)
            .accessibilityLabel(document.status.title)
    }

    private var tags: some View {
        HStack(spacing: 6) {
            TCStatusChip(spec.provider.title, fill: Theme.primarySoft, text: Theme.navy)
            if let slot = spec.ppimSlot, let mb = spec.maxMB {
                TCStatusChip("PPIM ช่อง \(slot) · ≤ \(mb) MB", fill: Theme.okSoft, text: Theme.okText)
            }
            if spec.optional { TCStatusChip("ถ้ามี", fill: Theme.disabledFill, text: Theme.inkMuted) }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(HomeDocStatus.allCases, id: \.self) { s in
                Button { set(s) } label: { Label(s.title, systemImage: document.status == s ? "checkmark" : "") }
            }
        } label: {
            TCStatusChip(document.status.title, kind: document.status.isDone ? .done : .pending)
                .frame(minHeight: touchMin)
        }
        .accessibilityLabel("สถานะ \(document.status.title)")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s) {
            if spec.form != nil && spec.form != .roofWeight {
                NavigationLink(destination: destination) {
                    Label("เปิดแบบฟอร์ม", systemImage: "square.and.pencil").font(.sarabun(14, .semibold, relativeTo: .body))
                        .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
            if spec.ppimSlot != nil || spec.form == nil {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Label("รูป", systemImage: "photo").font(.sarabun(14, .semibold, relativeTo: .body))
                        .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
                }
                .buttonStyle(.plain)
                TCButton("ไฟล์ PDF", systemImage: "doc", kind: .secondary, size: .card) { showImporter = true }
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(document.files.enumerated()), id: \.element) { i, name in
                HStack {
                    Button { preview = store.url(name) } label: {
                        Label("ไฟล์ \(i + 1) · \(name.hasSuffix("pdf") ? "PDF" : "รูป")", systemImage: name.hasSuffix("pdf") ? "doc.richtext" : "photo")
                            .font(.sarabun(13.5, relativeTo: .caption)).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { remove(name) } label: {
                        Image(systemName: "trash").frame(width: touchMin, height: 32)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.dangerText)
                    .accessibilityLabel("ลบไฟล์ \(i + 1)")
                }
            }
        }
    }

    private func add(_ data: Data, ext: String) {
        let name = store.addFile(data, ext: ext)
        document.files.append(name)
        if !document.status.isDone { document.status = .received }
        document.updatedAt = .now
    }

    private func remove(_ name: String) {
        store.deletePhoto(name)
        document.files.removeAll { $0 == name }
        if document.files.isEmpty && spec.form == nil { document.status = .missing }
        document.updatedAt = .now
    }

    private func set(_ status: HomeDocStatus) {
        document.status = status
        document.updatedAt = .now
    }
}
