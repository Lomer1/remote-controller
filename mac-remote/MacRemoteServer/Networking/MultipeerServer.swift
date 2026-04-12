import Foundation
import MultipeerConnectivity
import os

// MARK: - MultipeerConnectivity сервер (Bluetooth/Wi-Fi Direct)

/// Запасной транспорт через MultipeerConnectivity.
/// Работает по Bluetooth и Wi-Fi Direct — полезно, когда устройства
/// не в одной Wi-Fi сети.
@Observable
final class MultipeerServer: NSObject {

    // MARK: - Состояние

    private(set) var isRunning = false
    private(set) var connectedPeers: [MCPeerID] = []

    /// Колбэк для обработки полученных команд
    var onCommand: ((RemoteCommand) -> Void)?

    // MARK: - MultipeerConnectivity объекты

    private let peerID: MCPeerID
    private let serviceType = "macremote" // Максимум 15 символов, только [a-z0-9-]
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?
    private let logger = Logger(subsystem: "com.macremote.server", category: "MultipeerServer")

    /// Буферы для накопления неполных JSON-строк (по peer)
    private var buffers: [MCPeerID: Data] = [:]

    // MARK: - Инициализация

    override init() {
        self.peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        super.init()
    }

    // MARK: - Запуск / Остановка

    /// Начинает объявление сервиса и приём подключений.
    func start() {
        guard !isRunning else { return }

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["app": "MacRemote"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        isRunning = true
        logger.info("MultipeerConnectivity сервер запущен")
    }

    /// Отправляет данные всем подключённым пирам.
    func broadcast(_ data: Data) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    /// Останавливает объявление и закрывает сессию.
    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        connectedPeers.removeAll()
        buffers.removeAll()
        isRunning = false
        logger.info("MultipeerConnectivity сервер остановлен")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerServer: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Автоматически принимаем все входящие подключения
        logger.info("Приглашение от: \(peerID.displayName)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logger.error("Ошибка объявления: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerServer: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateName: String
        switch state {
        case .notConnected: stateName = "отключён"
        case .connecting:   stateName = "подключается"
        case .connected:    stateName = "подключён"
        @unknown default:   stateName = "неизвестно"
        }
        logger.info("Peer \(peerID.displayName): \(stateName)")

        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            if state == .notConnected {
                self.buffers.removeValue(forKey: peerID)
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // MultipeerConnectivity передаёт данные целыми сообщениями,
        // но на всякий случай используем буферизацию
        var buffer = (buffers[peerID] ?? Data()) + data
        let (commands, remainder) = RemoteCommand.parseBuffer(buffer)
        buffer = remainder
        buffers[peerID] = buffer

        for command in commands {
            DispatchQueue.main.async { [weak self] in
                self?.onCommand?(command)
            }
        }
    }

    // Обязательные методы MCSessionDelegate (не используются)

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
