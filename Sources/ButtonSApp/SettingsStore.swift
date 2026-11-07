import Foundation
import Combine
import ButtonSCore

/// Настройки приложения. Хранятся в `UserDefaults`, читаются на старте.
///
/// Набор соответствует вкладкам v1, кроме провайдеров и перефразирования.
public final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let prefix = "buttonS.v2."

    @Published var layoutEnabled: Bool { didSet { save("layoutEnabled", layoutEnabled) } }
    @Published var autoSwitchLayout: Bool { didSet { save("autoSwitchLayout", autoSwitchLayout) } }
    @Published var typosEnabled: Bool { didSet { save("typosEnabled", typosEnabled) } }
    @Published var typoMode: String { didSet { save("typoMode", typoMode) } }
    @Published var typoMaxDistance: Int { didSet { save("typoMaxDistance", typoMaxDistance) } }
    @Published var shiftFixEnabled: Bool { didSet { save("shiftFixEnabled", shiftFixEnabled) } }
    @Published var capitalizationEnabled: Bool { didSet { save("capitalizationEnabled", capitalizationEnabled) } }
    @Published var listsEnabled: Bool { didSet { save("listsEnabled", listsEnabled) } }
    @Published var notifyOnFix: Bool { didSet { save("notifyOnFix", notifyOnFix) } }
    @Published var launchAtLogin: Bool { didSet { save("launchAtLogin", launchAtLogin) } }

    @Published var voiceEnabled: Bool { didSet { save("voiceEnabled", voiceEnabled) } }
    @Published var voiceKey: String { didSet { save("voiceKey", voiceKey) } }
    @Published var whisperModel: String { didSet { save("whisperModel", whisperModel) } }
    @Published var voiceLanguage: String { didSet { save("voiceLanguage", voiceLanguage) } }

    @Published var autoPunctuation: Bool { didSet { save("autoPunctuation", autoPunctuation) } }
    @Published var removeFillers: Bool { didSet { save("removeFillers", removeFillers) } }
    @Published var uiScale: Double { didSet { save("uiScale", uiScale) } }

    public init() {
        layoutEnabled = defaults.object(forKey: prefix + "layoutEnabled") as? Bool ?? true
        autoSwitchLayout = defaults.object(forKey: prefix + "autoSwitchLayout") as? Bool ?? true
        typosEnabled = defaults.object(forKey: prefix + "typosEnabled") as? Bool ?? true
        typoMode = defaults.string(forKey: prefix + "typoMode") ?? "auto"
        typoMaxDistance = defaults.object(forKey: prefix + "typoMaxDistance") as? Int ?? 1
        shiftFixEnabled = defaults.object(forKey: prefix + "shiftFixEnabled") as? Bool ?? true
        capitalizationEnabled = defaults.object(forKey: prefix + "capitalizationEnabled") as? Bool ?? true
        listsEnabled = defaults.object(forKey: prefix + "listsEnabled") as? Bool ?? true
        notifyOnFix = defaults.object(forKey: prefix + "notifyOnFix") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: prefix + "launchAtLogin") as? Bool ?? false
        voiceEnabled = defaults.object(forKey: prefix + "voiceEnabled") as? Bool ?? true
        voiceKey = defaults.string(forKey: prefix + "voiceKey") ?? "ShiftRight"
        whisperModel = defaults.string(forKey: prefix + "whisperModel") ?? "large-v3-turbo"
        voiceLanguage = defaults.string(forKey: prefix + "voiceLanguage") ?? "ru"
        autoPunctuation = defaults.object(forKey: prefix + "autoPunctuation") as? Bool ?? true
        removeFillers = defaults.object(forKey: prefix + "removeFillers") as? Bool ?? true
        uiScale = defaults.object(forKey: prefix + "uiScale") as? Double ?? 1.0
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: prefix + key)
    }

    /// Настройки в терминах движка.
    public var engineSettings: EngineSettings {
        var settings = EngineSettings()
        settings.layoutEnabled = layoutEnabled
        settings.autoSwitchLayout = autoSwitchLayout
        settings.typosEnabled = typosEnabled
        settings.typoMode = EngineSettings.TypoMode(rawValue: typoMode) ?? .auto
        settings.typoMaxDistance = typoMaxDistance
        settings.shiftFixEnabled = shiftFixEnabled
        settings.capitalizationEnabled = capitalizationEnabled
        settings.listsEnabled = listsEnabled
        return settings
    }
}
