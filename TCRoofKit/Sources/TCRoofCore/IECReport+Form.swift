import Foundation

/// Reads a report written in the form's own JSON (docs/forms/iec62446-pwa/form-schema.json), such as the
/// แพรกหนามแดง sample taken from the PWA's filled Excel and Word. Values the form keeps as text (`"pass"`,
/// `"normal"`) become the app's types; calculated values (kWp, Yf, PR, efficiency) are dropped, the app derives them.
public extension IECReport {
    init(form data: Data) throws {
        let f = try JSONDecoder().decode(Form.self, from: data)
        self.init(stationLine: f.site?.titleLine ?? f.site?.name ?? "",
                  module: .init(brand: f.module?.brand ?? "", powerW: f.module?.powerW ?? 0, areaM2: f.module?.areaM2),
                  inverters: (f.inverters ?? []).map { inv in
                      var slots = [Slot?](repeating: nil, count: IECReport.slotCount)
                      for s in inv.strings ?? [] where (1...IECReport.slotCount).contains(s.slot) {
                          slots[s.slot - 1] = Slot(modules: s.moduleCount ?? 0, brand: s.moduleBrand, optimizers: s.optimizerCount,
                                                   polarityOK: s.before?.polarity.map { $0 == "pass" }, irTestV: s.before?.irTestVoltageV,
                                                   irPosMOhm: s.before?.irPositiveEarthMOhm, irNegMOhm: s.before?.irNegativeEarthMOhm,
                                                   vocV: s.before?.voltageV, iBeforeA: s.before?.currentA,
                                                   vmpV: s.after?.voltageV, impA: s.after?.currentA)
                      }
                      return Inverter(ratedKW: inv.ratedKW ?? 0, serial: inv.serial ?? "", slots: slots,
                                      continuity: inv.before?.continuity.flatMap(Check.init), functionalBefore: inv.before?.inverterFunctional.flatMap(Check.init),
                                      functionalAfter: inv.after?.inverterFunctional.flatMap(Check.init), energy7dKWh: inv.after?.sevenDayEnergyKWh,
                                      remark: inv.after?.remark ?? "")
                  },
                  before: .init(ambientC: f.conditions?.before?.ambientC, irradianceWm2: f.conditions?.before?.irradianceWm2, time: f.conditions?.before?.time),
                  after: .init(ambientC: f.conditions?.after?.ambientC, irradianceWm2: f.conditions?.after?.irradianceWm2, time: f.conditions?.after?.time),
                  yrKWhM2Day: f.conditions?.after?.avgIrradiationKWhM2Day, arrayTempC: f.conditions?.after?.arrayTempC,
                  testDate: f.testDate.flatMap(Self.formDate), tester: f.tester ?? "")
        if let i = f.instruments {
            instruments.multimeterClamp = i.multimeterClamp ?? ""
            instruments.insulationTester = i.insulationTester ?? ""
            instruments.irradianceMeter = i.irradianceMeter ?? ""
            instruments.thermalCamera = i.thermalCamera ?? ""
        }
    }

    private static func formDate(_ s: String) -> Date? {
        let n = s.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return MasterSchedule.calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
    }
}

/// The form JSON, only as far as the app reads it.
private struct Form: Decodable {
    struct Site: Decodable { var name: String?; var titleLine: String? }
    struct Module: Decodable { var brand: String?; var powerW: Double?; var areaM2: Double? }
    struct Instruments: Decodable { var multimeterClamp, insulationTester, irradianceMeter, thermalCamera: String? }
    struct Phase: Decodable {
        var ambientC: Double?; var irradianceWm2: Double?; var time: String?
        var avgIrradiationKWhM2Day: Double?; var arrayTempC: Double?
    }
    struct Conditions: Decodable { var before: Phase?; var after: Phase? }
    struct InvBefore: Decodable { var continuity: String?; var inverterFunctional: String? }
    struct InvAfter: Decodable { var inverterFunctional: String?; var sevenDayEnergyKWh: Double?; var remark: String? }
    struct StrBefore: Decodable {
        var polarity: String?; var irTestVoltageV: Int?; var irPositiveEarthMOhm: Double?; var irNegativeEarthMOhm: Double?
        var voltageV: Double?; var currentA: Double?
    }
    struct StrAfter: Decodable { var voltageV: Double?; var currentA: Double? }
    struct Str: Decodable {
        var slot: Int; var moduleBrand: String?; var moduleCount: Int?; var optimizerCount: Int?
        var before: StrBefore?; var after: StrAfter?
    }
    struct Inv: Decodable {
        var ratedKW: Double?; var serial: String?; var before: InvBefore?; var after: InvAfter?; var strings: [Str]?
    }
    var site: Site?
    var module: Module?
    var testDate: String?
    var tester: String?
    var instruments: Instruments?
    var conditions: Conditions?
    var inverters: [Inv]?
}
