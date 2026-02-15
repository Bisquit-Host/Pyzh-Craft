import SwiftUI

/// Language manager
/// Only responsible for language list and bundle
public class LanguageManager {
    private static let appleLanguagesKey = "AppleLanguages"

    /// The currently selected language (take the first one in the AppleLanguages ​​array)
    public var selectedLanguage: String {
        get {
            UserDefaults.standard.stringArray(forKey: Self.appleLanguagesKey)?.first ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.set([String](), forKey: Self.appleLanguagesKey)
            } else {
                var langs = UserDefaults.standard.stringArray(forKey: Self.appleLanguagesKey) ?? []
                langs.removeAll { $0 == newValue }
                langs.insert(newValue, at: 0)
                UserDefaults.standard.set(langs, forKey: Self.appleLanguagesKey)
            }
        }
    }

    /// Singleton instance
    public static let shared = LanguageManager()

    private init() {
        // If it is the first startup (selectedLanguage is empty), the default language is set according to the system language
        if selectedLanguage.isEmpty {
            selectedLanguage = Self.getDefaultLanguage()
        }
    }

    /// Supported language list
    public let languages: [(String, String)] = [
        ("🇨🇳 简体中文", "zh-Hans"),
        ("🇨🇳 繁體中文", "zh-Hant"),
        // ("🇸🇦 العربية", "ar"),
        ("🇩🇰 Dansk", "da"),
        ("🇩🇪 Deutsch", "de"),
        ("🇺🇸 English", "en"),
        ("🇪🇸 Español", "es"),
        ("🇫🇮 Suomi", "fi"),
        ("🇫🇷 Français", "fr"),
        ("🇮🇳 हिन्दी", "hi"),
        ("🇮🇹 Italiano", "it"),
        ("🇯🇵 日本語", "ja"),
        ("🇰🇷 한국어", "ko"),
        ("🇳🇴 Norsk Bokmål", "nb"),
        ("🇳🇱 Nederlands", "nl"),
        ("🇵🇱 Polski", "pl"),
        ("🇵🇹 Português", "pt"),
        ("🇷🇺 Русский", "ru"),
        ("🇸🇪 Svenska", "sv"),
        ("🇹🇭 ไทย", "th"),
        ("🇹🇷 Türkçe", "tr"),
        ("🇻🇳 Tiếng Việt", "vi"),
    ]

    /// Get the Bundle of the current language
    public var bundle: Bundle {
        if let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    public static func getDefaultLanguage() -> String {

        let preferredLanguages = Locale.preferredLanguages

        for preferredLanguage in preferredLanguages {
            // Handle language code matching
            let languageCode = preferredLanguage.prefix(2).lowercased()

            switch languageCode {
            case "zh":
                // Chinese: Simplified Chinese first, then Traditional Chinese
                if preferredLanguage.contains("Hans") || preferredLanguage.contains("CN") {
                    return "zh-Hans"
                } else if preferredLanguage.contains("Hant") || preferredLanguage.contains("TW") || preferredLanguage.contains("HK") {
                    return "zh-Hant"
                } else {
                    // Default Simplified Chinese
                    return "zh-Hans"
                }
            case "ar": return "ar"
            case "da": return "da"
            case "de": return "de"
            case "en": return "en"
            case "es": return "es"
            case "fi": return "fi"
            case "fr": return "fr"
            case "hi": return "hi"
            case "it": return "it"
            case "ja": return "ja"
            case "ko": return "ko"
            case "nb", "no": return "nb"  // Norwegian
            case "nl": return "nl"
            case "pl": return "pl"
            case "pt": return "pt"
            case "ru": return "ru"
            case "sv": return "sv"
            case "th": return "th"
            case "tr": return "tr"
            case "vi": return "vi"
            default:
                continue
            }
        }

        // If the system language is not supported, English will be used by default
        return "en"
    }
}

// MARK: - String Localization Extension

extension String {
    /// Get localized string
    /// - Parameter bundle: language pack, using the current language by default
    /// - Returns: localized string
    public func localized(
        _ bundle: Bundle = LanguageManager.shared.bundle
    ) -> String {
        bundle.localizedString(forKey: self, value: self, table: nil)
    }
}
