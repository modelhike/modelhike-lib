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

    /// True if this node or any descendant uses a `websocket>` statement (`isWebSocketClientStmt`).
    public func subtreeContainsWebSocketStatement() async -> Bool {
        if kind.isWebSocketClientStmt { return true }
        for child in children {
            if await child.subtreeContainsWebSocketStatement() { return true }
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

    /// `websocket>` blocks — for e.g. `WebSocketClient` injection (distinct from `http>`).
    public func containsWebSocketStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsWebSocketStatement() { return true }
        }
        return false
    }
}
