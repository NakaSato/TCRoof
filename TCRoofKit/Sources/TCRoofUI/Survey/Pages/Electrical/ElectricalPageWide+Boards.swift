#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

// MARK: - Electrical Boards Extension

extension ElectricalPageWide {
    /// "125A×4, 63A×2" from the breakers' sizes.
    func sizeSummary(_ bs: [Breaker]) -> String {
        var order: [String] = [], counts: [String: Int] = [:]
        for b in bs where !b.at.isEmpty {
            if counts[b.at] == nil { order.append(b.at) }
            counts[b.at, default: 0] += max(b.count, 1)
        }
        return order.prefix(2).map { "\($0)A×\(counts[$0] ?? 0)" }.joined(separator: ", ")
    }
    func breakerTotal(_ bs: [Breaker]) -> Int { bs.reduce(0) { $0 + max($1.count, 1) } }

    func mainName(_ i: Int) -> Binding<String> {
        Binding(get: { job.values.text("tr\(i)_feed") }, set: { v in
            let before = job
            job.values["tr\(i)_feed"] = v.isEmpty ? nil : .text(v)
            SiteSync.pull(&job, since: before)
        })
    }
    func boardName(_ i: Int, _ k: Int) -> String {
        if k == 0 { let n = job.values.text("tr\(i)_feed"); return n.isEmpty ? "ตู้หลัก" : n }
        let n = boards(i)[safe: k]?.name ?? ""
        return n.isEmpty ? "SDB \(k)" : n
    }

