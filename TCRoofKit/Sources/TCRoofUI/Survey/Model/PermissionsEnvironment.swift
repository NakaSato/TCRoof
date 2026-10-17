import SwiftUI
import TCRoofCore

public extension EnvironmentValues {
    /// What the signed-in member may do (`Permissions`): the app sets it from the member's role, and views hide or
    /// disable the actions it refuses. Defaults to the internal team, as everyone was before roles.
    @Entry var permissions: Permissions = .team
}
