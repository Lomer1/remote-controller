import SwiftUI
import UIKit

// MARK: - Тачпад: полная эмуляция трекпада Mac через UIKit

/// SwiftUI-обёртка для тачпада. Вся логика жестов реализована
/// в UIKit (UIViewRepresentable → TouchpadUIView) для точного
/// контроля над мультитач-жестами, как на настоящем трекпаде Mac.
struct TouchpadView: View {
    var body: some View {
        TouchpadRepresentable()
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

// MARK: - UIViewRepresentable обёртка

struct TouchpadRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchpadUIView {
        TouchpadUIView()
    }

    func updateUIView(_ uiView: TouchpadUIView, context: Context) {}
}

// MARK: - UIKit View с жестами

/// Основной UIView тачпада. Содержит все UIGestureRecognizer'ы
/// для эмуляции поведения трекпада Mac:
/// - 1 палец drag → перемещение курсора
/// - 1 тап → левый клик
/// - 2 тапа (double tap) → правый клик (контекстное меню)
/// - Long press + drag → drag & drop (mouseDown → mouseDrag → mouseUp)
/// - 2 пальца drag → скролл
/// - 2 пальца свайп горизонтально → назад/вперёд (swipe2)
/// - 3 пальца свайп → Mission Control / Exposé / смена рабочего стола (swipe3)
final class TouchpadUIView: UIView, UIGestureRecognizerDelegate {

    private let connection = ConnectionManager.shared

    // MARK: - Настройки

    /// Множитель чувствительности курсора.
    private let sensitivity: CGFloat = 1.8

    // MARK: - Haptic-генераторы

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Состояние жестов

    /// Последняя позиция pan-жеста (для вычисления дельты).
    private var lastPanTranslation: CGPoint = .zero

    /// Последняя позиция скролл-жеста.
    private var lastScrollTranslation: CGPoint = .zero

    /// Режим перетаскивания (drag & drop): активен после long press.
    private var isDragMode = false

    // MARK: - Ссылки на жесты (для настройки зависимостей)

    private var panGesture: UIPanGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!

    // MARK: - Инициализация

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
    }

    private func setupView() {
        backgroundColor = .black
        isMultipleTouchEnabled = true
    }

    // MARK: - Точечная сетка (фон тачпада)

    override func layoutSubviews() {
        super.layoutSubviews()
        drawDotGrid()
    }

    /// Рисует точечную сетку на фоне тачпада через CAShapeLayer.
    private func drawDotGrid() {
        // Удаляем предыдущий слой сетки (при перерисовке)
        layer.sublayers?.filter { $0.name == "dotGrid" }.forEach { $0.removeFromSuperlayer() }

        let gridLayer = CAShapeLayer()
        gridLayer.name = "dotGrid"
        let path = UIBezierPath()

        let spacing: CGFloat = 24
        let dotRadius: CGFloat = 0.75
        let cols = Int(bounds.width / spacing)
        let rows = Int(bounds.height / spacing)
        let offsetX = (bounds.width - CGFloat(cols) * spacing) / 2
        let offsetY = (bounds.height - CGFloat(rows) * spacing) / 2

        for row in 0...rows {
            for col in 0...cols {
                let x = offsetX + CGFloat(col) * spacing
                let y = offsetY + CGFloat(row) * spacing
                path.move(to: CGPoint(x: x + dotRadius, y: y))
                path.addArc(
                    withCenter: CGPoint(x: x, y: y),
                    radius: dotRadius,
                    startAngle: 0,
                    endAngle: .pi * 2,
                    clockwise: true
                )
            }
        }

        gridLayer.path = path.cgPath
        gridLayer.fillColor = UIColor.white.withAlphaComponent(0.25).cgColor
        layer.addSublayer(gridLayer)
    }

    // MARK: - Настройка жестов

