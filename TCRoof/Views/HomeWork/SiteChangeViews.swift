import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore
import SurveyUI

/// Photos for a change or a punch item: camera (when there is one) or the photo library, thumbnails with delete.
struct SitePhotoStrip: View {
    @Binding var photos: [String]
    let store: PermitStore
    var title = "รูป"

    @State private var picks: [PhotosPickerItem] = []
    @State private var camera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(photos, id: \.self) { thumb($0) }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        addButton("camera") { camera = true }.accessibilityLabel("ถ่ายรูป")
                    }
                    PhotosPicker(selection: $picks, maxSelectionCount: 6, matching: .images) {
                        addTile("photo.on.rectangle")
                    }
                    .accessibilityLabel("เลือกรูป")
                }
            }
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for i in items {
                    if let d = try? await i.loadTransferable(type: Data.self) { photos.append(store.addPhoto(ImageUtil.compressed(d))) }
                }
                picks = []
            }
        }
        .fullScreenCover(isPresented: $camera) {
            StampedCamera { data in photos.append(store.addPhoto(data)) }
        }
    }

    private func addTile(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
            .frame(width: 72, height: 72)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private func addButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { addTile(icon) }.buttonStyle(.plain)
    }

    private func thumb(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = store.photo(name).flatMap(UIImage.init(data:)) { Image(uiImage: img).resizable().scaledToFill() } else { Theme.disabledFill }
            }
            .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            Button { photos.removeAll { $0 == name }; store.deletePhoto(name) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.surface, Theme.dangerText)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .buttonStyle(.plain).offset(x: 10, y: -10).accessibilityLabel("ลบรูป")
        }
    }
}

// MARK: - Changes

/// ใบขอเปลี่ยนแปลงงาน: what differs on site, its photos and cost, and the engineer's decision. A change of size is
/// checked against what the sell request filed and moves the drawings to the next revision.
struct SiteChangesPage: View {
    let job: Job
    @Binding var home: HomeJob
    let store: PermitStore
    let export: (SiteDocRenderer.Doc, String) -> Void

