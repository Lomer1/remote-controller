import AppKit
import Foundation
import IOKit

// MARK: - Контроллер медиаклавиш и системных параметров
/// Отвечает за:
/// - эмуляцию медиаклавиш (play/pause, next, previous, mute, step volume/brightness)
/// - чтение/установку системной громкости
/// - чтение/установку яркости основного дисплея
enum MediaController {
    // MARK: - Media key codes
    private static let NX_KEYTYPE_PLAY: Int32 = 16
    private static let NX_KEYTYPE_NEXT: Int32 = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32 = 18
    private static let NX_KEYTYPE_SOUND_UP: Int32 = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    private static let NX_KEYTYPE_MUTE: Int32 = 7

    // MARK: - Errors
    enum MediaError: Error, LocalizedError {
        case volumeReadFailed
        case volumeParseFailed
        case volumeSetFailed(code: Int32)
        case muteSetFailed(code: Int32)
        case brightnessReadFailed(code: Int32)
        case brightnessSetFailed(code: Int32)

        var errorDescription: String? {
            switch self {
            case .volumeReadFailed:
                return "Не удалось прочитать системную громкость"
            case .volumeParseFailed:
                return "Не удалось распарсить системную громкость"
            case .volumeSetFailed(let code):
                return "Не удалось установить громкость, код: \(code)"
            case .muteSetFailed(let code):
                return "Не удалось изменить mute, код: \(code)"
            case .brightnessReadFailed(let code):
                return "Не удалось прочитать яркость, код: \(code)"
            case .brightnessSetFailed(let code):
                return "Не удалось установить яркость, код: \(code)"
            }
        }
    }

    // MARK: - Public API
    static func perform(_ action: RemoteCommand.MediaAction) {
        switch action {
        case .brightnessup:
            do {
                let current = try getScreenBrightness()
                try setScreenBrightness(min(current + 1.0 / 16.0, 1.0))
            } catch {
                NSLog("Brightness up failed: \(error.localizedDescription)")
            }

        case .brightnessdown:
            do {
                let current = try getScreenBrightness()
                try setScreenBrightness(max(current - 1.0 / 16.0, 0.0))
            } catch {
                NSLog("Brightness down failed: \(error.localizedDescription)")
            }
            
        default:
            let keyType = keyType(for: action)
            sendMediaKey(keyType, down: true)
            sendMediaKey(keyType, down: false)
        }
    }

    // MARK: - Volume
    static func getSystemVolume() throws -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "output volume of (get volume settings)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw MediaError.volumeReadFailed
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let vol = Double(str)
        else {
            throw MediaError.volumeParseFailed
        }

        return min(max(vol / 100.0, 0.0), 1.0)
    }
    
    static func isSystemMuted() throws -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "output muted of (get volume settings)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw MediaError.volumeReadFailed
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw MediaError.volumeParseFailed
        }

        return str == "true"
    }

    static func setSystemVolume(_ value: Double) throws {
        let clamped = min(max(value, 0.0), 1.0)
        let percent = Int(round(clamped * 100.0))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "set volume output volume \(percent)"]
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw MediaError.volumeSetFailed(code: task.terminationStatus)
        }
    }

    static func setMuted(_ enabled: Bool) throws {
        let value = enabled ? "true" : "false"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "set volume output muted \(value)"]

        let errorPipe = Pipe()
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "unknown AppleScript error"
            print("setMuted AppleScript error: \(errorText)")
            throw MediaError.muteSetFailed(code: task.terminationStatus)
        }
    }

    // MARK: - Brightness
    static func getScreenBrightness() throws -> Double {
        guard MRDisplayServicesCanControlBrightness() else {
            throw MediaError.brightnessReadFailed(code: -1)
        }

        let displayID = CGMainDisplayID()
        var current: Float = 0

        let result = MRDisplayServicesGetBrightness(displayID, &current)
        guard result == 0 else {
            throw MediaError.brightnessReadFailed(code: result)
        }

        return min(max(Double(current), 0.0), 1.0)
    }

    static func setScreenBrightness(_ value: Double) throws {
        guard MRDisplayServicesCanControlBrightness() else {
            throw MediaError.brightnessSetFailed(code: -1)
        }

        let displayID = CGMainDisplayID()
        let clamped = Float(min(max(value, 0.0), 1.0))

        let result = MRDisplayServicesSetBrightness(displayID, clamped)
        guard result == 0 else {
            throw MediaError.brightnessSetFailed(code: result)
        }
    }

    // MARK: - System info
    static func getSystemInfoJSON() -> String {
        let volume = try? getSystemVolume()
        let brightness = try? getScreenBrightness()
        let muted = try? isSystemMuted()

        let volumeValue = volume.map { "\($0)" } ?? "null"
        let brightnessValue = brightness.map { "\($0)" } ?? "null"
        let mutedValue = muted.map { $0 ? "true" : "false" } ?? "null"

        return """
        {"type":"systeminfo","volume":\(volumeValue),"brightness":\(brightnessValue),"muted":\(mutedValue)}
        """
    }

    // MARK: - HID event
    private static func sendMediaKey(_ key: Int32, down: Bool) {
        let flags: Int32 = down ? 0xA00 : 0xB00
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

    // MARK: - Mapping
    private static func keyType(for action: RemoteCommand.MediaAction) -> Int32 {
        switch action {
        case .playpause: return NX_KEYTYPE_PLAY
        case .volumeup: return NX_KEYTYPE_SOUND_UP
        case .volumedown: return NX_KEYTYPE_SOUND_DOWN
        case .next: return NX_KEYTYPE_NEXT
        case .previous: return NX_KEYTYPE_PREVIOUS
        case .mute: return NX_KEYTYPE_MUTE
        case .brightnessup: return 0
        case .brightnessdown: return 0
        }
    }
}
