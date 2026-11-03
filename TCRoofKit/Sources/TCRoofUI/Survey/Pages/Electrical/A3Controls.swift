#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore

// MARK: - Reusable A3 Controls

/// Small label above a control, with the red star of a required field.
struct A3Label: View {
    let text: String
    var required = false
    var body: some View {
        HStack(spacing: 3) {
            Text(text).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            if required { Text("*").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.danger) }
        }
    }
}

/// Labelled text box (44 pt high), with an optional unit at the right.
struct A3Input: View {
    let label: String
    @Binding var text: String
    var required = false
    var unit: String?
    var keyboard: UIKeyboardType = .default
    /// The value came from the A2 picture.
    var a2 = false
    /// The value was read from a nameplate or a sensor.
    var source: FillSource? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: label, required: required)
            HStack(spacing: 4) {
                TextField("", text: $text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                if a2 { A2Badge() }
                SourceChip(source: source)
                if let unit { Text(unit).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
            }
            .inputBox(minHeight: 44, trailing: 10)
        }
    }
}

/// One-of-n buttons; tapping the chosen one clears it.
struct A3Segments: View {
    let options: [String]
    var titles: [String]?
    let selected: String
    let set: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { n, o in
                let on = selected == o
                Button { set(on ? "" : o) } label: {
                    Text(titles?[n] ?? o).font(.sarabunFixed(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.teal : Theme.borderControl.opacity(0.6), lineWidth: on ? 2 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// White card with a 1-pt navy border.
struct A3Panel<Content: View>: View {
    var accent = false
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent ? Theme.primary : Theme.navy.opacity(0.25), lineWidth: accent ? 2 : 1))
    }
}

/// Round badge with a short code ("TX 1", "MDB").
struct A3Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.sarabunFixed(11, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(Theme.navy, lineWidth: 1.5))
    }
}

func a3Chip(_ text: String, ok: Bool) -> some View {
    Text(text).font(.sarabunFixed(13, .bold)).lineLimit(1)
        .foregroundStyle(ok ? Theme.success : Theme.danger)
        .padding(.horizontal, 10).frame(minHeight: 26)
        .background((ok ? Theme.mint.opacity(0.4) : Theme.danger.opacity(0.1)), in: Capsule())
}

/// A small photo frame on the shared `PhotoSlot`: the compact empty layout, and the label on the filled photo.
struct A3PhotoTile: View {
    @Binding var photo: Photo?
    let jobID: UUID
    let label: String
    var required = false
    var height: CGFloat = 96
    @Environment(SurveyModel.self) private var model

    var body: some View {
        PhotoSlot(photo: photo, jobID: jobID, hint: label + (required ? " *" : ""), required: required, title: label, dense: true,
                  onPick: { img in if let p = model.addPhoto(img, to: jobID) { photo = p } },
                  onClear: { photo = nil })
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay(alignment: .bottomLeading) {
                if photo != nil {
                    Text(label).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.onMedia).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4)).padding(4)
                        .allowsHitTesting(false)
                }
            }
    }
}
#endif
