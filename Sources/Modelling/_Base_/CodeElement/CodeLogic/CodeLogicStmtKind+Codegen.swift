//
//  CodeLogicStmtKind+Codegen.swift
//  ModelHike
//

import Foundation

extension CodeLogicStmtKind {
    /// True if this statement kind implies database access or transaction control (language-agnostic).
    public var isDatabaseRelatedStmt: Bool {
        switch self {
        case .db, .where, .include, .orderBy, .skip, .take, .toList, .first, .single,
             .dbInsert, .dbUpdate, .dbDelete, .set, .groupBy, .aggregate,
             .dbProcCall, .params, .sql, .dbRaw,
             .transaction, .savepoint, .commit, .rollback, .dbEnv:
            return true
        default:
            return false
        }
    }
}
