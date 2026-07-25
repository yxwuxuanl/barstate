import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let userDefaultsKey = "BarState.appLanguage"

    public var id: String { rawValue }

    public static var storedPreference: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey) else {
            return .system
        }
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    public static let launchPreference = storedPreference

    public var displayName: String {
        switch self {
        case .system: L10n.string("language.system")
        case .simplifiedChinese: L10n.string("language.simplified_chinese")
        case .english: L10n.string("language.english")
        }
    }

    public var localizationIdentifier: String? {
        self == .system ? nil : rawValue
    }

    public func save() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        } else {
            UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
        }
    }
}

public enum L10n {
    public static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: locale,
            arguments: arguments
        )
    }

    public static func plural(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(string(key), Int64(count))
    }

    public static var locale: Locale {
        activeLanguageIdentifier.map(Locale.init(identifier:)) ?? Locale.current
    }

    private static let activeLanguageIdentifier =
        ProcessInfo.processInfo.environment["BARSTATE_LANGUAGE"]
            ?? AppLanguage.launchPreference.localizationIdentifier

    private static let bundle: Bundle = {
        let baseBundle: Bundle
        if let overridePath = ProcessInfo.processInfo.environment[
            "BARSTATE_RESOURCE_BUNDLE_PATH"
        ], let overrideBundle = Bundle(path: overridePath) {
            baseBundle = overrideBundle
        } else {
            #if SWIFT_PACKAGE
            baseBundle = Bundle.module
            #else
            baseBundle = Bundle.main
            #endif
        }

        if let language = activeLanguageIdentifier,
           let localizationPath = baseBundle.path(
               forResource: language,
               ofType: "lproj"
           ), let localizedBundle = Bundle(path: localizationPath)
        {
            return localizedBundle
        }
        return baseBundle
    }()
}
