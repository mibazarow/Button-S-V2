import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import Carbon

/// Разрешения и защищённый ввод — тонкая обёртка над системными вызовами.
public enum Accessibility {
    /// Разрешён ли «Универсальный доступ». При `prompt = true` покажет системный запрос.
    public static func isTrusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Разрешён ли захват ввода (отдельное разрешение на macOS 10.15+).
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }
}

/// Определяет, активен ли защищённый ввод (пароли, Keychain).
public enum SecureInput {
    public static var isActive: Bool {
        IsSecureEventInputEnabled()
    }
}

/// Идентификатор приложения на переднем плане и отдельные случаи.
public enum FrontmostApp {
    public static func bundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    /// Адресная строка браузера: там править нельзя — ломает навигацию.
    public static func isBrowserAddressBar(bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        guard Self.browsers.contains(bundleID) else { return false }
        guard let focused = AXFocusedElement() else { return false }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, role == (kAXTextFieldRole as String) {
            // В адресной строке браузера фокус — текстовое поле самого приложения.
            return true
        }
        return false
    }

    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]
}

/// Текущий сфокусированный AX-элемент.
public func AXFocusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
    guard status == .success, let value = focused else { return nil }
    return (value as! AXUIElement)
}

/// Переключение системной раскладки под язык исправленного текста.
public enum InputSource {
    public static func switcher(for language: String) -> String {
        language == "ru" ? "ru" : "en"
    }

    @discardableResult
    public static func activate(_ language: String) -> Bool {
        let wanted = switcher(for: language)
        guard let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        for source in sources {
            guard let langs = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
                    .map({ Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] }) ?? nil else {
                continue
            }
            guard let code = langs.first?.prefix(2), String(code) == wanted else { continue }
            if TISSelectInputSource(source) == noErr { return true }
        }
        return false
    }
}
