import SwiftUI
import TCRoofUI
import TCRoofCore

// The right column (docs/ui/weekly-request-ipad-map §4.4): the week row with the week list and the working time, the
// week's team as the daily report's dropdown rows, and the requester's sign card.

extension WeeklyRequestOnePage {
    var rightColumn: some View {
        VStack(spacing: 12) {
            AnyView(weekRow)
            AnyView(teamCard)
            AnyView(signCard)
        }
    }

    func popBinding(_ p: Pop) -> Binding<Bool> {
        Binding(get: { pop == p }, set: { open in
            if open { pop = p } else if pop == p { pop = nil }
        })
    }

    // MARK: week row

    private var weekRow: some View {
        HStack(spacing: 6) {
            weekStep(-1, icon: "chevron.left", label: "สัปดาห์ก่อน")
            weekButton
            weekStep(1, icon: "chevron.right", label: "สัปดาห์ถัดไป")
            timeChip
        }
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .popover(isPresented: popBinding(.weeks), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            weekList.presentationCompactAdaptation(.popover)
        }
        .background {
            Color.clear.popover(isPresented: popBinding(.time), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                DailyWorkTimePopover(report: workDay, date: request.weekStart, close: { pop = nil }, weather: nil,
                                     title: "สัปดาห์ที่ \(weekNumber)", summary: "ทำงาน \(workHours) ชม. ต่อวัน")
                    .presentationCompactAdaptation(.popover)
                    .disabled(!editable)
            }
        }
    }

    private func weekStep(_ step: Int, icon: String, label: String) -> some View {
        Button { actions.week(step) } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(step < 0 ? "requestWeekBack" : "requestWeekOn")
    }

