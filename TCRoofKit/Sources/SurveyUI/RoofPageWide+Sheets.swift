#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Roofs saved with "บันทึกค่าปัจจุบันเป็นแบบใหม่". They are kept on this iPad only: the app has no shared store for
/// them yet, so "ทั้งทีม" is recorded with the roof but not sent to the team.
enum RoofStandards {
    static let key = "c1.savedRoofs"
    static func load() -> [Roof.Standard] {
        guard let d = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([Roof.Standard].self, from: d) else { return [] }
        return list
    }
    static func save(_ list: [Roof.Standard]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }
}

extension RoofPageWide {
    // MARK: หลังคามาตรฐาน

    var standardField: some View {
        let label = Roof.standardLabel(values, in: Roof.standards + saved), open = dropdown == "std"
        return VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "หลังคามาตรฐาน")
            Button { dropdown = open ? nil : "std" } label: {
                HStack {
                    Text(label).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 2)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Home.primary)
                }
                .inputBox(focused: open, minHeight: 44, trailing: 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("หลังคามาตรฐาน " + label)
            .popover(isPresented: Binding(get: { dropdown == "std" }, set: { if !$0 { dropdown = nil } }), arrowEdge: .top) {
                standardList.presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }

    var standardList: some View {
        let hit = Roof.matchingStandard(values, in: Roof.standards + saved)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                listHeader("แบบมาตรฐาน กปภ.")
                ForEach(Roof.standards) { s in standardRow(s, on: hit?.id == s.id) }
                if !saved.isEmpty {
                    Divider().padding(.vertical, 4)
                    listHeader("แบบที่ทีมบันทึก")
                    ForEach(saved) { s in
                        standardRow(s, on: hit?.id == s.id)
                            .contextMenu { Button("ลบแบบนี้", role: .destructive) { saved.removeAll { $0.id == s.id }; RoofStandards.save(saved) } }
                    }
                }
                Button { dropdown = nil; savingStandard = true } label: {
                    Label("บันทึกค่าปัจจุบันเป็นแบบใหม่", systemImage: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Home.primary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Self.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .foregroundStyle(Home.navy)
        .frame(width: 390)
        .frame(maxHeight: 520)
    }

    func listHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Home.muted).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }

    func standardRow(_ s: Roof.Standard, on: Bool) -> some View {
        Button { update { Roof.applyStandard(&$0, s) }; dropdown = nil; span = nil } label: {
            HStack(spacing: 12) {
                Image("c1-std-\(s.frame)", bundle: .module).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(Home.navy).frame(width: 40, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title()).font(.system(size: 16, weight: on ? .bold : .regular)).lineLimit(1)
                    Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.ok) }
            }
            .padding(.horizontal, 12).frame(minHeight: 52)
            .background(on ? Self.soft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    var saveStandardSheet: some View {
        SaveRoofStandardSheet(defaultName: defaultStandardName, summary: standardSummary) { name, team in
            let f = DateFormatter(); f.locale = Locale(identifier: "th_TH"); f.dateFormat = "d MMM"
            let by = job.values.text("engineer").split(separator: " ").first.map(String.init) ?? "ฉัน"
            let s = Roof.standard(from: values, id: "t-" + UUID().uuidString, name: name, by: by.isEmpty ? "ฉัน" : by,
                                  scope: team ? "ทั้งทีม" : "เฉพาะฉัน", date: f.string(from: Date()))
            saved.append(s); RoofStandards.save(saved)
            update { $0[Roof.Key.standard] = .text(s.id) }
        }
    }

    /// "โรงกรอง (สถานีผลิตน้ำ 1)": the matching standard's name or the section's name, with the site from A1.
    var defaultStandardName: String {
        let base = Roof.matchingStandard(values, in: Roof.standards)?.name ?? job.modules.first { $0.id == moduleID }.map { $0.name.isEmpty ? "แบบกำหนดเอง" : $0.name } ?? "แบบกำหนดเอง"
        let site = job.projectName.trimmingCharacters(in: .whitespaces)
        return String((site.isEmpty ? base : base + " (" + site + ")").prefix(40))
    }

    var standardSummary: String {
        let xs = Roof.spans(values, .x), ys = Roof.spans(values, .y)
        return fmt(xs.reduce(0, +)) + " × " + fmt(ys.reduce(0, +)) + " ม. · " + Roof.frame(values).label + " · แป @"
            + String(format: "%.2f", Roof.purlinSpacing(values)) + " · กริด \(xs.count + 1) × \(ys.count + 1)"
    }

    // MARK: ระยะแป

    var purlinEditor: some View {
        let p = Roof.purlinSpacing(values), r = Roof.purlinRange
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ระยะแป").font(.system(size: 17, weight: .bold))
                Text("วัดตามแนวลาด").font(.system(size: 12)).foregroundStyle(Home.muted)
                Spacer()
                Button { dropdown = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Home.muted).frame(width: 44, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            HStack(spacing: 10) {
                stepButton("minus", enabled: p > r.lowerBound + 0.001) { update { Roof.setPurlinSpacing(&$0, p - 0.05) } }
                (Text(String(format: "%.2f", p)).font(.system(size: 24, weight: .bold)) + Text(" ม.").font(.system(size: 14)).foregroundColor(Home.muted))
                    .monospacedDigit().frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.primary, lineWidth: 2))
                stepButton("plus", enabled: p < r.upperBound - 0.001) { update { Roof.setPurlinSpacing(&$0, p + 0.05) } }
            }
            HStack(spacing: 6) {
                ForEach([0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { q in
                    let on = abs(q - p) < 0.001
                    Button { update { Roof.setPurlinSpacing(&$0, q) } } label: {
                        Text(String(format: "%.2f", q)).font(.system(size: 14, weight: on ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Home.navy.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(Roof.purlinNote(values) + " · 0.60–1.50 ม.").font(.system(size: 12.5)).foregroundStyle(Home.muted)
        }
        .foregroundStyle(Home.navy)
        .padding(16)
        .frame(width: 330)
    }

    // MARK: ขยาย (section full screen)

    var sectionZoom: some View {
        let f = Roof.frame(values)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("รูปตัด A–A · " + f.title).font(.system(size: 20, weight: .bold))
                    Text("หน่วย ม. · แตะรายการขนาดชิ้นส่วนเพื่อไฮไลต์ตำแหน่ง").font(.system(size: 13)).foregroundStyle(Home.muted)
                }
                Spacer()
                Button { sectionBig = false } label: {
                    Text("ปิด").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 110, height: 48).background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            sectionStage(big: true)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { n in
                        let on = member == n, name = f.members[n - 1].name
                        Button { member = on ? nil : n } label: {
                            HStack(spacing: 6) {
                                Text("\(n)").font(.system(size: 14, weight: .bold)).foregroundStyle(on ? .white : Self.red)
                                Text(name).font(.system(size: 14, weight: on ? .bold : .regular)).foregroundStyle(on ? .white : Home.navy)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(on ? Self.red : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : Home.navy.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Home.navy)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .padding(32)
    }

    // MARK: ส่งออก CAD

    var cadSheet: some View {
        RoofCADSheet(job: job, values: values, section: job.modules.first { $0.id == moduleID }.map { m in
            job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? "C1"
        } ?? "C1", pvMode: mode == .pv, close: { showCAD = false })
    }
}

/// บันทึกเป็นแบบโครงสร้าง: name (40 characters), who may use it.
struct SaveRoofStandardSheet: View {
    let defaultName: String
    let summary: String
    let save: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var team = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("บันทึกเป็นแบบโครงสร้าง").font(.system(size: 19, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.muted).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            Text(summary).font(.system(size: 13)).foregroundStyle(Home.muted)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    A3Label(text: "ชื่อแบบ")
                    Spacer()
                    Button("เปลี่ยนใหม่") { name = "" }.font(.system(size: 13, weight: .semibold)).frame(minHeight: 32)
                }
                TextField("ชื่อแบบ", text: $name).font(.system(size: 17)).inputBox(minHeight: 46)
                    .onChange(of: name) { _, t in if t.count > 40 { name = String(t.prefix(40)) } }
                Text("ในวงเล็บคือชื่อสถานที่ (จาก A1) · ขนาดใส่ให้อัตโนมัติ · สูงสุด 40 ตัวอักษร · \(name.count)/40")
                    .font(.system(size: 12)).foregroundStyle(Home.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                A3Label(text: "ใครใช้ได้")
                RoofSegments(options: ["ทั้งทีม", "เฉพาะฉัน"], selected: team ? 0 : 1, minSegment: 90) { team = $0 == 0 }
                Text(team ? "ทุกคนในทีมเห็นในรายการ \"แบบที่ทีมบันทึก\" และเลือกใช้ได้ทันที" : "เห็นเฉพาะในเครื่อง/บัญชีของคุณ")
                    .font(.system(size: 12)).foregroundStyle(Home.muted)
            }
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("ยกเลิก").font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.35)))
                }
                .buttonStyle(.plain)
                Button {
                    let t = name.trimmingCharacters(in: .whitespaces)
                    save(t.isEmpty ? defaultName : t, team); dismiss()
                } label: {
                    Text("บันทึกแบบ").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 46)
                        .background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            }
        }
        .foregroundStyle(Home.navy)
        .padding(20)
        .presentationDetents([.height(440)])
        .onAppear { name = defaultName }
    }
}

/// ส่งออก CAD: which parts, units, then a .dxf to share (AirDrop, Files, Mail …).
struct RoofCADSheet: View {
    let job: Job
    let values: Values
    let section: String
    let pvMode: Bool
    let close: () -> Void
    @State private var parts: Set<RoofDXF.Part> = [.plan, .section, .table]
    @State private var mm = true
    @State private var result: (url: URL, out: RoofDXF.Output)?
    @State private var sharing = false

    var chosen: Set<RoofDXF.Part> { pvMode ? parts : parts.subtracting([.pv]) }
    var fileName: String {
        let no = job.docNo.isEmpty ? "C1" : "NO" + job.docNo
        return (no + "_" + section).replacingOccurrences(of: " ", with: "") + ".dxf"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ส่งออก CAD").font(.system(size: 17, weight: .bold))
                    Text("DXF R12 · เปิดได้ใน CAD ทั่วไป").font(.system(size: 12)).foregroundStyle(Home.muted)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Home.muted).frame(width: 44, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            if let r = result { done(r) } else { form }
        }
        .foregroundStyle(Home.navy)
        .padding(14)
        .frame(width: 360)
        .sheet(isPresented: $sharing) { if let r = result { ShareSheet(items: [r.url]) } }
    }

    var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(.plan, "แปลนโครงหลังคา", "กริด เสา โครงถัก แป")
            row(.section, "รูปตัด A-A", "พร้อมระยะ")
            row(.table, "ตารางชิ้นส่วน 1–7", "ขนาดหน้าตัด")
            row(.pv, "ตำแหน่งแผงโซลาร์", pvMode ? "ตามการจัดแผง" : "เปิดโหมดจัดแผงก่อน", enabled: pvMode)
            HStack(spacing: 8) {
                Text("หน่วย").font(.system(size: 14))
                RoofSegments(options: ["มม. (1:1)", "ม."], selected: mm ? 0 : 1, minSegment: 80) { mm = $0 == 0 }
            }
            Text("เลเยอร์: " + (chosen.isEmpty ? "—" : RoofDXF.layerSummary(chosen))).font(.system(size: 12)).foregroundStyle(Home.muted)
            Button(action: export) {
                Label("ส่งออก " + fileName, systemImage: "square.and.arrow.down").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(chosen.isEmpty ? Home.disabledText : .white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(chosen.isEmpty ? Home.disabledFill : Home.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).disabled(chosen.isEmpty)
        }
    }

    func row(_ p: RoofDXF.Part, _ t: String, _ s: String, enabled: Bool = true) -> some View {
        let on = chosen.contains(p)
        return Button { if on { parts.remove(p) } else { parts.insert(p) } } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(on ? Home.primary : Home.muted)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t).font(.system(size: 15, weight: .semibold))
                    Text(s).font(.system(size: 12)).foregroundStyle(Home.muted)
                }
                Spacer()
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func done(_ r: (url: URL, out: RoofDXF.Output)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(r.url.lastPathComponent, systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Home.ok)
            Text("\(r.out.entities) วัตถุ · \(r.out.layers.count) เลเยอร์ · \(max(1, r.out.data.count / 1024)) KB · " + (mm ? "มม. 1:1" : "ม."))
                .font(.system(size: 12.5)).foregroundStyle(Home.muted)
            HStack(spacing: 8) {
                Button { result = nil } label: {
                    Text("ย้อนกลับ").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.35)))
                }
                .buttonStyle(.plain)
                Button { sharing = true } label: {
                    Text("ส่งอีกครั้ง").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    func export() {
        let out = RoofDXF.build(values, parts: chosen, millimetres: mm)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do { try out.data.write(to: url, options: .atomic); result = (url, out); sharing = true } catch {}
    }
}
#endif
