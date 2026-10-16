#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// E1 before the first signature: required photos still missing (signing is still allowed).
struct MissingPhotosBanner: View {
    let missing: Int
    var review: () -> Void
    var body: some View {
        HStack(spacing: Space.m) {
            Label("ยังขาดรูปบังคับ \(missing) รูป", systemImage: "camera.badge.ellipsis")
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            Spacer(minLength: Space.s)
            TCButton("ไปตรวจรูป", systemImage: "photo.on.rectangle", kind: .secondary, size: .card, action: review).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
