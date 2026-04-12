import Foundation
import Network
import os

// MARK: - Обнаружение Mac через Bonjour (NWBrowser + NWConnection)

/// Ищет сервисы _macremote._tcp в локальной сети через NWBrowser
/// и подключается к выбранному серверу через TCP (NWConnection).
@Observable
final class BonjourBrowser {

    // MARK: - Обнаруженные сервисы

    /// Найденные серверы в сети.
    private(set) var discoveredServices: [NWBrowser.Result] = []

    /// Активное TCP-соединение.
    private(set) var connection: NWConnection?

    /// Имя подключённого сервера.
    private(set) var connectedServerName: String?

    /// Подключены ли мы через TCP.
    var isConnected: Bool { connection?.state == .ready }

    // MARK: - Callbacks

    /// Вызывается при получении данных от сервера (если нужен двусторонний обмен).
    var onReceiveData: ((Data) -> Void)?

    /// Уведомление об изменении состояния подключения.
    var onConnectionStateChange: ((Bool) -> Void)?

    // MARK: - Private

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.macremote.bonjour-browser")
    private let logger = Logger(subsystem: "com.macremote.client", category: "BonjourBrowser")

    // MARK: - Обнаружение сервисов

    /// Начинает поиск серверов в сети.
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_macremote._tcp", domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            self?.logger.info("Browser state: \(String(describing: state))")
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.discoveredServices = Array(results)
                self.logger.info("Найдено сервисов: \(results.count)")
            }
        }

        browser.start(queue: queue)
        self.browser = browser
        logger.info("Bonjour браузер запущен")
    }

    /// Останавливает поиск.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async {
            self.discoveredServices = []
        }
    }

    // MARK: - Подключение к серверу

    /// Подключается к конкретному результату обнаружения.
    func connect(to result: NWBrowser.Result) {
        // Отключаемся от предыдущего, если был
        disconnect()

        let conn = NWConnection(to: result.endpoint, using: .tcp)
        self.connection = conn

        // Извлекаем имя сервиса
        if case .service(let name, _, _, _) = result.endpoint {
            connectedServerName = name
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.logger.info("TCP connection state: \(String(describing: state))")

            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.onConnectionStateChange?(true)
                    self.receiveLoop()
                case .failed, .cancelled:
                    self.onConnectionStateChange?(false)
                    self.connectedServerName = nil
                default:
                    break
                }
            }
        }

        conn.start(queue: queue)
        logger.info("Подключение к \(result.endpoint.debugDescription)")
    }

    /// Подключается к серверу по endpoint.
    func connect(to endpoint: NWEndpoint) {
        disconnect()

        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        if case .service(let name, _, _, _) = endpoint {
            connectedServerName = name
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.onConnectionStateChange?(true)
                    self.receiveLoop()
                case .failed, .cancelled:
                    self.onConnectionStateChange?(false)
                    self.connectedServerName = nil
                default:
                    break
                }
            }
        }

        conn.start(queue: queue)
    }

    /// Отключается от текущего сервера.
    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.connectedServerName = nil
            self.onConnectionStateChange?(false)
        }
    }

    // MARK: - Отправка данных

    /// Отправляет данные через TCP.
    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Ошибка отправки TCP: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Приём данных (цикл)

    /// Рекурсивный цикл чтения данных из TCP-потока.
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let content, !content.isEmpty {
                self.onReceiveData?(content)
            }

            if isComplete {
                self.logger.info("TCP соединение закрыто сервером")
                DispatchQueue.main.async {
                    self.connectedServerName = nil
                    self.onConnectionStateChange?(false)
                }
            } else if error == nil {
                self.receiveLoop()
            }
        }
    }
}

// MARK: - Вспомогательное: извлечение информации из NWBrowser.Result

extension NWBrowser.Result {
    /// Имя сервиса для отображения.
    var serviceName: String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return endpoint.debugDescription
    }
}
