//
//  CodeLogicRemoteApiDetection.swift
//  ModelHike
//

import Foundation

extension CodeLogicStmt {
    /// True if this node or any descendant uses HTTP client statement kinds (`isHttpClientStmt`).
    public func subtreeContainsHttpClientStatement() async -> Bool {
        if kind.isHttpClientStmt { return true }
        for child in children {
            if await child.subtreeContainsHttpClientStatement() { return true }
        }
        return false
    }

    /// True if this node or any descendant uses gRPC client statement kinds (`isGrpcClientStmt`).
    public func subtreeContainsGrpcClientStatement() async -> Bool {
        if kind.isGrpcClientStmt { return true }
        for child in children {
            if await child.subtreeContainsGrpcClientStatement() { return true }
        }
        return false
    }

    /// True if an `http` node’s URL suggests WebSocket (`ws://` / `wss://`) — no separate DSL keyword.
    public func subtreeContainsWebSocketClientHint() async -> Bool {
        switch node {
        case .http(let n):
            let u = n.url.lowercased()
            if u.contains("ws://") || u.contains("wss://") { return true }
        default:
            break
        }
        for child in children {
            if await child.subtreeContainsWebSocketClientHint() { return true }
        }
        return false
    }
}

extension CodeLogic {
    /// HTTP/REST/GraphQL/http-raw — for e.g. `WebClient` injection.
    public func containsHttpClientStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsHttpClientStatement() { return true }
        }
        return false
    }

    /// gRPC call surface — for e.g. `ManagedChannel` / `@GrpcClient` injection.
    public func containsGrpcClientStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsGrpcClientStatement() { return true }
        }
        return false
    }

    /// WebSocket-style URL on an `http` line — for e.g. `WebSocketClient` injection.
    public func containsWebSocketClientHintStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsWebSocketClientHint() { return true }
        }
        return false
    }
}
