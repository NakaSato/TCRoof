import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// A form of the tool and vehicle log.
enum ToolLogForm: Identifiable {
    case borrow
    case giveBack(ToolLog.Event)
    /// nil: pick the vehicle in the form.
    case carOut(ToolLog.Vehicle?)
    case carIn(ToolLog.Event)
    case fuel(ToolLog.Vehicle)
    /// nil: a new one.
    case vehicle(ToolLog.Vehicle?)

    var id: String {
        switch self {
        case .borrow: "borrow"
        case .giveBack(let e): "back-" + e.id
        case .carOut(let v): "out-" + (v?.id ?? "")
        case .carIn(let e): "in-" + e.id
        case .fuel(let v): "fuel-" + v.id
        case .vehicle(let v): "vehicle-" + (v?.id ?? "new")
        }
    }

    var title: String {
        switch self {
        case .borrow: "ยืมเครื่องมือ"
        case .giveBack: "รับคืนเครื่องมือ"
        case .carOut: "ออกรถ"
        case .carIn: "คืนรถ"
        case .fuel: "เติมน้ำมัน"
        case .vehicle(let v): v == nil ? "เพิ่มรถ" : "แก้ไขรถ"
        }
    }
}

struct ToolLogFormSheet: View {
    let form: ToolLogForm
    let events: [ToolLog.Event]
    let vehicles: [ToolLog.Vehicle]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var tools = InstrumentStore.shared

    @State private var toolID = ""
    @State private var toolName = ""
    @State private var vehicleID = ""
    @State private var job = ""
    @State private var hasDue = true
    @State private var due = Date.now.adding(days: 3)
    @State private var odometer = ""
    @State private var fuel = 0.5
    @State private var litres = ""
    @State private var baht = ""
    @State private var condition = "สภาพปกติ"
    @State private var note = ""
    @State private var name = ""
    @State private var plate = ""
    @State private var serviceAt = ""

