import Foundation

/// Which wizard step fills each cell of an inverter's sheet (`INV nn-ก่อน` / `-หลัง`), for the sheet preview's
/// `แสดงที่มา` tints (docs/ui/iec62446-sheet-before). Cells the overview fills (E11 continuity, E20 inverter testing
/// before) and the form's own labels have none; a string column is tinted only where the slot has a string.
public extension IECReport {
    /// `ref` like `I16`; nil = untinted.
    static func sheetSource(_ ref: String, inverter inv: Inverter, phase: Phase) -> Stage? {
        let letters = ref.prefix { $0.isLetter }, row = Int(ref.dropFirst(letters.count)) ?? 0
        let col = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        switch ref {
        case "C3", "E5", "O5", "AA4", "E29", "E30", "AA30": return .setup
        case "E14": return .beforeInsulation
        case "E21": return .afterVoltage
        case "E22", "E23", "E24", "E25", "E26", "AA25", "AA26": return phase == .after ? .energy : nil
        default: break
        }
        // a string column: E…X is slot 1…20
        guard (5...24).contains(col), inv.slots[col - 5] != nil else { return nil }
        switch row {
        case 8, 9: return .setup
        case 12, 16, 18: return .beforeVoltage
        case 13: return .beforeInsulation
        case 17, 19: return phase == .after ? .afterVoltage : nil
        default: return nil
        }
    }

    /// The 1-based slot of a string-column cell (`I16` → 5), nil for any other cell.
    static func sheetSlot(_ ref: String) -> Int? {
        let letters = ref.prefix { $0.isLetter }
        let col = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        return (5...24).contains(col) ? col - 4 : nil
    }
}
