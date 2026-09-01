import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var label: String { self == .simplifiedChinese ? "中文" : "English" }
    var shortLabel: String { self == .simplifiedChinese ? "中" : "EN" }
    var locale: Locale { Locale(identifier: rawValue) }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let defaultsKey = "TaskDeck.appLanguage"
    private let defaults: UserDefaults

    @Published var current: AppLanguage {
        didSet { defaults.set(current.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }

    func text(_ chinese: String, _ english: String) -> String {
        current == .simplifiedChinese ? chinese : english
    }

    func format(_ chinese: String, _ english: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(chinese, english),
            locale: current.locale,
            arguments: arguments
        )
    }
}
