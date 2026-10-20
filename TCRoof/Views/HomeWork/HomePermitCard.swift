import SwiftUI
import TCRoofUI
import TCRoofCore

/// ขออนุญาต | กฟภ.: the five steps with PEA for the job's route (ผลิตใช้เอง / ขายไฟ), who acts at each, and PEA's time
/// limits. A step is done when the documents that close it are in (`HomeJob.permitSteps`).
struct HomePermitCard: View {
    let home: HomeJob

    var body: some View {
        let steps = home.permitSteps
        let current = steps.firstIndex { $0.state == .current }
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ขออนุญาต | กฟภ. (PEA)").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    Text(home.mode == .sell ? "ขายไฟส่วนเกิน (ภาคประชาชน 2569)" : "ผลิตใช้เอง ไม่ขายไฟ")
                        .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: Space.s)
                Text(current.map { "ขั้น \($0 + 1) / \(steps.count)" } ?? "ครบทุกขั้น")
                    .font(.sarabun(13, .semibold, relativeTo: .caption))
                    .foregroundStyle(current == nil ? Theme.okText : Theme.inkMuted)
            }
            HStack(spacing: 4) {
                ForEach(steps) { s in Capsule().fill(barColor(s.state)).frame(height: 6) }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in row(i, s) }
            }
            Text(home.permitNote)
                .font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.l)
    }

    private func row(_ i: Int, _ s: HomePermitStep) -> some View {
        HStack(spacing: Space.m) {
            ZStack {
                Circle().fill(dotFill(s.state))
                if s.state == .done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else {
                    Text("\(i + 1)").font(.sarabun(13, .bold, relativeTo: .caption))
                }
            }
            .foregroundStyle(dotText(s.state))
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.sarabun(15, s.state == .current ? .bold : .regular, relativeTo: .body))
                    .foregroundStyle(s.state == .current ? Theme.primary : Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.who).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Text(statusText(s))
                .font(.sarabun(13, s.state == .current ? .semibold : .regular, relativeTo: .caption))
                .foregroundStyle(s.state == .done ? Theme.okText : s.state == .current ? Theme.primary : Theme.inkMuted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .frame(minHeight: touchMin)
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ s: HomePermitStep) -> String {
        switch s.state {
        case .done: "เสร็จ"
        case .current: s.limit.isEmpty ? "กำลังดำเนินการ" : "กำลังดำเนินการ | \(s.limit)"
        case .todo: s.limit.isEmpty ? "—" : s.limit
        }
    }

    private func barColor(_ state: HomePermitStep.State) -> Color {
        switch state {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .todo: Theme.borderSubtle
        }
    }

    private func dotFill(_ state: HomePermitStep.State) -> Color {
        switch state {
        case .done: Theme.okSoft
        case .current: Theme.primary
        case .todo: Theme.background
        }
    }

    private func dotText(_ state: HomePermitStep.State) -> Color {
        switch state {
        case .done: Theme.okText
        case .current: Theme.onPrimary
        case .todo: Theme.inkMuted
        }
    }
}
