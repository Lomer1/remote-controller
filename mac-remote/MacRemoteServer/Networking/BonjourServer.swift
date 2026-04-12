import Foundation
import Network
import os

// MARK: - TCP-сервер с Bonjour (Network.framework)

/// TCP-сервер, использующий NWListener для приёма соединений
/// и Bonjour для автоматического обнаружения в локальной сети.
/// Сервис объявляется как `_macremote._tcp`.
@Observable
final class BonjourServer {

    // MARK: - Состояние

    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var connections: [ClientConnection] = []

    /// Информация о подключённом клиенте
    struct ClientConnection: Identifiable {
        let id: UUID
        let endpoint: String
        let connection: NWConnection

        /// Буфер для накопления неполных JSON-строк
        var buffer = Data()
    }

    /// Колбэк для обработки полученных команд
    var onCommand: ((RemoteCommand) -> Void)?

    // MARK: - Приватные свойства

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.macremote.bonjour", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.macremote.server", category: "BonjourServer")

    // MARK: - Запуск / Остановка

    /// Запускает TCP-сервер с Bonjour-объявлением.
    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)

            // Bonjour-объявление — iOS-клиент найдёт сервер автоматически
            listener.service = NWListener.Service(name: "MacRemote", type: "_macremote._tcp")

            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
            logger.info("Bonjour-сервер запускается...")
        } catch {
            logger.error("Не удалось создать NWListener: \(error.localizedDescription)")
        }
    }

    /// Останавливает сервер и закрывает все соединения.
    func stop() {
        listener?.cancel()
        listener = nil
        for client in connections {
            client.connection.cancel()
        }
        connections.removeAll()
        isRunning = false
        logger.info("Bonjour-сервер остановлен")
    }

    // MARK: - Обработка состояния слушателя

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                self.port = port.rawValue
            }
            DispatchQueue.main.async {
                self.isRunning = true
            }
            logger.info("Сервер слушает на порту \(self.port)")

        case .failed(let error):
            logger.error("Listener failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isRunning = false
            }
            // Попытка перезапуска через секунду
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.start()
            }

        case .cancelled:
            DispatchQueue.main.async {
                self.isRunning = false
            }

        default:
            break
        }
    }

    // MARK: - Обработка новых соединений

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let endpointDescription = "\(nwConnection.endpoint)"
        logger.info("Новое подключение: \(endpointDescription)")

        let client = ClientConnection(
            id: UUID(),
            endpoint: endpointDescription,
            connection: nwConnection
        )

        nwConnection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, clientId: client.id)
        }

        nwConnection.start(queue: queue)
        receiveData(from: client.id, connection: nwConnection)

        DispatchQueue.main.async {
            self.connections.append(client)
        }
    }

    // MARK: - Обработка состояния соединения

    private func handleConnectionState(_ state: NWConnection.State, clientId: UUID) {
        switch state {
        case .ready:
            logger.info("Клиент \(clientId) подключён")

        case .failed(let error):
            logger.warning("Клиент \(clientId) — ошибка: \(error.localizedDescription)")
            removeConnection(clientId)

        case .cancelled:
            logger.info("Клиент \(clientId) отключён")
            removeConnection(clientId)

        default:
            break
        }
    }

    private func removeConnection(_ clientId: UUID) {
        DispatchQueue.main.async {
            self.connections.removeAll { $0.id == clientId }
        }
    }

    // MARK: - Получение данных

    /// Рекурсивно читает данные из соединения и парсит JSON-команды.
    private func receiveData(from clientId: UUID, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.processReceivedData(data, clientId: clientId)
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            // Продолжаем читать
            self.receiveData(from: clientId, connection: connection)
        }
    }

    /// Обрабатывает полученные данные: добавляет в буфер, парсит команды.
    private func processReceivedData(_ data: Data, clientId: UUID) {
        // Находим клиента и обновляем буфер
        guard let index = connections.firstIndex(where: { $0.id == clientId }) else { return }

        var buffer = connections[index].buffer + data
        let (commands, remainder) = RemoteCommand.parseBuffer(buffer)
        buffer = remainder

        DispatchQueue.main.async {
            if let idx = self.connections.firstIndex(where: { $0.id == clientId }) {
                self.connections[idx].buffer = buffer
            }
        }

        // Выполняем команды на главном потоке
        for command in commands {
            DispatchQueue.main.async { [weak self] in
                self?.onCommand?(command)
            }
        }
    }
}
