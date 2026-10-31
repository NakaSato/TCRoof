#if canImport(UIKit)
import SwiftUI
import Observation
import TCRoofCore

/// D1's `↶ เลิกทำ` (docs/specs/tank-drawing-swift.md §4.3): snapshots of the tank's answers, the last 30. Changes less
/// than 0.8 s apart are one step, so a drag, a run of typing or a layout search undo at once. Undo clears the selection;
/// ⌘Z / ⇧⌘Z on an iPad keyboard.
extension TankPageWide {
    static let undoLimit = 30, undoGap: TimeInterval = 0.8

    /// Called on every change of the tank's values with the values before it.
    func recordUndo(_ old: Values) {
        if undo.applying { undo.applying = false; return }
        let now = Date()
        if undo.back.isEmpty || now.timeIntervalSince(undo.at) > Self.undoGap {
            undo.back.append(old)
            if undo.back.count > Self.undoLimit { undo.back.removeFirst() }
        }
        undo.at = now
        // a published write draws the page again, so only when there is something to clear
        if !undo.forward.isEmpty { undo.forward = [] }
    }

    func undoStep() {
        guard let last = undo.back.popLast() else { return }
        undo.forward.append(values)
        apply(last)
    }

    func redoStep() {
        guard let next = undo.forward.popLast() else { return }
        undo.back.append(values)
        apply(next)
    }

    private func apply(_ v: Values) {
        undo.applying = true
        undo.at = .distantPast
        pointSel = nil
        update { $0 = v }
    }

    /// `↶` and `↷`, 44 pt each; `compact` drops the redo button (iPhone).
    func undoButtons(compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            Button { undoStep() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
            }
            .disabled(undo.back.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("เลิกทำ")
            if !compact {
                Button { redoStep() } label: {
                    Image(systemName: "arrow.uturn.forward").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                }
                .disabled(undo.forward.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("ทำซ้ำ")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primary)
    }
}

/// The undo history: kept in a reference so recording a step doesn't need a state write per change.
@MainActor
@Observable
final class TankUndo {
    var back: [Values] = []
    var forward: [Values] = []
    @ObservationIgnored var at = Date.distantPast
    @ObservationIgnored var applying = false
}
#endif
