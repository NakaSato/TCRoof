#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// E1 on iPad landscape (docs/ui/survey-e1): the verdict, remarks with on-device suggestions and the gaps on other pages
/// on the left; both signatures and the reviewer on the right. Binds to the existing `Schema.final` fields only, so
/// completion, the PDF and Excel are unchanged. iPad portrait and iPhone keep the schema form (`groupPage`).
struct FinalPageWide: View {
    @Binding var job: Job
    /// Width of the page's content.
    let width: CGFloat
    /// One scrolling column (free width under 1100 pt).
    var stacked = false
    /// "ไปที่หน้า ›" on a row of the gaps card.
    var open: (MissingGroup.Target) -> Void = { _ in }
    /// false for offscreen renders (`-surveyFinalRender`): ImageRenderer leaves scroll views blank.
    var scrolls = true
    @Environment(SurveyModel.self) var model
    @State var signingSurveyor = false
    @State var signingCustomer = false

    var v: Values { job.values }
    func set(_ id: String, _ value: FieldValue?) { job.values[id] = value }

    static let purple = Color(red: 0.357, green: 0.294, blue: 0.769)
    static let purpleText = Color(red: 0.416, green: 0.353, blue: 0.878)
    static let purpleSoft = Color(red: 0.945, green: 0.933, blue: 1.0)
    static let purpleFill = Color(red: 0.984, green: 0.980, blue: 1.0)
    static let okText = Color(red: 0.118, green: 0.482, blue: 0.271)
    static let hairline = Color(red: 0.933, green: 0.945, blue: 0.961)
    static let bodyText = Color(red: 0.231, green: 0.290, blue: 0.376)
    /// Selected colour and tint of each `Options.verdict` choice.
    static let verdictColors: [(Color, Color)] = [
        (Color(red: 0.180, green: 0.490, blue: 0.196), Color(red: 0.180, green: 0.490, blue: 0.196).opacity(0.12)),
        (Color(red: 0.698, green: 0.416, blue: 0.0), Color(red: 0.941, green: 0.549, blue: 0.0).opacity(0.13)),
        (Color(red: 0.851, green: 0.271, blue: 0.231), Color(red: 0.851, green: 0.271, blue: 0.231).opacity(0.12)),
    ]

