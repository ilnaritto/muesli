import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    static func resolved(_ raw: String) -> AppLanguage {
        AppLanguage(rawValue: raw) ?? .system
    }

    var label: String {
        switch self {
        case .system: return tr("System", "Как в системе")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

@Observable
final class L10n {
    static let shared = L10n()

    var language: AppLanguage = .system

    var isRussian: Bool {
        switch language {
        case .russian:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
        }
    }
}

/// Returns the Russian string when the app language resolves to Russian,
/// otherwise the English string. Reading `L10n.shared` inside a SwiftUI body
/// registers Observation tracking, so views re-render on language change.
func tr(_ english: String, _ russian: String) -> String {
    L10n.shared.isRussian ? russian : english
}
