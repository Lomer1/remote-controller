import SwiftUI

// MARK: - Точка входа приложения

/// Menu bar приложение (без иконки в Dock).
/// Использует MenuBarExtra (macOS 13+) для отображения статуса в меню баре.
@main
struct MacRemoteServerApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        // MenuBarExtra — приложение живёт только в меню баре
        MenuBarExtra {
            StatusView()
                .environment(connectionManager)
        } label: {
            // SF Symbol + количество подключённых клиентов
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Иконка и бейдж в меню баре.
    private var menuBarLabel: some View {
        HStack(spacing: 2) {
            Image(systemName: connectionManager.totalConnectedCount > 0
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")

            if connectionManager.totalConnectedCount > 0 {
                Text("\(connectionManager.totalConnectedCount)")
                    .font(.caption2)
            }
        }
        .onAppear {
            // Запускаем серверы при старте приложения
            connectionManager.startAll()
        }
    }
}
