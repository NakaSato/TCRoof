import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import TCRoofUI
import TCRoofCore

/// คลังเอกสาร: the engineer's papers and datasheets, kept once and attached to every home job that needs them.
/// Datasheets attach by the model typed for PPIM; the engineer and the equipment set by the default.
struct HomeLibraryView: View {
    @State private var library = HomeLibrary()
    @State private var loaded = false
    @State private var editing: HomeLibrary.Item?

    private let store = PermitStore.library

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "คลังเอกสาร", trail: ["งานบ้าน"], current: "คลังเอกสาร") {}
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("เก็บครั้งเดียว ใช้ทุกงาน · datasheet จับคู่จากรุ่นที่กรอกในข้อมูล PPIM · วิศวกรและชุดอุปกรณ์ใช้ตัวที่ตั้งเป็นค่าหลัก")
                        .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
                    ForEach(HomeLibrary.Kind.allCases, id: \.self) { kindCard($0) }
                }
                .padding(isPhone ? Space.l : Space.xl)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !loaded else { return }
            library = store.load(HomeLibrary.self, PermitStore.libraryFile) ?? HomeLibrary()
            loaded = true
        }
        .onChange(of: library) { _, new in if loaded { store.save(new, PermitStore.libraryFile) } }
        .sheet(item: $editing) { item in
            HomeLibraryItemSheet(item: item, store: store) { saved in
                if let saved {
                    if saved.isDefault {
                        for i in library.items.indices where library.items[i].kind == saved.kind { library.items[i].isDefault = false }
                    }
                    if let i = library.items.firstIndex(where: { $0.id == saved.id }) { library.items[i] = saved } else { library.items.append(saved) }
                }
                editing = nil
            } delete: {
                item.files.forEach(store.deletePhoto)
                library.items.removeAll { $0.id == item.id }
                editing = nil
            }
        }
    }

    private func kindCard(_ kind: HomeLibrary.Kind) -> some View {
        PermitSection(title: kind.title, subtitle: kind == .engineer ? "บัตร + ใบ กว. เซ็นรับรองสำเนา + หนังสือรับรองสภาวิศวกร" : nil) {
            ForEach(library.items(kind)) { itemRow($0) }
            TCButton("เพิ่ม", systemImage: "plus", kind: .secondary, size: .card) {
                var item = HomeLibrary.Item(kind: kind, name: "")
                item.isDefault = library.items(kind).isEmpty
                editing = item
            }
        }
    }

    private func itemRow(_ item: HomeLibrary.Item) -> some View {
        Button { editing = item } label: {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "ไม่มีชื่อ" : item.name).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    Text(detail(item)).font(.sarabun(TypeScale.caption, relativeTo: .caption))
                        .foregroundStyle((HomeLibrary.daysLeft(issued: item.issued) ?? 1) < 0 ? Theme.dangerText : Theme.inkMuted)
                }
                Spacer()
                if item.isDefault { TCStatusChip("ค่าหลัก", kind: .active) }
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkMuted)
            }
            .padding(Space.m)
            .frame(minHeight: touchMin)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ item: HomeLibrary.Item) -> String {
        var parts = [item.files.isEmpty ? "ยังไม่มีไฟล์" : "\(item.files.count) ไฟล์"]
        if item.kind == .engineer {
            if let left = HomeLibrary.daysLeft(issued: item.issued) {
                parts.append(left < 0 ? "หนังสือรับรองหมดอายุ \(-left) วัน" : "หนังสือรับรองใช้ได้อีก \(left) วัน")
            } else {
                parts.append("ยังไม่ใส่วันที่ออกหนังสือรับรอง")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Adds or edits one library item: name, files in order, the engineer's certificate date, default.
struct HomeLibraryItemSheet: View {
    @State var item: HomeLibrary.Item
    let store: PermitStore
    let done: (HomeLibrary.Item?) -> Void
    let delete: () -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var preview: URL?
    @State private var confirmDelete = false
    /// Files are written when picked; on cancel the new ones go, on save the removed ones go.
    @State private var added: [String] = []
    @State private var removed: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    PermitSection(title: item.kind.title) {
                        PermitField(item.kind.nameLabel, text: $item.name, required: true)
                        if item.kind == .engineer {
                            HomeDateRow(title: "หนังสือรับรองสภาวิศวกร ออกวันที่", date: $item.issued,
                                        caption: "ใช้ได้ 120 วัน งานที่ใช้วิศวกรคนนี้จะนับวันจากวันที่นี้", setLabel: "ใส่วันที่ออก")
                        }
                        if item.kind == .engineer || item.kind == .equipment {
                            TCSwitchRow("ใช้เป็นค่าหลักของงานใหม่", isOn: $item.isDefault)
                        }
                    }
                    filesCard
                    if !item.files.isEmpty || !item.name.isEmpty {
                        TCButton("ลบออกจากคลัง", systemImage: "trash", kind: .secondary, size: .card) { confirmDelete = true }
                    }
                }
                .padding(Space.l)
            }
            .background(Theme.background)
            .navigationTitle(item.name.isEmpty ? "เพิ่มในคลัง" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { added.forEach(store.deletePhoto); done(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { removed.forEach(store.deletePhoto); done(item) }.disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("ลบ \(item.name) ออกจากคลัง? งานที่ใช้อยู่จะต้องแนบไฟล์เอง", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("ลบ", role: .destructive) { delete() }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for p in items {
                    if let data = try? await p.loadTransferable(type: Data.self) { addFile(ImageUtil.compressed(data), ext: "jpg") }
                }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { addFile(data, ext: url.pathExtension) }
            }
        }
        .quickLookPreview($preview)
    }

    private func addFile(_ data: Data, ext: String) {
        let name = store.addFile(data, ext: ext)
        item.files.append(name)
        added.append(name)
    }

    private var filesCard: some View {
        PermitSection(title: "ไฟล์", subtitle: "เรียงตามลำดับที่จะอยู่ในไฟล์ PPIM") {
            ForEach(Array(item.files.enumerated()), id: \.element) { i, name in
                HStack {
                    Button { preview = store.url(name) } label: {
                        Label("ไฟล์ \(i + 1) · \(name.hasSuffix("pdf") ? "PDF" : "รูป")", systemImage: name.hasSuffix("pdf") ? "doc.richtext" : "photo")
                            .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) {
                        item.files.removeAll { $0 == name }
                        if added.contains(name) { store.deletePhoto(name); added.removeAll { $0 == name } } else { removed.append(name) }
                    } label: { Image(systemName: "trash").frame(width: touchMin, height: touchMin) }
                    .buttonStyle(.plain).foregroundStyle(Theme.dangerText)
                    .accessibilityLabel("ลบไฟล์ \(i + 1)")
                }
            }
            HStack(spacing: Space.s) {
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
}
