import Foundation

/// The bundled reference data: module catalog, mounting profiles and rule set, each with its version. A record keeps
/// the versions it was validated against, so an old report re-opens with the rules it was signed under.
public enum ModuleCatalog {
    struct CatalogFile: Codable { var version: String; var source: String; var models: [ModuleModel] }
    struct ProfilesFile: Codable { var version: String; var profiles: [MountingProfile] }
    struct RulesFile: Codable { var version: String; var rules: [RuleSpec] }

    static func load<T: Decodable>(_ name: String, as: T.Type) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { fatalError("ModuleRules: \(name).json is missing from the bundle") }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { fatalError("ModuleRules: \(name).json: \(error)") }
    }

    private static let catalog = load("module-catalog", as: CatalogFile.self)
    private static let profilesFile = load("mounting-profiles", as: ProfilesFile.self)
    private static let rulesFile = load("rule-set", as: RulesFile.self)

    public static var version: String { catalog.version }
    public static var models: [ModuleModel] { catalog.models }
    public static func model(_ id: String) -> ModuleModel? { catalog.models.first { $0.id == id } }

    public static var profilesVersion: String { profilesFile.version }
    public static var profiles: [MountingProfile] { profilesFile.profiles }
    public static func profile(_ m: MountingMethod) -> MountingProfile? { profilesFile.profiles.first { $0.method == m } }

    public static var ruleSetVersion: String { rulesFile.version }
    public static var rules: [RuleSpec] { rulesFile.rules }
    public static func rule(_ id: String) -> RuleSpec? { rulesFile.rules.first { $0.id == id } }
}
