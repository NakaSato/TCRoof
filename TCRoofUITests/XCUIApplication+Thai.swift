import XCTest

extension XCUIApplication {
    /// Launches the app in Thai, whatever the simulator's language. The tests find buttons by their Thai text, and
    /// `Localizable.xcstrings` gives some of them English (`ปิด` is `Close`, `บันทึก` is `Save`) on an English simulator.
    func launchInThai() {
        if !launchArguments.contains("-AppleLanguages") { launchArguments += ["-AppleLanguages", "(th)"] }
        launch()
    }
}
