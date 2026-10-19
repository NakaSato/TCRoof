import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// One day of travel (§B2, §B3): the vehicle, each station with its arrival and departure, the road distance of each leg
/// (worked out by Maps, or typed with a reason), the way back and the odometer. Changes are kept as they are made; a
/// submitted month's day is read only.
struct TripEditor: View {
    @Bindable var trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @State private var routing = false
    @State private var addStop = false
    @State private var odoCamera: OdoEnd?
    @State private var confirmDelete = false

    enum OdoEnd: String, Identifiable { case start, end; var id: String { rawValue } }

    private var locked: Bool { TravelStore.isLocked(context, month: trip.monthKey) }

    var body: some View {
        NavigationStack {
            Form {
                vehicleSection
                stopsSection
                distanceSection
                odometerSection
                if !locked {
                    Section { Button("ลบการเดินทางวันนี้", role: .destructive) { confirmDelete = true } }
                }
            }
            .disabled(locked)
            .tcFormStyle()
            .navigationTitle(RoutineReport.thaiDate(trip.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { try? context.save(); dismiss() } }
            }
            .sheet(isPresented: $addStop) {
                JobPickerSheet(title: "เพิ่มสถานี") { job in
                    var stops = trip.stops
                    stops.append(TravelClaim.Stop(jobID: job.ensureSyncID(), label: TravelStore.label(job)))
                    trip.stops = stops
                    Task { await recalc(again: false) }
                }
            }
            .fullScreenCover(item: $odoCamera) { end in
                StampedCamera { data in
                    let jpeg = ReceiptImage.jpeg(data)
                    if end == .start { trip.odoStartPhoto = jpeg; trip.odoStartDriveID = nil } else { trip.odoEndPhoto = jpeg; trip.odoEndDriveID = nil }
                    Task {
                        let reading = ReceiptParser.odometer(await TextReader.read(jpeg))
                        if end == .start, trip.odoStart == nil { trip.odoStart = reading }
                        if end == .end, trip.odoEnd == nil { trip.odoEnd = reading }
                    }
                }
            }
            .confirmationDialog("ลบการเดินทางวันนี้?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("ลบ", role: .destructive) { context.delete(trip); try? context.save(); dismiss() }
            } message: { Text("เวลาถึง/ออกและระยะทางของวันนี้จะหายไป ใบเสร็จยังอยู่") }
            .task { await downloadOdometers() }
        }
    }

    // MARK: sections

