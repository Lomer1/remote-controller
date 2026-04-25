import Foundation
import Network
import os

// MARK: - Менеджер подключений сервера
/// Управляет Bonjour TCP + MultipeerConnectivity транспортами
/// и маршрутизирует команды в контроллеры ввода.
@Observable
final class ConnectionManager {

    // MARK: - Серверы
    let bonjourServer    = BonjourServer()
    let multipeerServer  = MultipeerServer()

    private let logger = Logger(subsystem: "com.macremote.server", category: "ConnectionManager")

    // MARK: - Состояние

    var totalConnectedCount: Int {
        bonjourServer.connections.count + multipeerServer.connectedPeers.count
    }

    var connectedClientDescriptions: [String] {
        let tcp = bonjourServer.connections.map { "TCP: \($0.endpoint)" }
        let mc  = multipeerServer.connectedPeers.map { "MC: \($0.displayName)" }
        return tcp + mc
    }

    var localIPAddress: String {
        Self.getLocalIPAddress() ?? "—"
    }

    var serverPort: UInt16 {
        bonjourServer.port
    }

    var isRunning: Bool {
        bonjourServer.isRunning || multipeerServer.isRunning
    }

    // MARK: - Запуск / Остановка

    func startAll() {
        let handler: (RemoteCommand) -> Void = { [weak self] command in
            self?.handleCommand(command)
        }
        bonjourServer.onCommand   = handler
        multipeerServer.onCommand = handler
        bonjourServer.start()
        multipeerServer.start()
        logger.info("Все серверы запущены")
    }

    func stopAll() {
        bonjourServer.stop()
        multipeerServer.stop()
        logger.info("Все серверы остановлены")
    }

    // MARK: - Обработка команд

    private func handleCommand(_ command: RemoteCommand) {
        switch command {

        // Мышь
        case .mouseMove(let dx, let dy):
            MouseController.moveMouse(dx: dx, dy: dy)

        case .click(let button, let count):
            MouseController.click(button: button, count: count)

        // Клавиатура
        case .keypress(let text):
            KeyboardController.typeText(text)

        case .hotkey(let modifiers, let key):
            KeyboardController.sendHotkey(modifiers: modifiers, key: key)

        // Медиа (шаговые клавиши)
        case .media(let action):
            MediaController.perform(action)
            switch action {
            case .volumeup, .volumedown, .mute:
                broadcastToClients(MediaController.getSystemInfoJSON())
            default:
                break
            }

        // Медиа (абсолютные значения)
        case .setVolume(let value):
            do {
                try MediaController.setSystemVolume(value)
                broadcastToClients(MediaController.getSystemInfoJSON())
            } catch {
                logger.error("setVolume failed: \(error)")
            }

        case .setBrightness(let value):
            do {
                try MediaController.setScreenBrightness(value)
                broadcastToClients(MediaController.getSystemInfoJSON())
            } catch {
                logger.error("setBrightness failed: \(error)")
            }

        case .setMute(let enabled):
            do {
                try MediaController.setMuted(enabled)
                broadcastToClients(MediaController.getSystemInfoJSON())
            } catch {
                logger.error("setMute failed: \(error)")
            }

        // Запрос состояния
        case .getSystemInfo:
            broadcastToClients(MediaController.getSystemInfoJSON())

        // Остальные кейсы (scroll, drag, swipe) — клиент больше не отправляет
        default:
            break
        }
    }

    // MARK: - Отправка клиентам

    func broadcastToClients(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        for client in bonjourServer.connections {
            client.connection.send(content: data, completion: .idempotent)
        }
        multipeerServer.broadcast(data)
    }

    // MARK: - Локальный IP

    static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                &addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            ) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}
