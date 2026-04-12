import SwiftUI

// MARK: - Подключение: обнаружение и подключение к Mac

/// Показывает обнаруженные Mac-серверы, статус подключения,
/// переключатель авто-переподключения.
struct ConnectionView: View {

    @Bindable private var connection = ConnectionManager.shared
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Статус текущего подключения
                connectionStatusCard

                // Переключатель автореконнекта
                autoReconnectToggle

                // Заголовок списка
                HStack {
                    Text("Доступные устройства")
                        .font(.headline)
                    Spacer()

                    // Кнопка обновления
                    Button {
                        connection.stopDiscovery()
                        connection.startDiscovery()
                        impact.impactOccurred()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 4)

                // Список обнаруженных серверов
                if connection.discoveredServers.isEmpty {
                    emptyStateView
                } else {
                    serversList
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color.black)
        .onAppear {
            connection.startDiscovery()
        }
    }

    // MARK: - Карточка статуса подключения

    private var connectionStatusCard: some View {
        VStack(spacing: 12) {
            // Иконка статуса
            ZStack {
                Circle()
                    .fill(
                        connection.isConnected
                            ? RadialGradient(colors: [.green.opacity(0.3), .clear], center: .center, startRadius: 10, endRadius: 40)
                            : RadialGradient(colors: [.gray.opacity(0.2), .clear], center: .center, startRadius: 10, endRadius: 40)
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: connection.isConnected ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(connection.isConnected ? .green : .secondary)
            }

            // Текст статуса
            if connection.isConnected {
                Text(connection.connectedServerName ?? "Mac")
                    .font(.title3.weight(.semibold))
                Text("Подключено через \(connection.activeTransport?.rawValue ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Кнопка отключения
                Button {
                    connection.disconnect()
                    impact.impactOccurred()
                } label: {
                    Text("Отключиться")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.1), in: Capsule())
                }
            } else {
                Text("Не подключено")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Ищем Mac в сети...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Авто-переподключение

    private var autoReconnectToggle: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
            Text("Авто-переподключение")
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $connection.autoReconnect)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Список серверов

    private var serversList: some View {
        VStack(spacing: 10) {
            ForEach(connection.discoveredServers) { server in
                serverCard(server)
            }
        }
    }

    /// Карточка обнаруженного сервера.
    private func serverCard(_ server: DiscoveredServer) -> some View {
        let isThisConnected = connection.isConnected && connection.connectedServerName == server.name

        return Button {
            if isThisConnected {
                connection.disconnect()
            } else {
                connection.connect(to: server)
            }
            impact.impactOccurred()
        } label: {
            HStack(spacing: 14) {
                // Иконка транспорта
                Image(systemName: server.transport == .bonjour ? "wifi" : "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(
                        isThisConnected
                            ? AnyShapeStyle(.green)
                        : AnyShapeStyle(.white)
                    )
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())

                // Инфо
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)

                    Text(server.transport.rawValue)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()

                // Индикатор состояния
                if isThisConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Подключено")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isThisConnected ? .green.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
    }

    // MARK: - Пустое состояние

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("Серверы не найдены")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Убедитесь, что MacRemote Server\nзапущен на вашем Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    ConnectionView()
        .preferredColorScheme(.dark)
}