    private func setupGestures() {

        // --- Тапы ---

        // Одиночный тап = левый клик
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1

        // Двойной тап = правый клик (контекстное меню)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1

        // Одиночный тап ждёт, пока двойной не провалится
        singleTap.require(toFail: doubleTap)

        // --- Перемещение курсора (1 палец) ---

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self  // Для одновременного распознавания с long press
        self.panGesture = pan

        // --- Long press = режим drag & drop ---

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.3
        longPress.delegate = self  // Для одновременного распознавания с pan
        self.longPressGesture = longPress

        // Pan и long press работают одновременно — isDragMode управляет поведением.
        // НЕ делаем pan.require(toFail: longPress), иначе курсор не будет двигаться
        // до завершения long press таймера.

        // --- Скролл (2 пальца) ---

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2

        // --- 2-пальцевые свайпы (назад/вперёд) ---

        let swipe2Left = makeSwipeRecognizer(direction: .left, touches: 2, action: #selector(handleSwipe2Left))
        let swipe2Right = makeSwipeRecognizer(direction: .right, touches: 2, action: #selector(handleSwipe2Right))

        // Скролл ждёт провала свайпов (свайпы приоритетнее)
        scroll.require(toFail: swipe2Left)
        scroll.require(toFail: swipe2Right)

        // --- 3-пальцевые свайпы (Mission Control, Exposé, смена рабочего стола) ---

        let swipe3Up = makeSwipeRecognizer(direction: .up, touches: 3, action: #selector(handleSwipe3Up))
        let swipe3Down = makeSwipeRecognizer(direction: .down, touches: 3, action: #selector(handleSwipe3Down))
        let swipe3Left = makeSwipeRecognizer(direction: .left, touches: 3, action: #selector(handleSwipe3Left))
        let swipe3Right = makeSwipeRecognizer(direction: .right, touches: 3, action: #selector(handleSwipe3Right))

        // --- Добавляем все жесты на view ---

        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(pan)
        addGestureRecognizer(longPress)
        addGestureRecognizer(scroll)
        addGestureRecognizer(swipe2Left)
        addGestureRecognizer(swipe2Right)
        addGestureRecognizer(swipe3Up)
        addGestureRecognizer(swipe3Down)
        addGestureRecognizer(swipe3Left)
        addGestureRecognizer(swipe3Right)
    }

    /// Фабрика для создания UISwipeGestureRecognizer с настройками.
    private func makeSwipeRecognizer(
        direction: UISwipeGestureRecognizer.Direction,
        touches: Int,
        action: Selector
    ) -> UISwipeGestureRecognizer {
        let swipe = UISwipeGestureRecognizer(target: self, action: action)
        swipe.direction = direction
        swipe.numberOfTouchesRequired = touches
        swipe.delegate = self  // Для одновременного распознавания свайпов
        return swipe
    }

    // MARK: - Обработчики тапов

    /// 1 тап → левый клик.
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        lightImpact.impactOccurred()
        connection.send(.click(button: .left, count: 1))
        showTapFeedback(at: gesture.location(in: self))
    }

    /// 2 тапа (double tap) → правый клик (контекстное меню).
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.click(button: .right, count: 1))
        showTapFeedback(at: gesture.location(in: self))
    }

    // MARK: - Перемещение курсора / drag

    /// 1 палец drag → перемещение курсора (или mouseDrag в режиме drag & drop).
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastPanTranslation = .zero

        case .changed:
            let translation = gesture.translation(in: self)
            let dx = (translation.x - lastPanTranslation.x) * sensitivity
            let dy = (translation.y - lastPanTranslation.y) * sensitivity
            lastPanTranslation = translation

            if isDragMode {
                // В режиме drag: двигаем с зажатой кнопкой
                connection.send(.mouseDrag(dx: dx, dy: dy))
            } else {
                // Обычное перемещение курсора
                connection.send(.mouseMove(dx: dx, dy: dy))
            }

        case .ended, .cancelled:
            if isDragMode {
                // Отпускаем кнопку мыши при завершении перетаскивания
                connection.send(.mouseUp(button: .left))
                isDragMode = false
            }

        default:
            break
        }
    }

    // MARK: - Long press (drag & drop)

    /// Long press → включает режим drag & drop.
    /// При began: зажимает кнопку мыши (mouseDown).
    /// Перемещение после этого обрабатывается в handlePan через isDragMode.
    /// При ended: отпускает кнопку (mouseUp) — дублируется здесь на случай,
    /// если pan завершился раньше или не сработал.
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDragMode = true
            mediumImpact.impactOccurred()
            connection.send(.mouseDown(button: .left))

        case .ended, .cancelled:
            if isDragMode {
                connection.send(.mouseUp(button: .left))
                isDragMode = false
            }

        default:
            break
        }
    }

    // MARK: - Скролл (2 пальца)

    /// 2 пальца drag → скролл. Y инвертирован для natural scrolling.
    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastScrollTranslation = .zero

        case .changed:
            let translation = gesture.translation(in: self)
            let dx = translation.x - lastScrollTranslation.x
            let dy = translation.y - lastScrollTranslation.y
            lastScrollTranslation = translation
            // Инвертируем Y для natural scrolling (как на Mac)
            connection.send(.scroll(dx: dx, dy: -dy))

        case .ended, .cancelled:
            lastScrollTranslation = .zero

        default:
            break
        }
    }

    // MARK: - 2-пальцевые свайпы (навигация назад/вперёд)

    @objc private func handleSwipe2Left(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.twoFingerSwipe(direction: .left))
    }

    @objc private func handleSwipe2Right(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.twoFingerSwipe(direction: .right))
    }

    // MARK: - 3-пальцевые свайпы (Mission Control / Exposé / рабочие столы)

    @objc private func handleSwipe3Up(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.threeFingerSwipe(direction: .up))
    }

    @objc private func handleSwipe3Down(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.threeFingerSwipe(direction: .down))
    }

    @objc private func handleSwipe3Left(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.threeFingerSwipe(direction: .left))
    }

    @objc private func handleSwipe3Right(_ gesture: UISwipeGestureRecognizer) {
        mediumImpact.impactOccurred()
        connection.send(.threeFingerSwipe(direction: .right))
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Разрешает одновременное распознавание для:
    /// - Pan + LongPress (drag & drop: long press включает режим, pan двигает)
    /// - Все свайпы между собой (чтобы не блокировали друг друга)
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Pan + LongPress — нужно для drag & drop
        let isPanAndLongPress =
            (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer) ||
            (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
        if isPanAndLongPress { return true }

        // Свайпы между собой
        let bothSwipes =
            gestureRecognizer is UISwipeGestureRecognizer && otherGestureRecognizer is UISwipeGestureRecognizer
        if bothSwipes { return true }

        return false
    }

    // MARK: - Визуальная обратная связь

    /// Показывает круг-вспышку в точке тапа с анимацией затухания.
    private func showTapFeedback(at point: CGPoint) {
        let size: CGFloat = 50
        let circle = CAShapeLayer()
        circle.path = UIBezierPath(
            ovalIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        ).cgPath
        circle.fillColor = UIColor.white.withAlphaComponent(0.2).cgColor
        layer.addSublayer(circle)

        CATransaction.begin()
        CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.3
        fade.toValue = 0.0
        fade.duration = 0.3
        circle.add(fade, forKey: "fade")
        circle.opacity = 0

        CATransaction.commit()
    }
}

// MARK: - Preview

#Preview {
    TouchpadView()
        .preferredColorScheme(.dark)
}