    private var vehicleSection: some View {
        Section("ยานพาหนะ") {
            Picker("ยานพาหนะ", selection: Binding(get: { trip.vehicle }, set: { trip.vehicle = $0 })) {
                ForEach(TravelClaim.Vehicle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("ทะเบียนรถ", text: $trip.plate)
            TextField("ออกจาก", text: $trip.startPlace)
            if trip.vehicle.paysMileage {
                LabeledContent("อัตรา (บาท/กม.)") {
                    TextField("5", value: $trip.rate, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var stopsSection: some View {
        Section {
            ForEach(Array(trip.stops.enumerated()), id: \.element.id) { i, stop in
                StopRow(stop: stop, day: trip.date, update: { new in
                    var stops = trip.stops
                    guard i < stops.count else { return }
                    stops[i] = new
                    trip.stops = stops
                }, remove: {
                    var stops = trip.stops
                    guard i < stops.count else { return }
                    stops.remove(at: i)
                    // the next leg starts somewhere else now
                    if i < stops.count, !stops[i].legEdited { stops[i].legKm = nil }
                    trip.stops = stops
                    Task { await recalc(again: false) }
                })
            }
            if !locked {
                Button { addStop = true } label: { Label("เพิ่มสถานี", systemImage: "plus.circle") }
            }
        } header: { Text("สถานีที่ไป") } footer: {
            Text("กด ถึงสถานีแล้ว / ออกจากสถานี ที่หน้างานเพื่อบันทึกเวลาและตำแหน่ง แก้เวลาที่นี่ได้")
        }
    }

    private var distanceSection: some View {
        Section {
            LabeledContent("ระยะทางรวม", value: trip.day.km.map { String(format: "%.1f กม.", $0) } ?? "ยังคำนวณไม่ครบ")
            LabeledContent("ขากลับ (กม.)") {
                TextField("–", value: $trip.backKm, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            if trip.vehicle.paysMileage, let m = trip.day.mileage {
                LabeledContent("ค่าเดินทาง", value: TravelClaim.baht(m) + " บาท")
            }
            Button { Task { await recalc(again: true) } } label: {
                HStack {
                    Label("คำนวณระยะทางใหม่จากแผนที่", systemImage: "map")
                    if routing { Spacer(); ProgressView() }
                }
            }
            .disabled(routing)
            if TravelSettings.officeLocation == nil {
                Text("ยังไม่ได้ตั้งตำแหน่งสำนักงาน ขาแรกและขากลับจึงคำนวณไม่ได้ ตั้งได้ที่ ตั้งค่าการเบิก").font(.footnote).foregroundStyle(Theme.warningText)
            }
        } header: { Text("ระยะทาง") } footer: {
            Text("คิดจากเส้นทางถนนของ Apple Maps เก็บไว้กับวันนั้น ระยะที่แก้เองจะไม่ถูกคำนวณทับ")
        }
    }

    private var odometerSection: some View {
        Section {
            odoRow("เลขไมล์ออก", value: $trip.odoStart, photo: trip.odoStartPhoto, end: .start)
            odoRow("เลขไมล์กลับ", value: $trip.odoEnd, photo: trip.odoEndPhoto, end: .end)
            if let km = trip.day.odometerKm { LabeledContent("ระยะตามไมล์", value: "\(km) กม.") }
            if trip.day.odometerDiffers {
                TextField("เหตุผลที่ไมล์กับระยะทางต่างกัน (จำเป็น)", text: $trip.odoReason, axis: .vertical)
            }
        } header: { Text("เลขไมล์ (ไม่บังคับ)") } footer: {
            Text("ถ่ายรูปหน้าปัด แอปอ่านเลขให้ ตรวจแล้วแก้ได้ ถ้าต่างจากระยะทางเกิน 20% ต้องใส่เหตุผล")
        }
    }

    private func odoRow(_ title: String, value: Binding<Int?>, photo: Data?, end: OdoEnd) -> some View {
        HStack(spacing: 12) {
            if let photo { Thumbnail(data: photo).frame(width: 44, height: 44) }
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.grouping(.never)).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(maxWidth: 120)
            if !locked {
                PadRowButton("ถ่ายรูป\(title)", systemImage: "camera") { odoCamera = end }
            }
        }
    }

    // MARK: actions

    private func recalc(again: Bool) async {
        routing = true
        await TravelStore.route(trip, context: context, again: again)
        routing = false
    }

    private func downloadOdometers() async {
        if trip.odoStartPhoto == nil, let id = trip.odoStartDriveID { trip.odoStartPhoto = try? await session.survey.driveDownload(id) }
        if trip.odoEndPhoto == nil, let id = trip.odoEndDriveID { trip.odoEndPhoto = try? await session.survey.driveDownload(id) }
    }
}

/// A station on the day: times, the leg to it, and its typed distance with the reason.
private struct StopRow: View {
    let stop: TravelClaim.Stop
    /// The trip's day, for a time typed in where none was stamped.
    let day: Date
    let update: (TravelClaim.Stop) -> Void
    let remove: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stop.label.isEmpty ? "สถานที่" : stop.label).font(.sarabun(16, .bold, relativeTo: .body))
                Spacer()
                if let s = stop.onSite { Text("อยู่ \(Int(s / 60)) นาที").font(.footnote).foregroundStyle(Theme.muted) }
                if enabled { PadRowButton("ลบสถานี", systemImage: "trash", destructive: true, action: remove) }
            }
            HStack {
                timePicker("ถึง", \.arrivedAt)
                timePicker("ออก", \.departedAt)
            }
            HStack {
                Text("ระยะจากจุดก่อนหน้า")
                Spacer()
                TextField("–", value: Binding(get: { stop.legKm }, set: { v in
                    var s = stop; s.legKm = v; s.legEdited = v != nil; update(s)
                }), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                Text("กม.")
            }
            if stop.legEdited {
                TextField("เหตุผลที่แก้ระยะ (ถนนปิด อ้อม …)", text: Binding(get: { stop.legNote }, set: { var s = stop; s.legNote = $0; update(s) }))
                    .font(.footnote)
                if enabled {
                    Button("ใช้ระยะจากแผนที่") { var s = stop; s.legEdited = false; s.legKm = nil; s.legNote = ""; update(s) }.font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timePicker(_ title: String, _ key: WritableKeyPath<TravelClaim.Stop, Date?>) -> some View {
        Group {
            if let time = stop[keyPath: key] {
                DatePicker(title, selection: Binding(get: { time }, set: { var s = stop; s[keyPath: key] = $0; update(s) }),
                           displayedComponents: .hourAndMinute)
            } else {
                Button("\(title) –:–") {
                    var s = stop
                    let cal = TravelClaim.calendar
                    let now = cal.dateComponents([.hour, .minute], from: .now)
                    s[keyPath: key] = cal.date(bySettingHour: now.hour ?? 9, minute: now.minute ?? 0, second: 0, of: day)
                    update(s)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
