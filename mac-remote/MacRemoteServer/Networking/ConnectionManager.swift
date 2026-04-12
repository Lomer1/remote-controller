import Foundation
import Network
import os

// MARK: - Единый менеджер подключений
/// Управляет обоими транспортами (Bonjour TCP + MultipeerConnectivity)
/// и маршрутизирует полученные команды в обработчик ввода.
@Observable
final class ConnectionManager {
    // MARK: - Серверы
    let bonjourServer = BonjourServer()
    let multipeerServer = MultipeerServer()

    // MARK: - Состояние
    /// Общее число подключённых клиентов (оба транспорта).
    var totalConnectedCount: Int {
        bonjourServer.connections.count + multipeerServer.connectedPeers.count
    }

    /// Текстовое описание всех подключённых клиентов.
    var connectedClientDescriptions: [String] {
        let tcp = bonjourServer.connections.map { "TCP: \($0.endpoint)" }
        let mc = multipeerServer.connectedPeers.map { "MC: \($0.displayName)" }
        return tcp + mc
    }

    /// Локальный IP-адрес Mac в Wi-Fi сети.
    var localIPAddress: String {
        Self.getLocalIPAddress() ?? "—"
    }

    /// TCP-порт сервера.
    var serverPort: UInt16 {
        bonjourServer.port
    }

    /// Оба сервера работают.
    var isRunning: Bool {
        bonjourServer.isRunning || multipeerServer.isRunning
    }

    private let logger = Logger(subsystem: "com.macremote.server", category: "ConnectionManager")

    // MARK: - Запуск / Остановка
    /// Запускает оба транспорта и устанавливает обработчик команд.
    func startAll() {
        let handler: (RemoteCommand) -> Void = { [weak self] command in
            self?.handleCommand(command)
        }

        bonjourServer.onCommand = handler
        multipeerServer.onCommand = handler

        bonjourServer.start()
        multipeerServer.start()

        logger.info("Все серверы запущены")
    }

    /// Останавливает оба транспорта.
    func stopAll() {
        bonjourServer.stop()
        multipeerServer.stop()
        logger.info("Все серверы остановлены")
    }

    // MARK: - Обработка команд
    /// Маршрутизирует команду в соответствующий контроллер ввода.
    private func handleCommand(_ command: RemoteCommand) {
        switch command {
        case .mouseMove(let dx, let dy):
            MouseController.moveMouse(dx: dx, dy: dy)

        case .click(let button, let count):
            MouseController.click(button: button, count: count)

        case .scroll(let dx, let dy):
            MouseController.scroll(dx: dx, dy: dy)

        case .keypress(let text):
            KeyboardController.typeText(text)

        case .hotkey(let modifiers, let key):
            KeyboardController.sendHotkey(modifiers: modifiers, key: key)

        case .media(let action):
            MediaController.perform(action)

            switch action {
            case .volumeup, .volumedown, .mute:
                let json = MediaController.getSystemInfoJSON()
                broadcastToClients(json)
            default:
                break
            }

        case .setVolume(let value):
            do {
                try MediaController.setSystemVolume(value)
                let json = MediaController.getSystemInfoJSON()
                broadcastToClients(json)
            } catch {
                print("setVolume failed: \(error)")
            }

        case .setBrightness(let value):
            do {
                try MediaController.setScreenBrightness(value)
                let json = MediaController.getSystemInfoJSON()
                broadcastToClients(json)
            } catch {
                print("setBrightness failed: \(error)")
            }

        case .setMute(let enabled):
            do {
                try MediaController.setMuted(enabled)
                let json = MediaController.getSystemInfoJSON()
                broadcastToClients(json)
            } catch {
                print("setMute failed: \(error)")
            }

        case .mouseDown(let button):
            MouseController.mouseDown(button: button)

        case .mouseUp(let button):
            MouseController.mouseUp(button: button)

        case .mouseDrag(let dx, let dy):
            MouseController.mouseDrag(dx: dx, dy: dy)

        case .threeFingerSwipe(let direction):
            MouseController.threeFingerSwipe(direction)

        case .twoFingerSwipe(let direction):
            MouseController.twoFingerSwipe(direction)

        case .getSystemInfo:
            let json = MediaController.getSystemInfoJSON()
            broadcastToClients(json)
        }
    }

    // MARK: - Отправка данных клиентам
    /// Отправляет сообщение всем подключённым клиентам (TCP + MC).
    func broadcastToClients(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }

        // TCP-клиенты
        for client in bonjourServer.connections {
            client.connection.send(content: data, completion: .idempotent)
        }

        // MultipeerConnectivity-клиенты
        multipeerServer.broadcast(data)
    }

    /// Отправляет клиентам актуальное состояние системы.
    private func broadcastSystemInfo() {
        let json = MediaController.getSystemInfoJSON()
        broadcastToClients(json)
    }

    // MARK: - Определение IP-адреса
    /// Получает локальный IPv4-адрес через getifaddrs (Wi-Fi/Ethernet).
    static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            // Только IPv4
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)

            // en0 — Wi‑Fi, en1 — Ethernet (на некоторых Mac наоборот)
            guard name == "en0" || name == "en1" else { continue }

            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            if getnameinfo(
                &addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                return String(cString: hostname)
            }
        }

        return nil
    }
}
