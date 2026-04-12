import AppKit
import Foundation
import IOKit

// MARK: - Контроллер медиаклавиш (IOKit HID + CoreDisplay)

/// Эмулирует нажатие медиаклавиш (play/pause, громкость, mute)
/// через системные события NSEvent → CGEvent.
/// Для яркости экрана использует CoreDisplay (приватный фреймворк).
/// Также умеет считывать текущие значения громкости и яркости.
enum MediaController {

    // MARK: - NX_KEYTYPE коды (из IOKit/hidsystem/ev_keymap.h)

    private static let NX_KEYTYPE_PLAY: Int32       = 16
    private static let NX_KEYTYPE_NEXT: Int32       = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32   = 18
    private static let NX_KEYTYPE_SOUND_UP: Int32   = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    private static let NX_KEYTYPE_MUTE: Int32       = 7
    private static let NX_KEYTYPE_BRIGHTNESS_DOWN: UInt32 = 10
    private static let NX_KEYTYPE_BRIGHTNESS_UP:   UInt32 = 11

    // MARK: - Публичный API

    /// Выполняет медиа-действие.
    /// Яркость экрана обрабатывается отдельно через CoreDisplay,
    /// остальное — через системные события HID.
    static func perform(_ action: RemoteCommand.MediaAction) {
        switch action {
        case .brightnessup:
            adjustScreenBrightness(delta: 1.0 / 16.0)
        case .brightnessdown:
            adjustScreenBrightness(delta: -1.0 / 16.0)
        default:
            let keyType = keyType(for: action)
            sendMediaKey(keyType, down: true)
            sendMediaKey(keyType, down: false)
        }
    }

    // MARK: - Яркость экрана через CoreDisplay

    /// Изменяет яркость экрана на delta (шаг 1/16 ≈ 6%).
    /// Использует CoreDisplay — приватный, но стабильный фреймворк Apple.
    /// NX_KEYTYPE_BRIGHTNESS_UP/DOWN (22/23) управляют подсветкой КЛАВИАТУРЫ,
    /// а не экрана, поэтому для экрана нужен CoreDisplay.
    // MARK: - Яркость экрана через DisplayServices (Apple Silicon)

    /// Изменяет яркость экрана на delta (шаг 1/16 ≈ 6%).
    static func adjustScreenBrightness(delta: Double) {
        let displayID = CGMainDisplayID()

        var current: Float = 0
        let getResult = DisplayServicesGetBrightness(displayID, &current)
        guard getResult == 0 else { return } // 0 = kIOReturnSuccess

        let newValue = min(1.0, max(0.0, Double(current) + delta))
        let setResult = DisplayServicesSetBrightness(displayID, Float(newValue))
        guard setResult == 0 else { return }
    }

    /// Возвращает текущую яркость экрана (0.0 – 1.0).
    static func getScreenBrightness() -> Double {
        let displayID = CGMainDisplayID()

        var current: Float = 0
        let result = DisplayServicesGetBrightness(displayID, &current)
        guard result == 0 else { return 0.5 }

        return Double(current)
    }

//    // MARK: - Яркость через osascript + brightness CLI
//
//    /// Возвращает текущую яркость основного дисплея (0.0 – 1.0).
//    static func getSystemBrightness() -> Double {
//        let task = Process()
//        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/brightness") // или "/opt/homebrew/bin/brightness" на Apple Silicon
//        task.arguments = ["-l"]
//        
//        let pipe = Pipe()
//        task.standardOutput = pipe
//        
//        try? task.run()
//        task.waitUntilExit()
//        
//        let data = pipe.fileHandleForReading.readDataToEndOfFile()
//        guard let str = String(data: data, encoding: .utf8) else { return 0.5 }
//        
//        // Ищем строку вида: "display 0: brightness 0.750000"
//        for line in str.split(separator: "\n") {
//            if line.contains("display 0: brightness") {
//                let parts = line.split(separator: " ")
//                if let last = parts.last, let value = Double(last) {
//                    return min(max(value, 0.0), 1.0)
//                }
//            }
//        }
//        return 0.5
//    }
//
//    /// Устанавливает яркость основного дисплея (0.0 – 1.0).
//    static func setSystemBrightness(_ value: Double) {
//        let clamped = min(max(value, 0.0), 1.0)
//        
//        let task = Process()
//        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/brightness") // или "/opt/homebrew/bin/brightness"
//        task.arguments = ["-m", String(format: "%.3f", clamped)]
//        
//        try? task.run()
//    }


    // MARK: - Громкость через osascript

    /// Возвращает текущую системную громкость (0.0 – 1.0) через osascript.
    static func getSystemVolume() -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "output volume of (get volume settings)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let vol = Double(str) {
            return vol / 100.0
        }
        return 0.5
    }

    // MARK: - Системная информация (JSON)

    /// Возвращает JSON-строку с текущими значениями громкости и яркости.
    /// Формат: {"type":"systeminfo","volume":0.5,"brightness":0.7}
    static func getSystemInfoJSON() -> String {
        let vol = getSystemVolume()
        let bright = getScreenBrightness()
        return "{\"type\":\"systeminfo\",\"volume\":\(vol),\"brightness\":\(bright)}"
    }

    // MARK: - Отправка системного события (HID)

    /// Создаёт и отправляет системное событие для медиаклавиши.
    /// Формат data1: (keyType << 16) | flags
    /// flags: 0xa00 для keyDown, 0xb00 для keyUp
    private static func sendMediaKey(_ key: Int32, down: Bool) {
        let flags: Int32 = down ? 0xa00 : 0xb00
        let data1 = Int32((key << 16) | flags)

        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(data1),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Маппинг действий

    /// Преобразует действие протокола в NX_KEYTYPE код.
    private static func keyType(for action: RemoteCommand.MediaAction) -> Int32 {
        switch action {
        case .playpause:    return NX_KEYTYPE_PLAY
        case .volumeup:     return NX_KEYTYPE_SOUND_UP
        case .volumedown:   return NX_KEYTYPE_SOUND_DOWN
        case .next:         return NX_KEYTYPE_NEXT
        case .previous:     return NX_KEYTYPE_PREVIOUS
        case .mute:         return NX_KEYTYPE_MUTE
        case .brightnessup: return 0
            // Обрабатывается отдельно через CoreDisplay
        case .brightnessdown: return 0
        }
    }
}
