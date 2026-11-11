import SwiftUI
import TCRoofUI
import TCRoofCore

/// กำลังคนผู้รับเหมา (CHA-78, PMBOK 5th §6.4): the people each contractor (or our own team) says it has per week, set
/// against what its stations with an MP plan need over the next four weeks (`Assistant.Strategy.priorities`). A week
/// whose stations need more than the supply shows `คนไม่พอ`, counted once across all the group's stations; the
/// assistant's `station_priorities` then offers to move tasks not started inside their float (`leveling`). Whoever may set
/// up the MP plan (`mp.setup`) edits it; it reaches the team's other devices through Firestore `config/crewSupply`.
struct CrewSupplySheet: View {
    let jobs: [Job]
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @State private var saved = CrewSupply.Store.shared.current ?? CrewSupply()
    @State private var draft = CrewSupply.Store.shared.current ?? CrewSupply()

    private var canEdit: Bool { permissions.can(.mpSetup) }
    private var changed: Bool { !draft.sameValues(saved) }
    private let cal = MasterSchedule.calendar

    /// The stations' figures against the draft, worked out once per render.
    private var priorities: Assistant.Strategy.Priorities {
        let stations = jobs.pwaStations.filter { $0.scheduleInput != nil }.map { $0.assistantJob(permissions) }
        return Assistant.Strategy.priorities(stations, supply: draft, today: .now, calendar: cal)
    }

    private var weeks: [Date] {
        let first = MasterSchedule.weekStart(.now, calendar: cal)
        return (0..<4).compactMap { cal.date(byAdding: .day, value: 7 * $0, to: first) }
    }

    var body: some View {
        let p = priorities
        let groups = Set(p.stations.map(\.crewGroup)).union(draft.groups.keys).sorted()
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection {
                    LabeledContent("ฉบับ", value: revisionText)
                } footer: {
                    Text(canEdit ? "จำนวนคนที่ผู้รับเหมาแจ้งต่อสัปดาห์ เทียบกับคนที่สถานีของเขาต้องใช้ใน 4 สัปดาห์ (จากแผน MP และรายงานประจำวัน)"
                                 : "แก้ได้เฉพาะผู้ที่ตั้งค่าแผน MP ได้")
                }
                if groups.isEmpty {
                    TCEmptyState("ยังไม่มีสถานีที่มีแผน MP", systemImage: "person.3",
                                 description: Text("ใส่ชื่อผู้รับเหมาในตั้งค่าของแต่ละสถานี"))
                }
                ForEach(groups, id: \.self) { g in
                    PadSection(g) {
                        usualRow(g)
                        ForEach(weeks, id: \.self) { w in weekRow(g, w, p) }
                    } footer: {
                        footer(g, p)
                    }
                }
                let problems = draft.problems
                if !problems.isEmpty {
                    PadSection("ยังบันทึกไม่ได้") {
                        ForEach(problems, id: \.self) { Text($0).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .navigationTitle("กำลังคนผู้รับเหมา")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(changed ? "ยกเลิก" : "ปิด") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("บันทึก") { save() }.disabled(!changed || !draft.problems.isEmpty)
                    }
                }
            }
        }
        .tint(Theme.primary)
    }

    private var revisionText: String {
        guard saved.revision > 0 else { return "ยังไม่มีผู้รับเหมาแจ้งจำนวนคน" }
        let date = saved.savedAt.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return ["rev \(saved.revision)", saved.savedBy ?? "", date].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// The group's usual people per week.
    @ViewBuilder private func usualRow(_ g: String) -> some View {
        let usual = draft.groups[g]?.crew ?? 0
        if canEdit {
            Stepper(value: Binding(get: { usual }, set: { draft.set(usual: $0, group: g) }), in: 0...1000) {
                LabeledContent("คนต่อสัปดาห์", value: usual == 0 ? "ยังไม่ระบุ" : "\(usual) คน")
            }
        } else {
            LabeledContent("คนต่อสัปดาห์", value: usual == 0 ? "ยังไม่ระบุ" : "\(usual) คน")
        }
    }

    /// One week: what the stations need, and the people that week (the usual, or its own number).
    @ViewBuilder private func weekRow(_ g: String, _ w: Date, _ p: Assistant.Strategy.Priorities) -> some View {
        let key = ScheduleBrief.day(w, calendar: cal)
        let load = p.loads.first { $0.crewGroup == g && $0.week == key }
        let have = draft.crew(g, week: w, calendar: cal)
        let short = load?.overSupply == true
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("สัปดาห์ " + w.formatted(.dateTime.day().month(.abbreviated)))
                Text(load.map { "ต้องใช้ \($0.crewNeeded) คน | \($0.stations.count) สถานี" } ?? "ไม่มีงานหน้างาน")
                    .font(.footnote).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            if short { TCToneChip("คนไม่พอ", tone: .red) }
            if canEdit, draft.groups[g] != nil {
                Stepper(value: Binding(get: { have ?? 0 }, set: { draft.set($0, group: g, week: w, calendar: cal) }), in: 0...1000) {
                    Text(have.map { "\($0) คน" } ?? "–").monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: 200)
                .accessibilityLabel("คนสัปดาห์ " + w.formatted(.dateTime.day().month(.abbreviated)))
            } else {
                Text(have.map { "มี \($0) คน" } ?? "–").monospacedDigit()
            }
        }
        .foregroundStyle(short ? Theme.danger : Theme.navy)
    }

    /// The assistant's leveling for the group: which station's tasks can wait, inside their float.
    @ViewBuilder private func footer(_ g: String, _ p: Assistant.Strategy.Priorities) -> some View {
        let moves = p.leveling.filter { $0.crewGroup == g }
        if !moves.isEmpty {
            Text("เลื่อนได้ภายในเวลาลอย (วันส่งมอบไม่เปลี่ยน): "
                 + moves.map { m in m.station + " " + m.tasks.map { "\($0.code) → \($0.newStart)" }.joined(separator: ", ") }.joined(separator: " | ")
                 + " | ให้ผู้ช่วยเสนอแผนใหม่ได้จาก แผน MP ทุกสถานี")
        } else if p.loads.contains(where: { $0.crewGroup == g && $0.overSupply == true }) {
            Text("ไม่มีงานที่ยังไม่เริ่มที่เลื่อนได้ภายในเวลาลอย: เพิ่มคน หรือขอแผนใหม่")
        }
    }

    private func save() {
        guard let s = CrewSupply.Store.shared.save(draft, by: permissions.email.isEmpty ? nil : permissions.email) else { return }
        saved = s; draft = s
    }
}
