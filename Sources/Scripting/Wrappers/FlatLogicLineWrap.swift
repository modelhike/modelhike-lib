//
//  FlatLogicLineWrap.swift
//  ModelHike
//

import Foundation

/// One row in a flattened method logic tree (language-independent); templates iterate this to emit target syntax.
public struct FlatLogicLineData: Sendable {
    public enum LineType: Sendable {
        case open
        case leaf
        case close
    }

    /// Statement kind from the logic tree, or `.close` for a synthetic closing-brace row.
    public enum FlatLogicLineKind: Sendable, Equatable {
        case statement(CodeLogicStmtKind)
        case close

        /// Pipe-gutter keyword (`CodeLogicStmtKind.keyword`) or `"close"` for synthetic closes — matches template `line.kind == "…"` checks.
        public var keyword: String {
            switch self {
            case .statement(let k): k.keyword
            case .close: "close"
            }
        }
    }

    public let kind: FlatLogicLineKind
    public let expression: String
    public let depth: Int
    public let lineType: LineType
    public let condition: String
    public let forItem: String
    public let forCollection: String
    public let assignLhs: String
    public let assignRhs: String
    public let callExpression: String
    public let catchVariable: String
    public let catchType: String
    public let switchSubject: String
    public let caseValue: String
    public let letName: String
    /// `FILTER`/`MAP`/`SELECT` lambda parameter name (e.g. `employee` in `employee -> employee.isActive`).
    public let lambdaParam: String
    /// `FILTER`/`MAP`/`SELECT` lambda body — the predicate/projection expression after `->`.
    public let lambdaBody: String
    /// `REDUCE`'s accumulator variable name (first of the `(acc,item)` pair).
    public let reduceAccumulator: String
    /// `REDUCE`'s per-item variable name (second of the `(acc,item)` pair).
    public let reduceItem: String
    /// `REDUCE`'s combining expression (between the `(acc,item)` pair and the initial value).
    public let reduceExpression: String
    /// `REDUCE`'s initial accumulator value.
    public let reduceInitial: String
    /// For `lineType == .close`: the pipe-gutter keyword of the block being closed (empty otherwise).
    public let closingKind: String
    /// The pipe-gutter keyword of the enclosing block (empty at top level).
    public let parentKind: String
    /// When `sql` opens under `db-raw` merged with `LET name = _`: the variable name to declare before `databaseClient.sql(`; also on `db-raw` close for `.map(row -> …)` vs `.fetch()`.
    public let mergedDbRawResultLetName: String
    /// Depth of the enclosing parent block (same as `depth - 1` for direct children; 0 at top level).
    public let parentDepth: Int

    /// Flattens a `CodeLogic` tree into a linear list with depth and open/close markers.
    /// Starts at depth 1 so top-level statements emit one indent level (4 spaces) via `{{line.indent}}`,
    /// matching the indentation expected inside a method body without needing leading whitespace at the call site.
    public static func flatten(logic: CodeLogic) async -> [FlatLogicLineData] {
        await flatten(stmts: logic.statements, baseDepth: 1)
    }

    public static func flatten(stmts: [CodeLogicStmt], baseDepth: Int, parentStmt: CodeLogicStmt? = nil) async -> [FlatLogicLineData] {
        var result: [FlatLogicLineData] = []
        var i = stmts.startIndex
        while i < stmts.endIndex {
            let stmt = stmts[i]
            let kind = stmt.kind
            let nextIdx = stmts.index(after: i)

            // Skip `let` children absorbed into the parent block's letBinding.
            if kind == .let, let p = parentStmt, p.node.resultLetName.isNotEmpty {
                i = nextIdx
                continue
            }

            let isBlock = kind.isBlock
            if isBlock {
                result.append(await makeLineData(stmt: stmt, depth: baseDepth, lineType: .open, parentStmt: parentStmt))
            } else {
                result.append(await makeLineData(stmt: stmt, depth: baseDepth, lineType: .leaf, parentStmt: parentStmt))
            }
            if isBlock {
                let children = stmt.children
                if children.isNotEmpty {
                    result.append(contentsOf: await flatten(stmts: children, baseDepth: baseDepth + 1, parentStmt: stmt))
                }
            }
            if isBlock {
                if Self.shouldEmitClose(for: stmt, parentStmt: parentStmt) {
                    result.append(closeLine(for: stmt, depth: baseDepth, parentStmt: parentStmt))
                }
            }
            i = nextIdx
        }
        return result
    }

    private static func closeLine(for stmt: CodeLogicStmt, depth: Int, parentStmt: CodeLogicStmt?) -> FlatLogicLineData {
        return FlatLogicLineData(
            kind: .close,
            expression: "",
            depth: depth,
            lineType: .close,
            condition: "",
            forItem: "",
            forCollection: "",
            assignLhs: "",
            assignRhs: "",
            callExpression: "",
            catchVariable: "",
            catchType: "",
            switchSubject: "",
            caseValue: "",
            letName: "",
            lambdaParam: "",
            lambdaBody: "",
            reduceAccumulator: "",
            reduceItem: "",
            reduceExpression: "",
            reduceInitial: "",
            closingKind: stmt.kind.keyword,
            parentKind: parentStmt?.kind.keyword ?? "",
            mergedDbRawResultLetName: stmt.node.resultLetName,
            parentDepth: max(0, depth - 1)
        )
    }

