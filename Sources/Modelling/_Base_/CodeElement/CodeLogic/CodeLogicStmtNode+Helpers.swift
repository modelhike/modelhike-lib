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
