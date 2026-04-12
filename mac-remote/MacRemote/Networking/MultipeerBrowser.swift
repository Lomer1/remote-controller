import Foundation
import MultipeerConnectivity
import os

// MARK: - Обнаружение Mac через MultipeerConnectivity (Bluetooth/Wi-Fi Direct)

/// Ищет серверы через MCNearbyServiceBrowser и подключается через MCSession.
/// Используется как fallback-транспорт, когда Bonjour TCP недоступен.
@Observable
final class MultipeerBrowser: NSObject {

    // MARK: - Состояние

    /// Найденные пиры.
    private(set) var discoveredPeers: [MCPeerID] = []

    /// Подключённые пиры.
    private(set) var connectedPeers: [MCPeerID] = []

    /// Подключены ли мы.
    var isConnected: Bool { !connectedPeers.isEmpty }

    // MARK: - Callbacks

    /// Уведомление об изменении состояния подключения.
    var onConnectionStateChange: ((Bool) -> Void)?

    /// Получение данных от пира.
    var onReceiveData: ((Data) -> Void)?

    // MARK: - Private

    private let serviceType = "macremote" // Макс. 15 символов, без подчёркиваний
    private let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private let logger = Logger(subsystem: "com.macremote.client", category: "MultipeerBrowser")

    // MARK: - Обнаружение

    /// Начинает поиск серверов через MultipeerConnectivity.
    func startBrowsing() {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        logger.info("MultipeerConnectivity браузер запущен")
    }

    /// Останавливает поиск.
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil

        DispatchQueue.main.async {
            self.discoveredPeers = []
            self.connectedPeers = []
        }
    }

    // MARK: - Подключение

    /// Приглашает найденный пир к сессии.
    func connect(to peer: MCPeerID) {
        guard let session, let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
        logger.info("Приглашение отправлено: \(peer.displayName)")
    }

    /// Отключается от всех пиров.
    func disconnect() {
        session?.disconnect()
        DispatchQueue.main.async {
            self.connectedPeers = []
            self.onConnectionStateChange?(false)
        }
    }

    // MARK: - Отправка данных

    /// Отправляет данные всем подключённым пирам.
    func send(_ data: Data) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            logger.error("Ошибка отправки MC: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerBrowser: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        logger.info("Найден пир: \(peerID.displayName)")
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("Потерян пир: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerBrowser: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        logger.info("Peer \(peerID.displayName) state: \(String(describing: state))")

        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            self.onConnectionStateChange?(!session.connectedPeers.isEmpty)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onReceiveData?(data)
    }

    // Неиспользуемые обязательные методы делегата
    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