    private static func shouldEmitClose(for stmt: CodeLogicStmt, parentStmt: CodeLogicStmt?) -> Bool {
        if let parentKind = parentStmt?.kind,
           CodeLogicStmt.blockOwnership(for: parentKind).branchKinds.contains(stmt.kind) {
            return false
        }
        return true
    }

    private static func makeLineData(stmt: CodeLogicStmt, depth: Int, lineType: LineType, parentStmt: CodeLogicStmt? = nil) async -> FlatLogicLineData {
        let kind = stmt.kind
        var expr = stmt.expression
        let node = stmt.node

        var condition = ""
        var forItem = ""
        var forCollection = ""
        var assignLhs = ""
        var assignRhs = ""
        var callExpression = ""
        var catchVariable = ""
        var catchType = ""
        var switchSubject = ""
        var caseValue = ""
        var letName = ""
        var lambdaParam = ""
        var lambdaBody = ""
        var reduceAccumulator = ""
        var reduceItem = ""
        var reduceExpression = ""
        var reduceInitial = ""

        switch node {
        case .ifStmt(let n):
            condition = n.condition
        case .elseIfStmt(let n):
            condition = n.condition
        case .elseBranch:
            break
        case .forLoop(let n):
            forItem = n.item
            forCollection = n.collection
        case .whileLoop(let n):
            condition = n.condition
        case .returnStmt(let n):
            expr = n.expression
        case .assign(let n):
            assignLhs = n.lhs
            assignRhs = n.rhs
        case .call(let n):
            callExpression = n.callExpression
        case .expr(let n):
            expr = n.expression
        case .letBinding(let n):
            letName = n.name
            let parts = expr.slicingAroundFirstEquals()
            expr = parts.rhs
        case .filter(let n):
            let parts = n.lambda.slicingAroundArrow()
            lambdaParam = parts.param
            lambdaBody = parts.body
        case .select(let n):
            let parts = n.lambda.slicingAroundArrow()
            lambdaParam = parts.param
            lambdaBody = parts.body
        case .map(let n):
            let parts = n.lambda.slicingAroundArrow()
            lambdaParam = parts.param
            lambdaBody = parts.body
        case .reduce(let n):
            let parts = n.expression.slicingReduceExpression()
            reduceAccumulator = parts.accumulator
            reduceItem = parts.item
            reduceExpression = parts.expression
            reduceInitial = parts.initial
        case .tryBlock:
            break
        case .catchClause(let n):
            catchVariable = n.variable
            catchType = n.type ?? ""
        case .finallyBlock:
            break
        case .throwStmt(let n):
            expr = n.expression
        case .switchStmt(let n):
            switchSubject = n.subject
        case .caseClause(let n):
            caseValue = n.value
        case .defaultCase:
            break
        case .breakStmt(let n):
            if let label = n.label { expr = label }
        case .continueStmt(let n):
            if let label = n.label { expr = label }
        case .db(let n):
            letName = n.letBinding?.name ?? ""
        case .dbProcCall(let n):
            letName = n.letBinding?.name ?? ""
        case .notify(let n):
            if let r = n.recipient {
                expr = "\(n.notificationType) \(r)".trimmingCharacters(in: .whitespaces)
            } else {
                expr = n.notificationType
            }
        case .publish(let n):
            expr = n.channel.map { "\(n.eventName) TO \($0)" } ?? n.eventName
        case .notifyField(let n):
            expr = n.expression
        default:
            break
        }

        // Own node carries the name (db-raw, db-proc-call open rows).
        // Child rows (e.g. sql open) inherit it from the parent stmt's node.
        let mergedDbRawResultLetName: String
        if node.resultLetName.isNotEmpty {
            mergedDbRawResultLetName = node.resultLetName
        } else {
            mergedDbRawResultLetName = parentStmt?.node.resultLetName ?? ""
        }

        return FlatLogicLineData(
            kind: .statement(kind),
            expression: expr,
            depth: depth,
            lineType: lineType,
            condition: condition,
            forItem: forItem,
            forCollection: forCollection,
            assignLhs: assignLhs,
            assignRhs: assignRhs,
            callExpression: callExpression,
            catchVariable: catchVariable,
            catchType: catchType,
            switchSubject: switchSubject,
            caseValue: caseValue,
            letName: letName,
            lambdaParam: lambdaParam,
            lambdaBody: lambdaBody,
            reduceAccumulator: reduceAccumulator,
            reduceItem: reduceItem,
            reduceExpression: reduceExpression,
            reduceInitial: reduceInitial,
            closingKind: "",
            parentKind: parentStmt?.kind.keyword ?? "",
            mergedDbRawResultLetName: mergedDbRawResultLetName,
            parentDepth: max(0, depth - 1)
        )
    }
}

