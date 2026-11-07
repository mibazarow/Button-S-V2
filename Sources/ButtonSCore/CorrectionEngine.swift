import Foundation

/// Что именно исправили — для истории и отмены.
public enum ChangeKind: String, Sendable {
    case layout
    case typo
    case shift
    case manual
    case list
    case caseFix = "case"
}

/// Правка, применённая к тексту.
public struct AppliedChange: Sendable {
    public let kind: ChangeKind
    public let from: String
    public let to: String
    public let at: Date

    public init(kind: ChangeKind, from: String, to: String, at: Date = Date()) {
        self.kind = kind
        self.from = from
        self.to = to
        self.at = at
    }
}

/// Действия, которые конвейеру нужны от системы.
///
/// Движок остаётся чистым и тестируемым: в тестах подставляется подделка,
/// в приложении — реализация на CGEvent/AXUIElement.
public protocol PlatformActions: AnyObject, Sendable {
    /// Идентификатор приложения на переднем плане.
    func frontmostAppID() -> String
    /// Курсор стоит в адресной строке браузера — там не правим.
    func isBrowserAddressBar(appID: String) -> Bool
    /// Включён режим защищённого ввода (пароли).
    func isSecureInput() -> Bool
    /// Заменить последние `deleteCount` символов на `insertion`.
    func replaceTyped(deleteCount: Int, insertion: String) -> Bool
    /// Вставить текст в текущую позицию.
    func insertText(_ text: String) -> Bool
    /// Переключить системную раскладку на язык текста.
    func switchLayout(to language: String) -> Bool
}

/// Настройки конвейера. Соответствуют вкладкам v1.
public struct EngineSettings: Sendable {
    public var layoutEnabled = true
    public var autoSwitchLayout = true
    public var layoutDelayMs = 0
    public var layout = LayoutSettings.default

    public var typosEnabled = true
    public var typoMode: TypoMode = .auto
    public var typoMaxDistance = 1

    public var shiftFixEnabled = true
    public var capitalizationEnabled = true
    public var capitalizationAfterColon = true
    public var listsEnabled = true

    public enum TypoMode: String, Sendable {
        case off
        case auto
        case suggest
    }

    public init() {}

    public static let `default` = EngineSettings()
}

/// Ядро: собирает символы в слова и правит их на границе слова.
///
/// Порт `engine/mod.rs` без привязки к Tauri и без истории в базе.
public final class CorrectionEngine {
    private let dictionary: Dictionary
    private let actions: PlatformActions
    private var buffer = ""
    private var line = ""
    private var tracker = SentenceTracker()
    private var lastBoundary: Character?
    private var backspacesSinceBoundary = 0

    public var settings: EngineSettings
    public private(set) var history: [AppliedChange] = []
    /// Последнее предложение для всплывающей подсказки в режиме `.suggest`.
    public var onSuggestion: ((String, String, Float) -> Void)?
    /// Уведомление о применённой правке.
    public var onCorrection: ((AppliedChange) -> Void)?

    public init(actions: PlatformActions,
                settings: EngineSettings = .default,
                dictionary: Dictionary = .shared) {
        self.actions = actions
        self.settings = settings
        self.dictionary = dictionary
    }

    // MARK: - События

    public func characterTyped(_ ch: Character) {
        if buffer.count < 128 { buffer.append(ch) }
        if line.count < 1024 { line.append(ch) }

        let capitalize = tracker.onChar(ch)
        if capitalize && settings.capitalizationEnabled {
            applyCapitalization(ch)
        }
    }

    public func backspace() {
        if !buffer.isEmpty { buffer.removeLast() }
        if !line.isEmpty { line.removeLast() }
        tracker.onBackspace()
        backspacesSinceBoundary += 1
    }

    /// Граница слова: пробел, знак препинания, перевод строки.
    public func boundary(_ separator: Character) {
        let previousLine: String?
        if separator == "\n" {
            previousLine = line
            line = ""
        } else {
            line.append(separator)
            previousLine = nil
        }

        let word = buffer
        buffer = ""

        var replacement: String?
        if !Context.isProtectedContext(previous: lastBoundary, separator: separator, word: word) {
            replacement = handleBoundary(word, separator: separator)
        }

        tracker.onBoundary(replacement ?? word,
                           separator: separator,
                           afterColon: settings.capitalizationAfterColon)
        lastBoundary = separator

        if let previousLine, settings.listsEnabled, let marker = Rules.listContinuation(previousLine) {
            if actions.insertText(marker) {
                line.append(marker)
                record(.list, from: "", to: marker)
            }
        }
    }

