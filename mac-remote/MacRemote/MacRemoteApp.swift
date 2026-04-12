import SwiftUI

// MARK: - Точка входа iOS-приложения MacRemote

/// Главное приложение — пульт дистанционного управления Mac.
/// Тёмная тема по умолчанию, четыре вкладки: Тачпад, Клавиатура, Медиа, Связь.
@main
struct MacRemoteApp: App {

    /// Единый менеджер подключений, доступный через environment.
    @State private var connectionManager = ConnectionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // Запускаем обнаружение при старте приложения
                    connectionManager.startDiscovery()
                }
        }
    }
}
