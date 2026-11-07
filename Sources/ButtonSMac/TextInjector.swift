import Foundation
import CoreGraphics
import AppKit

/// Вставка текста через `CGEvent` — без буфера обмена, без потери выделения.
///
/// Порт `platform/macos/inject.rs`: чанки по 16 UTF-16 юнитов, маркер в
/// `eventSourceUserData`, бэкспейсы с паузой, код клавиш как в оригинале.
public enum TextInjector {
    static let backspaceKey: CGKeyCode = 51
    static let returnKey: CGKeyCode = 36
    static let tabKey: CGKeyCode = 48
    static let chunkSize = 16

    /// Ставит событие в поток ввода с меткой.
    static func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: buttonSMagicMarker)
        event.post(tap: .cghidEventTap)
    }

    static func sendKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) {
            down.flags = flags
            post(down)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
            up.flags = flags
            post(up)
        }
    }

    static func sendChunk(_ units: [UniChar]) {
        guard !units.isEmpty else { return }
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(down)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            post(up)
        }
    }

    /// Вставляет текст. Возвращает `false`, если система не дала доступ.
    @discardableResult
    public static func type(_ text: String) -> Bool {
        guard Accessibility.isTrusted() else { return false }
        guard !SecureInput.isActive else { return false }

        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let end = min(index + chunkSize, units.count)
            sendChunk(Array(units[index..<end]))
            index = end
            Thread.sleep(forTimeInterval: 0.003)
        }
        return true
    }

    /// Удаляет `count` символов.
    @discardableResult
    public static func delete(count: Int) -> Bool {
        guard Accessibility.isTrusted() else { return false }
        guard !SecureInput.isActive else { return false }
        guard count > 0 else { return true }

        for _ in 0..<count {
            sendKey(backspaceKey)
            Thread.sleep(forTimeInterval: 0.002)
        }
        return true
    }

    /// Заменяет набранное: удаляет символы и печатает новое.
    @discardableResult
    public static func replace(deleteCount: Int, with text: String) -> Bool {
        guard !SecureInput.isActive else { return false }
        guard delete(count: deleteCount) else { return false }
        if !text.isEmpty {
            Thread.sleep(forTimeInterval: 0.008)
            guard type(text) else { return false }
        }
        return true
    }

    /// Копирует выделение (Cmd+C).
    @discardableResult
    public static func copySelection() -> Bool {
        guard Accessibility.isTrusted() else { return false }
        sendKey(8, flags: .maskCommand)
        return true
    }

    /// Вставляет из буфера обмена (Cmd+V).
    @discardableResult
    public static func paste() -> Bool {
        guard Accessibility.isTrusted() else { return false }
        sendKey(9, flags: .maskCommand)
        return true
    }
}

/// Чтение текста вокруг курсора через AXUIElement.
public enum AXContext {
    public struct Snapshot: Sendable {
        public let before: String
        public let selected: String
        public let after: String
    }

    /// Выделение целиком, если оно есть. Для хоткея «сменить раскладку».
    public static func selection() -> String? {
        guard let element = AXFocusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
