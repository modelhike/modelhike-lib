//
//  CodeLogicDatabaseDetection.swift
//  ModelHike
//

import Foundation

extension CodeLogicStmt {
    /// True if this node or any descendant uses a database-related statement kind.
    public func subtreeContainsDatabaseStatement() async -> Bool {
        if kind.isDatabaseRelatedStmt { return true }
        for child in children {
            if await child.subtreeContainsDatabaseStatement() { return true }
        }
        return false
    }
}

extension CodeLogic {
    /// True if any statement in the tree uses a database-related kind (`CodeLogicStmtKind.isDatabaseRelatedStmt`).
    public func containsDatabaseStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsDatabaseStatement() { return true }
        }
        return false
    }
}
