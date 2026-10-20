#if canImport(UIKit)
import SwiftUI
import TCRoofCore

// SLD level 2 (docs/specs/single-line-diagram.md, "Level 2 — detailed MDP"): the optional feeder and board details the
// single line diagram draws. Nothing here counts towards A3's completion or the SLD's missing list.

extension ElectricalPageWide {
    /// One board whose busbar / ground is being edited.
    struct BoardSLDEdit: Identifiable {
        let trafo: Int
        let board: Int
        var id: String { "\(trafo)-\(board)" }
    }

    /// "บัสบาร์ | สายดิน (SLD)" row on a board card; opens `BoardSLDSheet`.
    func boardSLDButton(_ i: Int, _ k: Int) -> some View {
        let b = boards(i)[safe: k] ?? Board()
        let summary = [b.busbar, b.ground].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " | ")
        return Button { editBoardSLD = BoardSLDEdit(trafo: i, board: k) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("บัสบาร์ | สายดิน (SLD)").font(.sarabunFixed(13, .bold))
                    Text(summary.isEmpty ? "ไม่บังคับ" : summary).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.2)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func boardSLDBinding(_ e: BoardSLDEdit) -> Binding<Board> {
        Binding(get: { boards(e.trafo)[safe: e.board] ?? Board() },
                set: { new in editBoards(e.trafo) { b in if b.indices.contains(e.board) { b[e.board].busbar = new.busbar; b[e.board].ground = new.ground } } })
    }
}

/// Busbar and ground of one board, as written on the drawing.
struct BoardSLDSheet: View {
    @Binding var board: Board
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ไม่บังคับ | แสดงบนแผนภาพเส้นเดียว เมื่อ PV ต่อที่ตู้นี้")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    A3Input(label: "บัสบาร์ (เช่น 4x300A. Cu. BUSBAR W/GROUND BUS)", text: $board.busbar)
                    A3Input(label: "สายดิน (เช่น 1x35-IEC01 ø20 PVC.)", text: $board.ground)
                }
                .padding(20)
            }
            .navigationTitle("บัสบาร์ | สายดิน").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
        }
    }
}

/// The breaker sheet's level 2 part: spare, then the cable, conduit, load name and floor of a breaker in use.
struct BreakerSLDFields: View {
    @Binding var breaker: Breaker
    @State private var expanded = false

    var filled: Bool { breaker.spare || ![breaker.cable, breaker.conduit, breaker.load, breaker.floor].allSatisfy(\.isEmpty) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    A3Label(text: "การใช้งาน")
                    A3Segments(options: ["in", "spare"], titles: ["ใช้งาน", "สำรอง (SPARE)"], selected: breaker.spare ? "spare" : "in") {
                        breaker.spare = $0 == "spare"
                    }
                }
                if !breaker.spare { feederFields }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("รายละเอียดสาย / โหลด (SLD)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text(summary).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
        .tint(Theme.navy)
        .onAppear { expanded = filled }
    }

    var summary: String {
        if breaker.spare { return "สำรอง (SPARE)" }
        let s = [breaker.cable, breaker.load, breaker.floor].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return s.isEmpty ? "ไม่บังคับ | ขนาดสาย ท่อ ชื่อโหลด ชั้น" : s.joined(separator: " | ")
    }

    var feederFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                A3Input(label: "สาย (เช่น 4x50,1x10-IEC01)", text: $breaker.cable)
                A3Input(label: "ท่อ / ราง (เช่น ø50mm. UPVC)", text: $breaker.conduit)
            }
            HStack(spacing: 10) {
                A3Input(label: "ชื่อโหลด (เช่น LC11)", text: $breaker.load)
                A3Input(label: "ชั้น / ตำแหน่ง (เช่น 1st FL.)", text: $breaker.floor)
            }
        }
    }
}
#endif
