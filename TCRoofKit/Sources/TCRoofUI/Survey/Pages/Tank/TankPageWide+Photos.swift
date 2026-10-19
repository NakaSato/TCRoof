#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 4 "ภาพถ่าย" on iPad (docs/ui/survey-d1-photo-ipad, regular width): the photo gallery on the left (a ring
/// of the required photos, the filter, three columns of tiles, the add-obstacle bar) and the inspector of the selected
/// tile on the right (the photo, วิธีถ่าย, the shot point, the note, retake / delete, the next missing photo). The tiles
/// are `TankPhotos` over the group's fields; photos go through the same pipeline as the form (`SurveyModel.addPhoto`).
/// iPhone and the stacked layout keep `formStep`.
extension TankPageWide {
    /// Where the next photo from the camera or the library goes.
    enum PhotoTarget: Equatable { case tile(String, wall: Int?), newObstacle }

    var photoTiles: [TankPhotos.Tile] { TankPhotos.tiles(values) }
    var selectedPhotoTile: TankPhotos.Tile? {
        let all = photoTiles
        return all.first { $0.id == photoSel } ?? all.first
    }

    @ViewBuilder var padPhotoStep: some View {
        HStack(alignment: .top, spacing: 16) {
            photoGallery.frame(maxWidth: .infinity, maxHeight: .infinity)
            photoInspector.frame(width: 430).frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .photoSources(picker: $photoPicker, camera: $photoCamera) { img in storePhoto(img) }
    }

    // MARK: gallery

    var photoGallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            photoHeader
            photoGrid
            if values.photos("obstPhotos").count < TankPhotos.obstacleMax { addObstacleBar }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }

