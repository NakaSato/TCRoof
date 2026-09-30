#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Icons from the A2 design (docs/ui/survey-a2/icons, copied to Resources/A2Icons.xcassets).
/// Symbols keep their own colours; `ui` icons (tools, sources, shortcuts) are templates tinted like the button's text.
/// An icon missing from the catalog falls back to the SF Symbol given.
struct A2Icon: View {
    let name: String?
    let fallback: String
    /// nil fills the space the parent gives it.
    var size: CGFloat? = 24

    static func has(_ name: String?) -> Bool { name.map { UIImage(named: $0, in: .module, with: nil) != nil } ?? false }

    var body: some View {
        if let name, Self.has(name) {
            Image(name, bundle: .module).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: fallback).resizable().scaledToFit().padding((size ?? 24) * 0.12).frame(width: size, height: size)
        }
    }
}

extension MarkKind {
    /// The design's icon for this symbol, or its SF Symbol where the design has none (`water`).
    func icon(size: CGFloat? = 34) -> some View {
        A2Icon(name: assetName, fallback: symbol, size: size)
            .foregroundStyle(Color(red: color.r, green: color.g, blue: color.b))
    }
}
#endif
