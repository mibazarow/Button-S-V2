import Foundation
import ButtonSCore

/// Реализация `PlatformActions` поверх macOS.
///
/// Всё, что движку нужно от системы, собрано здесь: кто на переднем плане,
/// можно ли править, чем заменить набранное.
public final class MacPlatform: PlatformActions, @unchecked Sendable {
    public init() {}

    public func frontmostAppID() -> String {
        FrontmostApp.bundleID()
    }

    public func isBrowserAddressBar(appID: String) -> Bool {
        FrontmostApp.isBrowserAddressBar(bundleID: appID)
    }

    public func isSecureInput() -> Bool {
        SecureInput.isActive
    }

    public func replaceTyped(deleteCount: Int, insertion: String) -> Bool {
        TextInjector.replace(deleteCount: deleteCount, with: insertion)
    }

    public func insertText(_ text: String) -> Bool {
        TextInjector.type(text)
    }

    public func switchLayout(to language: String) -> Bool {
        InputSource.activate(language)
    }
}
