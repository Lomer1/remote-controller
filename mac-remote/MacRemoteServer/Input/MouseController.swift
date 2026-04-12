import CoreGraphics
import Foundation

// MARK: - Контроллер мыши (CGEvent)

/// Управляет курсором мыши через CGEvent API.
/// Требует разрешение Accessibility в Системных настройках.
enum MouseController {

    // MARK: - Перемещение курсора

    /// Сдвигает курсор на (dx, dy) пикселей относительно текущей позиции.
    static func moveMouse(dx: Double, dy: Double) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(
            x: currentPos.x + dx,
            y: currentPos.y + dy
        )
        postMouseEvent(.mouseMoved, at: newPos, button: .left)
    }

    // MARK: - Клик

    /// Выполняет клик (или двойной/тройной клик) указанной кнопкой.
    static func click(button: RemoteCommand.MouseButton, count: Int = 1) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let (downType, upType, cgButton) = eventTypes(for: button)

        for i in 0..<max(count, 1) {
            if let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: currentPos, mouseButton: cgButton) {
                down.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: currentPos, mouseButton: cgButton) {
                up.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Прокрутка (scroll)

    /// Прокручивает колесо мыши на указанное количество пикселей.
    /// dy > 0 — прокрутка вверх, dy < 0 — вниз.
    /// dx > 0 — прокрутка вправо, dx < 0 — влево.
    static func scroll(dx: Double, dy: Double) {
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Зажатие / отпускание кнопки (для drag & drop)

    /// Зажимает кнопку мыши (для drag & drop).
    static func mouseDown(button: RemoteCommand.MouseButton) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let (downType, _, cgButton) = eventTypes(for: button)
        if let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: currentPos, mouseButton: cgButton) {
            down.post(tap: .cghidEventTap)
        }
    }

    /// Отпускает кнопку мыши.
    static func mouseUp(button: RemoteCommand.MouseButton) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let (_, upType, cgButton) = eventTypes(for: button)
        if let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: currentPos, mouseButton: cgButton) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// Перемещает мышь с зажатой левой кнопкой (drag).
    static func mouseDrag(dx: Double, dy: Double) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: newPos, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Свайпы (эмуляция через горячие клавиши)

    /// Эмулирует 3-пальцевый свайп через клавиатурные сокращения Mission Control.
    static func threeFingerSwipe(_ direction: RemoteCommand.SwipeDirection) {
        switch direction {
        case .up:    // Mission Control
            KeyboardController.sendHotkey(modifiers: [.ctrl], key: "up")
        case .down:  // App Exposé
            KeyboardController.sendHotkey(modifiers: [.ctrl], key: "down")
        case .left:  // Переключение рабочего стола влево
            KeyboardController.sendHotkey(modifiers: [.ctrl], key: "left")
        case .right: // Переключение рабочего стола вправо
            KeyboardController.sendHotkey(modifiers: [.ctrl], key: "right")
        }
    }

    /// Эмулирует 2-пальцевый свайп (навигация назад/вперёд).
    static func twoFingerSwipe(_ direction: RemoteCommand.SwipeDirection) {
        switch direction {
        case .left:  // Назад (Cmd+[)
            KeyboardController.sendHotkey(modifiers: [.cmd], key: "[")
        case .right: // Вперёд (Cmd+])
            KeyboardController.sendHotkey(modifiers: [.cmd], key: "]")
        case .up, .down:
            break // Не используется для 2 пальцев
        }
    }

    // MARK: - Вспомогательные методы

    private static func postMouseEvent(_ type: CGEventType, at position: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Возвращает типы событий для нажатия/отпускания по кнопке мыши.
    static func eventTypes(for button: RemoteCommand.MouseButton) -> (down: CGEventType, up: CGEventType, cgButton: CGMouseButton) {
        switch button {
        case .left:
            return (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            return (.rightMouseDown, .rightMouseUp, .right)
        }
    }
}
