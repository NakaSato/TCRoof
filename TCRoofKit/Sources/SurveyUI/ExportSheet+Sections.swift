#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import DriveSync
import TCRoofUI


/// Sections of the sheet: readiness checks, file choice, Drive account and the action bar.
extension ExportSheet {
    func statusSection(_ job: Job) -> some View {
        Section {
            HStack(spacing: 14) {
                TCProgressRing(.percent(job.completion.fraction), size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName).font(.headline).lineLimit(2)
                    Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo) · กรอกแล้ว \(job.completion.filled)/\(job.completion.total) · รูป \(job.photoCount)")
                        .font(.subheadline).foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Photos taken on another iPad: download progress, or a button to fetch the ones already on Drive.
    func photoSection(_ gap: PhotoGap) -> some View {
        let fetch = model.photoFetch[jobID]
        return Section {
            if let f = fetch, f.running {
                ProgressView(value: Double(f.done + f.failed), total: Double(f.total)) {
                    Text("กำลังดาวน์โหลดรูปจาก Google Drive \(f.done)/\(f.total)").font(.callout)
                }
            } else {
                Label("มีรูป \(gap.missing) รูปที่ยังไม่อยู่ในเครื่องนี้", systemImage: "icloud.slash").font(.headline).foregroundStyle(Theme.pending)
                if gap.onDrive > 0 {
                    Button { fetchPhotos() } label: { Label("ดาวน์โหลด \(gap.onDrive) รูปจาก Google Drive", systemImage: "icloud.and.arrow.down") }
                        .disabled(busy != nil)
                }
                if let e = fetch?.error, fetch?.failed ?? 0 > 0 {
                    Text("ดาวน์โหลดไม่สำเร็จ \(fetch!.failed) รูป: \(e)").font(.caption).foregroundStyle(Theme.dangerText)
                }
            }
        } footer: {
            Text(gap.missing > gap.onDrive
                 ? "\(gap.missing - gap.onDrive) รูปยังไม่ได้บันทึกขึ้น Google Drive — ให้เครื่องที่ถ่ายส่งออก \"รูปภาพ\" ลง Drive ก่อน แล้วเปิดงานนี้อีกครั้ง"
                 : "รูปถ่ายจากเครื่องอื่น ถ้าส่งออกตอนนี้รายงานจะไม่มีรูปเหล่านี้")
        }
    }

    /// A PDF is selected but the report isn't signed by both sides yet.
    func signatureSection(_ names: [String]) -> some View {
        Section {
            Label("PDF ยังไม่มีลายเซ็น", systemImage: "signature").font(.headline).foregroundStyle(Theme.dangerText)
            ForEach(names, id: \.self) { Text("• " + $0).font(.callout) }
            Button { dismiss(); goTo(.final) } label: { Label("ไปลงนามที่หน้า E1", systemImage: "arrow.right.circle") }
                .font(.callout)
        } footer: {
            Text("ส่งออกเป็นฉบับร่างได้ แต่ PDF ที่ส่ง กปภ. ต้องมีลายเซ็นทั้งวิศวกรผู้สำรวจและผู้ประสานงาน")
        }
    }

    /// Every required answer still missing, grouped by editor page; each group opens its page.
    func missingSection(_ groups: [MissingGroup]) -> some View {
        let count = groups.reduce(0) { $0 + $1.items.count }
        return Section {
            Label("ยังขาด \(count) รายการ", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Theme.pending)
            ForEach(groups) { g in
                DisclosureGroup {
                    ForEach(Array(g.items.enumerated()), id: \.offset) { Text("• " + $0.element).font(.callout) }
                    Button { dismiss(); goTo(g.target) } label: { Label("ไปกรอกหัวข้อนี้", systemImage: "arrow.right.circle") }
                        .font(.callout)
                } label: {
                    HStack {
                        Text(g.title).font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(g.items.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.pending)
                    }
                }
            }
        } footer: {
            Text("ส่งออกต่อได้ แต่รายงานจะขาดข้อมูลเหล่านี้")
        }
    }

    var formatsSection: some View {
        Section {
            ForEach(Format.allCases) { f in formatRow(f) }
        } header: { Text("ไฟล์ที่จะส่งออก") } footer: {
            let notes = [selected.contains(.summary) ? "PDF สรุป 1 หน้า แชร์ได้อย่างเดียว ไม่บันทึกลง Google Drive" : nil,
                         selected.contains(.photos) ? "รูปภาพบันทึกลง Google Drive เท่านั้น" : nil].compactMap { $0 }
            if !notes.isEmpty { Text(notes.joined(separator: "\n")) }
        }
    }

    func formatRow(_ f: Format) -> some View {
        let on = selected.contains(f)
        return HStack(spacing: 12) {
            Image(systemName: f.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 36, height: 36).background(f.tint, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.body.weight(.semibold))
                Text(f == .photos ? photoDetail : f.detail).font(.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            if f.isPDF {
                Button { previewPDF(f) } label: { Image(systemName: "eye").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(Theme.primary).disabled(busy != nil).accessibilityLabel("ดูตัวอย่าง " + f.title)
            }
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(on ? Paper.tick : Theme.borderControl)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if busy == nil { toggle(f) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// "46 รูป · รูปใหม่ 12 รูป" — how much the next Drive save will send.
    var photoDetail: String {
        guard let job = model.job(jobID) else { return Format.photos.detail }
        let all = job.allPhotos.count
        guard all > 0 else { return "ยังไม่มีรูปในงานนี้" }
        let sent = Set((job.drive?.photoFiles ?? [:]).keys)
        let new = job.driveFolders.flatMap(\.photos).filter { !sent.contains($0.photo.id.uuidString) }.count
        if sent.isEmpty { return "\(all) รูป · แยกโฟลเดอร์ตามหัวข้อใน Drive" }
        return "\(all) รูป · " + (new == 0 ? "อยู่ใน Drive ครบแล้ว" : "รูปใหม่ \(new) รูป")
    }

    func driveSection(_ job: Job) -> some View {
        Section("Google Drive") {
            if signedIn {
                LabeledContent("บัญชี", value: model.google.email ?? "ลงชื่อเข้าใช้แล้ว")
            } else {
                Button { signIn() } label: { Label("ลงชื่อเข้าใช้ Google", systemImage: "person.crop.circle.badge.plus") }
                    .disabled(busy != nil)
            }
            LabeledContent("โฟลเดอร์", value: "\(model.settings.driveRoot) / \(DriveSync.folderName(job))")
            if let t = job.drive?.lastSaved { LabeledContent("บันทึกล่าสุด", value: t.formatted(date: .abbreviated, time: .shortened)) }
            if let url = job.drive?.folderURL, let u = URL(string: url) { Link("เปิดโฟลเดอร์ใน Google Drive", destination: u) }
            if let id = job.drive?.photosFolderID, let u = URL(string: "https://drive.google.com/drive/folders/\(id)") { Link("เปิดโฟลเดอร์รูปภาพ", destination: u) }
        }
    }

    var actionBar: some View {
        VStack(spacing: 8) {
            if let busy {
                HStack(spacing: 8) { ProgressView(); Text(busy).font(.callout).foregroundStyle(Theme.inkMuted) }
            }
            HStack(spacing: 12) {
                Button { share() } label: {
                    Label("แชร์ไฟล์", systemImage: "square.and.arrow.up").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card)).disabled(!canShare)
                Button { saveToDrive() } label: {
                    Label("Google Drive", systemImage: "icloud.and.arrow.up").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).disabled(!canDrive)
            }
            .controlSize(.large)
            .disabled(busy != nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}
#endif
