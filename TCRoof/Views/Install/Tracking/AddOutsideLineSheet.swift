import SwiftUI
import TCRoofUI
import TCRoofCore

/// `+ เพิ่มงานนอกแผน MP`: a line with no MP task, its name, location and quantity.
struct AddOutsideLineSheet: View {
    let locations: [String]
    let onAdd: (RoutineReport.PlanLine) -> Void
    @State private var name = ""
    @State private var location = ""
    @State private var qty: Double?
    @State private var unit = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 560) {
                PadSection("งานนอกแผน MP") {
                    TextField("ชื่องาน", text: $name).accessibilityIdentifier("outsideName")
                    LocationMenu(location: $location, locations: locations)
                    HStack {
                        TextField("ปริมาณ", value: $qty, format: .number).keyboardType(.decimalPad)
                        TextField("หน่วย", text: $unit)
                    }
                }
            }
            .navigationTitle("เพิ่มงานนอกแผน MP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม") {
                        onAdd(.init(task: nil, description: name.trimmingCharacters(in: .whitespaces), location: location, qty: qty ?? 0, unit: unit))
                        dismiss()
                    }
                    .bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
