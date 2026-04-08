//
//  CodeLogicStmtKind.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// The type of a single pipe-gutter logic statement in CodeLogic (see `DSL/codelogic.dsl.md`).
///
/// Statements are grouped into: control-flow, compiler directives, core imperatives,
/// functional/pipeline, database, and HTTP/API categories.
///
/// The raw value of each case is its canonical pipe-gutter keyword (what appears in the DSL).
public enum CodeLogicStmtKind: String, Sendable, Equatable {

    // MARK: Control flow
    case `if`   = "if"
    case elseIf = "elseif"
    case `else` = "else"
    case `for`  = "for"
    case `while` = "while"
    case `break` = "break"
    case `continue` = "continue"
    case `try`  = "try"
    case `catch` = "catch"
    case `finally` = "finally"
    case `throw` = "throw"
    case `switch` = "switch"
    case `case` = "case"
    case `default` = "default"

    // MARK: Compiler directives
    case compilerIf    = "#if"
    case compilerElse  = "#else"
    case compilerEndIf = "#endif"

    // MARK: Core imperatives
    case call   = "call"
    case assign = "assign"
    case `return` = "return"
    case expr   = "expr"
    case raw    = "raw"

    // MARK: Functional / pipelines
    case pipe     = "pipe"
    case filter   = "filter"
    case select   = "select"
    case map      = "map"
    case reduce   = "reduce"
    case `let`    = "let"
    case match    = "match"
    case when     = "when"
    case endMatch = "endmatch"

    // MARK: Database
    case db        = "db"
    case `where`   = "where"
    case include   = "include"
    case orderBy   = "order-by"
    case skip      = "skip"
    case take      = "take"
    case toList    = "to-list"
    case first     = "first"
    case single    = "single"
    case dbInsert  = "db-insert"
    case dbUpdate  = "db-update"
    case dbDelete  = "db-delete"
    case set       = "set"
    case groupBy   = "group-by"
    case aggregate = "aggregate"
    case dbProcCall = "db-proc-call"
    case params    = "params"
    case sql       = "sql"
    case dbRaw     = "db-raw"

    // MARK: Transaction control
    case transaction = "transaction"
    case savepoint   = "savepoint"
    case commit      = "commit"
    case rollback    = "rollback"

    // MARK: Database session / environment
    /// `db-env> setting` — a database session-level configuration directive (e.g. SET NOCOUNT ON,
    /// SET TRANSACTION ISOLATION LEVEL). Not executable code logic — affects connection behavior.
    case dbEnv = "db-env"

    // MARK: Review annotation
    /// `needs-review> reason` — flags a statement that cannot be automatically converted and
    /// requires a human to decide the correct equivalent. Children preserve the original form.
    case needsReview = "needs-review"

    // MARK: HTTP / API
    case http       = "http"
    /// WebSocket client call — same child shape as `http` (`path`, `query`, `headers`, `auth`, `body`, `let`); URL typically `ws://` / `wss://`.
    case websocket  = "websocket"
    case path       = "path"
    case query      = "query"
    case headers    = "headers"
    case auth       = "auth"
    case expect     = "expect"
    case body       = "body"
    case httpGraphQL = "http-graphql"
    case variables  = "variables"
    case grpc       = "grpc"
    case payload    = "payload"
    case metadata   = "metadata"
    case httpRaw    = "http-raw"
    case note       = "note"

    // MARK: Notifications / domain events
    case notify     = "notify"
    case to         = "to"
    case subject    = "subject"
    case title      = "title"
    case message    = "message"
    case priority   = "priority"
    case severity   = "severity"
    case channel    = "channel"
    case data       = "data"
    case template   = "template"
    case publish    = "publish"

    // MARK: Fallback
    case unknown = "unknown"

    /// Parses a keyword string (stripped of the trailing `>` and leading `|` depth markers)
    /// into a `LogicStatementKind`. Matching is case-insensitive.
    static func parse(_ keyword: String) -> CodeLogicStmtKind {
        Self(rawValue: keyword.lowercased()) ?? .unknown
    }