    func boardsRow(_ i: Int) -> some View {
        let bs = boards(i), isOpen = i == openIndex
        return HStack(alignment: .top, spacing: Self.boardGap) {
            ForEach(Array(bs.enumerated()), id: \.element.id) { k, b in
                if isOpen {
                    (k == 0 ? AnyView(mainBoardCard(i)) : AnyView(subBoardCard(i, k)))
                        .frame(width: k == 0 ? Self.mainW : Self.subW, height: Self.expandedH)
                } else {
                    miniBoardCard(i, k, b).frame(width: Self.miniW, height: Self.collapsedH)
                }
            }
            Group {
                if bs.count < Transformer.maxBoards {
                    Button { editBoards(i) { $0.append(Board(name: "SDB \($0.count)")) }; withAnimation { open = i } } label: {
                        Text("+ เพิ่มตู้").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                            .frame(width: Self.addW, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, isOpen ? 4 : 20)
        }
    }

    func miniBoardCard(_ i: Int, _ k: Int, _ b: Board) -> some View {
        A3Panel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(boardName(i, k)).font(.sarabunFixed(14, .bold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("ปลายสาย").font(.sarabunFixed(10, .bold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 6).frame(minHeight: 20).background(Theme.mint.opacity(0.4), in: Capsule())
                }
                HStack(spacing: 6) {
                    Text(b.at.isEmpty ? "—" : b.at).font(.sarabunFixed(16, .bold))
                    Text("AT").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 0)
                }
                Text("CB ย่อย \(breakerTotal(b.breakers))" + (sizeSummary(b.breakers).isEmpty ? "" : " | " + sizeSummary(b.breakers)))
                    .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { open = i } }
        .accessibilityAddTraits(.isButton)
    }

    // main board (k = 0)

    func mainBoardCard(_ i: Int) -> some View {
        let b = boards(i)[0]
        let shots = Self.mainPhotoSlots
        let have = shots.filter { job.values.photo("tr\(i)_\($0.key)") != nil }.count
        return A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    A3Badge(text: "MDB")
                    HStack(spacing: 6) {
                        TextField("MDP-1", text: mainName(i)).font(.sarabunFixed(18, .bold))
                        if a2Badges.contains(.boardName(i, 0)) { A2Badge() }
                    }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.3)))
                    Text("ตู้หลัก | ปลายสาย").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 10).frame(minHeight: 26).background(Theme.mint.opacity(0.4), in: Capsule())
                }
                (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "เมนเบรกเกอร์ (Main CB)", required: true)
                            A3Segments(options: ["ACB", "MCCB"], selected: b.mainType) { v in editBoards(i) { $0[0].mainType = v } }
                        }
                        if narrow { phoneMainBreakerFields(i, b) } else { mainBreakerFields(i, b) }
                        boardSLDButton(i, 0)
                        breakerList(i, 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            A3Label(text: "ภาพตู้หลัก", required: true)
                            Spacer(minLength: 0)
                            a3Chip("\(have)/4", ok: have == 4)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(Array(shots.enumerated()), id: \.offset) { n, s in
                                A3PhotoTile(photo: photoBinding("tr\(i)_\(s.key)"), jobID: job.id, label: "\(n + 1). \(s.label)", required: s.key == "mdbSpace", height: 104)
                                    .photoShot("tr\(i)_\(s.key)")
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "สภาพอุปกรณ์", required: true)
                            A3Segments(options: ["ดี", "พอใช้", "ชำรุด"], selected: b.condition) { v in editBoards(i) { $0[0].condition = v } }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            A3Label(text: "หมายเหตุสภาพ")
                            TextField("", text: bText(i, 0, \.conditionNote), axis: .vertical).lineLimit(2...3)
                                .inputBox(minHeight: 66, trailing: 10)
                        }
                        A3Input(label: "ตำแหน่งตู้", text: vText("tr\(i)_feedLoc"))
                    }
                    .frame(width: narrow ? nil : 258)
                }
            }
        }
    }

    /// The main breaker as typed boxes (iPhone).
    func phoneMainBreakerFields(_ i: Int, _ b: Board) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                A3Input(label: "AT (ตั้งตัด)", text: bText(i, 0, \.at, number: true), required: true, unit: "A", keyboard: .numberPad,
                        a2: a2Badges.contains(.boardAT(i, 0)))
                A3Input(label: "AF (เฟรม)", text: bText(i, 0, \.af, number: true), required: true, unit: "A", keyboard: .numberPad)
            }
            HStack(alignment: .bottom, spacing: 8) {
                A3Input(label: "Icu", text: bText(i, 0, \.icu, number: true), required: true, unit: "kA", keyboard: .decimalPad)
                VStack(alignment: .leading, spacing: 3) {
                    A3Label(text: "จำนวนขั้ว", required: true)
                    A3Segments(options: ["3P", "4P"], selected: b.poles) { v in editBoards(i) { $0[0].poles = v } }
                }
            }
            A3Input(label: "ยี่ห้อ / รุ่น", text: bText(i, 0, \.brand))
        }
    }

    /// `CB ลูกย่อย | แตะแถวเพื่อแก้` on iPhone; on iPad the board's longer hint at the right.
    @ViewBuilder var breakerListTitle: some View {
        if narrow {
            A3Label(text: "CB ลูกย่อย | แตะแถวเพื่อแก้")
        } else {
            HStack(spacing: 6) {
                A3Label(text: "CB ลูกย่อย")
                Spacer(minLength: 4)
                Text("แตะแถวเพื่อแก้ AT/AF/Icu/ยี่ห้อ/สภาพ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// iPad: the main board's breaker `e` is edited in a popover anchored to its row.
    func breakerPopover(_ e: BreakerEdit) -> Binding<Bool> {
        Binding(get: { !narrow && editBreaker?.id == e.id }, set: { if !$0 && editBreaker?.id == e.id { editBreaker = nil } })
    }

    /// The breaker editor of the row `n` (`BreakerSheet` in its popover style).
    func breakerEditor(_ e: BreakerEdit, number n: Int) -> some View {
        BreakerSheet(breaker: breakerBinding(e), isMain: e.board == 0, onDelete: { removeBreaker(e); editBreaker = nil },
                     number: n, popover: true)
            .presentationCompactAdaptation(.popover)
    }

    /// A row that opens its breaker: the sheet on iPhone (its texts read as they are); on iPad its popover, the row named
    /// `CB ลูกย่อย n` with its sizes as the value.
    @ViewBuilder func breakerRowButton(_ n: Int, _ br: Breaker, _ e: BreakerEdit) -> some View {
        let button = Button { editBreaker = e } label: { breakerRow(n, br) }.buttonStyle(.plain)
        if narrow {
            button
        } else {
            button
                .accessibilityLabel("CB ลูกย่อย \(n)")
                .accessibilityValue(breakerSummary(br))
                .popover(isPresented: breakerPopover(e), arrowEdge: .top) { breakerEditor(e, number: n) }
        }
    }

    /// Outgoing breakers of the main board: one row each, tap to edit.
    func breakerList(_ i: Int, _ k: Int) -> some View {
        let list = boards(i)[safe: k]?.breakers ?? []
        return VStack(alignment: .leading, spacing: 6) {
            breakerListTitle
            let rows = VStack(spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, br in
                    breakerRowButton(n + 1, br, BreakerEdit(id: br.id, trafo: i, board: k))
                }
            }
            // iPhone: the page scrolls, so the list takes its own height
            if narrow { rows } else { ScrollView { rows }.scrollIndicators(.hidden) }
            Button {
                let br = Breaker()
                editBoards(i) { $0[k].breakers.append(br) }
                editBreaker = BreakerEdit(id: br.id, trafo: i, board: k)
            } label: {
                Text("+ เพิ่ม CB ลูกย่อย").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// iPad: an empty AF reads as its อัตโนมัติ frame; nil on iPhone, which shows `?AF`.
    func shownAF(_ b: Breaker) -> String {
        if !b.af.isEmpty || narrow { return b.af }
        return A3Options.autoAF(at: b.at, frames: A3Options.subAF) ?? ""
    }

    /// "100AT/100AF | ?kA | ยี่ห้อ ?" for VoiceOver and UI tests.
    func breakerSummary(_ b: Breaker) -> String {
        let q = { (s: String, u: String) in s.isEmpty ? "?" + u : s + u }
        return q(b.at, "AT") + "/" + q(shownAF(b), "AF") + " | " + q(b.ic, "kA") + " | " + (b.brand.isEmpty ? "ยี่ห้อ ?" : b.brand)
    }

    func breakerRow(_ n: Int, _ b: Breaker) -> some View {
        func v(_ s: String, _ unit: String) -> Text { s.isEmpty ? Text("?" + unit).foregroundColor(Theme.danger).bold() : Text(s + unit) }
        let af = shownAF(b)
        // iPad: AF has its อัตโนมัติ value, so a row reads red only for a missing trip, Icu or brand
        let unknown = b.at.isEmpty || af.isEmpty || b.ic.isEmpty || b.brand.isEmpty
        let line1 = Text(b.poles.isEmpty ? "" : "\(b.poles)P | ") + v(b.at, "AT") + Text("/") + v(af, "AF") + Text(" | ") + v(b.ic, "kA")
        let line2 = [b.brand.isEmpty ? "ยี่ห้อ ?" : b.brand, b.target.isEmpty ? nil : "→ " + b.target].compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 8) {
            Text("\(n)").font(.sarabunFixed(13, .bold)).frame(width: 24, height: 24).background(Theme.primarySoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                line1.font(.sarabunFixed(13, .semibold)).lineLimit(1)
                Text(line2).font(.sarabunFixed(12)).foregroundStyle(b.brand.isEmpty ? Theme.danger : Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if b.spare { a3Chip("SPARE", ok: true) }
            if !b.condition.isEmpty { a3Chip(b.condition, ok: b.condition != "ชำรุด") }
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(unknown ? Theme.danger.opacity(0.7) : Theme.navy.opacity(0.2)))
        .contentShape(Rectangle())
    }

    // sub-board (k > 0)

    func subBoardCard(_ i: Int, _ k: Int) -> some View {
        let b = boards(i)[k]
        return A3Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    A3Badge(text: "SDB")
                    TextField("ชื่อตู้", text: bText(i, k, \.name)).font(.sarabunFixed(16, .bold)).lineLimit(1)
                        .padding(.horizontal, 8).frame(minHeight: 44)
                    Button { editBoards(i) { if $0.indices.contains(k) { $0.remove(at: k) } } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("ลบตู้")
                }
                A3Input(label: "เมนเบรกเกอร์", text: bText(i, k, \.at, number: true), required: true, unit: "AT", keyboard: .numberPad)
                HStack {
                    A3Label(text: "CB ลูกย่อย")
                    Spacer(minLength: 0)
                    Text("รวม \(breakerTotal(b.breakers)) ลูก").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                ForEach(b.breakers) { br in sizeRow(i, k, br) }
                Button { editBoards(i) { $0[k].breakers.append(Breaker()) } } label: {
                    Text("+ เพิ่มขนาด CB").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                A3Input(label: "ตำแหน่งตู้", text: bText(i, k, \.location))
                boardSLDButton(i, k)
                Spacer(minLength: 0)
                A3PhotoTile(photo: Binding(get: { boards(i)[safe: k]?.photos.first },
                                           set: { p in editBoards(i) { if $0.indices.contains(k) { $0[k].photos = p.map { [$0] } ?? [] } } }),
                            jobID: job.id, label: "ภาพตู้ (ไม่บังคับ)", height: 84)
            }
        }
    }

    /// "100 A × [− 2 +]": breakers of one size.
    func sizeRow(_ i: Int, _ k: Int, _ br: Breaker) -> some View {
        func set(_ body: @escaping (inout Breaker) -> Void) {
            editBoards(i) { b in if b.indices.contains(k), let n = b[k].breakers.firstIndex(where: { $0.id == br.id }) { body(&b[k].breakers[n]) } }
        }
        return HStack(spacing: 4) {
            TextField("", text: Binding(get: { br.at }, set: { v in set { $0.at = NumberInput.clean(v) } })).keyboardType(.numberPad)
                .frame(width: 44).multilineTextAlignment(.trailing)
            Text("A ×").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            stepper("minus") {
                editBoards(i) { b in
                    guard b.indices.contains(k), let n = b[k].breakers.firstIndex(where: { $0.id == br.id }) else { return }
                    if b[k].breakers[n].count <= 1 { b[k].breakers.remove(at: n) } else { b[k].breakers[n].count -= 1 }
                }
            }
            Text("\(max(br.count, 1))").font(.sarabunFixed(15, .bold)).frame(minWidth: 18)
            stepper("plus") { set { $0.count = max($0.count, 1) + 1 } }
        }
        .padding(.leading, 8).frame(maxWidth: .infinity, minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.3)))
    }

    func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary).frame(width: 34, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "เพิ่ม" : "ลด")
    }
}
#endif
