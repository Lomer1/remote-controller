import SwiftUI

// MARK: - Клавиатура: ввод текста и быстрые действия

/// Экран клавиатуры с текстовым полем для ввода и сеткой горячих клавиш.
/// Модификаторы (Cmd, Shift, Ctrl, Opt) — переключаемые кнопки-пилюли сверху.
struct KeyboardView: View {

    private let connection = ConnectionManager.shared
    private let impact = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Состояние

    @State private var textInput = ""
    @State private var cmdActive = false
    @State private var shiftActive = false
    @State private var ctrlActive = false
    @State private var optActive = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Текстовое поле для ввода
                textInputSection

                // Модификаторы
                modifierKeysRow

                // Быстрые действия (горячие клавиши)
                quickActionsGrid

                // Клавиши навигации (стрелки)
                arrowKeysSection

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.black)
    }

    // MARK: - Текстовый ввод

    private var textInputSection: some View {
        HStack(spacing: 12) {
            TextField("Введите текст...", text: $textInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendTextAndClear()
                }
                .onChange(of: textInput) { oldValue, newValue in
                    // Отправляем каждый новый символ
                    if newValue.count > oldValue.count {
                        let newChars = String(newValue.suffix(newValue.count - oldValue.count))
                        connection.send(.keypress(text: newChars))
                    }
                }

            // Кнопка Enter
            Button {
                connection.send(.hotkey(modifiers: [], key: "return"))
                impact.impactOccurred()
            } label: {
                Image(systemName: "return")
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
        }
    }

    // MARK: - Модификаторы (Cmd, Shift, Ctrl, Opt)

    private var modifierKeysRow: some View {
        HStack(spacing: 8) {
            modifierPill("Cmd", symbol: "command", isActive: $cmdActive)
            modifierPill("Shift", symbol: "shift", isActive: $shiftActive)
            modifierPill("Ctrl", symbol: "control", isActive: $ctrlActive)
            modifierPill("Opt", symbol: "option", isActive: $optActive)
        }
    }

    /// Кнопка-пилюля для модификатора.
    private func modifierPill(_ title: String, symbol: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
            impact.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isActive.wrappedValue
                    ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .foregroundStyle(isActive.wrappedValue ? .white : .secondary)
        }
    }

    // MARK: - Быстрые действия

    private var quickActionsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 10) {
            // Буфер обмена
            quickKey("doc.on.doc", label: "Copy", modifiers: [.cmd], key: "c")
            quickKey("doc.on.clipboard", label: "Paste", modifiers: [.cmd], key: "v")
            quickKey("scissors", label: "Cut", modifiers: [.cmd], key: "x")
            quickKey("arrow.uturn.backward", label: "Undo", modifiers: [.cmd], key: "z")

            // Редактирование
            quickKey("checkmark.rectangle", label: "All", modifiers: [.cmd], key: "a")
            quickKey("square.and.arrow.down", label: "Save", modifiers: [.cmd], key: "s")
            quickKey("magnifyingglass", label: "Find", modifiers: [.cmd], key: "f")
            quickKey("rectangle.on.rectangle", label: "Tab", modifiers: [.cmd], key: "tab")

            // Системные
            quickKey("escape", label: "Esc", modifiers: [], key: "escape")
            quickKey("arrow.right.to.line", label: "Tab", modifiers: [], key: "tab")
            quickKey("delete.left", label: "Delete", modifiers: [], key: "delete")
            quickKey("magnifyingglass", label: "Spotlight", modifiers: [.cmd], key: "space")

            // Скриншот и ещё
            quickKey("camera.viewfinder", label: "Screen", modifiers: [.cmd, .shift], key: "3")
            quickKey("terminal", label: "Terminal", modifiers: [.cmd], key: "space")
            quickKey("arrow.uturn.forward", label: "Redo", modifiers: [.cmd, .shift], key: "z")
            quickKey("xmark.circle", label: "Quit", modifiers: [.cmd], key: "q")
        }
    }

    /// Кнопка быстрого действия.
    private func quickKey(
        _ symbol: String,
        label: String,
        modifiers: [RemoteCommand.Modifier],
        key: String
    ) -> some View {
        Button {
            // Добавляем активные модификаторы с панели
            var allMods = modifiers
            if cmdActive && !allMods.contains(.cmd) { allMods.append(.cmd) }
            if shiftActive && !allMods.contains(.shift) { allMods.append(.shift) }
            if ctrlActive && !allMods.contains(.ctrl) { allMods.append(.ctrl) }
            if optActive && !allMods.contains(.opt) { allMods.append(.opt) }

            connection.send(.hotkey(modifiers: allMods, key: key))
            impact.impactOccurred()

            // Сбрасываем модификаторы после отправки (одноразовый режим)
            cmdActive = false
            shiftActive = false
            ctrlActive = false
            optActive = false
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Стрелки

    private var arrowKeysSection: some View {
        VStack(spacing: 6) {
            // Верхняя стрелка
            arrowButton("chevron.up", key: "up")

            HStack(spacing: 6) {
                arrowButton("chevron.left", key: "left")
                arrowButton("chevron.down", key: "down")
                arrowButton("chevron.right", key: "right")
            }
        }
        .padding(.top, 4)
    }

    /// Кнопка стрелки.
    private func arrowButton(_ symbol: String, key: String) -> some View {
        Button {
            var mods: [RemoteCommand.Modifier] = []
            if cmdActive { mods.append(.cmd) }
            if shiftActive { mods.append(.shift) }
            if ctrlActive { mods.append(.ctrl) }
            if optActive { mods.append(.opt) }

            connection.send(.hotkey(modifiers: mods, key: key))
            impact.impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .frame(width: 70, height: 50)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Отправка текста

    private func sendTextAndClear() {
        guard !textInput.isEmpty else { return }
        // Текст уже отправлен по символам через onChange
        textInput = ""
    }
}

#Preview {
    KeyboardView()
        .preferredColorScheme(.dark)
}
