//
//  CodeLogicStmtNode+Helpers.swift
//  ModelHike
//

import Foundation

public extension CodeLogicStmt.Node {
    /// The result-variable name from a `let` binding inside any block that supports one
    /// (`db`, `db-proc-call`, `db-raw`, `http`, `http-graphql`, `grpc`); empty otherwise.
    var resultLetName: String {
        switch self {
        case .db(let n):          return n.letBinding?.name ?? ""
        case .dbProcCall(let n):  return n.letBinding?.name ?? ""
        case .dbRaw(let n):       return n.letBinding?.name ?? ""
        case .http(let n):
            return n.letBinding?.name ?? ""
        case .webSocket(let n):
            return n.letBinding?.name ?? ""
        case .httpGraphQL(let n): return n.letBinding?.name ?? ""
        case .grpc(let n):        return n.letBinding?.name ?? ""
        default:                  return ""
        }
    }
}

extension CodeLogicStmt.Node {
    /// Splits `head remainder...` into `(head, remainder?)`, trimming both sides.
    static func splitHeadAndTail(from expression: String) -> (head: String, tail: String?) {
        let trimmed = expression.trim()
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let head = parts.first?.trim() ?? ""
        let tail = parts.count > 1 ? parts[1].trim() : nil
        return (head, tail)
    }

    /// Splits `left KEYWORD right` case-insensitively, preserving original casing in the result.
    static func splitAroundKeyword(_ keyword: String, in expression: String) -> (left: String, right: String)? {
        let trimmed = expression.trim()
        let upper = trimmed.uppercased()
        let needle = " \(keyword.uppercased()) "
        guard let range = upper.range(of: needle) else { return nil }
        let left = String(trimmed[..<range.lowerBound]).trim()
        let right = String(trimmed[range.upperBound...]).trim()
        return (left, right)
    }
}
