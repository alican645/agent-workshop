import AjanTakipCore
import Foundation
import Network
import os

/// 127.0.0.1 üzerinde hook olaylarını (`POST /event`) dinleyen minimal HTTP sunucusu.
final class EventServer: @unchecked Sendable {
    private static let maxRequestBytes = 1 << 20
    private let port: UInt16
    private let onEvent: @Sendable (HookEvent) -> Void
    private let queue = DispatchQueue(label: "ajantakip.server")
    private let log = Logger(subsystem: "com.ajantakip.app", category: "server")
    private var listener: NWListener?

    init(port: UInt16, onEvent: @escaping @Sendable (HookEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    /// `onFailure` dinleyici çalışırken başarısız olursa (ör. port dolu) çağrılır.
    func start(onFailure: @escaping @Sendable (String) -> Void) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [log, port] state in
            if case .failed(let error) = state {
                log.error("listener failed: \(error.localizedDescription)")
                onFailure("Port \(port) açılamadı: \(error.localizedDescription)")
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest.parse(buffer) {
                self.respond(conn, status: self.handle(request))
            } else if error != nil || isComplete || buffer.count > Self.maxRequestBytes {
                self.respond(conn, status: "400 Bad Request")
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest) -> String {
        guard request.method == "POST", request.path == "/event" else { return "404 Not Found" }
        do {
            onEvent(try HookEvent.parse(body: request.body, headers: request.headers))
            return "204 No Content"
        } catch {
            log.error("invalid event: \(String(describing: error))")
            return "400 Bad Request"
        }
    }

    private func respond(_ conn: NWConnection, status: String) {
        let response = Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }
}
