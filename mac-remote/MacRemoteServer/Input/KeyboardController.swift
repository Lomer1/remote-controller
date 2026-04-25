import CoreGraphics
import Carbon.HIToolbox
import Foundation

// MARK: - Контроллер клавиатуры (CGEvent)

/// Управляет клавиатурным вводом через CGEvent API.
/// Поддерживает ввод Unicode-текста и горячие клавиши с модификаторами.
enum KeyboardController {

    // MARK: - Ввод текста (Unicode)

    /// Набирает текст посимвольно через CGEventKeyboardSetUnicodeString.
    /// Поддерживает любые Unicode-символы (кириллица, эмодзи и т.д.).
    static func typeText(_ text: String) {
        for character in text {
            let utf16 = Array(String(character).utf16)
            typeUnicodeCharacter(utf16)
        }
    }

    /// Отправляет один Unicode-символ (массив UTF-16 code units).
    private static func typeUnicodeCharacter(_ utf16: [UniChar]) {
        // Событие keyDown с Unicode-строкой
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyDown.post(tap: .cghidEventTap)
        }
        // Событие keyUp
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Горячие клавиши (hotkey)

    /// Нажимает комбинацию клавиш, например Cmd+Shift+C.
    static func sendHotkey(modifiers: [RemoteCommand.Modifier], key: String) {
        guard let keyCode = keyCodeForString(key) else { return }
        let flags = cgEventFlags(from: modifiers)

        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Маппинг модификаторов

    /// Преобразует массив модификаторов протокола в CGEventFlags.
    private static func cgEventFlags(from modifiers: [RemoteCommand.Modifier]) -> CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .cmd:   flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .ctrl:  flags.insert(.maskControl)
            case .opt:   flags.insert(.maskAlternate)
            }
        }
        return flags
    }

    // MARK: - Маппинг клавиш → виртуальные коды (CGKeyCode)

    /// Возвращает виртуальный код клавиши по строковому имени.
    /// Поддерживает буквы, цифры, F-клавиши и специальные клавиши.
    private static func keyCodeForString(_ key: String) -> CGKeyCode? {
        let lowered = key.lowercased()

        // Специальные клавиши
        if let special = specialKeyCodes[lowered] {
            return special
        }

        // Одиночный символ — ищем в таблице
        if lowered.count == 1, let code = charKeyCodes[Character(lowered)] {
            return code
        }

        return nil
    }

    /// Спецклавиши: return, escape, tab, space, delete, стрелки, F1–F12 и др.
    private static let specialKeyCodes: [String: CGKeyCode] = [
        "return":      CGKeyCode(kVK_Return),
        "enter":       CGKeyCode(kVK_Return),
        "tab":         CGKeyCode(kVK_Tab),
        "space":       CGKeyCode(kVK_Space),
        "delete":      CGKeyCode(kVK_Delete),
        "backspace":   CGKeyCode(kVK_Delete),
        "forwarddelete": CGKeyCode(kVK_ForwardDelete),
        "escape":      CGKeyCode(kVK_Escape),
        "esc":         CGKeyCode(kVK_Escape),
        "up":          CGKeyCode(kVK_UpArrow),
        "down":        CGKeyCode(kVK_DownArrow),
        "left":        CGKeyCode(kVK_LeftArrow),
        "right":       CGKeyCode(kVK_RightArrow),
        "home":        CGKeyCode(kVK_Home),
        "end":         CGKeyCode(kVK_End),
        "pageup":      CGKeyCode(kVK_PageUp),
        "pagedown":    CGKeyCode(kVK_PageDown),
        "f1":          CGKeyCode(kVK_F1),
        "f2":          CGKeyCode(kVK_F2),
        "f3":          CGKeyCode(kVK_F3),
        "f4":          CGKeyCode(kVK_F4),
        "f5":          CGKeyCode(kVK_F5),
        "f6":          CGKeyCode(kVK_F6),
        "f7":          CGKeyCode(kVK_F7),
        "f8":          CGKeyCode(kVK_F8),
        "f9":          CGKeyCode(kVK_F9),
        "f10":         CGKeyCode(kVK_F10),
        "f11":         CGKeyCode(kVK_F11),
        "f12":         CGKeyCode(kVK_F12),
        "capslock":    CGKeyCode(kVK_CapsLock),
        "volumeup":    CGKeyCode(kVK_VolumeUp),
        "volumedown":  CGKeyCode(kVK_VolumeDown),
        "mute":        CGKeyCode(kVK_Mute),
    ]

    /// Обычные символы → виртуальные коды (US ANSI раскладка).
    private static let charKeyCodes: [Character: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        "-": CGKeyCode(kVK_ANSI_Minus),
        "=": CGKeyCode(kVK_ANSI_Equal),
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "\\": CGKeyCode(kVK_ANSI_Backslash),
        ";": CGKeyCode(kVK_ANSI_Semicolon),
        "'": CGKeyCode(kVK_ANSI_Quote),
        ",": CGKeyCode(kVK_ANSI_Comma),
        ".": CGKeyCode(kVK_ANSI_Period),
        "/": CGKeyCode(kVK_ANSI_Slash),
        "`": CGKeyCode(kVK_ANSI_Grave),
    ]
}
