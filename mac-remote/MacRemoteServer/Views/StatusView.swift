import SwiftUI

// MARK: - Popover-вью статуса сервера

/// Отображается при нажатии на иконку в меню баре.
/// Показывает: статус серверов, IP-адрес, порт, список подключённых клиентов.
struct StatusView: View {
    @Environment(ConnectionManager.self) private var connectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок
            headerSection

            Divider()

            // Информация о сервере
            serverInfoSection

            Divider()

            // Список подключённых клиентов
            connectedClientsSection

            Divider()

            // Кнопки управления
            controlsSection
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Секции

    private var headerSection: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(connectionManager.isRunning ? .green : .red)

            VStack(alignment: .leading) {
                Text("MacRemote Server")
                    .font(.headline)
                Text(connectionManager.isRunning ? "Работает" : "Остановлен")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Индикатор числа подключений
            if connectionManager.totalConnectedCount > 0 {
                Text("\(connectionManager.totalConnectedCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue, in: Capsule())
            }
        }
    }

    private var serverInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("IP: \(connectionManager.localIPAddress)")
                    .font(.system(.body, design: .monospaced))
            } icon: {
                Image(systemName: "network")
                    .frame(width: 20)
            }

            if connectionManager.serverPort > 0 {
                Label {
                    Text("Порт: \(connectionManager.serverPort)")
                        .font(.system(.body, design: .monospaced))
                } icon: {
                    Image(systemName: "door.left.hand.open")
                        .frame(width: 20)
                }
            }

            Label {
                HStack(spacing: 4) {
                    statusDot(active: connectionManager.bonjourServer.isRunning)
                    Text("Bonjour TCP")
                        .font(.caption)
                    Spacer()
                    statusDot(active: connectionManager.multipeerServer.isRunning)
                    Text("Multipeer")
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .frame(width: 20)
            }
        }
    }

    private var connectedClientsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Подключённые устройства")
                .font(.subheadline.bold())

            if connectionManager.connectedClientDescriptions.isEmpty {
                Text("Нет подключений")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(connectionManager.connectedClientDescriptions, id: \.self) { description in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundStyle(.blue)
                        Text(description)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var controlsSection: some View {
        HStack {
            Button(connectionManager.isRunning ? "Остановить" : "Запустить") {
                if connectionManager.isRunning {
                    connectionManager.stopAll()
                } else {
                    connectionManager.startAll()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(connectionManager.isRunning ? .red : .green)

            Spacer()

            Button("Завершить") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Вспомогательные вью

    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? .green : .red)
            .frame(width: 8, height: 8)
    }
}
