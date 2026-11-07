import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// Метка своих же событий: чтобы не реагировать на собственную вставку.
public let buttonSMagicMarker: Int64 = 0x4255_5454

/// События клавиатуры, которые интересны конвейеру.
public enum InputEvent: Sendable {
    case character(Character)
    case backspace
    case boundary(Character)
    case reset
    case shortcut
    /// Нажатие/отпускание хоткея диктовки.
    case dictate(Bool)
}

/// Перехват клавиатуры через `CGEventTap` в режиме listen-only.
///
/// Порт `platform/macos/hook.rs`: маска тех же событий, тот же маркер,
/// та же защита от автоповтора, тот же сброс на стрелках и Escape.
public final class KeyboardTap: @unchecked Sendable {
    public var onEvent: ((InputEvent) -> Void)?
    public var onTapDisabled: (() -> Void)?
    /// Хоткей диктовки: по умолчанию правый Shift, как в v1.
    public var dictateHotkey: String = "ShiftRight"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private let marker = buttonSMagicMarker

    private static let eventMask: CGEventMask = {
        (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
    }()

    public init() {}

    public func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            self?.runLoop()
        }
        t.name = "ButtonS.KeyboardTap"
        t.stackSize = 512 * 1024
        thread = t
        t.start()
    }

    public func stop() {
        if let source = runLoopSource, let tap {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        thread = nil
    }

    private func runLoop() {
        guard Accessibility.isTrusted(prompt: true) else {
            onTapDisabled?()
            return
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let instance = Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue()
                instance.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            onTapDisabled?()
            return
        }

        tap = port
        CGEvent.tapEnable(tap: port, enable: true)

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapDisabled?()
            return
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return
        case .keyDown, .flagsChanged:
            break
        default:
            return
        }

        if event.getIntegerValueField(.eventSourceUserData) == marker { return }

        if SecureInput.isActive {
            if type == .keyDown { onEvent?(.reset) }
            return
        }

        if type == .flagsChanged {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let expected: String
            switch code {
            case 56: expected = "ShiftLeft"
            case 60: expected = "ShiftRight"
            default: return
            }
            if expected == dictateHotkey {
                let down = event.flags.contains(.maskShift)
                onEvent?(.dictate(down))
            }
            return
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }

        let flags = event.flags
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            onEvent?(.shortcut)
            return
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)

        switch code {
        case 51:
            onEvent?(.backspace)
        case 36, 76:
            onEvent?(.boundary("\n"))
        case 48:
            onEvent?(.reset)
        case 53, 115, 119, 116, 121, 123, 124, 125, 126:
            onEvent?(.reset)
        default:
            var buffer = [UniChar](repeating: 0, count: 8)
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                          actualStringLength: &length,
                                          unicodeString: &buffer)
            guard length > 0 else { return }

            let text = String(utf16CodeUnits: buffer, count: min(length, buffer.count))
            for ch in text {
                if ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                    onEvent?(.reset)
                } else if ch.isWhitespace || Self.boundaries.contains(ch) {
                    onEvent?(.boundary(ch))
                } else {
                    onEvent?(.character(ch))
                }
            }
        }
    }

    static let boundaries: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "…", "»", ")", "]", "}", "\"", "“", "”", "„",
    ]
}
