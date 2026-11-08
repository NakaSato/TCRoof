import XCTest

extension XCUIApplication {
    /// Launches the app in Thai, whatever the simulator's language. The tests find buttons by their Thai text; the app
    /// is Thai only for now, but this keeps the tests right once an English translation ships.
    func launchInThai() {
        if !launchArguments.contains("-AppleLanguages") { launchArguments += ["-AppleLanguages", "(th)"] }
        launch()
    }
}
