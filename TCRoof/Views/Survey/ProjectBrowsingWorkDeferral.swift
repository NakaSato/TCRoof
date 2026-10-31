import SwiftUI

/// Hidden tab stacks remain mounted, so visibility includes dock selection and scene activity.
private struct ProjectBrowsingWorkDeferral: ViewModifier {
    @Environment(PhoneDock.self) private var phoneDock: PhoneDock?
    @Environment(PadDock.self) private var padDock: PadDock?
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var owner = UUID()

    private var isBrowsing: Bool {
        let selected = phoneDock.map { $0.tab == .pwa } ?? padDock.map { $0.tab == .pwa } ?? true
        return appeared && selected && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .onAppear { appeared = true }
            .onChange(of: isBrowsing, initial: true) { _, active in
                PhotoSync.shared.setProjectListVisible(active, owner: owner)
            }
            .onDisappear {
                appeared = false
                PhotoSync.shared.setProjectListVisible(false, owner: owner)
            }
    }
}

extension View {
    func deferBackgroundFilesWhileBrowsingProjects() -> some View {
        modifier(ProjectBrowsingWorkDeferral())
    }
}
