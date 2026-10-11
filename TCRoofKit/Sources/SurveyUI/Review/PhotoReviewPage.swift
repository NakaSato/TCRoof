#if canImport(UIKit)
import SwiftUI
import UIKit
import ImageIO
import TCRoofCore
import TCRoofUI

/// ตรวจรูปทั้งหมด (docs/specs/review-lock-revisions-swift.md §2.2–2.3): every photo slot of the job on one grid, grouped
/// like the Drive folders; a missing required photo is a red frame that opens the camera straight into its field.
struct PhotoReviewPage: View {
    enum Filter: String, CaseIterable { case all = "ทั้งหมด", missing = "ขาด", filled = "มีแล้ว" }

    @Binding var job: Job
    @Binding var filter: Filter
    let readOnly: Bool
    let width: CGFloat
    /// The page (and field) a slot belongs to: ไปที่ช่องในฟอร์ม, and a signature slot.
    var openField: (ReviewSlot) -> Void
    @Environment(SurveyModel.self) private var model
    @AppStorage("photoReview.columns") private var columns = 4.0
    @AppStorage("photoReview.requiredOnly") private var requiredOnly = false
    @State private var target: ReviewSlot?
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var viewing: ReviewSlot?
    @State private var lockedNote = false

    var body: some View {
        let groups = job.photoSlots
        let required = groups.flatMap(\.slots).filter(\.required)
        let filled = required.filter { $0.photo != nil }.count
        // never narrower than 100 pt a cell, so Split View keeps working from 320 pt
        let n = max(1, min(Int(columns), Int((width - 32) / 110)))
        let cell = max(100, (width - 32 - CGFloat(n - 1) * 10) / CGFloat(n) - 1)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar(filled: filled, total: required.count)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 10)], alignment: .leading, spacing: 12,
                          pinnedViews: .sectionHeaders) {
                    ForEach(groups) { g in
                        let slots = g.slots.filter(shows)
                        if !slots.isEmpty {
                            Section {
                                ForEach(slots) { s in cellView(s) }
                            } header: { header(g) }
                        }
                    }
                }
                if groups.allSatisfy({ $0.slots.filter(shows).isEmpty }) {
                    ContentUnavailableView(filter == .missing ? "รูปบังคับครบแล้ว" : "ยังไม่มีรูป", systemImage: filter == .missing ? "checkmark.circle" : "photo")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .photoSources(picker: $showPicker, camera: $showCamera) { img in
            guard let s = target, let p = model.addPhoto(img, to: job.id) else { return }
            job.setPhoto(p, slot: s)
            target = nil
        }
        .sheet(item: $viewing) { s in viewer(s) }
        .alert("ฟอร์มล็อกแล้ว · เปิด REV ใหม่เพื่อเพิ่มรูป", isPresented: $lockedNote) { Button("ตกลง", role: .cancel) {} }
    }

    func shows(_ s: ReviewSlot) -> Bool {
        switch filter {
        case .all: return true
        case .filled: return s.photo != nil
        case .missing: return s.photo == nil && (s.required || !requiredOnly) && s.kind != .leftover
        }
    }

    func topBar(filled: Int, total: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { progress(filled, total); Spacer(minLength: 8); filters; sizeSlider }
            VStack(alignment: .leading, spacing: 10) { progress(filled, total); filters; sizeSlider }
        }
    }

    func progress(_ filled: Int, _ total: Int) -> some View {
        HStack(spacing: 10) {
            Text("รูปบังคับ \(filled)/\(total)").font(.title3.bold()).foregroundStyle(Theme.navy).monospacedDigit()
                .accessibilityIdentifier("photoReview.progress")
            if total > filled { TCStatusChip("ขาด \(total - filled)", kind: .overdue) } else { TCStatusChip("ครบ", kind: .done) }
        }
    }

    var filters: some View {
        HStack(spacing: 10) {
            Picker("แสดง", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 240)
            if filter == .missing { Toggle("เฉพาะที่บังคับ", isOn: $requiredOnly).fixedSize() }
        }
    }

    var sizeSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3").foregroundStyle(Theme.inkMuted)
            Slider(value: $columns, in: 3...6, step: 1).frame(width: 120)
            Image(systemName: "square.grid.2x2").foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("จำนวนคอลัมน์ \(Int(columns))")
    }

    func header(_ g: ReviewSlotGroup) -> some View {
        HStack(spacing: 8) {
            Text(g.title).font(.headline).foregroundStyle(Theme.navy).lineLimit(1)
            if g.requiredCount > 0 {
                Text("· \(g.filledRequired)/\(g.requiredCount)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(g.missingRequired > 0 ? Theme.dangerText : Theme.okText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(Paper.page)
    }

    // MARK: cells

    func cellView(_ s: ReviewSlot) -> some View {
        Button { tap(s) } label: {
            VStack(alignment: .leading, spacing: 4) {
                frame(s).aspectRatio(4 / 3, contentMode: .fit)
                Text(s.label).font(.caption).foregroundStyle(Theme.navy).lineLimit(2, reservesSpace: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { actions(s) }
        .accessibilityLabel(s.label + (s.photo == nil ? (s.required ? " ยังขาด" : " ยังไม่มีรูป") : " มีรูปแล้ว"))
    }

    @ViewBuilder func frame(_ s: ReviewSlot) -> some View {
        if let p = s.photo {
            Color.clear
                .overlay { Thumbnail(photo: p, jobID: job.id) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.15)))
                .overlay(alignment: .topLeading) { if s.kind != .leftover { PhotoDoneBadge(inset: 4) } }
        } else {
            let red = s.required
            VStack(spacing: 6) {
                Image(systemName: s.kind == .signature ? "signature" : s.kind == .photosAdd ? "plus.viewfinder" : "camera")
                    .font(.system(size: 22, weight: .semibold))
                Text(s.kind == .signature ? "ไปลงนาม" : readOnly ? "ยังไม่มีรูป" : "แตะเพื่อถ่าย").font(.caption.weight(.semibold))
            }
            .foregroundStyle(red ? Theme.dangerText : Theme.inkMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(red ? Theme.dangerSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(red ? Theme.danger : Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
    }

    func tap(_ s: ReviewSlot) {
        if s.kind == .signature && s.photo == nil { return openField(s) }
        if s.photo != nil { viewing = s; return }
        if readOnly { lockedNote = true; return }
        capture(s, camera: true)
    }

    func capture(_ s: ReviewSlot, camera: Bool) {
        target = s
        #if DEBUG
        // `-surveyCameraStub YES` (UI tests; the simulator has no camera): a generated photo lands in the slot at once
        if UserDefaults.standard.bool(forKey: "surveyCameraStub") {
            let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { c in
                UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
            if let p = model.addPhoto(img, to: job.id) { job.setPhoto(p, slot: s) }
            target = nil
            return
        }
        #endif
        if camera && UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { showPicker = true }
    }

    @ViewBuilder func actions(_ s: ReviewSlot) -> some View {
        if s.photo != nil { Button { viewing = s } label: { Label("ดูภาพ", systemImage: "eye") } }
        if !readOnly && s.kind != .leftover && s.kind != .signature {
            Button { capture(s, camera: true) } label: { Label(s.photo == nil ? "ถ่ายภาพ" : "ถ่ายใหม่", systemImage: "camera") }
            Button { capture(s, camera: false) } label: { Label("เลือกจากคลังภาพ", systemImage: "photo.on.rectangle") }
            if s.photo != nil { Button(role: .destructive) { job.removePhoto(slot: s) } label: { Label("ลบ", systemImage: "trash") } }
        }
        if s.kind != .leftover { Button { openField(s) } label: { Label("ไปที่ช่องในฟอร์ม", systemImage: "arrow.right.doc.on.clipboard") } }
    }

    /// Full screen with ถ่ายใหม่ (in place), เลือกจากคลังภาพ, ลบ and ไปที่ช่องในฟอร์ม.
    func viewer(_ s: ReviewSlot) -> some View {
        NavigationStack {
            Group {
                if let p = s.photo, let img = model.image(p, in: job.id) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    PhotoSlot.notDownloaded
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            .navigationTitle(s.label).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("ปิด") { viewing = nil } }
                ToolbarItemGroup(placement: .bottomBar) {
                    if !readOnly && s.kind != .leftover && s.kind != .signature {
                        Button { after { capture(s, camera: true) } } label: { Label("ถ่ายใหม่", systemImage: "camera") }
                        Button { after { capture(s, camera: false) } } label: { Label("เลือกจากคลังภาพ", systemImage: "photo.on.rectangle") }
                        Button(role: .destructive) { viewing = nil; job.removePhoto(slot: s) } label: { Label("ลบ", systemImage: "trash") }
                    }
                    Spacer()
                    if s.kind != .leftover { Button { after { openField(s) } } label: { Label("ไปที่ช่องในฟอร์ม", systemImage: "arrow.right.doc.on.clipboard") } }
                }
            }
        }
    }

    /// Closes the viewer first: the camera and the page change can't run under a sheet.
    func after(_ go: @escaping () -> Void) {
        viewing = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: go)
    }
}

/// A 300 px thumbnail read straight from the file and cached per photo, so a grid of 100+ photos stays smooth.
struct Thumbnail: View {
    let photo: Photo
    let jobID: UUID
    @Environment(SurveyModel.self) private var model
    @State private var image: UIImage?
    static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { PhotoSlot.stageColor.overlay { Image(systemName: "photo").foregroundStyle(Theme.inkMuted) } }
        }
        .task(id: photo.id) {
            let key = "\(jobID.uuidString)/\(photo.fileName)" as NSString
            if let hit = Self.cache.object(forKey: key) { image = hit; return }
            let url = model.store.url(of: photo, in: jobID)
            let made = await Task.detached(priority: .userInitiated) { Self.thumbnail(url) }.value
            if let made { Self.cache.setObject(made, forKey: key) }
            image = made
        }
    }

    nonisolated static func thumbnail(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 300,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
#endif