    @State private var editing: String?
    @State private var approver = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PermitSection(title: "ใบขอเปลี่ยนแปลงงาน",
                          subtitle: "หน้างานไม่ตรงแบบ: เปิดใบก่อนลงมือ · รออนุมัติ \(home.site.pendingChanges.count) ใบ") {
                TCButton("เปิดใบขอเปลี่ยนแปลง", systemImage: "plus", kind: .primary, size: .card) {
                    let c = HomeChange(number: home.site.nextChangeNumber, title: "")
                    home.site.changes.append(c)
                    editing = c.id
                }
                if let m = message {
                    Text(m).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.pending)
                }
            }
            ForEach(home.site.changes.reversed()) { c in
                if editing == c.id { editor(c.id) } else { summary(c) }
            }
        }
    }

    private func binding(_ id: String) -> Binding<HomeChange> {
        Binding(get: { home.site.changes.first { $0.id == id } ?? HomeChange(id: id, number: 0, title: "") },
                set: { new in if let i = home.site.changes.firstIndex(where: { $0.id == id }) { home.site.changes[i] = new } })
    }

    private func summary(_ c: HomeChange) -> some View {
        Button { editing = c.id } label: {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.number). " + (c.title.isEmpty ? "ไม่มีหัวข้อ" : c.title)).font(.sarabun(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.navy).multilineTextAlignment(.leading)
                    Text(detail(c)).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s)
                TCStatusChip(c.status.title, kind: c.status == .approved ? .done : c.status == .pending ? .pending : .overdue)
            }
            .padding(Space.m).frame(minHeight: touchMin)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ c: HomeChange) -> String {
        var p = [PermitDate.long(c.raised)]
        if c.laborDelta != 0 { p.append("ค่าแรง " + BOQRenderer.money(c.laborDelta)) }
        if c.priceDelta != 0 { p.append("ราคาลูกค้า " + BOQRenderer.money(c.priceDelta)) }
        if c.changesSize { p.append("เปลี่ยนขนาดระบบ") }
        if !c.decidedBy.isEmpty { p.append("โดย " + c.decidedBy) }
        return p.joined(separator: " · ")
    }

    private func editor(_ id: String) -> some View {
        let c = binding(id)
        let pending = c.wrappedValue.status == .pending
        return PermitSection(title: "ใบขอเปลี่ยนแปลงที่ \(c.wrappedValue.number)", subtitle: c.wrappedValue.status.title) {
            PermitField("เปลี่ยนอะไร", text: c.title, required: true)
            PermitField("เหตุผล / สภาพหน้างาน", text: c.reason)
            PermitField("ผู้ขอ", text: c.raisedBy)
            SitePhotoStrip(photos: c.photos, store: store, title: "รูปหน้างาน")
            PermitRow {
                BOQNumberField(title: "ค่าแรงเพิ่ม/ลด (ผู้รับเหมา)", value: c.laborDelta, unit: "บาท")
                BOQNumberField(title: "ราคาเพิ่ม/ลด (ลูกค้า)", value: c.priceDelta, unit: "บาท")
            }
            sizeFields(c)
            let blockers = c.wrappedValue.blockers(for: home)
            if !blockers.isEmpty { PermitIssuesCard(issues: blockers) }
            if pending { decision(id, blocked: !blockers.isEmpty) }
            HStack(spacing: Space.s) {
                TCButton("PDF", systemImage: "square.and.arrow.up", kind: .secondary, size: .card) { export(doc(c.wrappedValue), "ใบขอเปลี่ยนแปลง \(c.wrappedValue.number)") }
                TCButton("ปิด", systemImage: "chevron.up", kind: .secondary, size: .card) { editing = nil }
                if pending {
                    TCButton("ลบ", systemImage: "trash", kind: .secondary, size: .card) {
                        c.wrappedValue.photos.forEach(store.deletePhoto)
                        home.site.changes.removeAll { $0.id == id }
                        editing = nil
                    }
                }
            }
        }
    }

    private func sizeFields(_ c: Binding<HomeChange>) -> some View {
        PermitRow {
            BOQNumberField(title: "แผงใหม่ (เว้นว่างถ้าไม่เปลี่ยน)", value: Binding(get: { c.wrappedValue.newPVKWp ?? 0 },
                                                                          set: { c.wrappedValue.newPVKWp = $0 > 0 ? $0 : nil }), unit: "kWp")
            BOQNumberField(title: "อินเวอร์เตอร์ใหม่", value: Binding(get: { c.wrappedValue.newInverterKW ?? 0 },
                                                                 set: { c.wrappedValue.newInverterKW = $0 > 0 ? $0 : nil }), unit: "kW")
        }
    }

    private func decision(_ id: String, blocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PermitField("ผู้อนุมัติ (วิศวกร / PM)", text: $approver)
            HStack(spacing: Space.s) {
                TCButton("อนุมัติ", systemImage: "checkmark", kind: .primary, size: .card) { approve(id) }
                    .disabled(blocked || approver.trimmingCharacters(in: .whitespaces).isEmpty)
                TCButton("ไม่อนุมัติ", systemImage: "xmark", kind: .secondary, size: .card) {
                    home.site.reject(id, by: approver)
                    editing = nil
                }
                .disabled(approver.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func approve(_ id: String) {
        var job = home
        var site = job.site
        let sized = site.changes.first { $0.id == id }?.changesSize ?? false
        let errors = site.approve(id, by: approver, job: &job)
        guard errors.isEmpty else { message = errors.joined(separator: " · "); return }
        job.site = site
        home = job
        message = sized ? "ขนาดระบบเปลี่ยนแล้ว: ร่าง BOQ ใหม่และออกชุดแบบ Rev.\(site.workOrder.revision) ก่อนลงมือ" : nil
        editing = nil
    }

    private func doc(_ c: HomeChange) -> SiteDocRenderer.Doc {
        var facts: [(String, String)] = [
            ("ผู้รับเหมา", home.site.workOrder.contractor), ("สถานที่", job.address), ("วันที่ขอ", PermitDate.long(c.raised)),
            ("ผู้ขอ", c.raisedBy), ("เรื่อง", c.title), ("เหตุผล", c.reason),
            ("ค่าแรงเพิ่ม/ลด", BOQRenderer.money(c.laborDelta) + " บาท"), ("ราคาลูกค้าเพิ่ม/ลด", BOQRenderer.money(c.priceDelta) + " บาท"),
        ]
        if let pv = c.newPVKWp { facts.append(("แผงใหม่", HomeBOQ.kw(pv) + " kWp")) }
        if let inv = c.newInverterKW { facts.append(("อินเวอร์เตอร์ใหม่", HomeBOQ.kw(inv) + " kW")) }
        facts.append(("ผลพิจารณา", c.status.title + (c.decidedBy.isEmpty ? "" : " โดย " + c.decidedBy)
                      + (c.decided.map { " " + PermitDate.long($0) } ?? "")))
        var d = SiteDocRenderer.Doc(title: "ใบขอเปลี่ยนแปลงงาน", number: "\(home.site.workOrder.number)-C\(c.number)", facts: facts)
        d.signatures = [("ผู้ขอ", nil), ("ผู้อนุมัติ", nil)]
        return d
    }
}

// MARK: - Punch list

/// Defects found at inspection: a before photo, where, by when; closed only with an after photo.
struct SitePunchPage: View {
    @Binding var home: HomeJob
    let store: PermitStore

    @State private var showClosed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PermitSection(title: "Punch list", subtitle: "เปิด \(home.site.openPunches.count) · ปิดแล้ว \(home.site.punches.count - home.site.openPunches.count)") {
                TCButton("เพิ่มจุดที่ต้องแก้", systemImage: "plus", kind: .primary, size: .card) {
                    var p = HomePunch(title: "")
                    p.due = Calendar(identifier: .gregorian).date(byAdding: .day, value: 3, to: .now)
                    home.site.punches.insert(p, at: 0)
                }
                if home.site.punches.contains(where: { !$0.isOpen }) {
                    TCSwitchRow("แสดงรายการที่ปิดแล้ว", isOn: $showClosed)
                }
            }
            ForEach(home.site.punches.filter { $0.isOpen || showClosed }) { item($0.id) }
        }
    }

    private func binding(_ id: String) -> Binding<HomePunch> {
        Binding(get: { home.site.punches.first { $0.id == id } ?? HomePunch(id: id, title: "") },
                set: { new in if let i = home.site.punches.firstIndex(where: { $0.id == id }) { home.site.punches[i] = new } })
    }

    private func item(_ id: String) -> some View {
        let p = binding(id)
        let v = p.wrappedValue
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                if v.isLate() { TCStatusChip("เลยกำหนด", kind: .overdue) }
                if !v.isOpen { TCStatusChip("ปิดแล้ว " + (v.closed.map(PermitDate.short) ?? ""), kind: .done) }
                Spacer()
            }
            PermitRow {
                PermitField("ต้องแก้อะไร", text: p.title, required: true)
                PermitField("ตำแหน่ง", text: p.location)
            }
            HomeDateRow(title: "กำหนดเสร็จ", date: p.due, caption: "ผู้รับเหมาแก้ให้เสร็จภายในวันนี้")
            SitePhotoStrip(photos: p.before, store: store, title: "รูปก่อนแก้")
            SitePhotoStrip(photos: p.after, store: store, title: "รูปหลังแก้ (ต้องมีก่อนปิด)")
            HStack(spacing: Space.s) {
                if v.isOpen {
                    TCButton("ปิดรายการ", systemImage: "checkmark", kind: .primary, size: .card) { p.wrappedValue.closed = .now }
                        .disabled(!v.canClose || v.title.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    TCButton("เปิดใหม่", systemImage: "arrow.uturn.backward", kind: .secondary, size: .card) { p.wrappedValue.closed = nil }
                }
                TCButton("ลบ", systemImage: "trash", kind: .secondary, size: .card) {
                    (v.before + v.after).forEach(store.deletePhoto)
                    home.site.punches.removeAll { $0.id == id }
                }
            }
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(v.isLate() ? Theme.danger : Theme.borderSubtle))
    }
}