    var leftWidth: CGFloat { max(320, (width - 28) / 3) }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .final, title: Schema.final.title)
            if stacked {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        left
                        right.frame(height: 760)
                    }
                    .padding(.bottom, 16)
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    // fits on one screen at 1366 × 1024; scrolls only if a shorter screen can't hold every row
                    Group {
                        if scrolls {
                            ScrollView { left.padding(.bottom, 8) }.scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
                        } else {
                            Color.clear.overlay(alignment: .top) { left }.clipped()
                        }
                    }
                    .frame(width: leftWidth)
                    right.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(Home.navy)
        #if DEBUG
        .task { await debugState() }
        #endif
    }

    #if DEBUG
    /// `-surveyE1 two|installable|notrec|alladded|empty|pad|pad2|cleared|complete` writes that state of
    /// docs/ui/survey-e1/states into the opened job (no taps in the simulator here).
    func debugState() async {
        guard let state = UserDefaults.standard.string(forKey: "surveyE1") else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let all = RemarkSuggestions.make(job: job)
        func verdict(_ i: Int) { set("verdict", .choice(Options.verdict[i], other: "")) }
        func remarks(_ n: Int) {
            let t = RemarkSuggestions.appending(Array(all.prefix(n)), to: "")
            set("remarks", t.isEmpty ? nil : .text(t))
        }
        switch state {
        case "two": verdict(1); remarks(2)
        case "installable": verdict(0); remarks(2)
        case "notrec": verdict(2); remarks(2)
        case "alladded": verdict(1); remarks(all.count)
        case "empty": verdict(1); remarks(0)
        case "pad": signingSurveyor = true
        case "pad2": signingCustomer = true
        case "cleared": verdict(1); remarks(2); set("surveyorSign", nil)
        case "complete":
            verdict(0); remarks(2)
            if v.text("customerName").isEmpty { set("customerName", .text("ผู้ประสานงาน")) }
        default: break
        }
    }
    #endif

    var left: some View {
        VStack(alignment: .leading, spacing: 16) {
            verdictField
            remarksField
            suggestions
            otherPages
        }
    }

    // MARK: verdict

    var verdictField: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("ผลการประเมินความเหมาะสมในการติดตั้ง ") + Text("*").foregroundColor(Home.danger)).font(.system(size: 16, weight: .bold))
            ForEach(Array(Options.verdict.enumerated()), id: \.offset) { i, option in verdictButton(i, option) }
        }
    }

    func verdictButton(_ i: Int, _ option: String) -> some View {
        let on = v.choice("verdict") == option, c = Self.verdictColors[i]
        return Button { set("verdict", .choice(option, other: "")) } label: {
            HStack(spacing: 8) {
                Circle().fill(on ? c.0 : Color.clear).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(on ? Color.clear : Home.navy.opacity(0.45), lineWidth: 1.5))
                Text(option).font(.system(size: 15, weight: .bold)).foregroundStyle(on ? c.0 : Home.navy)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? c.1 : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? c.0 : Home.navy.opacity(0.45), lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: remarks

    var remarks: String { v.text("remarks") }

    var remarksAside: (String, Color, Bool) {
        switch Options.verdict.firstIndex(of: v.choice("verdict") ?? "") {
        case 1?: return ("ระบุเงื่อนไขให้ครบ", Self.verdictColors[1].0, true)
        case 2?: return ("ระบุเหตุผล", Self.verdictColors[2].0, true)
        default: return ("ไม่บังคับ", Home.muted, false)
        }
    }

    var remarksField: some View {
        let aside = remarksAside
        let lines = remarks.split(whereSeparator: \.isNewline).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ความเห็น / เงื่อนไข / สิ่งที่ต้องแก้ไขก่อนติดตั้ง").font(.system(size: 16, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(aside.0).font(.system(size: 13, weight: aside.2 ? .bold : .regular)).foregroundStyle(aside.1).fixedSize()
            }
            TextEditor(text: Binding(get: { remarks }, set: { set("remarks", $0.isEmpty ? nil : .text($0)) }))
                .font(.system(size: 14.5)).lineSpacing(4).foregroundStyle(Home.navy)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .overlay(alignment: .topLeading) {
                    if remarks.isEmpty {
                        Text("พิมพ์ความเห็น หรือแตะข้อเสนอแนะด้านล่าง").font(.system(size: 14.5)).foregroundStyle(Home.muted)
                            .padding(.horizontal, 14).padding(.vertical, 12).allowsHitTesting(false)
                    }
                }
                .frame(height: lines > 2 ? 236 : 150)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.borderControl.opacity(0.6)))
                .accessibilityLabel("ความเห็น / เงื่อนไข / สิ่งที่ต้องแก้ไขก่อนติดตั้ง")
        }
    }

    // MARK: suggestions

    @ViewBuilder var suggestions: some View {
        let all = RemarkSuggestions.make(job: job)
        if !all.isEmpty {
            let rest = RemarkSuggestions.pending(all, remarks: remarks)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    A2Icon(name: "e1-ai-sparkle", fallback: "sparkle", size: 15).foregroundStyle(Self.purple)
                    Text("ข้อเสนอแนะอัตโนมัติจาก AI").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.purple)
                    Text("· บนเครื่อง").font(.system(size: 13)).foregroundStyle(Home.muted)
                    Spacer(minLength: 4)
                    if rest.count >= 2 {
                        Button { add(rest) } label: {
                            Text("เพิ่มทั้งหมด").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.purple)
                                .padding(.horizontal, 10).frame(minHeight: 36)
                                .background(Self.purpleSoft, in: RoundedRectangle(cornerRadius: 8))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 44)
                ForEach(rest) { s in suggestionRow(s) }
                if rest.isEmpty {
                    Text("✓ ใส่ข้อเสนอแนะครบแล้ว · แก้ข้อความในช่องได้").font(.system(size: 13)).foregroundStyle(Self.okText)
                }
            }
            .padding(.top, -10)
        }
    }

    func add(_ list: [RemarkSuggestion]) {
        let text = RemarkSuggestions.appending(list, to: remarks)
        set("remarks", text.isEmpty ? nil : .text(text))
    }

    func suggestionRow(_ s: RemarkSuggestion) -> some View {
        Button { add([s]) } label: {
            HStack(spacing: 10) {
                (Text(s.text + " ") + Text(s.source).bold().foregroundColor(Self.purpleText))
                    .font(.system(size: 13.5)).foregroundStyle(Home.navy).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                Text("+ เพิ่ม").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.purple).fixedSize()
            }
            .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 4)
            .frame(minHeight: 48)
            .background(Self.purpleFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Self.purpleText.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.text + " จากหน้า " + s.source)
        .accessibilityHint("แตะเพื่อเพิ่มในความเห็น")
    }

    // MARK: gaps on other pages

    @ViewBuilder var otherPages: some View {
        let groups = FinalSummary.otherPages(job)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ยังขาดในหน้าอื่น").font(.system(size: 16, weight: .bold))
                    Spacer(minLength: 8)
                    Text("ส่งออกได้ แต่จะยังไม่ครบ").font(.system(size: 13)).foregroundStyle(Home.muted)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
                ForEach(groups.prefix(4)) { g in gapRow(g) }
                if groups.count > 4 {
                    Text("และอีก \(groups.count - 4) หน้า").font(.system(size: 13)).foregroundStyle(Home.muted)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Self.hairline).frame(height: 1) }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
        }
    }

    func gapRow(_ g: MissingGroup) -> some View {
        HStack(spacing: 10) {
            Text(FinalSummary.code(g)).font(.system(size: 14, weight: .bold)).frame(minWidth: 30, alignment: .leading).fixedSize()
            Text(g.items.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(Self.bodyText).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { open(g.target) } label: {
                Text("ไปที่หน้า ›").font(.system(size: 14, weight: .semibold)).fixedSize()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ไปที่หน้า " + g.title)
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 2)
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Rectangle().fill(Self.hairline).frame(height: 1) }
    }
}
#endif