    private static let conditions = ["สภาพปกติ", "ชำรุด / ต้องซ่อม", "อุปกรณ์ไม่ครบ"]

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) { fields }
                .environment(\.locale, ThaiFormat.locale)
                .navigationTitle(form.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("บันทึก") { save(); dismiss() }.bold().disabled(!canSave)
                    }
                }
                .onAppear(perform: prefill)
        }
    }

    @ViewBuilder private var fields: some View {
        switch form {
        case .borrow:
            PadSection("เครื่องมือ") {
                Picker("จากทะเบียน", selection: $toolID) {
                    Text("พิมพ์ชื่อเอง").tag("")
                    ForEach(tools.all.filter { ToolLog.out($0.id, in: events) == nil }) { t in
                        Text(t.code.isEmpty ? t.name : t.name + " · " + t.code).tag(t.id)
                    }
                }
                if toolID.isEmpty { TextField("ชื่อเครื่องมือ เช่น Fluke 376 FC", text: $toolName) }
            }
            jobSection
            PadSection("กำหนดคืน") {
                Toggle("มีกำหนดคืน", isOn: $hasDue).tint(Theme.primary)
                if hasDue { DatePicker("ครบคืน", selection: $due, in: Date.now..., displayedComponents: [.date, .hourAndMinute]) }
            }
            noteSection
        case .giveBack(let e):
            PadSection(e.itemName) {
                Picker("สภาพเครื่อง", selection: $condition) { ForEach(Self.conditions, id: \.self) { Text($0).tag($0) } }
                TextField("หมายเหตุ", text: $note)
            } footer: {
                Text("ยืมโดย \(e.person) · \(ToolLogCard.time(e.at, now: .now))")
            }
        case .carOut(let v):
            if v == nil {
                PadSection("รถ") {
                    Picker("คัน", selection: $vehicleID) {
                        ForEach(vehicles.filter { ToolLog.out($0.id, in: events) == nil }) { Text($0.title).tag($0.id) }
                    }
                }
            }
            jobSection
            PadSection("ไมล์ตอนออก") { numberField("เลขไมล์ (กม.)", $odometer) }
        case .carIn(let e):
            PadSection(e.itemName) {
                numberField("เลขไมล์ตอนคืน (กม.)", $odometer)
                VStack(alignment: .leading) {
                    Text("น้ำมันเหลือ \(Int((fuel * 100).rounded()))%")
                    Slider(value: $fuel, in: 0...1, step: 0.05).tint(Theme.primary)
                }
                TextField("หมายเหตุ", text: $note)
            } footer: {
                Text("ออกโดย \(e.person)" + (e.odometer.map { " · ไมล์ตอนออก \($0.formatted())" } ?? ""))
            }
        case .fuel(let v):
            PadSection(v.title) {
                decimalField("ลิตร", $litres)
                decimalField("บาท", $baht)
                numberField("เลขไมล์ (ไม่บังคับ)", $odometer)
            }
        case .vehicle(let v):
            PadSection {
                TextField("รุ่น เช่น Isuzu D-Max", text: $name)
                TextField("ทะเบียน เช่น 1กข 1234", text: $plate)
                numberField("เช็กระยะครั้งถัดไปที่ไมล์ (ไม่บังคับ)", $serviceAt)
            }
            if let v {
                PadSection {
                    Button("ลบรถคันนี้", role: .destructive) { delete(v); dismiss() }
                } footer: {
                    Text("บันทึกที่ผ่านมาของรถคันนี้ยังอยู่")
                }
            }
        }
    }

    private var jobSection: some View {
        PadSection("ใช้กับงาน") {
            Picker("งาน", selection: $job) {
                Text("ไม่ระบุ").tag("")
                ForEach(jobs.filter { $0.status != .completed }) { j in Text(j.code + " " + j.projectName).tag(j.code) }
            }
        }
    }

    private var noteSection: some View {
        PadSection { TextField("หมายเหตุ", text: $note) }
    }

    private func numberField(_ title: String, _ text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.numberPad)
    }

    private func decimalField(_ title: String, _ text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad)
    }

    private var canSave: Bool {
        switch form {
        case .borrow: !toolID.isEmpty || !toolName.trimmingCharacters(in: .whitespaces).isEmpty
        case .carOut: !vehicleID.isEmpty && Int(odometer) != nil
        case .carIn: Int(odometer) != nil
        case .fuel: Double(litres) != nil && Double(baht) != nil
        case .vehicle: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .giveBack: true
        }
    }

    private func prefill() {
        switch form {
        case .carOut(let v):
            vehicleID = v?.id ?? vehicles.first { ToolLog.out($0.id, in: events) == nil }?.id ?? ""
            if let last = ToolLog.lastReading(vehicleID, in: events).odometer { odometer = "\(last)" }
        case .carIn(let e):
            job = e.job
            if let o = e.odometer { odometer = "\(o)" }
            fuel = ToolLog.lastReading(e.item, in: events).fuel ?? 0.5
        case .vehicle(let v?):
            name = v.name; plate = v.plate; serviceAt = v.serviceAtKm.map { "\($0)" } ?? ""
        default: break
        }
    }

    private func event(_ action: ToolLog.Action, item: String, itemName: String) -> ToolLog.Event {
        ToolLog.Event(action: action, item: item, itemName: itemName, person: TravelStore.person, personEmail: TravelStore.owner, job: job)
    }

    private func save() {
        guard !ToolLogDemo.on else { return }
        var e: ToolLog.Event?
        switch form {
        case .borrow:
            let tool = tools.all.first { $0.id == toolID }
            let typed = toolName.trimmingCharacters(in: .whitespaces)
            // a typed tool keeps its name as its id, so its return matches it
            var b = event(.borrow, item: tool?.id ?? "typed:" + typed, itemName: tool?.name ?? typed)
            b.due = hasDue ? due : nil
            b.note = note
            e = b
        case .giveBack(let out):
            var b = event(.giveBack, item: out.item, itemName: out.itemName)
            b.job = out.job
            b.note = [condition, note].filter { !$0.isEmpty }.joined(separator: " · ")
            e = b
        case .carOut:
            guard let v = vehicles.first(where: { $0.id == vehicleID }) else { return }
            var b = event(.carOut, item: v.id, itemName: v.title)
            b.odometer = Int(odometer)
            e = b
        case .carIn(let out):
            var b = event(.carIn, item: out.item, itemName: out.itemName)
            b.odometer = Int(odometer); b.fuelLevel = fuel; b.note = note
            e = b
        case .fuel(let v):
            var b = event(.fuel, item: v.id, itemName: v.title)
            b.litres = Double(litres); b.baht = Double(baht); b.odometer = Int(odometer)
            e = b
        case .vehicle(let v):
            let made = ToolLog.Vehicle(id: v?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                                       plate: plate.trimmingCharacters(in: .whitespaces), serviceAtKm: Int(serviceAt))
            let id = made.id
            if let stored = try? context.fetch(FetchDescriptor<CompanyVehicle>(predicate: #Predicate { $0.syncID == id })).first {
                stored.vehicle = made
            } else {
                context.insert(CompanyVehicle(made))
            }
        }
        if let e { context.insert(ToolEvent(e)) }
        try? context.save()
    }

    private func delete(_ v: ToolLog.Vehicle) {
        let id = v.id
        if let stored = try? context.fetch(FetchDescriptor<CompanyVehicle>(predicate: #Predicate { $0.syncID == id })).first {
            context.delete(stored)
            try? context.save()
        }
    }
}
