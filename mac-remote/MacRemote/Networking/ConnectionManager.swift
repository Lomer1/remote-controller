import Foundation
import Network
import MultipeerConnectivity
import os

// MARK: - Тип транспорта

enum TransportType: String {
    case bonjour = "Wi-Fi"
    case multipeer = "Bluetooth"
}

// MARK: - Обнаруженный сервер (для отображения в UI)

struct DiscoveredServer: Identifiable {
    let id: String
    let name: String
    let transport: TransportType

    /// Ссылка на оригинальный результат Bonjour (для подключения).
    var bonjourResult: NWBrowser.Result?
    /// Ссылка на MC пир (для подключения).
    var multipeerPeerID: MCPeerID?
}

// MARK: - Единый менеджер подключений (iOS-клиент)

/// Управляет обоими транспортами (Bonjour + MultipeerConnectivity),
/// предоставляет единый интерфейс для отправки команд
/// и публикует состояние для SwiftUI.
@Observable
final class ConnectionManager {

    // MARK: - Singleton

    static let shared = ConnectionManager()

    // MARK: - Состояние подключения

    /// Подключены ли мы к серверу.
    private(set) var isConnected = false

    /// Имя подключённого сервера.
    private(set) var connectedServerName: String?

    /// Тип транспорта текущего подключения.
    private(set) var activeTransport: TransportType?

    /// Автоматическое переподключение.
    var autoReconnect = true

    // MARK: - Реальные значения с Mac (обновляются через systeminfo)

    /// Текущая громкость Mac (0.0 – 1.0).
    private(set) var currentVolume: Double = 0.5

    /// Текущая яркость экрана Mac (0.0 – 1.0).
    private(set) var currentBrightness: Double = 0.5
    
    /// Текущее сотояние звука
    private(set) var isMuted: Bool = false

    /// Список обнаруженных серверов.
    var discoveredServers: [DiscoveredServer] {
        var servers: [DiscoveredServer] = []

        // Bonjour-сервисы
        for result in bonjourBrowser.discoveredServices {
            let name = result.serviceName
            servers.append(DiscoveredServer(
                id: "bonjour-\(name)",
                name: name,
                transport: .bonjour,
                bonjourResult: result
            ))
        }

        // MultipeerConnectivity-пиры
        for peer in multipeerBrowser.discoveredPeers {
            // Не дублируем, если уже найден через Bonjour
            if !servers.contains(where: { $0.name == peer.displayName }) {
                servers.append(DiscoveredServer(
                    id: "mc-\(peer.displayName)",
                    name: peer.displayName,
                    transport: .multipeer,
                    multipeerPeerID: peer
                ))
            }
        }

        return servers
    }

    // MARK: - Транспорты

    let bonjourBrowser = BonjourBrowser()
    let multipeerBrowser = MultipeerBrowser()

    // MARK: - Private

    private var lastBonjourResult: NWBrowser.Result?
    private var lastMultipeerPeer: MCPeerID?
    private var reconnectTask: Task<Void, Never>?
    private var systemInfoTask: Task<Void, Never>?
    private var receiveBuffer = Data()
    private let logger = Logger(subsystem: "com.macremote.client", category: "ConnectionManager")

    // MARK: - Init

    private init() {
        setupCallbacks()
    }

    // MARK: - Настройка callbacks

    private func setupCallbacks() {
        // Bonjour: изменение состояния подключения
        bonjourBrowser.onConnectionStateChange = { [weak self] connected in
            guard let self else { return }
            if connected {
                self.isConnected = true
                self.connectedServerName = self.bonjourBrowser.connectedServerName
                self.activeTransport = .bonjour
                self.logger.info("Подключён через Bonjour: \(self.connectedServerName ?? "?")")
                self.requestSystemInfoAfterConnect()
            } else {
                // Потеряли TCP-соединение
                if self.activeTransport == .bonjour {
                    self.handleDisconnect()
                }
            }
        }

        // Bonjour: получение данных от сервера
        bonjourBrowser.onReceiveData = { [weak self] data in
            self?.handleServerMessage(data)
        }

        // MultipeerConnectivity: изменение состояния
        multipeerBrowser.onConnectionStateChange = { [weak self] connected in
            guard let self else { return }
            if connected {
                self.isConnected = true
                self.connectedServerName = self.multipeerBrowser.connectedPeers.first?.displayName
                self.activeTransport = .multipeer
                self.logger.info("Подключён через MC: \(self.connectedServerName ?? "?")")
                self.requestSystemInfoAfterConnect()
            } else {
                if self.activeTransport == .multipeer {
                    self.handleDisconnect()
                }
            }
        }

        // MultipeerConnectivity: получение данных от сервера
        multipeerBrowser.onReceiveData = { [weak self] data in
            self?.handleServerMessage(data)
        }
    }