    public func reset() {
        buffer = ""
        line = ""
        tracker.reset()
        lastBoundary = nil
        backspacesSinceBoundary = 0
    }

    // MARK: - Правила

    private func applyCapitalization(_ ch: Character) {
        let appID = actions.frontmostAppID()
        guard !appID.isEmpty, !actions.isBrowserAddressBar(appID: appID) else { return }

        let upper = String(ch).uppercased()
        guard actions.replaceTyped(deleteCount: 1, insertion: upper) else { return }

        if !buffer.isEmpty {
            buffer.removeLast()
            buffer.append(contentsOf: upper)
        }
    }

    /// Разбирает слово на границе: Shift → раскладка → опечатки.
    private func handleBoundary(_ word: String, separator: Character) -> String? {
        guard !word.isEmpty else { return nil }
        guard !actions.isSecureInput() else { return nil }

        let appID = actions.frontmostAppID()
        guard !appID.isEmpty, !actions.isBrowserAddressBar(appID: appID) else { return nil }

        // 1. Залипший Shift.
        if settings.shiftFixEnabled, let fixed = Rules.fixStuckShift(word) {
            if apply(.shift, from: word, to: fixed, separator: separator) {
                return fixed
            }
        }

        if Context.hasInnerUppercase(word) { return nil }

        let sourceLanguage = languageOf(word)
        let sourceIsKnown = sourceLanguage.map { dictionary.known($0, word) } ?? false

        // 2. Раскладка — только если слова нет в его собственном словаре.
        let layoutDecision: LayoutDecision? = settings.layoutEnabled
            ? LayoutEngine.decide(word, settings: settings.layout, dictionary: dictionary)
            : nil

        if layoutDecision == nil, Context.looksLikeProperNoun(word), !sourceIsKnown {
            return nil
        }

        if !sourceIsKnown, let decision = layoutDecision {
            if apply(.layout, from: word, to: decision.text, separator: separator) {
                return decision.text
            }
        }

        // 3. Опечатки.
        if settings.typosEnabled, settings.typoMode != .off, let language = sourceLanguage {
            if let suggestion = TypoEngine.suggest(word,
                                                  language: language,
                                                  maxDistance: settings.typoMaxDistance,
                                                  dictionary: dictionary) {
                if settings.typoMode == .auto,
                   TypoEngine.isConfident(distance: suggestion.distance,
                                          confidence: suggestion.confidence) {
                    if apply(.typo, from: word, to: suggestion.text, separator: separator) {
                        return suggestion.text
                    }
                } else if settings.typoMode == .suggest {
                    onSuggestion?(word, suggestion.text, suggestion.confidence)
                    return nil
                }
            }
        }

        // 4. Раскладка как последний шанс.
        if let decision = layoutDecision {
            if apply(.layout, from: word, to: decision.text, separator: separator) {
                return decision.text
            }
        }

        return nil
    }

    /// Удаляет «слово + разделитель», вставляет «замену + разделитель».
    @discardableResult
    private func apply(_ kind: ChangeKind,
                       from word: String,
                       to replacement: String,
                       separator: Character) -> Bool {
        guard replacement != word else { return false }

        let deleteCount = word.count + 1
        let insertion = "\(replacement)\(separator)"
        guard actions.replaceTyped(deleteCount: deleteCount, insertion: insertion) else { return false }

        record(kind, from: "\(word)\(separator)", to: insertion)

        if kind == .layout, settings.autoSwitchLayout,
           let language = languageOf(replacement) {
            _ = actions.switchLayout(to: language)
        }

        return true
    }

    private func record(_ kind: ChangeKind, from: String, to: String) {
        let change = AppliedChange(kind: kind, from: from, to: to)
        history.append(change)
        if history.count > 200 { history.removeFirst(history.count - 200) }
        onCorrection?(change)
    }
}