    var photoHeader: some View {
        HStack(spacing: 14) {
            photoRing
            VStack(alignment: .leading, spacing: 0) {
                Text("ภาพที่ต้องถ่าย").font(.sarabunFixed(17, .bold))
                Text(TankPhotos.summary(values)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            photoFilterSegment
        }
    }

    /// The required photos taken, as a ring (`Tank.photoCompletion`).
    var photoRing: some View {
        let c = Tank.photoCompletion(values), share = c.total > 0 ? Double(c.filled) / Double(c.total) : 1
        let done = c.filled >= c.total
        return ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 6)
            Circle().trim(from: 0, to: share).stroke(done ? Theme.success : Theme.primary, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text("\(c.filled)/\(c.total)").font(.sarabunFixed(13, .bold)).monospacedDigit()
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ภาพบังคับ \(c.filled) จาก \(c.total)")
    }

    var photoFilterSegment: some View {
        let all = photoTiles, done = all.filter { TankPhotos.taken(values, $0) }.count
        let items: [(TankPhotos.Filter, String)] = [(.all, "ทั้งหมด \(all.count)"), (.missing, "ยังขาด \(all.count - done)"), (.done, "ถ่ายแล้ว \(done)")]
        return HStack(spacing: 3) {
            ForEach(items, id: \.0) { f, title in
                let on = photoFilter == f
                Button { photoFilter = f } label: {
                    Text(title).font(.sarabunFixed(13, on ? .bold : .semibold)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .background { if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) } }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Three columns; the rows stretch to fill the card (at least 150 pt) and scroll past that.
    var photoGrid: some View {
        let tiles = TankPhotos.filtered(values, photoFilter)
        return GeometryReader { g in
            let rows = max(1, (tiles.count + 2) / 3)
            let rowH = max(150, (g.size.height - CGFloat(rows - 1) * 10) / CGFloat(rows))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(tiles) { t in photoTile(t).frame(height: rowH) }
                }
            }
            .scrollIndicators(.hidden)
            .overlay {
                if tiles.isEmpty {
                    Text(photoFilter == .missing ? "ถ่ายครบทุกภาพแล้ว" : "ยังไม่มีภาพที่ถ่าย").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    func photoTile(_ t: TankPhotos.Tile) -> some View {
        let p = TankPhotos.photo(values, t), on = selectedPhotoTile?.id == t.id
        return Button { photoSel = t.id; photoWall = 0 } label: {
            VStack(spacing: 0) {
                photoFace(t, p).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.name).font(.sarabunFixed(14, .bold)).lineLimit(1)
                    Text(t.subtitle).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 8)
                .background(Theme.surface)
            }
            .overlay(alignment: .topLeading) { photoPill(t, taken: p != nil, compact: true).padding(8) }
            .overlay(alignment: .topTrailing) {
                if t.id == "walls", p != nil {
                    Text("\(TankPhotos.walls(values).count)/\(TankPhotos.walls.count)").font(.sarabunFixed(11.5, .bold)).foregroundStyle(Theme.onMedia)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.navy.opacity(0.75), in: Capsule()).padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(photoBorder(t, taken: p != nil, on: on))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t.name) · " + (p != nil ? "ถ่ายแล้ว" : t.required ? "บังคับ" : "ไม่บังคับ"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The photo, aspect-fill, or the empty face: a red tint for a required photo, blue for an optional one.
    @ViewBuilder func photoFace(_ t: TankPhotos.Tile, _ p: Photo?) -> some View {
        if let p, let img = model.image(p, in: job.id) {
            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
        } else if p != nil {
            ZStack { Theme.hairline; Image(systemName: "icloud.and.arrow.down").foregroundStyle(Theme.inkMuted) }
        } else {
            let ink = t.required ? Theme.dangerText : Theme.primary
            ZStack {
                (t.required ? Theme.danger.opacity(0.04) : Theme.primarySoft.opacity(0.35))
                VStack(spacing: 6) {
                    Image(systemName: "camera").font(.system(size: 24, weight: .medium))
                    Text("แตะเพื่อถ่าย").font(.sarabunFixed(12.5, .bold))
                }
                .foregroundStyle(ink)
            }
        }
    }

    /// `✓ ถ่ายแล้ว` / `บังคับ` / `ไม่บังคับ`.
    func photoPill(_ t: TankPhotos.Tile, taken: Bool, compact: Bool) -> some View {
        let text = taken ? "✓ ถ่ายแล้ว" : t.required ? "บังคับ" : "ไม่บังคับ"
        let fg = taken ? (compact ? Theme.onMedia : Theme.okText) : t.required ? Theme.dangerText : Theme.inkMuted
        let bg = taken ? (compact ? Theme.success.opacity(0.92) : Theme.okSoft) : t.required ? Theme.dangerSoft : Theme.hairline
        return Text(text).font(.sarabunFixed(compact ? 11.5 : 12.5, .bold)).foregroundStyle(fg)
            .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 2 : 3)
            .background(bg, in: Capsule())
    }

    func photoBorder(_ t: TankPhotos.Tile, taken: Bool, on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return ZStack {
            if on {
                shape.stroke(Theme.primary.opacity(0.18), lineWidth: 6)
                shape.stroke(Theme.primary, lineWidth: 2)
            } else if taken {
                shape.stroke(Theme.borderSubtle, lineWidth: 1)
            } else {
                shape.stroke(t.required ? Theme.danger.opacity(0.6) : Theme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
    }

    var addObstacleBar: some View {
        Button { capture(.newObstacle, camera: true) } label: {
            HStack(spacing: 8) {
                Text("+").font(.sarabunFixed(20, .bold))
                Text("เพิ่มภาพสิ่งกีดขวาง").font(.sarabunFixed(14, .bold))
                Text("V1–V10 · บันได · ช่องลงถัง").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.primarySoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    // MARK: inspector

    @ViewBuilder var photoInspector: some View {
        if let t = selectedPhotoTile {
            let p = inspectedPhoto(t)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(t.id == "walls" ? "ผนังถัง · " + TankPhotos.walls[photoWall] : t.name).font(.sarabunFixed(17, .bold)).lineLimit(1)
                    Spacer(minLength: 6)
                    photoPill(t, taken: TankPhotos.taken(values, t), compact: false)
                }
                inspectorPhoto(t, p).frame(maxHeight: .infinity)
                if t.id == "walls" { wallStrip }
                inspectorTipRow(t)
                if p != nil { inspectorEdits(t) }
                inspectorButtons(t, p)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
        }
    }

    /// The photo shown: the selected wall's for the walls tile.
    func inspectedPhoto(_ t: TankPhotos.Tile) -> Photo? {
        t.id == "walls" ? TankPhotos.walls(values)[safe: photoWall] : TankPhotos.photo(values, t)
    }

    @ViewBuilder func inspectorPhoto(_ t: TankPhotos.Tile, _ p: Photo?) -> some View {
        if let p, let img = model.image(p, in: job.id) {
            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                .frame(minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    Text(photoMeta(p)).font(.sarabunFixed(12.5)).foregroundStyle(Theme.onMedia)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.navy.opacity(0.75), in: RoundedRectangle(cornerRadius: 6)).padding(10)
                }
                .accessibilityLabel("ภาพ \(t.name)")
        } else {
            VStack(spacing: 12) {
                Text(p == nil ? "ยังไม่มีภาพ" : "ภาพยังไม่ได้ดาวน์โหลด").font(.sarabunFixed(15, .bold))
                HStack(spacing: 10) {
                    Button { capture(.tile(t.id, wall: wallSlot(t)), camera: true) } label: {
                        Label("กล้อง", systemImage: "camera").font(.sarabunFixed(15, .bold)).frame(width: 130, height: 48)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    Button { capture(.tile(t.id, wall: wallSlot(t)), camera: false) } label: {
                        Label("อัปโหลด", systemImage: "photo").font(.sarabunFixed(15, .bold)).frame(width: 130, height: 48)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 240)
            .background((t.required ? Theme.danger.opacity(0.03) : Theme.primarySoft.opacity(0.35)), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.required ? Theme.danger.opacity(0.7) : Theme.primary.opacity(0.6),
                                                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        }
    }

    /// The wall slot a new photo of the walls tile goes into: the selected one, or the next free one.
    func wallSlot(_ t: TankPhotos.Tile) -> Int? {
        t.id == "walls" ? min(photoWall, TankPhotos.walls(values).count) : nil
    }

    /// The four walls in order: a tap selects one (an empty one is filled next).
    var wallStrip: some View {
        let list = TankPhotos.walls(values)
        return HStack(spacing: 8) {
            ForEach(Array(TankPhotos.walls.enumerated()), id: \.offset) { i, name in
                let p = list[safe: i], on = photoWall == i, open = i <= list.count
                Button { photoWall = min(i, list.count) } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            if let p, let img = model.image(p, in: job.id) {
                                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                            } else {
                                Theme.hairline
                                Image(systemName: "plus").foregroundStyle(open ? Theme.primary : Theme.disabledText)
                            }
                        }
                        .frame(height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                        Text(name).font(.sarabunFixed(11.5, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!open)
                .accessibilityLabel("ผนัง\(name)" + (p == nil ? " ยังไม่มีภาพ" : ""))
            }
        }
    }

    /// วิธีถ่าย and the shot point (hidden without a position).
    func inspectorTipRow(_ t: TankPhotos.Tile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("วิธีถ่าย").font(.sarabunFixed(13, .bold))
                Text(t.tip).font(.sarabunFixed(13)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                Text(t.subtitle).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let plan = TankPhotos.shotPlan(values, site: job.values.text("gps"), selected: t.id) {
                VStack(spacing: 2) {
                    HStack { Text("จุดถ่าย").font(.sarabunFixed(11.5, .bold)); Spacer(); Text("GPS").font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted) }
                    GeometryReader { g in SketchCanvas(ops: plan.ops, fit: SketchFit(plan.width, plan.height, in: g.size)) }
                        .frame(width: 128, height: 128)
                        .accessibilityLabel("จุดถ่ายภาพรอบถัง")
                }
                .frame(width: 128)
            }
        }
    }

    /// The note, and the opening an obstacle photo shows (shared with `ภาพที่เลือก`).
    @ViewBuilder func inspectorEdits(_ t: TankPhotos.Tile) -> some View {
        let p = inspectedPhoto(t)
        PhotoNoteField(note: p?.note) { n in update { TankPhotos.edit(&$0, t, wall: wallSlot(t)) { $0.note = n } } }
            .id("note-\(t.id)-\(photoWall)")
        if t.field == "obstPhotos" {
            PhotoTagPicker(tag: p?.tag, context: photoDetails("obstPhotos")) { tag in
                update { TankPhotos.edit(&$0, t) { $0.tag = tag } }
            }
        }
    }

    func inspectorButtons(_ t: TankPhotos.Tile, _ p: Photo?) -> some View {
        let next = TankPhotos.nextMissing(values, after: t.id)
        // the board's "all done" would be wrong while this very photo is the last one missing
        let lastHere = next == nil && t.required && p == nil
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { capture(.tile(t.id, wall: wallSlot(t)), camera: true) } label: {
                    Text("ถ่ายใหม่").font(.sarabunFixed(14, .bold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                Button { deletePhoto(t) } label: {
                    Text("ลบภาพ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.dangerText).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            .disabled(p == nil)
            .opacity(p == nil ? 0.4 : 1)
            Button {
                if let next { photoFilter = .all; photoSel = next.id; photoWall = 0 }
            } label: {
                Text(next != nil ? "ภาพที่ยังขาดถัดไป ›" : lastHere ? "เหลือภาพบังคับภาพนี้ภาพเดียว" : "✓ ครบทุกภาพบังคับ")
                    .font(.sarabunFixed(15, .bold)).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card))
            .disabled(next == nil)
        }
    }

    /// `29/9/2569 10:42 · 13.7512, 100.5014`
    func photoMeta(_ p: Photo) -> String {
        let c = Calendar(identifier: .buddhist).dateComponents([.day, .month, .year, .hour, .minute], from: p.takenAt)
        let when = String(format: "%d/%d/%d %02d:%02d", c.day ?? 0, c.month ?? 0, c.year ?? 0, c.hour ?? 0, c.minute ?? 0)
        guard let lat = p.lat, let lon = p.lon else { return when }
        return when + String(format: " · %.4f, %.4f", lat, lon)
    }

    // MARK: taking photos (the form's pipeline)

    func capture(_ target: PhotoTarget, camera: Bool) {
        photoTarget = target
        #if DEBUG
        // `-surveyCameraStub YES` (UI tests; the simulator has no camera): a generated photo lands at once
        if UserDefaults.standard.bool(forKey: "surveyCameraStub") {
            let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { c in
                UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
            storePhoto(img)
            return
        }
        #endif
        if camera && UIImagePickerController.isSourceTypeAvailable(.camera) { photoCamera = true } else { photoPicker = true }
    }

    func storePhoto(_ img: UIImage) {
        guard let target = photoTarget, let p = model.addPhoto(img, to: job.id) else { return }
        photoTarget = nil
        switch target {
        case .newObstacle:
            var added = false
            update { added = TankPhotos.addObstacle(&$0, p) }
            if added { photoFilter = .all; photoSel = "obst.\(values.photos("obstPhotos").count - 1)" }
        case let .tile(id, wall):
            guard let t = photoTiles.first(where: { $0.id == id }) else { return }
            update { TankPhotos.set(&$0, t, p, wall: wall) }
            if let wall { photoWall = min(wall, TankPhotos.walls.count - 1) }
        }
    }

    func deletePhoto(_ t: TankPhotos.Tile) {
        update { TankPhotos.set(&$0, t, nil, wall: wallSlot(t)) }
        if t.field == "obstPhotos" { photoSel = nil }
        photoWall = max(0, min(photoWall, TankPhotos.walls(values).count - 1))
    }
}
#endif