private extension String {
    func slicingAroundFirstEquals() -> (lhs: String, rhs: String) {
        guard let range = range(of: " = ") else {
            return (trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
        let lhs = String(self[startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rhs = String(self[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (lhs, rhs)
    }

    /// Splits a `FILTER`/`MAP`/`SELECT` lambda (`param -> body`) into its two halves. Only the
    /// first `->` is treated as the separator, so an arrow appearing again inside `body` (e.g. a
    /// nested ternary-like expression) is left alone.
    func slicingAroundArrow() -> (param: String, body: String) {
        guard let range = range(of: " -> ") else {
            return (trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
        let param = String(self[startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let body = String(self[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (param, body)
    }

    /// Splits a `REDUCE` expression (`source -> (acc,item) -> expr -> init`) into its four parts.
    /// `source` itself is discarded here — mid-chain it's always the placeholder `_` (the running
    /// pipe value), and a template renderer tracking an accumulated chain doesn't need it repeated.
    /// Falls back to putting the whole raw text in `expression` (leaving the others empty) if the
    /// shape doesn't match, so a renderer can still fall back to showing something useful.
    func slicingReduceExpression() -> (accumulator: String, item: String, expression: String, initial: String) {
        let parts = components(separatedBy: " -> ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 else {
            return ("", "", trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        let pair = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let pairParts = pair.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let accumulator = pairParts.first ?? ""
        let item = pairParts.count > 1 ? pairParts[1] : ""

        return (accumulator, item, parts[2], parts[3])
    }
}

public actor FlatLogicLine_Wrap: DynamicMemberLookup, SendableDebugStringConvertible {
    private let data: FlatLogicLineData

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = FlatLogicLineProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: FlatLogicLineProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .kind: data.kind.keyword
        case .expression: data.expression
        case .depth: data.depth
        case .indent: String(repeating: "    ", count: data.depth)
        /// One indent level above `indent` — useful for child statements that should render at the parent block's indentation (e.g. `sql` open line inside `db-raw`).
        case .parentIndent: String(repeating: "    ", count: data.parentDepth)
        /// Two indent levels deeper than `indent` — for chained continuations that should align with grandchild statements (e.g. method-call chains that follow a block close).
        case .chainIndent: String(repeating: "    ", count: data.depth + 2)
        case .isOpen: data.lineType == .open
        case .isClose: data.lineType == .close
        case .isLeaf: data.lineType == .leaf
        case .condition: data.condition
        case .forItem: data.forItem
        case .forCollection: data.forCollection
        case .assignLhs: data.assignLhs
        case .assignRhs: data.assignRhs
        case .callExpression: data.callExpression
        case .catchVariable: data.catchVariable
        case .catchType: data.catchType
        case .switchSubject: data.switchSubject
        case .caseValue: data.caseValue
        case .letName: data.letName
        case .lambdaParam: data.lambdaParam
        case .lambdaBody: data.lambdaBody
        case .reduceAccumulator: data.reduceAccumulator
        case .reduceItem: data.reduceItem
        case .reduceExpression: data.reduceExpression
        case .reduceInitial: data.reduceInitial
        case .closingKind: data.closingKind
        case .parentKind: data.parentKind
        case .mergedDbRawResultLet: data.mergedDbRawResultLetName
        case .returnExpression:
            if case .statement(.return) = data.kind { data.expression } else { "" }
        case .throwExpression:
            if case .statement(.throw) = data.kind { data.expression } else { "" }
        }
    }

    public var debugDescription: String {
        "FlatLogicLine(kind: \(data.kind.keyword), depth: \(data.depth), type: \(data.lineType))"
    }

    public init(_ data: FlatLogicLineData) {
        self.data = data
    }
}

// MARK: - Flat logic line property keys (template-facing raw strings)

private enum FlatLogicLineProperty: String, CaseIterable {
    case kind
    case expression
    case depth
    case indent
    case parentIndent = "parent-indent"
    case chainIndent = "chain-indent"
    case isOpen = "is-open"
    case isClose = "is-close"
    case isLeaf = "is-leaf"
    case condition
    case forItem = "for-item"
    case forCollection = "for-collection"
    case assignLhs = "assign-lhs"
    case assignRhs = "assign-rhs"
    case callExpression = "call-expression"
    case catchVariable = "catch-variable"
    case catchType = "catch-type"
    case switchSubject = "switch-subject"
    case caseValue = "case-value"
    case letName = "let-name"
    case lambdaParam = "lambda-param"
    case lambdaBody = "lambda-body"
    case reduceAccumulator = "reduce-accumulator"
    case reduceItem = "reduce-item"
    case reduceExpression = "reduce-expression"
    case reduceInitial = "reduce-initial"
    case closingKind = "closing-kind"
    case parentKind = "parent-kind"
    case mergedDbRawResultLet = "merged-db-raw-result-let"
    case returnExpression = "return-expression"
    case throwExpression = "throw-expression"
}