    // MARK: - Запуск / Остановка обнаружения

    /// Запускает поиск серверов через оба транспорта.
    func startDiscovery() {
        bonjourBrowser.startBrowsing()
        multipeerBrowser.startBrowsing()
        logger.info("Обнаружение серверов запущено")
    }

    /// Останавливает поиск и отключается.
    func stopDiscovery() {
        bonjourBrowser.stopBrowsing()
        multipeerBrowser.stopBrowsing()
        disconnect()
    }

    // MARK: - Подключение к серверу

    /// Подключается к обнаруженному серверу.
    func connect(to server: DiscoveredServer) {
        disconnect()

        switch server.transport {
        case .bonjour:
            if let result = server.bonjourResult {
                lastBonjourResult = result
                lastMultipeerPeer = nil
                bonjourBrowser.connect(to: result)
            }
        case .multipeer:
            if let peer = server.multipeerPeerID {
                lastMultipeerPeer = peer
                lastBonjourResult = nil
                multipeerBrowser.connect(to: peer)
            }
        }
    }

    /// Отключается от текущего сервера.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        bonjourBrowser.disconnect()
        multipeerBrowser.disconnect()
        isConnected = false
        connectedServerName = nil
        activeTransport = nil
    }

    // MARK: - Отправка команд

    /// Отправляет команду на сервер через активный транспорт.
    func send(_ command: RemoteCommand) {
        guard isConnected, let data = command.jsonData() else { return }

        switch activeTransport {
        case .bonjour:
            bonjourBrowser.send(data)
        case .multipeer:
            multipeerBrowser.send(data)
        case nil:
            break
        }

        // Старые step-команды
        if case .media(let action) = command {
            switch action {
            case .volumeup, .volumedown, .brightnessup, .brightnessdown, .mute:
                requestSystemInfoDelayed()
            default:
                break
            }
        }
    }

    // MARK: - Переподключение

    /// Обрабатывает потерю соединения и запускает авто-переподключение.
    private func handleDisconnect() {
        isConnected = false
        connectedServerName = nil
        let transport = activeTransport
        activeTransport = nil

        logger.info("Соединение потеряно (\(transport?.rawValue ?? "?"))")

        guard autoReconnect else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            // Пробуем переподключиться каждые 2 секунды, до 15 попыток
            for attempt in 1...15 {
                guard !Task.isCancelled else { return }

                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, !self.isConnected else { return }

                self.logger.info("Попытка переподключения #\(attempt)")

                await MainActor.run {
                    if let result = self.lastBonjourResult {
                        self.bonjourBrowser.connect(to: result)
                    } else if let peer = self.lastMultipeerPeer {
                        self.multipeerBrowser.connect(to: peer)
                    }
                }

                // Ждём 3 секунды, чтобы дать время на установление соединения
                try? await Task.sleep(for: .seconds(3))
                if self.isConnected { return }
            }
            self.logger.info("Все попытки переподключения исчерпаны")
        }
    }

    // MARK: - Обработка сообщений от сервера

    /// Парсит данные от сервера (newline-delimited JSON).
    /// TCP может прислать несколько сообщений в одном пакете
    /// или одно сообщение фрагментами — буфер решает обе проблемы.
    private func handleServerMessage(_ data: Data) {
        receiveBuffer.append(data)

        // Разбираем буфер по символам новой строки (0x0A)
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let messageData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
            receiveBuffer = Data(receiveBuffer[receiveBuffer.index(after: newlineIndex)...])

            guard !messageData.isEmpty else { continue }

            parseSystemInfo(messageData)
        }
    }

    /// Парсит JSON-сообщение systeminfo и обновляет громкость/яркость.
    private func parseSystemInfo(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "systeminfo" else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let volume = json["volume"] as? Double {
                self.currentVolume = min(1, max(0, volume))
            }

            if let brightness = json["brightness"] as? Double {
                self.currentBrightness = min(1, max(0, brightness))
            }

            if let muted = json["muted"] as? Bool {
                self.isMuted = muted
            }

            self.logger.info("SystemInfo: volume=\(self.currentVolume), brightness=\(self.currentBrightness), muted=\(self.isMuted)")
        }
    }
    /// Запрашивает системную информацию после установления соединения (с задержкой).
    private func requestSystemInfoAfterConnect() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.isConnected else { return }
            await MainActor.run {
                self.send(.getSystemInfo)
            }
        }
    }

    /// Запрашивает системную информацию после изменения громкости/яркости (с задержкой).
    private func requestSystemInfoDelayed() {
        systemInfoTask?.cancel()
        systemInfoTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.isConnected else { return }
            await MainActor.run {
                self.send(.getSystemInfo)
            }
        }
    }
}