    /// The canonical pipe-gutter keyword string for this statement kind.
    public var keyword: String { rawValue }

    /// Same-depth sibling statement kinds that this block kind claims as its own children.
    ///
    /// Each block node struct defines its own `static siblingChildKinds`; this property
    /// forwards to those definitions so `CodeLogicParser` can access them without depending
    /// on the node types directly. Update the struct's set — this stays as a thin bridge.
    public var siblingChildKinds: Set<CodeLogicStmtKind> {
        switch self {
        case .db:          return CodeLogicStmt.DbQueryNode.siblingChildKinds
        case .dbUpdate:    return CodeLogicStmt.DbUpdateNode.siblingChildKinds
        case .dbProcCall:  return CodeLogicStmt.DbProcCallNode.siblingChildKinds
        case .dbRaw:       return CodeLogicStmt.DbRawNode.siblingChildKinds
        case .http:      return CodeLogicStmt.HttpNode.siblingChildKinds
        case .websocket: return CodeLogicStmt.WebSocketNode.siblingChildKinds
        case .httpGraphQL: return CodeLogicStmt.HttpGraphQLNode.siblingChildKinds
        case .httpRaw:     return CodeLogicStmt.HttpRawNode.siblingChildKinds
        case .grpc:        return CodeLogicStmt.GrpcNode.siblingChildKinds
        case .notify:      return CodeLogicStmt.NotifyNode.siblingChildKinds
        case .publish:     return CodeLogicStmt.PublishNode.siblingChildKinds
        default:           return []
        }
    }

    /// True if this kind only appears as a sub-statement claimed by a parent block and has no
    /// standalone meaning (e.g. `where`, `include`, `path`, `params`, `sql`).
    /// Used by the parser to detect a missing blank line between blocks.
    public var isSubStatementOnly: Bool {
        let allClaimable: Set<CodeLogicStmtKind> = CodeLogicStmt.DbQueryNode.siblingChildKinds
            .union(CodeLogicStmt.DbUpdateNode.siblingChildKinds)
            .union(CodeLogicStmt.DbProcCallNode.siblingChildKinds)
            .union(CodeLogicStmt.DbRawNode.siblingChildKinds)
            .union(CodeLogicStmt.HttpNode.siblingChildKinds)
            .union(CodeLogicStmt.WebSocketNode.siblingChildKinds)
            .union(CodeLogicStmt.HttpGraphQLNode.siblingChildKinds)
            .union(CodeLogicStmt.HttpRawNode.siblingChildKinds)
            .union(CodeLogicStmt.GrpcNode.siblingChildKinds)
            .union(CodeLogicStmt.NotifyNode.siblingChildKinds)
            .union(CodeLogicStmt.PublishNode.siblingChildKinds)
        // `let` and `set` are also used as standalone statements — exclude them.
        let standaloneAlso: Set<CodeLogicStmtKind> = [.let, .set]
        return allClaimable.contains(self) && !standaloneAlso.contains(self)
    }

    /// Whether this statement kind opens a scoped block whose body lines appear at depth+1.
    public var isBlock: Bool {
        switch self {
        case .`if`, .elseIf, .`else`,
             .`for`, .`while`,
             .`try`, .`catch`, .`finally`,
             .`switch`, .`case`, .`default`,
             .compilerIf, .compilerElse,
             .pipe, .filter, .select, .map, .reduce, .`let`,
             .match, .when,
             .db, .dbUpdate, .dbProcCall, .dbRaw,
             .transaction, .savepoint,
             .needsReview,
             .http, .websocket, .path, .query, .headers, .body,
             .httpGraphQL, .variables,
             .httpRaw,
             .grpc, .payload, .metadata,
             .params, .sql,
             .raw, .note,
             .notify, .data, .publish:
            return true
        default:
            return false
        }
    }
}
