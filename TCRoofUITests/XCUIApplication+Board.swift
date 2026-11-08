import XCTest

extension XCUIApplication {
    /// Scrolls up inside the 1366 × 1024 board that `-homeBoard YES` draws scaled into the top of a portrait simulator.
    /// `swipeUp()` starts at the screen's centre, below the board, where nothing scrolls.
    func swipeUpOnBoard() {
        let from = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
    }

    /// Scrolls back down (towards the top of the page) inside the board.
    func swipeDownOnBoard() {
        let from = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        from.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
}
