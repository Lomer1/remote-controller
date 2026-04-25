import Foundation

// MARK: - Команды удалённого управления (Remote Command Protocol)
/// Перечисление всех типов команд, отправляемых на macOS-сервер.
/// Формат: JSON, разделённый символами новой строки (newline-delimited JSON).
/// Этот файл — зеркало серверной модели с добавлением Encodable.
enum RemoteCommand: Codable {
    case mouseMove(dx: Double, dy: Double)
    case click(button: MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case keypress(text: String)
    case hotkey(modifiers: [Modifier], key: String)
    case media(action: MediaAction)

    case setVolume(value: Double)
    case setBrightness(value: Double)
    case setMute(enabled: Bool)

    case mouseDown(button: MouseButton)
    case mouseUp(button: MouseButton)
    case mouseDrag(dx: Double, dy: Double)
    case threeFingerSwipe(direction: SwipeDirection)
    case twoFingerSwipe(direction: SwipeDirection)
    case getSystemInfo

    // MARK: - Вложенные типы
    enum MouseButton: String, Codable {
        case left
        case right
    }

    enum Modifier: String, Codable {
        case cmd
        case shift
        case ctrl
        case opt
    }

    enum SwipeDirection: String, Codable {
        case up, down, left, right
    }

    enum MediaAction: String, Codable {
        case playpause
        case volumeup
        case volumedown
        case next
        case previous
        case brightnessup
        case brightnessdown
        case mute
    }

    // MARK: - Ключи кодирования
    private enum CodingKeys: String, CodingKey {
        case type
        case dx, dy
        case button, count
        case text
        case modifiers, key
        case action
        case direction
        case value
        case enabled
    }

    // MARK: - Декодирование (по полю "type")
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "mousemove":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .mouseMove(dx: dx, dy: dy)

        case "click":
            let button = try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
            let count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
            self = .click(button: button, count: count)

        case "scroll":
            let dx = try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0
            let dy = try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
            self = .scroll(dx: dx, dy: dy)

        case "keypress":
            let text = try container.decode(String.self, forKey: .text)
            self = .keypress(text: text)

        case "hotkey":
            let modifiers = try container.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
            let key = try container.decode(String.self, forKey: .key)
            self = .hotkey(modifiers: modifiers, key: key)

        case "media":
            let action = try container.decode(MediaAction.self, forKey: .action)
            self = .media(action: action)

        case "setvolume":
            let value = try container.decode(Double.self, forKey: .value)
            self = .setVolume(value: value)

        case "setbrightness":
            let value = try container.decode(Double.self, forKey: .value)
            self = .setBrightness(value: value)

        case "setmute":
            let enabled = try container.decode(Bool.self, forKey: .enabled)
            self = .setMute(enabled: enabled)

        case "mousedown":
            let button = try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
            self = .mouseDown(button: button)

        case "mouseup":
            let button = try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
            self = .mouseUp(button: button)

        case "mousedrag":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .mouseDrag(dx: dx, dy: dy)

        case "swipe3":
            let direction = try container.decode(SwipeDirection.self, forKey: .direction)
            self = .threeFingerSwipe(direction: direction)

        case "swipe2":
            let direction = try container.decode(SwipeDirection.self, forKey: .direction)
            self = .twoFingerSwipe(direction: direction)

        case "getsysteminfo":
            self = .getSystemInfo

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Неизвестный тип команды: \(type)"
            )
        }
    }

    // MARK: - Кодирование (для отправки на сервер)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .mouseMove(let dx, let dy):
            try container.encode("mousemove", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)

        case .click(let button, let count):
            try container.encode("click", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(count, forKey: .count)

        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)

        case .keypress(let text):
            try container.encode("keypress", forKey: .type)
            try container.encode(text, forKey: .text)

        case .hotkey(let modifiers, let key):
            try container.encode("hotkey", forKey: .type)
            try container.encode(modifiers, forKey: .modifiers)
            try container.encode(key, forKey: .key)

        case .media(let action):
            try container.encode("media", forKey: .type)
            try container.encode(action, forKey: .action)

        case .setVolume(let value):
            try container.encode("setvolume", forKey: .type)
            try container.encode(value, forKey: .value)

        case .setBrightness(let value):
            try container.encode("setbrightness", forKey: .type)
            try container.encode(value, forKey: .value)

        case .setMute(let enabled):
            try container.encode("setmute", forKey: .type)
            try container.encode(enabled, forKey: .enabled)

        case .mouseDown(let button):
            try container.encode("mousedown", forKey: .type)
            try container.encode(button, forKey: .button)

        case .mouseUp(let button):
            try container.encode("mouseup", forKey: .type)
            try container.encode(button, forKey: .button)

        case .mouseDrag(let dx, let dy):
            try container.encode("mousedrag", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)

        case .threeFingerSwipe(let direction):
            try container.encode("swipe3", forKey: .type)
            try container.encode(direction, forKey: .direction)

        case .twoFingerSwipe(let direction):
            try container.encode("swipe2", forKey: .type)
            try container.encode(direction, forKey: .direction)

        case .getSystemInfo:
            try container.encode("getsysteminfo", forKey: .type)
        }
    }
}

// MARK: - Сериализация в JSON-строку с переводом строки
extension RemoteCommand {
    /// Кодирует команду в JSON Data с символом новой строки на конце.
    func jsonData() -> Data? {
        guard var data = try? JSONEncoder().encode(self) else { return nil }
        data.append(0x0A) // \n — разделитель команд
        return data
    }
}
