//
//  ExpressionEvaluator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// Resolves **single** operands (string/number/bool literals, `["a","b"]` via ``parseStringArrayLiteral``, variables).
/// **Compound** expressions (`kind == "if"`, `x in ["a","b"]`, `a and b`) are parsed and evaluated by
/// ``RegularExpressionEvaluator``; infix operators are **not** implemented here—they are registered in
/// ``DefaultOperatorsLibrary`` (e.g. `==`, `in` for string or numeric arrays, `not-in`, `and`, `or`, …) and applied via
/// overload resolution in ``RegularExpressionEvaluator``.
public actor ExpressionEvaluator {
    /// Stateless `struct` — one instance per ``ExpressionEvaluator`` avoids allocating a new parser for every compound expression.
    private let compoundExpressionEvaluator = RegularExpressionEvaluator()

    public func evaluate(value valueStr: String, pInfo: ParsedInfo) async throws -> Sendable? {
        let value = valueStr.trim()
        let ctx = pInfo.ctx
        
        //check if string literal
        if let match = value.wholeMatch(of: CommonRegEx.stringLiteralPattern_Capturing) {
            
            let (_, str, str2) = match.output
            return str ?? str2
        }
        
        // Number literal — Double if it has a decimal point, Int otherwise. No coercion.
        // flatMap unwraps the double-Optional produced by ChoiceOf's capture groups.
        if let match = value.wholeMatch(of: CommonRegEx.numberLiteralPattern_Capturing) {
            let (_, dbl, int) = match.output
            if let d = dbl.flatMap({ $0 }) { return d }
            if let i = int.flatMap({ $0 }) { return i }
            return 0
        }

        // String array literal — RHS of `in` is parsed here; the `in` operator itself is ``DefaultOperatorsLibrary/inStringArrayOperator``.
        if let arr = Self.parseStringArrayLiteral(value) {
            return arr
        }

        //check if variable or object property
        if let _ = value.wholeMatch(of: CommonRegEx.variableOrObjectProperty) {
            if let value = try await ctx.valueOf(variableOrObjProp: value, with: pInfo) {
                return value
            }
        }
        
        if let bool = Bool(value) {
            return bool
        }
        
        return nil
    }
    
    public func evaluate(expression: String, pInfo: ParsedInfo) async throws -> Sendable? {
        let expn = expression.trim()
        let ctx = pInfo.ctx
        
        if await ctx.variables.has(expn) {
            return await ctx.variables[expn]
        }
        
        if let result = try await evaluate(value: expn, pInfo: pInfo) {
            return result
        }
        
        //As, it is not an object, assume it is an expression,
        //syntax: LHS operator RHS
        //LHS and RHS can be nested and can have paranthesis
        //nested paranthesis is not supported;
        //but single-level of paranthesis is allowed
        return try await compoundExpressionEvaluator.evaluate(expression: expn, pInfo: pInfo)
    }

    public func evaluateCondition(expression: String, pInfo: ParsedInfo) async throws -> Bool {
        var expressionToEval = expression.trim()
        var negated = false
        if let firstWord = expressionToEval.firstWord(), firstWord == "not" {
            negated = true
            expressionToEval = expressionToEval.remainingLine(after: firstWord)
        }

        if let result = try await evaluate(expression: expressionToEval, pInfo: pInfo) {
            let boolResult = getEvaluatedBoolValueFor(result)
            return negated ? !boolResult : boolResult
        } else {
            // Expression resolved to nil — likely a typo or undefined variable.
            // Emit a warning so the user knows this happened; do not throw (non-breaking).
            let trimmed = expression.trim()
            if !trimmed.contains(" ") && !trimmed.contains(".") {
                let candidates = await pInfo.ctx.variables.keySnapshot
                await pInfo.ctx.debugLog.recordLookupDiagnostic(
                    .warning,
                    code: "W201",
                    "Condition '\(expression)' resolved to nil — treating as false. "
                        + "Check for typos in variable or property names.",
                    lookup: trimmed,
                    in: candidates,
                    availableOptionsLabel: "variables in scope",
                    pInfo: pInfo
                )
            } else {
                await pInfo.ctx.debugLog.recordDiagnostic(
                    .warning,
                    code: "W201",
                    "Condition '\(expression)' resolved to nil — treating as false. "
                        + "Check for typos in variable or property names.",
                    pInfo: pInfo
                )
            }
            return false
        }
    }
    
    public func evaluateCondition(value: Optional<Any>, with ctx: Context) -> Bool {
        if let result = value {
            return getEvaluatedBoolValueFor(result)
        } else {
            return false
        }
    }
    
    fileprivate func getEvaluatedBoolValueFor(_ resultOptional: Any) -> Bool {
        //Special handling for nested optionals of 'Any', which can be problematic with nil values
        //This is needed because Swift's type system doesn't allow direct checking of nested optionals within 'Any', due to type erasure.
        guard let result = deepUnwrap(resultOptional) else { return false }

        switch type(of: result) {
        case is String.Type :
            if let str = result as? String {
                return str.trim().isNotEmpty
            } else {
                return false
            }
        case is Int.Type :
            if let integer = result as? Int {
                return integer != 0
            } else {
                return false
            }
        case is Double.Type :
            if let dbl = result as? Double {
                return dbl != 0
            } else {
                return false
            }
        case is Bool.Type :
            if let b = result as? Bool {
                return b
            } else {
                return false
            }
        case is Date.Type :
            if let d = result as? Date {
                return d.timeIntervalSince1970 > 0
            } else {
                return false
            }
        default: //if type is object
            return true
        }
    }

    /// Parses a **string array literal** token into `[String]` for use as the RHS of `in` / `not-in` in template expressions.
    ///
    /// **Accepted shape:** After trim, the whole value must start with `[` and end with `]` (as produced by the expression
    /// tokenizer for `kind in ["a", "b"]`). Anything else returns `nil` so callers fall through to other literal parsers.
    ///
    /// **Empty array:** `[]` → `[]`.
    ///
    /// **Elements:** The content inside the brackets is split on **commas** (`,`) only. Each segment is trimmed of
    /// surrounding whitespace. This matches blueprint usage where elements are `"if"`, `elseif`, or similar—not JSON with
    /// nested structures inside elements.
    ///
    /// **Quoted vs bare:** If a segment both starts and ends with `"` and has length ≥ 2, the quotes are stripped and the
    /// inner text is the element (e.g. `"hello world"` → `hello world`). Otherwise the segment is used as-is (e.g.
    /// bare identifiers `elseif` without quotes, if the model or template emits them that way).
    ///
    /// **Limitations (by design):** No escape sequences inside `"..."`; commas inside a quoted string would still split
    /// incorrectly—avoid commas inside quoted elements in expressions. Single-quoted `'...'` literals are **not** handled
    /// here; only double quotes strip as string delimiters for array elements.
    static func parseStringArrayLiteral(_ raw: String) -> [String]? {
        let value = raw.trim()
        guard value.hasPrefix("["), value.hasSuffix("]") else { return nil }
        let inner = value.dropFirst().dropLast().trim()
        if inner.isEmpty { return [] }
        
        var result: [String] = []
        for segment in inner.split(separator: ",") {
            let seg = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seg.isNotEmpty else { continue }
            if seg.hasPrefix("\""), seg.hasSuffix("\""), seg.count >= 2 {
                result.append(String(seg.dropFirst().dropLast()))
            } else {
                result.append(seg)
            }
        }
        return result
    }
}



