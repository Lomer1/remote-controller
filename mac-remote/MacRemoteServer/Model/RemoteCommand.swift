import Foundation

// MARK: - Команды удалённого управления (Remote Command Protocol)

/// Перечисление всех типов команд, получаемых от iOS-клиента.
/// Формат: JSON, разделённый символами новой строки (newline-delimited JSON).
enum RemoteCommand: Decodable {
    case mouseMove(dx: Double, dy: Double)
    case click(button: MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case keypress(text: String)
    case hotkey(modifiers: [Modifier], key: String)
    case media(action: MediaAction)
    case mouseDown(button: MouseButton)
    case mouseUp(button: MouseButton)
    case mouseDrag(dx: Double, dy: Double)
    case threeFingerSwipe(direction: SwipeDirection)
    case twoFingerSwipe(direction: SwipeDirection)
    case getSystemInfo

    // MARK: - Вложенные типы

    enum MouseButton: String, Decodable {
        case left
        case right
    }

    enum Modifier: String, Decodable {
        case cmd
        case shift
        case ctrl
        case opt
    }

    enum SwipeDirection: String, Decodable {
        case up, down, left, right
    }

    enum MediaAction: String, Decodable {
        case playpause
        case volumeup
        case volumedown
        case next
        case previous
        case brightnessup
        case brightnessdown
        case mute
    }

    // MARK: - Ручной декодинг по полю "type"

    private enum CodingKeys: String, CodingKey {
        case type
        case dx, dy
        case button, count
        case text
        case modifiers, key
        case action
        case direction
    }

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
}

// MARK: - Парсинг команд из потока данных

extension RemoteCommand {
    /// Парсит одну строку JSON в команду.
    static func parse(_ data: Data) -> RemoteCommand? {
        try? JSONDecoder().decode(RemoteCommand.self, from: data)
    }

    /// Разбивает буфер на отдельные JSON-строки и парсит каждую.
    /// Возвращает массив распознанных команд и остаток (неполная строка).
    static func parseBuffer(_ buffer: Data) -> (commands: [RemoteCommand], remainder: Data) {
        guard let string = String(data: buffer, encoding: .utf8) else {
            return ([], buffer)
        }

        let lines = string.components(separatedBy: "\n")
        var commands: [RemoteCommand] = []
        var remainder = Data()

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Последняя строка может быть неполной (без \n на конце)
            if index == lines.count - 1 && !string.hasSuffix("\n") {
                remainder = Data(trimmed.utf8)
                continue
            }

            if let data = trimmed.data(using: .utf8),
               let command = parse(data) {
                commands.append(command)
            }
        }

        return (commands, remainder)
    }
}
