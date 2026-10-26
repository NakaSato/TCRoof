#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// E1's right column: the two signature cards and the reviewer.
extension FinalPageWide {
    static let surveyorRole = "วิศวกรผู้สำรวจ"
    static let customerRole = "ผู้ประสานงาน / เจ้าของสถานที่"
    static let canvasFill = Theme.paper
    static let fieldFill = Theme.background
    static let chipRed = Theme.dangerText

    /// "29/9/2569": day/month/Buddhist year.
    static func thaiDate(_ d: Date) -> String {
        let c = Calendar(identifier: .buddhist).dateComponents([.day, .month, .year], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)/\(c.year ?? 0)"
    }

    var right: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("ลงนาม").font(.sarabunFixed(17, .bold))
                Spacer(minLength: 8)
                Text("เซ็นด้วย Apple Pencil หรือนิ้ว").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            surveyorCard.frame(maxHeight: .infinity)
            customerCard.frame(maxHeight: .infinity)
            reviewerRow
        }
    }

    var surveyorCard: some View {
        let name = v.text("engineer").trimmingCharacters(in: .whitespaces)
        return signatureCard(title: Self.surveyorRole, field: "surveyorSign", role: Self.surveyorRole, emptyTint: Theme.inkMuted,
                             signing: $signingSurveyor, who: Self.surveyorRole + (name.isEmpty ? "" : " | " + name)) {
            Text("( \(name.isEmpty ? "ยังไม่ระบุชื่อใน A1" : name) )").font(.sarabunFixed(15, .semibold))
                .foregroundStyle(name.isEmpty ? Theme.inkMuted : Theme.navy).lineLimit(1)
                .frame(minHeight: 36).allowsHitTesting(false)
        }
    }

    var customerCard: some View {
        let name = v.text("customerName").trimmingCharacters(in: .whitespaces)
        return signatureCard(title: Self.customerRole, field: "customerSign", role: Self.customerRole, emptyTint: Theme.danger,
                             signing: $signingCustomer, who: Self.customerRole + (name.isEmpty ? "" : " | " + name)) {
            HStack(spacing: 4) {
                Text("(")
                TextField("ชื่อผู้ประสานงาน", text: Binding(get: { v.text("customerName") },
                                                           set: { set("customerName", $0.isEmpty ? nil : .text($0)) }))
                    .fixedSize().multilineTextAlignment(.center)
                    .accessibilityLabel("ชื่อผู้ประสานงาน / เจ้าของสถานที่")
                Text(")")
            }
            .font(.sarabunFixed(15, .semibold))
            .frame(minWidth: 220, minHeight: 36)
            .overlay(alignment: .bottom) {
                Line().stroke(Theme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(height: 1.5)
            }
        }
    }

    func signatureCard<Name: View>(title: String, field: String, role: String, emptyTint: Color, signing: Binding<Bool>, who: String,
                                   @ViewBuilder name: () -> Name) -> some View {
        let photo = v.photo(field)
        return VStack(spacing: 0) {
            Group {
                if narrow {
                    // iPhone: the role on its own line, the status and เซ็นใหม่ under it
                    VStack(alignment: .leading, spacing: 0) {
                        signatureTitle(title).padding(.top, 8)
                        HStack(spacing: 10) { signatureStatus(field: field, title: title) }
                    }
                } else {
                    HStack(spacing: 10) {
                        signatureTitle(title)
                        signatureStatus(field: field, title: title)
                    }
                }
            }
            .padding(.leading, 18).padding(.trailing, 10)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Self.hairline).frame(height: 1) }
            signatureBody(photo: photo, role: role, emptyTint: emptyTint, signing: signing, name: name)
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
        .shadow(color: Theme.navy.opacity(0.08), radius: 2, y: 1)
        .signaturePad(isPresented: signing, who: who, mine: field == "surveyorSign") { img in
            if let img, let p = model.addPhoto(img, to: job.id, maxSide: 900, png: true) { set(field, .photo(p)) }
        }
    }

    func signatureTitle(_ title: String) -> some View {
        (Text(title + " ") + Text("*").foregroundColor(Theme.danger)).font(.sarabunFixed(16, .bold)).lineLimit(1)
    }

    @ViewBuilder func signatureStatus(field: String, title: String) -> some View {
        let signed = v.photo(field) != nil
        Text(signed ? "✓ ลงนามแล้ว" : "รอลงนาม").font(.sarabunFixed(12.5, .bold))
            .foregroundStyle(signed ? Self.okText : Self.chipRed)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background((signed ? Theme.success.opacity(0.14) : Theme.danger.opacity(0.12)), in: Capsule())
            .fixedSize()
        Spacer(minLength: 0)
        if signed {
            Button { set(field, nil) } label: {
                HStack(spacing: 6) {
                    A2Icon(name: "e1-resign", fallback: "arrow.counterclockwise", size: 16)
                    Text("เซ็นใหม่").font(.sarabunFixed(14, .semibold))
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เซ็นใหม่ " + title)
        }
    }

    func signatureBody<Name: View>(photo: Photo?, role: String, emptyTint: Color, signing: Binding<Bool>, @ViewBuilder name: () -> Name) -> some View {
        let image = photo.flatMap { model.image($0, in: job.id) }
        let label = name()
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, base = h * 0.7
            ZStack(alignment: .topLeading) {
                DotGrid().fill(Theme.navy.opacity(0.07))
                    .background(Self.canvasFill)
                    .contentShape(Rectangle())
                    .onTapGesture { if permissions.can(.surveySignRev, on: model.access(job)) { signing.wrappedValue = true } }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel((photo == nil ? "เซ็นชื่อ" : "เซ็นชื่อใหม่ ") + role)
                Rectangle().fill(Theme.navy.opacity(0.35)).frame(width: max(0, w - 112), height: 1.5)
                    .position(x: w / 2, y: base).allowsHitTesting(false)
                Text("✕").font(.sarabunFixed(18)).foregroundStyle(Theme.navy.opacity(0.45))
                    .position(x: 40, y: base - 14).allowsHitTesting(false)
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: min(380, w * 0.8), height: min(124, base))
                            .position(x: w / 2, y: base + 14 - min(124, base) / 2)
                    } else if photo != nil {
                        Text("ลายเซ็นอยู่บนเครื่องอื่น").font(.sarabunFixed(15, .semibold)).foregroundStyle(Theme.inkMuted)
                            .position(x: w / 2, y: h * 0.34 + 20)
                    } else {
                        VStack(spacing: 6) {
                            A2Icon(name: "e1-sign-pen", fallback: "pencil.tip", size: 28)
                            Text("แตะเพื่อเซ็นชื่อ").font(.sarabunFixed(15, .semibold))
                        }
                        .foregroundStyle(emptyTint)
                        .position(x: w / 2, y: h * 0.34 + 28)
                    }
                }
                .allowsHitTesting(false)
                VStack(spacing: 2) {
                    label
                    Text(role + " | " + Self.thaiDate(photo?.takenAt ?? Date())).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1).allowsHitTesting(false)
                }
                .fixedSize()
                .position(x: w / 2, y: min(h - 26, max(base + 30, h * 0.88 - 26)))
            }
        }
        .frame(minHeight: 130)
    }

    var reviewerRow: some View {
        HStack(spacing: 12) {
            Text("ผู้ตรวจสอบ").font(.sarabunFixed(15, .bold))
            if !narrow { Text("ไม่บังคับ | ลงนามบนกระดาษ").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            Spacer(minLength: 8)
            TextField(narrow ? "ไม่บังคับ" : "ชื่อผู้ตรวจสอบ", text: Binding(get: { v.text("reviewer") }, set: { set("reviewer", $0.isEmpty ? nil : .text($0)) }))
                .font(.sarabunFixed(15))
                .padding(.horizontal, 12).frame(width: narrow ? nil : 220, height: 44).frame(maxWidth: narrow ? .infinity : nil)
                .background(Self.fieldFill, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("ผู้ตรวจสอบ")
        }
        .padding(.leading, 18).padding(.trailing, 8)
        .frame(minHeight: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }
}

/// Dots every 18 pt, the signature box's paper.
private struct DotGrid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var y = r.minY + 9
        while y < r.maxY {
            var x = r.minX + 9
            while x < r.maxX { p.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += 18 }
            y += 18
        }
        return p
    }
}

/// A horizontal line through the middle of its frame (for a dashed underline).
private struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}
#endif
