import CoreGraphics
import Foundation

// MARK: - Контроллер мыши (CGEvent)
/// Управляет курсором мыши через CGEvent API.
/// Требует разрешение Accessibility в Системных настройках.
enum MouseController {

    // MARK: - Перемещение курсора

    /// Сдвигает курсор на (dx, dy) пикселей относительно текущей позиции.
    static func moveMouse(dx: Double, dy: Double) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: current.x + dx, y: current.y + dy)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPos,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Клик

    /// Выполняет клик указанной кнопкой.
    /// count = 1 → одиночный клик, count = 2 → двойной.
    static func click(button: RemoteCommand.MouseButton, count: Int = 1) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        let (downType, upType, cgButton) = eventTypes(for: button)
        let clickCount = max(count, 1)

        for i in 1...clickCount {
            if let down = CGEvent(
                mouseEventSource: nil,
                mouseType: downType,
                mouseCursorPosition: pos,
                mouseButton: cgButton
            ) {
                down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                down.post(tap: .cghidEventTap)
            }

            if let up = CGEvent(
                mouseEventSource: nil,
                mouseType: upType,
                mouseCursorPosition: pos,
                mouseButton: cgButton
            ) {
                up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Вспомогательные методы

    /// Возвращает типы CGEvent для нажатия/отпускания по кнопке мыши.
    static func eventTypes(
        for button: RemoteCommand.MouseButton
    ) -> (down: CGEventType, up: CGEventType, cgButton: CGMouseButton) {
        switch button {
        case .left:  return (.leftMouseDown,  .leftMouseUp,  .left)
        case .right: return (.rightMouseDown, .rightMouseUp, .right)
        }
    }
}
