#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// A3 on iPhone: the power-flow diagram as one column of cards — meter, then each transformer with its boards —
/// joined by a blue line, in one scroll. The cards are the iPad's, laid out one field row at a time (`narrow`).
extension ElectricalPageWide {
    var phoneBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    PageStepBar(job: job, here: .electrical, compact: true, chip: job.stepChip(.electrical))
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text("ผังการจ่ายไฟ").font(.sarabunFixed(19, .bold)).lineLimit(1)
                            Spacer(minLength: 4)
                            diagramButton
                        }
                        a2Button.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        meterCard.padding(.top, 12)
                        ForEach(Array(trafos.indices), id: \.self) { i in
                            link
                            transformerView(i).id(i)
                            link
                            phoneBoards(i)
                        }
                        link
                        addTransformerButton.frame(height: 56)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: scrollTarget) { _, i in
                guard let i else { return }
                scrollTarget = nil
                withAnimation { proxy.scrollTo(i, anchor: .top) }
            }
            #if DEBUG
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "surveyScrollEnd") ? .bottom : .top)
            #endif
        }
    }

    /// The diagram's connecting line, between two cards.
    var link: some View {
        Rectangle().fill(Theme.primary).frame(width: 2, height: 14).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
            .accessibilityHidden(true)
    }

    /// Transformer `i`'s boards one above the other: the main board and the sub-boards open, folded summaries otherwise.
    func phoneBoards(_ i: Int) -> some View {
        let bs = boards(i), isOpen = i == openIndex
        return VStack(spacing: 10) {
            ForEach(Array(bs.enumerated()), id: \.element.id) { k, b in
                if isOpen {
                    if k == 0 { mainBoardCard(i) } else { subBoardCard(i, k) }
                } else {
                    miniBoardCard(i, k, b)
                }
            }
            if bs.count < Transformer.maxBoards {
                Button { editBoards(i) { $0.append(Board(name: "SDB \($0.count)")) }; withAnimation { open = i } } label: {
                    Text("+ เพิ่มตู้").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif
