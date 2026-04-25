import SwiftUI
import UIKit

// MARK: - Тачпад
struct TouchpadView: View {
    var body: some View {
        TouchpadRepresentable()
            .frame(maxWidth: .infinity, minHeight: 280)
            // Фон задаётся внутри UIKit-вью, чтобы не ломать hit-testing
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Важно: не перехватывать жесты на уровне SwiftUI
            .contentShape(Rectangle())
            .allowsHitTesting(true)
    }
}

// MARK: - UIViewRepresentable
struct TouchpadRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchpadUIView {
        TouchpadUIView()
    }
    func updateUIView(_ uiView: TouchpadUIView, context: Context) {}
}

// MARK: - UIKit View
/// Жесты:
/// - 1 палец drag  → перемещение курсора
/// - 1 тап         → левый клик
/// - 2 пальца тап  → правый клик (контекстное меню)
/// - Долгое удержание одним пальцем → зажать левую кнопку (drag) до конца жеста
final class TouchpadUIView: UIView {

    private let connection  = ConnectionManager.shared
    private let sensitivity: CGFloat = 1.8

    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    private var lastPanTranslation: CGPoint = .zero
    private var isMouseDown: Bool = false

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        isMultipleTouchEnabled = true

        // Подготовка тактильной отдачи
        lightImpact.prepare()
        mediumImpact.prepare()

        setupGestures()
    }

    // MARK: - Точечная сетка
    override func layoutSubviews() {
        super.layoutSubviews()
        drawDotGrid()
    }

    private func drawDotGrid() {
        layer.sublayers?
            .filter { $0.name == "dotGrid" }
            .forEach { $0.removeFromSuperlayer() }

        let gridLayer = CAShapeLayer()
        gridLayer.name = "dotGrid"

        let path    = UIBezierPath()
        let spacing : CGFloat = 24
        let dotR    : CGFloat = 0.75
        let cols    = Int(bounds.width  / spacing)
        let rows    = Int(bounds.height / spacing)
        let offX    = (bounds.width  - CGFloat(cols) * spacing) / 2
        let offY    = (bounds.height - CGFloat(rows) * spacing) / 2

        for row in 0...rows {
            for col in 0...cols {
                let x = offX + CGFloat(col) * spacing
                let y = offY + CGFloat(row) * spacing
                path.move(to: CGPoint(x: x + dotR, y: y))
                path.addArc(
                    withCenter: CGPoint(x: x, y: y),
                    radius: dotR,
                    startAngle: 0, endAngle: .pi * 2,
                    clockwise: true
                )
            }
        }

        gridLayer.path      = path.cgPath
        gridLayer.fillColor = UIColor.white.withAlphaComponent(0.25).cgColor
        layer.addSublayer(gridLayer)
    }

    // MARK: - Жесты
    private func setupGestures() {
        // 1 тап, 1 палец → левый клик
        let tap1 = UITapGestureRecognizer(
            target: self, action: #selector(handleSingleTap))
        tap1.numberOfTapsRequired    = 1
        tap1.numberOfTouchesRequired = 1

        // 1 тап, 2 пальца → правый клик
        let tap2 = UITapGestureRecognizer(
            target: self, action: #selector(handleTwoFingerTap))
        tap2.numberOfTapsRequired    = 1
        tap2.numberOfTouchesRequired = 2

        // 1 палец drag → перемещение курсора
        let pan = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

        // Долгое удержание — зажать левую кнопку (для drag)
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.25
        longPress.numberOfTouchesRequired = 1
        // Чтобы pan и longPress могли сосуществовать
        pan.require(toFail: longPress)

        addGestureRecognizer(tap1)
        addGestureRecognizer(tap2)
        addGestureRecognizer(pan)
        addGestureRecognizer(longPress)
    }

    // MARK: - Обработчики
    @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        lightImpact.impactOccurred()
        connection.send(.click(button: .left, count: 1))
        showTapFeedback(at: g.location(in: self))
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        mediumImpact.impactOccurred()
        connection.send(.click(button: .right, count: 1))
        showTapFeedback(at: g.location(in: self))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let t  = g.translation(in: self)
            let dx = (t.x - lastPanTranslation.x) * sensitivity
            let dy = (t.y - lastPanTranslation.y) * sensitivity
            lastPanTranslation = t

            if isMouseDown {
                connection.send(.mouseDrag(dx: dx, dy: dy))
            } else {
                connection.send(.mouseMove(dx: dx, dy: dy))
            }
        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
            if isMouseDown {
                // Отпускаем кнопку, если была зажата через longPress
                isMouseDown = false
                connection.send(.mouseUp(button: .left))
            }
        default:
            break
        }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            // Зажимаем левую кнопку для drag
            isMouseDown = true
            connection.send(.mouseDown(button: .left))
            lightImpact.impactOccurred(intensity: 0.7)
            showTapFeedback(at: g.location(in: self))
        case .ended, .cancelled, .failed:
            if isMouseDown {
                isMouseDown = false
                connection.send(.mouseUp(button: .left))
            }
        default:
            break
        }
    }

    // MARK: - Визуальная обратная связь
    private func showTapFeedback(at point: CGPoint) {
        let size: CGFloat = 50
        let circle = CAShapeLayer()
        circle.path = UIBezierPath(ovalIn: CGRect(
            x: point.x - size / 2, y: point.y - size / 2,
            width: size, height: size)
        ).cgPath
        circle.fillColor = UIColor.white.withAlphaComponent(0.2).cgColor
        layer.addSublayer(circle)

        CATransaction.begin()
        CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
        let fade          = CABasicAnimation(keyPath: "opacity")
        fade.fromValue    = 0.3
        fade.toValue      = 0.0
        fade.duration     = 0.3
        circle.add(fade, forKey: "fade")
        circle.opacity    = 0
        CATransaction.commit()
    }
}

// MARK: - Preview
#Preview {
    TouchpadView()
        .frame(height: 300)
        .preferredColorScheme(.dark)
}
