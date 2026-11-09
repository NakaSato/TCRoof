import SwiftUI
import TCRoofCore

/// Each tab's own state (CHA-56): an `@Observable` model the page keeps but never reads in its own body, so an edit on
/// one tab redraws that tab (the `InstallTabSection` that reads it) and not the page with every other tab. The page
/// itself keeps only what moves between tabs: the tab, the pushed screen and the sheets that cover the whole page.
/// The tabs with a view of their own (daily, plan, docs, request, weekly, the iPad settings) keep the rest as `@State`.

/// `ภาพรวม` on iPad and iPhone: the progress card's view (`Gantt | S-Curve | Key Plan`, also switched by the KPI cells)
/// and the task rows opened or closed against their default (the running task starts open).
@MainActor @Observable
final class InstallOverviewModel {
    var view: InstallTrackingPage.ProgressView
    var toggled: Set<String> = []

    init(view: InstallTrackingPage.ProgressView) { self.view = view }
}

/// iPad `ตั้งค่าโครงการ`: the edits not saved yet. The page asks about them before leaving the tab (`leave(to:)`), so it
/// holds the model, but only `InstallPadSettingsTabView` reads it while it draws.
@MainActor @Observable
final class InstallSettingsModel {
    var draft = SettingsDraft()
}

/// A tab's part of the page as a view of its own: what its content reads from a tab's model is tracked here, so a
/// change redraws this section only. Its content lays out in the parent stack as if written there.
struct InstallTabSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

extension InstallTrackingPage {
    /// The progress card's view, kept in `overview`.
    var view: ProgressView {
        get { overview.view }
        nonmutating set { overview.view = newValue }
    }

    /// The overview's task rows opened or closed, kept in `overview`.
    var toggled: Set<String> {
        get { overview.toggled }
        nonmutating set { overview.toggled = newValue }
    }

    /// iPad `ตั้งค่าโครงการ`'s edits not saved yet, kept in `settingsModel`.
    var settingsDraft: SettingsDraft {
        get { settingsModel.draft }
        nonmutating set { settingsModel.draft = newValue }
    }
}