    private var weekButton: some View {
        let open = pop == .weeks
        return Button { pop = open ? nil : .weeks } label: {
            HStack(spacing: 6) {
                Text("สัปดาห์ที่ \(weekNumber)").font(.sarabunFixed(17, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8))
            }
            .foregroundStyle(open ? Theme.onPrimary : Theme.navy)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(open ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("สัปดาห์ที่ \(weekNumber)")
        .accessibilityHint("เลือกสัปดาห์")
        .accessibilityIdentifier("requestWeek")
    }

    /// The working time shown: the request's own, else the station's.
    var workStartMinutes: Int { request.workStart ?? settings.workStart }
    var workEndMinutes: Int { request.workEnd ?? settings.workEnd }
    var workHours: Int { max(workEndMinutes - workStartMinutes, 0) / 60 }

    private var timeChip: some View {
        let open = pop == .time
        let time = Self.clock(workStartMinutes) + "–" + Self.clock(workEndMinutes)
        return Button { pop = open ? nil : .time } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("เวลาทำงาน").font(.sarabunFixed(11))
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6))
                }
                .foregroundStyle(open ? Theme.onPrimary.opacity(0.85) : Theme.inkMuted)
                Text(time).font(.sarabunFixed(15, .bold)).monospacedDigit()
                    .foregroundStyle(open ? Theme.onPrimary : Theme.navy)
            }
            .padding(.horizontal, 12).frame(height: 48)
            .background(open ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เวลาทำงาน")
        .accessibilityValue(time)
        .accessibilityIdentifier("requestWorkTime")
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// The daily report's working-time popover edits a day; this one hands it the request's hours and takes them back.
    private var workDay: Binding<RoutineReport.Daily> {
        Binding(get: {
            var d = RoutineReport.Daily(date: request.weekStart)
            d.workStart = RoutineReport.WorkHours.text(workStartMinutes / 60)
            d.workEnd = RoutineReport.WorkHours.text(workEndMinutes / 60)
            return d
        }, set: { d in
            request.workStart = (RoutineReport.hour(d.workStart) ?? 8) * 60
            request.workEnd = (RoutineReport.hour(d.workEnd) ?? 17) * 60
        })
    }

    /// Next week and the two before, each with its request's state.
    private var weekList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("เลือกสัปดาห์").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).padding(.horizontal, 6).padding(.bottom, 4)
            ForEach(weeks) { w in
                let r = RoutineReport.WeeklyRequest(weekStart: w.start)
                let on = r.id == request.id
                Button { pop = nil; actions.openWeek(w.start) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("สัปดาห์ที่ \(WeeklyRequestScreen.weekNumber(r))").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                            Text(Self.rangeText(r)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 8)
                        weekChip(w.status)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 56)
                    .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(Theme.surface)
    }

    private func weekChip(_ s: RoutineReport.WeeklyRequest.Status?) -> some View {
        let (text, ink, fill): (String, Color, Color) = switch s {
        case .approved: ("อนุมัติแล้ว", Theme.successText, Theme.successSoft)
        case .sent: ("ส่งแล้ว รออนุมัติ", Theme.warningText, Theme.warningSoft)
        case .draft: ("ร่าง", Theme.primary, Theme.primarySoft)
        case nil: ("ยังไม่เริ่ม", Theme.inkMuted, Theme.segmentTrack)
        }
        return Text(text).font(.sarabunFixed(12.5, .bold)).foregroundStyle(ink)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(fill, in: Capsule())
    }

    // MARK: team

    private var activeDays: [Int] { workingDays.filter { request.hasWork($0) } }

    private var teamCard: some View {
        let tools = request.tools.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ทีมงานสัปดาห์นี้").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer(minLength: 8)
                Text("\(request.perDay) คน เครื่องมือ \(request.tools.count) รายการ").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 8) {
                labourTile("แรงงานทั้งสัปดาห์", "\(request.manDays(days: workingDays)) คน·วัน", "\(request.perDay) คน × \(activeDays.count) วัน")
                labourTile("วันที่มีงาน", "\(activeDays.count) วัน", activeDays.isEmpty ? "ยังไม่เลือกวัน" : Self.dayNames(activeDays))
            }
            TCCountSegments([.init("คน", count: request.perDay), .init("เครื่องมือ", count: tools)],
                            selection: $teamTab, fontSize: 14, countSize: 13)
            ScrollView {
                if teamTab == 0 {
                    DailyCountRows(counts: crew, catalogue: settings.roles, unit: "คน", addTitle: "+ เพิ่มตำแหน่ง")
                } else {
                    DailyCountRows(counts: $request.tools, catalogue: settings.tools, unit: "ชิ้น", addTitle: "+ เพิ่มเครื่องมือ")
                }
            }
            .disabled(!editable)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .dailyCard()
    }

    /// The crew rows: a role taken out also takes its days off with it (`removeCrew`), which `crewOff` keeps.
    private var crew: Binding<[RoutineReport.Count]> {
        Binding(get: { request.crew }, set: { new in
            let ids = Set(new.map(\.id))
            if new.count == request.crew.count - 1, let i = request.crew.firstIndex(where: { !ids.contains($0.id) }) {
                request.removeCrew(at: i)
            } else {
                request.crew = new
            }
        })
    }

    private func labourTile(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
            Text(sub).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: sign

    private var signCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                Text("ลงนามผู้รายงาน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Text("*").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.danger)
                Spacer(minLength: 8)
                Text("SITE ENGINEER").font(.sarabunFixed(11.5, .bold)).tracking(0.8).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.primarySoft, in: Capsule())
            }
            Group {
                if let signature { signedBox(signature) } else { idleBox }
            }
            .frame(height: 160)
            VStack(alignment: .leading, spacing: 4) {
                Text("ชื่อผู้ลงนาม").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                TextField("ชื่อ Site Engineer ผู้รับเหมา", text: engineerName)
                    .font(.sarabunFixed(17)).multilineTextAlignment(.center)
                    .textFieldStyle(OutlinedFieldStyle(dense: true))
                    .frame(minHeight: 48)
                    .disabled(!editable || demo)
            }
        }
        .padding(16)
        .dailyCard()
    }

    /// The station's site engineer, as the daily report's sign card names them.
    private var engineerName: Binding<String> {
        Binding(get: { demo ? settings.siteEngineer : job.routineSettings.siteEngineer }, set: { v in
            var s = job.routineSettings
            s.siteEngineer = v
            job.routineSettings = s
        })
    }

    private func signLine(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint).padding(.leading, 2)
            Rectangle().fill(color).frame(height: 1)
        }
        .padding(.horizontal, 18).padding(.bottom, 36)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var idleBox: some View {
        Button(action: actions.sign) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                signLine(Theme.borderOutdoor)
                VStack(spacing: 2) {
                    Image(systemName: "signature").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text("แตะเพื่อเซ็น").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                    Text("เซ็นบนเส้นด้านล่าง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.bottom, 30)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel("ผู้รายงาน แตะเพื่อเซ็น")
        .accessibilityIdentifier("requestSignBox")
    }

    private func signedBox(_ s: Signature) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.successSoft)
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.success, lineWidth: 1)
            signLine(Theme.success.opacity(0.45))
            Group {
                if let image = UIImage(data: s.png) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 80)
                } else {
                    Text(settings.siteEngineer).font(.sarabunFixed(22, .bold)).italic().foregroundStyle(Theme.navy)
                }
            }
            .padding(.bottom, 40)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .accessibilityLabel("ลายเซ็น " + settings.siteEngineer)
        }
        .overlay(alignment: .topLeading) {
            Label("เซ็นแล้ว " + ThaiFormat.time.string(from: s.at), systemImage: "checkmark")
                .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successText)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.success.opacity(0.14), in: Capsule())
                .padding(10)
                .accessibilityIdentifier("requestSigned")
        }
        .overlay(alignment: .topTrailing) {
            if editable {
                Button(action: actions.clearSignature) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างลายเซ็นผู้รายงาน")
            }
        }
    }
}
