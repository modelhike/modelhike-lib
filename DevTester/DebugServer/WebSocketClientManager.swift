//
//  WebSocketClientManager.swift
//  DevTester
//

import Foundation
import NIOCore
import NIOWebSocket

/// A registered WebSocket client represented by a send closure. Using a closure
/// avoids existential dispatch on `any Channel` which may not correctly route
/// generic `writeAndFlush<T>` calls through protocol witness tables.
struct WebSocketClient: Sendable {
    let id: ObjectIdentifier
    /// Schedules `text` onto the client's event loop and writes it as a text frame.
    let send: @Sendable (String) -> Void
}

/// Actor tracking all live WebSocket connections.
/// Broadcasts JSON messages to every connected client.
actor WebSocketClientManager {

    private var clients: [ObjectIdentifier: WebSocketClient] = [:]

    func add(_ client: WebSocketClient) {
        clients[client.id] = client
        print("[WSManager] client connected, total=\(clients.count)")
    }

    func remove(id: ObjectIdentifier) {
        clients.removeValue(forKey: id)
        print("[WSManager] client removed id=\(id), total=\(clients.count)")
    }

    var count: Int { clients.count }

    /// Broadcast raw JSON `data` to every connected client as a WebSocket text frame.
    func broadcast(json data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        for client in clients.values {
            client.send(text)
        }
    }

    /// Encode `value` as JSON and broadcast to all clients.
    func broadcast<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        broadcast(json: data)
    }
}
