#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

extension RoofPageWide {
    // MARK: member sizes 1–7

    var membersCard: some View {
        card {
            cardTitle("ขนาดชิ้นส่วน 1–7", trailing: Roof.memberNote(values))
            VStack(spacing: 0) {
                ForEach(1...7, id: \.self) { n in
                    memberRow(n)
                    if n < 7 { Self.line.frame(height: 1) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    func memberRow(_ n: Int) -> some View {
        let f = Roof.frame(values), m = f.members[n - 1], size = Roof.memberSize(values, n)
        let spacing = StructureSizes.split(Roof.member(values, n)).spacing
        let off = Roof.memberOffList(values, n)
        return Button { member = member == n ? nil : n } label: {
            HStack(spacing: 10) {
                Text("\(n)").font(.sarabunFixed(17, .bold)).foregroundStyle(Self.red).frame(width: 14)
                Image("c1-member-\(f.iconFamily)-\(n)", bundle: .module).resizable().scaledToFit().frame(width: 60, height: 32)
                Text(m.name).font(.sarabunFixed(16)).lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail)
                Spacer(minLength: 6)
                if off { Circle().fill(Theme.warning).frame(width: 8, height: 8).accessibilityLabel("ขนาดนี้ไม่อยู่ในรายการของชนิดโครงนี้") }
                if !size.isEmpty {
                    Image("c1-profile-\(Roof.profile(size))", bundle: .module).resizable().scaledToFit().frame(width: 20, height: 20)
                }
                Text(size.isEmpty ? "เลือกขนาด" : size + (spacing.isEmpty ? "" : " " + spacing))
                    .font(.sarabunFixed(16, !size.isEmpty && size != "-" && size != m.defaultSize ? .bold : .regular))
                    .foregroundStyle(size.isEmpty ? Theme.primary : size == "-" ? Theme.disabledText : Theme.navy)
                    .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.middle)
                    .layoutPriority(1)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8)).foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(member == n ? Self.soft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เลือกขนาด \(n) \(m.name) " + (size.isEmpty ? "ยังไม่เลือก" : size))
        .popover(isPresented: Binding(get: { member == n }, set: { if !$0 { member = nil } }), arrowEdge: n <= 4 ? .top : .bottom) {
            memberPicker(n).presentationCompactAdaptation(.popover)
        }
    }

    func memberPicker(_ n: Int) -> some View {
        let m = Roof.frame(values).members[n - 1], cur = Roof.memberSize(values, n)
        let spacing = StructureSizes.split(Roof.member(values, n)).spacing
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(n) \(m.name) · เลือกขนาด").font(.sarabunFixed(16, .bold))
                Spacer()
                Button { member = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            .padding(.leading, 14)
            ForEach(m.sizes + (m.sizes.contains(cur) || cur.isEmpty ? [] : [cur]), id: \.self) { s in
                let on = s == cur
                Button { update { Roof.setMember(&$0, n, size: s) }; member = nil } label: {
                    HStack(spacing: 10) {
                        Image("c1-profile-\(Roof.profile(s))", bundle: .module).resizable().scaledToFit().frame(width: 18, height: 18)
                        Text(s == "-" ? "-  (ไม่มี / ไม่ใช้)" : s).font(.sarabunFixed(15, on ? .bold : .regular))
                        if s == m.defaultSize && s != "-" { Text("มาตรฐาน").font(.sarabunFixed(11, .semibold)).foregroundStyle(Theme.success) }
                        Spacer()
                        if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(on ? Self.soft : Theme.surface).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 8) {
                Menu {
                    ForEach(StructureSizes.sections, id: \.group) { g in
                        Menu(g.group) {
                            ForEach(g.items, id: \.self) { s in Button(s) { update { Roof.setMember(&$0, n, size: s) }; member = nil } }
                        }
                    }
                    Button("พิมพ์เอง…") { memberText = cur == "-" ? "" : cur; member = nil; typingMember = n }
                } label: {
                    Text("ขนาดอื่น ›").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
                }
                Spacer()
                Menu {
                    Button("ไม่ระบุ") { update { Roof.setSpacing(&$0, n, spacing: "") } }
                    ForEach(StructureSizes.spacings, id: \.self) { s in Button(s) { update { Roof.setSpacing(&$0, n, spacing: s) } } }
                } label: {
                    Text("ระยะห่าง " + (spacing.isEmpty ? "-" : spacing) + " ▾").font(.sarabunFixed(14, .bold))
                        .foregroundStyle(cur.isEmpty || cur == "-" ? Theme.disabledText : Theme.primary).frame(minHeight: 44)
                }
                .disabled(cur.isEmpty || cur == "-")
            }
            .padding(.horizontal, 14)
        }
        .foregroundStyle(Theme.navy)
        .frame(width: 340)
        .padding(.vertical, 6)
    }

    // MARK: photos

    var photosCard: some View {
        let missing = Roof.missingShots(values).count, extra = Roof.extraStructPhotos(values)
        return VStack(alignment: .leading, spacing: 8) {
            cardTitle("ภาพหลังคา", trailing: missing == 0 ? "ครบ 6 มุมที่แนะนำ ✓" : "\(6 - missing)/6 มุม · ต้องถ่ายครบทุกมุม",
                      trailingColor: missing == 0 ? Theme.success : Self.red, bold: missing > 0)
            // 6 in a row when the column has room, else 3 × 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cardsWidth >= 440 ? 6 : 3), spacing: 6) {
                ForEach(Roof.Shot.allCases, id: \.rawValue) { s in
                    RoofShotTile(photo: Binding(get: { Roof.photo(values, s) }, set: { p in update { Roof.setPhoto(&$0, s, p) } }),
                                 jobID: job.id, name: s.name, extra: s == .joint ? extra : 0)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.warning, lineWidth: flashShot == s ? 3 : 0).allowsHitTesting(false))
                        .animation(.easeInOut(duration: 0.3).repeatCount(3), value: flashShot)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }
}
/// One photo angle: a flexible tile at least 44 pt tall. Empty, the whole tile is a menu (อัปโหลด / กล้อง); filled, it is
/// the shared `PhotoSlot` (viewer, done badge, clear button).
struct RoofShotTile: View {
    @Binding var photo: Photo?
    let jobID: UUID
    let name: String
    var extra = 0
    @Environment(SurveyModel.self) private var model
    @State private var picker = false
    @State private var camera = false

    var body: some View {
        Group {
            if photo != nil {
                PhotoSlot(photo: photo, jobID: jobID, hint: name, required: true, title: name, dense: true,
                          onPick: pick, onClear: { photo = nil })
                    .overlay(alignment: .bottomLeading) {
                        Text(name).font(.sarabunFixed(10, .bold)).foregroundStyle(Theme.onMedia).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .padding(3).allowsHitTesting(false)
                    }
            } else {
                Menu {
                    Button { camera = true } label: { Label("กล้อง", systemImage: "camera") }
                    Button { picker = true } label: { Label("อัปโหลด", systemImage: "photo") }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                        Text(name).font(.sarabunFixed(11)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.danger, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("ถ่ายหรืออัปโหลดภาพ " + name)
                .photoSources(picker: $picker, camera: $camera, onPick: pick)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        .overlay(alignment: .topTrailing) {
            if extra > 0 {
                Text("+\(extra)").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.onMedia)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.navySolid.opacity(0.75), in: Capsule())
                    .padding(4).allowsHitTesting(false)
                    .accessibilityLabel("ภาพโครงสร้างเดิมอีก \(extra) ภาพ")
            }
        }
    }

    func pick(_ img: UIImage) { if let p = model.addPhoto(img, to: jobID) { photo = p } }
}
#endif
