import Foundation

/// Reads PVsyst .PAN module files (text format, PVsyst 6/7) into `PVModuleSpec`.
///
/// Format: `Key=Value` lines nested by `PVObject_…=` / `End of …` blocks, Windows line
/// endings, usually Windows-1252. Protected (binary/encrypted) PAN files cannot be read;
/// ask the manufacturer for an unprotected export or fall back to `DatasheetFitter`.
public enum PANParser {
    public enum ParseError: Error, Equatable {
        case notText
        case protectedOrBinary
        case notAModuleFile
        case missingKey(String)
        case invalidNumber(key: String, value: String)
    }

    public static func parse(data: Data, id: String? = nil) throws -> PVModuleSpec {
        if data.contains(0) { throw ParseError.protectedOrBinary }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else { throw ParseError.notText }
        return try parse(text: text, id: id)
    }

    public static func parse(text: String, id: String? = nil) throws -> PVModuleSpec {
        let doc = PANDocument(text: text)
        guard doc.rootType == "pvModule" else { throw ParseError.notAModuleFile }

        let m = doc.values(at: ["pvModule"])
        let c = doc.values(at: ["pvModule", "pvCommercial"])

        func num(_ key: String, _ dict: [String: String]) throws -> Double {
            guard let raw = dict[key] else { throw ParseError.missingKey(key) }
            guard let v = Double(raw.replacingOccurrences(of: ",", with: ".")) else {
                throw ParseError.invalidNumber(key: key, value: raw)
            }
            return v
        }
        func opt(_ key: String, _ dict: [String: String]) -> Double? {
            dict[key].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }

        let manufacturer = c["Manufacturer"] ?? "Unknown"
        let model = c["Model"] ?? "Unknown"
        let rsh = try num("RShunt", m)

        let stc = STCRatings(
            pNomW: try num("PNom", m), vmpV: try num("Vmp", m), impA: try num("Imp", m),
            vocV: try num("Voc", m), iscA: try num("Isc", m),
            toleranceMinusPercent: opt("PNomTolLow", m), tolerancePlusPercent: opt("PNomTolUp", m))
        let tc = TemperatureCoefficients(
            muIscAPerK: try num("muISC", m) / 1000,        // mA/K → A/K
            // mV/K → V/K; 0 when the file has none: `StringSizing` then takes the cold Voc from the model
            muVocVPerK: (opt("muVocSpec", m) ?? 0) / 1000,
            muPmpPercentPerK: opt("muPmpReq", m) ?? 0)
        let cells = CellLayout(cellsInSeries: Int(try num("NCelS", m)),
                               cellsInParallel: Int(opt("NCelP", m) ?? 1),
                               bypassDiodes: opt("NDiode", m).map(Int.init))
        let diode = OneDiodeParameters(
            rSeriesOhm: try num("RSerie", m), rShuntRefOhm: rsh,
            rShunt0Ohm: opt("Rp_0", m) ?? 4 * rsh, rShuntExp: opt("Rp_Exp", m) ?? 5.5,
            gammaRef: try num("Gamma", m), muGammaPerK: opt("muGamma", m) ?? 0)

        var dims: Dimensions?
        if let w = opt("Width", c), let h = opt("Height", c) { dims = Dimensions(widthM: w, heightM: h, depthM: opt("Depth", c)) }

        let iam = doc.points(under: ["pvModule", "pvIAM"])

        return PVModuleSpec(
            id: id ?? slug("\(manufacturer)-\(model)"),
            manufacturer: manufacturer, model: model,
            technology: technology(m["Technol"]),
            source: .pan, stc: stc, temperatureCoefficients: tc, cells: cells, oneDiode: diode,
            dimensions: dims, bifaciality: opt("BifacialityFactor", m),
            lidPercent: opt("LIDLoss", m), iamProfile: iam.isEmpty ? nil : iam,
            maxSystemVoltageV: opt("VMaxIEC", m))
    }

    static func technology(_ raw: String?) -> CellTechnology {
        switch raw {
        case "mtSiMono": return .monoSi
        case "mtSiPoly": return .polySi
        case "mtHIT": return .hit
        case "mtCdTe": return .cdTe
        case "mtCIS": return .cigs
        case "mtAmorphous", "mtTandem", "mtTriple": return .aSi
        default: return .other
        }
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return s.lowercased().unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
    }
}

/// Minimal tree reader for PVsyst PAN/OND text: tracks the block path for each key.
struct PANDocument {
    private(set) var rootType: String?
    /// "pvModule/pvCommercial" → [key: value]
    private var blocks: [String: [String: String]] = [:]
    /// Ordered `Point_n=x,y` entries per block path.
    private var pointLists: [String: [IAMPoint]] = [:]

    init(text: String) {
        var path: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("End of ") {
                if !path.isEmpty { path.removeLast() }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("PVObject_") {
                if path.isEmpty { rootType = value }
                path.append(value)
                continue
            }
            // Nested profile objects, e.g. "IAMProfile=TCubicProfile" … "End of TCubicProfile".
            if value.hasPrefix("T"), value.hasSuffix("Profile") {
                path.append(value)
                continue
            }
            let joined = path.joined(separator: "/")
            if key.hasPrefix("Point_") {
                let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 2 {
                    pointLists[joined, default: []].append(IAMPoint(angleDeg: parts[0], factor: parts[1]))
                }
                continue
            }
            blocks[joined, default: [:]][key] = value
        }
    }

    func values(at path: [String]) -> [String: String] {
        blocks[path.joined(separator: "/")] ?? [:]
    }

    /// All points in blocks at or below `path`, sorted by angle.
    func points(under path: [String]) -> [IAMPoint] {
        let prefix = path.joined(separator: "/")
        return pointLists.filter { $0.key == prefix || $0.key.hasPrefix(prefix + "/") }
            .flatMap(\.value).sorted { $0.angleDeg < $1.angleDeg }
    }
}
