//
//  RegexExpressionEvaluator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation
import RegexBuilder

public actor RegularExpressionEvaluator {
    /// Tokens produced by [`tokenize(_:)`] for template boolean/arithmetic expressions.
    public enum ExpressionToken: Equatable, Sendable {
        case openParen
        case closeParen
        case value(String)
    }

    /// Parens, string literals (`CommonRegEx`), and run-on tokens (`==`, `kind`, `starts-with`) use RegexBuilder.
    /// Balanced `[`…`]` (nested arrays, quotes inside) cannot be expressed as a flat regex; see ``consumeBalancedSquareBracketLiteral``.
    private enum ExpressionTokenizer {
        nonisolated(unsafe) static let openParen = Regex { "(" }
        nonisolated(unsafe) static let closeParen = Regex { ")" }
        /// One or more characters that are not whitespace or delimiters `()[]"'` 
        nonisolated(unsafe) static let wordRun = Regex {
            OneOrMore {
                CharacterClass(
                    .anyOf("()[]\"'"),
                    .whitespace
                ).inverted
            }
        }
    }

    /// Tokenizer: quoted strings and bracket array literals stay single `.value` tokens.
    nonisolated internal static func tokenize(_ expression: String) -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []
        var rest = expression[...]

        while !rest.isEmpty {
            while rest.first?.isWhitespace == true {
                rest.removeFirst()
            }
            guard !rest.isEmpty else { break }

            if rest.prefixMatch(of: ExpressionTokenizer.openParen) != nil {
                rest.removeFirst()
                tokens.append(.openParen)
                continue
            }
            if rest.prefixMatch(of: ExpressionTokenizer.closeParen) != nil {
                rest.removeFirst()
                tokens.append(.closeParen)
                continue
            }
            if let match = rest.prefixMatch(of: CommonRegEx.stringLiteralPattern) {
                let slice = rest[match.range]
                tokens.append(.value(String(slice)))
                rest = rest[match.range.upperBound...]
                continue
            }
            if let bracketLiteral = consumeBalancedSquareBracketLiteral(&rest) {
                tokens.append(.value(bracketLiteral))
                continue
            }
            if let match = rest.prefixMatch(of: ExpressionTokenizer.wordRun) {
                let slice = rest[match.range]
                tokens.append(.value(String(slice)))
                rest = rest[match.range.upperBound...]
                continue
            }

            rest.removeFirst()
        }
        return tokens
    }

    /// Consumes one array literal from the front of `rest` and returns it as a string (including the outer `[` and closing `]`).
    ///
    /// **Why not regex alone:** A flat pattern cannot match arbitrarily nested `[` / `]`; this scanner tracks nesting depth.
    ///
    /// **Algorithm:**
    /// - Require the first character to be `[`; otherwise return `nil` (caller tries other tokenizers).
    /// - `depth` counts how many `[` opens are still unmatched; it starts at 1 because we skip the opening `[` immediately.
    /// - Walk `i` forward until `depth == 0` (we have closed the outer literal) or we run out of characters.
    ///
    /// **Quoted regions:** Inside the literal, a `"` or `'` starts a string segment (same rules as the rest of the DSL: no
    /// escapes; the next matching quote ends the segment). Brackets inside quotes do **not** change `depth`, so
    /// `["a]`, `b"]` parses as a single string element and does not confuse the bracket scanner.
    ///
    /// **Nested arrays:** A `[` before the matching `]` for the current level increments `depth`; a `]` decrements it.
    ///
    /// **Cursor after return:** `rest` is set to everything after the closing `]` (when depth reached 0). If the literal
    /// is never closed (`depth > 0` at end of substring), `i` stops at `end`; the returned value is the unclosed prefix
    /// and `rest` becomes empty—same behavior as the previous hand-rolled tokenizer for malformed input.
    private nonisolated static func consumeBalancedSquareBracketLiteral(_ rest: inout Substring) -> String? {
        guard rest.first == "[" else { return nil }
        let start = rest.startIndex
        // Position after the opening `[`; depth accounts for that bracket already.
        var i = rest.index(after: rest.startIndex)
        let end = rest.endIndex
        var depth = 1
        while i < end, depth > 0 {
            let ch = rest[i]
            // Skip over a quoted run so `]` inside `"..."` does not close the array literal.
            if ch == "\"" || ch == "'" {
                let q = ch
                i = rest.index(after: i)
                while i < end, rest[i] != q {
                    i = rest.index(after: i)
                }
                // Include the closing quote in the spanned range; if string is unterminated, `i` may land at `end`.
                if i < end {
                    i = rest.index(after: i)
                }
                continue
            }
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
            }
            // Advance past the character we just classified (or the last char of a quoted segment, handled above).
            i = rest.index(after: i)
            if depth == 0 {
                break
            }
        }
        // Full literal including `[` … `]`; slice ends at `i` (exclusive), i.e. first index after the closing `]`.
        let value = String(rest[start..<i])
        rest = rest[i...]
        return value
    }

    public func evaluate(expression: String, pInfo: ParsedInfo) async throws -> Sendable? {
        let ctx = pInfo.ctx

        var negatedResult = false

        var expressionToParse = expression
        if let firstWord = expression.firstWord(), firstWord == "not" {
            negatedResult = true
            expressionToParse = expressionToParse.remainingLine(after: firstWord)
        }

        var parsedArrList = try await parseAsArray(expression: expressionToParse, pInfo: pInfo)
        //print(parsedArrList)

        //there is some expression given, but there is no parsed output
        //which means that something is wrong
        if parsedArrList.count == 0 && expression.trim().isNotEmpty {
            throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
        }

        guard parsedArrList.count != 0 else { return nil }

        var lhsArray = parsedArrList.removeFirst()
        var accumulated = try await executeArrayItems(&lhsArray, expression, pInfo: pInfo)

        while parsedArrList.count > 0 {
            //in the parsed array list, every even item is an operator,
            //which will be a single item in an array
            guard let op = parsedArrList.removeFirst().first else {
                throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
            }

            var rhsArray = parsedArrList.removeFirst()

            guard let rhsResult = try await executeArrayItems(&rhsArray, expression, pInfo: pInfo) else {
                throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
            }

            accumulated = try await Self.applyInfix(named: op, lhs: accumulated, rhs: rhsResult, pInfo: pInfo)
        }

        guard let accumulated = accumulated else { return nil }

        let result = await ctx.evaluateCondition(value: accumulated, with: pInfo)
        return negatedResult ? !result : result
    }

    fileprivate func executeArrayItems(_ arr: inout [String], _ expression: String, pInfo: ParsedInfo) async throws -> Sendable? {
        guard arr.count > 0 else { return nil }

        let ctx = pInfo.ctx
        let lhs = arr.removeFirst()

        guard var result = try await ctx.evaluate(value: lhs, with: pInfo) else {
            if lhs.isPattern(CommonRegEx.variableOrObjectProperty) {
                let candidates = await ctx.variables.keySnapshot
                throw Suggestions.expressionOperandNotFound(lhs, candidates: candidates, pInfo: pInfo)
            }
            return nil
        }

        while arr.count > 0 {
            //in the parsed array list, every even item is an operator
            let op = arr.removeFirst()

            guard arr.count > 0 else {
                throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
            }

            let rhs = arr.removeFirst()

            guard let rhsResult = try await ctx.evaluate(value: rhs, with: pInfo) else {
                if rhs.isPattern(CommonRegEx.variableOrObjectProperty) {
                    let candidates = await ctx.variables.keySnapshot
                    throw Suggestions.expressionOperandNotFound(rhs, candidates: candidates, pInfo: pInfo)
                }
                throw TemplateSoup_EvaluationError.objectNotFound(rhs, pInfo)
            }

            result = try await Self.applyInfix(named: op, lhs: result, rhs: rhsResult, pInfo: pInfo)

        }

        return result
    }

    fileprivate func parseAsArray(expression: String, pInfo: ParsedInfo) async throws -> [[String]] {
        var outer: [[String]] = []
        var inner: [String] = []
        var paranthesisStarted = false

        let tokens = Self.tokenize(expression)
        for token in tokens {
            switch token {
            case .openParen:
                if !paranthesisStarted {
                    paranthesisStarted = true

                    if inner.count > 0 {
                        outer.append(inner)
                        inner = []
                    }
                } else {
                    throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
                }
            case .closeParen:
                if paranthesisStarted {
                    paranthesisStarted = false

                    if inner.count > 0 {
                        outer.append(inner)
                        inner = []
                    }
                } else {
                    throw TemplateSoup_EvaluationError.errorInExpression(expression, pInfo)
                }
            case .value(let part):
                inner.append(part)
            }
        }

        if inner.count > 0 {
            outer.append(inner)
        }

        //till now array will be split as per scope
        //E.g. var1 and (var2 and var3) and var4 or var5
        //will be split into
        // item 0 - var1, and
        // item 1 - var2, or, var3
        // item 2 - and, var4, or, var5
        // NOW, the operators which join two score are to be split into another single array
        //i.e, operators at the end of item 0 and at the start of item 2 are to be split
        //expected:
        // item 0 - var1
        // item 1 - and
        // item 2 - var2, or, var3
        // item 3 - and
        // item 4 - var4, or, var5

        let ctx = pInfo.ctx
        var newOuter: [[String]] = []

        var i = 0
        while i < outer.count {
            var inner = outer[i]

            //arrays having extra operator at start/end will be having even count
            if inner.count % 2 == 0 {
                //check if the first item of the inner is an operator
                if let op = inner.first {
                    if let _ = await ctx.symbols.template.infixOperators.first(where: { $0.name == op }) {
                        inner.removeFirst()

                        newOuter.append([op])
                        newOuter.append(inner)

                        i += 1
                        continue
                    }
                }

                //check if the last item of the inner is an operator
                if let op = inner.last {
                    if let _ = await ctx.symbols.template.infixOperators.first(where: { $0.name == op }) {
                        inner.removeLast()

                        newOuter.append(inner)
                        newOuter.append([op])

                        i += 1
                        continue
                    }
                }

                throw TemplateSoup_ParsingError.invalidExpression(expression, pInfo)
            } else {
                newOuter.append(inner)
            }

            i += 1
        }

        return newOuter
    }

    public init() {
    }

    /// Dispatches an infix operator by **name** to the correct `InfixOperatorProtocol` implementation.
    ///
    /// **Why overload resolution exists:** The symbol table registers multiple operators with the same `name` but
    /// different generic `(lhs, rhs)` pairs—e.g. `in` for `(String, [String])` and `(Double, [Double])`. At runtime we
    /// only have `Sendable?` values, so we cannot pick an overload statically; we try each registration in order.
    ///
    /// **Per candidate:** `applyTo` checks types and either returns a result or throws `TemplateSoup_ParsingError`.
    /// - **Wrong LHS/RHS type** (`.infixOperatorCalledOnwrongLhsType` / `.infixOperatorCalledOnwrongRhsType`): treat as
    ///   “not this overload”—try the next registration. If this was the **last** candidate, rethrow that error so the
    ///   user still gets a precise E216/E217-style message (expected vs actual type), not a vague “operator not found”.
    /// - **Any other** parsing error: rethrow immediately (e.g. bad state; not overload selection).
    ///
    /// **No matching name:** If `filter` yields an empty list, throw `infixOperatorNotFound` (E215) with the full list
    /// of operator names for “did you mean?” style diagnostics.
    ///
    /// **Trailing throw:** After a non-empty `candidates` loop, every path either `return`s or `throw`s inside the
    /// `for`; the final `throw` exists to satisfy the compiler and as a defensive fallback (should be unreachable).
    private static func applyInfix(named op: String, lhs: Sendable?, rhs: Sendable?, pInfo: ParsedInfo) async throws -> Sendable {
        let allNames = (await pInfo.ctx.symbols.template.infixOperators).map { $0.name }
        let candidates = await pInfo.ctx.symbols.template.infixOperators.filter { $0.name == op }
        guard !candidates.isEmpty else {
            throw Suggestions.infixOperatorNotFound(op, candidates: allNames, pInfo: pInfo)
        }

        let lastOrdinal = candidates.count - 1
        for (ordinal, infix) in candidates.enumerated() {
            do {
                return try infix.applyTo(lhs: lhs, rhs: rhs, pInfo: pInfo)
            } catch let e as TemplateSoup_ParsingError {
                switch e {
                case .infixOperatorCalledOnwrongLhsType, .infixOperatorCalledOnwrongRhsType:
                    if ordinal == lastOrdinal {
                        throw e
                    }
                default:
                    throw e
                }
            }
        }
        
        throw Suggestions.infixOperatorNotFound(op, candidates: allNames, pInfo: pInfo)
    }
}
