//
//  CodeLogicStmtKind+Codegen.swift
//  ModelHike
//

import Foundation

extension CodeLogicStmtKind {
    /// True if this statement kind implies **data** access (queries, DML, raw SQL, session env) — not reactive transaction API keywords alone.
    public var isDataAccessStmt: Bool {
        switch self {
        case .db, .where, .include, .orderBy, .skip, .take, .toList, .first, .single,
             .dbInsert, .dbUpdate, .dbDelete, .set, .groupBy, .aggregate,
             .dbProcCall, .params, .sql, .dbRaw,
             .dbEnv:
            return true
        default:
            return false
        }
    }

    /// True for `transaction` / `savepoint` / `commit` / `rollback` (reactive transaction control; language-agnostic).
    public var isTransactionControlStmt: Bool {
        switch self {
        case .transaction, .savepoint, .commit, .rollback:
            return true
        default:
            return false
        }
    }

    /// Any codegen-relevant DB surface: data access and/or transaction control.
    public var isDatabaseRelatedStmt: Bool { isDataAccessStmt || isTransactionControlStmt }

    /// REST/HTTP client surface: `http` and its sibling blocks, GraphQL-over-HTTP, raw HTTP, notes under HTTP flows (language-agnostic).
    public var isHttpClientStmt: Bool {
        switch self {
        case .http, .path, .query, .headers, .auth, .expect, .body,
             .httpGraphQL, .variables, .httpRaw, .note:
            return true
        default:
            return false
        }
    }

    /// gRPC client surface: `grpc` and payload/metadata blocks (language-agnostic).
    public var isGrpcClientStmt: Bool {
        switch self {
        case .grpc, .payload, .metadata:
            return true
        default:
            return false
        }
    }
}
