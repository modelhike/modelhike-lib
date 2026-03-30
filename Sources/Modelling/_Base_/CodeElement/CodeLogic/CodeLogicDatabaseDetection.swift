//
//  CodeLogicDatabaseDetection.swift
//  ModelHike
//

import Foundation

extension CodeLogicStmt {
    /// True if this node or any descendant uses a data-access statement kind (`isDataAccessStmt`).
    public func subtreeContainsDataAccessStatement() async -> Bool {
        if kind.isDataAccessStmt { return true }
        for child in children {
            if await child.subtreeContainsDataAccessStatement() { return true }
        }
        return false
    }

    /// True if this node or any descendant uses a transaction-control statement kind (`isTransactionControlStmt`).
    public func subtreeContainsTransactionControlStatement() async -> Bool {
        if kind.isTransactionControlStmt { return true }
        for child in children {
            if await child.subtreeContainsTransactionControlStatement() { return true }
        }
        return false
    }

    /// True if this node or any descendant uses any database-related kind (data access or transaction control).
    public func subtreeContainsDatabaseStatement() async -> Bool {
        if kind.isDatabaseRelatedStmt { return true }
        for child in children {
            if await child.subtreeContainsDatabaseStatement() { return true }
        }
        return false
    }
}

extension CodeLogic {
    /// True if any statement uses data-access kinds (queries, SQL, DML, etc.) — for e.g. R2DBC `DatabaseClient` injection.
    public func containsDataAccessStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsDataAccessStatement() { return true }
        }
        return false
    }

    /// True if any statement uses transaction-control kinds — for e.g. `ReactiveTransactionManager` injection.
    public func containsTransactionControlStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsTransactionControlStatement() { return true }
        }
        return false
    }

    /// True if the tree contains data-access and/or transaction-control statements.
    public func containsDatabaseStatement() async -> Bool {
        for stmt in statements {
            if await stmt.subtreeContainsDatabaseStatement() { return true }
        }
        return false
    }
}
