#if canImport(UIKit)
import SwiftUI
import UIKit

/// Raw hardware-keyboard presses for a panel: an invisible view that holds the first responder while `active`, so Return
/// and ⌫ reach it (a SwiftUI shortcut without modifiers can't take them from the system). A text field takes the keys by
/// becoming the first responder; the catcher takes them back once `active` is set again.
struct KeyCatcher: UIViewRepresentable {
    var active: Bool
    let press: (UIKeyboardHIDUsage) -> Bool

    func makeUIView(context: Context) -> CatcherView { CatcherView() }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.press = press
        view.active = active
        view.claim()
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) { view.active = false; view.resignFirstResponder() }

    final class CatcherView: UIView {
        var press: (UIKeyboardHIDUsage) -> Bool = { _ in false }
        var active = false

        override var canBecomeFirstResponder: Bool { active }
        override func didMoveToWindow() { super.didMoveToWindow(); claim() }

        func claim() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.window != nil, !self.isFirstResponder else { return }
                // never from a text field that is being edited
                if let r = self.window?.firstResponder, r is UITextInput { return }
                self.becomeFirstResponder()
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for p in presses {
                guard let key = p.key, key.modifierFlags.intersection([.command, .alternate, .control, .shift]).isEmpty else { continue }
                if press(key.keyCode) { handled = true }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
    }
}

private extension UIView {
    var firstResponder: UIResponder? {
        if isFirstResponder { return self }
        for v in subviews { if let r = v.firstResponder { return r } }
        return nil
    }
}
#endif
