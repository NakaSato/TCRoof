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
    /// Optional for this job's route (`HomeDocSpec.isOptional(for:)`).
    var optional: Bool
    /// Library-backed documents: the item attached, the items to choose from, and how to change the pick.
    var libraryItem: HomeLibrary.Item? = nil
    var libraryChoices: [HomeLibrary.Item] = []
    var onPick: (String?) -> Void = { _ in }
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
            if HomeLibrary.Kind(docID: spec.id) != nil { libraryLine }
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
        return Image(systemName: done ? "checkmark.circle.fill" : (optional ? "circle.dashed" : "circle"))
            .font(.system(size: 22)).foregroundStyle(done ? Theme.okTick : Theme.borderControl)
            .accessibilityLabel(document.status.title)
    }

    private var tags: some View {
        HStack(spacing: 6) {
            TCStatusChip(spec.provider.title, fill: providerColors.fill, text: providerColors.text)
            if let slot = spec.ppim {
                TCStatusChip("PPIM ช่อง \(slot.number) | ≤ \(slot.maxMB) MB", fill: Theme.okSoft, text: Theme.okText)
            }
            if optional { TCStatusChip("ถ้ามี", fill: Theme.disabledFill, text: Theme.inkMuted) }
        }
    }

    /// Who brings it, by colour: team blue, customer amber, engineer navy, PEA green, council and กกพ. grey.
    private var providerColors: (fill: Color, text: Color) {
        switch spec.provider {
        case .team: (Theme.primarySoft, Theme.primary)
        case .customer: (Theme.pendingSoft, Theme.pending)
        case .engineer: (Theme.segmentTrack, Theme.navy)
        case .pea: (Theme.okSoft, Theme.okText)
        case .local, .erc: (Theme.disabledFill, Theme.inkMuted)
        }
    }

    /// PEA and กกพ. send these; until then the row waits rather than lacks.
    private var waitsForAuthority: Bool { (spec.provider == .pea || spec.provider == .erc) && spec.form == nil }

    private var statusTitle: String {
        waitsForAuthority && document.status == .missing ? "รอผล" : document.status.title
    }

    /// The button that opens the screen making this document, named for what it does there.
    private var formAction: (title: String, icon: String) {
        switch spec.form {
        case .surveyForm: ("ทำแบบสำรวจ", "list.clipboard")
        case .photoReport: ("ถ่ายรูป 9 หัวข้อ", "camera")
        case .powerOfAttorney: ("เซ็นมอบอำนาจ", "signature")
        case .selfCertification: ("เปิดแบบรับรอง", "checkmark.seal")
        case .installLog: ("เปิดบันทึกติดตั้ง", "hammer")
        case .inspection: ("เปิด ICL", "checkmark.shield")
        case .boq: ("ตรวจ BOQ", "tablecells")
        case .site: ("เปิดงานผู้รับเหมา", "person.2")
        case .roofWeight, nil: ("เปิดแบบฟอร์ม", "square.and.pencil")
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(HomeDocStatus.allCases, id: \.self) { s in
                Button { set(s) } label: { Label(s.title, systemImage: document.status == s ? "checkmark" : "") }
            }
        } label: {
            TCStatusChip(statusTitle, kind: document.status.isDone ? .done : .pending)
                .frame(minHeight: touchMin)
        }
        .accessibilityLabel("สถานะ \(statusTitle)")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s) {
            if spec.form != nil && spec.form != .roofWeight {
                NavigationLink(destination: destination) {
                    Label(formAction.title, systemImage: formAction.icon).font(.sarabun(14, .semibold, relativeTo: .body))
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
                TCButton(waitsForAuthority ? "แนบผล" : "ไฟล์ PDF", systemImage: "doc", kind: .secondary, size: .card) { showImporter = true }
            }
        }
    }

    /// Which library item this job uses, with a menu to change or detach it.
    private var libraryLine: some View {
        Menu {
            ForEach(libraryChoices) { item in
                Button { onPick(item.id) } label: {
                    Label(item.name, systemImage: libraryItem?.id == item.id ? "checkmark" : "doc.on.doc")
                }
            }
            if libraryItem != nil {
                Button(role: .destructive) { onPick(nil) } label: { Label("ไม่ใช้จากคลัง", systemImage: "xmark") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(libraryItem.map { "จากคลัง: \($0.name) | \($0.files.count) ไฟล์" }
                     ?? (libraryChoices.isEmpty ? "ยังไม่มีในคลังเอกสาร" : "เลือกจากคลังเอกสาร"))
                    .font(.sarabun(13.5, .semibold, relativeTo: .caption))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(libraryItem == nil ? Theme.inkMuted : Theme.okText)
            .padding(.horizontal, Space.m).frame(minHeight: touchMin)
            .background(libraryItem == nil ? Theme.disabledFill : Theme.okSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .disabled(libraryChoices.isEmpty)
        .accessibilityLabel(libraryItem.map { "ใช้ \($0.name) จากคลังเอกสาร" } ?? "เลือกจากคลังเอกสาร")
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(document.files.enumerated()), id: \.element) { i, name in
                HStack {
                    Button { preview = store.url(name) } label: {
                        Label("ไฟล์ \(i + 1) | \(name.hasSuffix("pdf") ? "PDF" : "รูป")", systemImage: name.hasSuffix("pdf") ? "doc.richtext" : "photo")
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
        if document.files.isEmpty && spec.form == nil && libraryItem == nil { document.status = .missing }
        document.updatedAt = .now
    }

    private func set(_ status: HomeDocStatus) {
        document.status = status
        document.updatedAt = .now
    }
}
