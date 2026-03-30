//
//  Suggestions.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Provides typo-tolerant "did you mean?" suggestions for lookup failures.
///
/// How this is used in ModelHike:
/// - Modifier lookup errors:
///   `lowercas` -> suggest `lowercase`
/// - Variable/property lookup diagnostics:
///   `usernme` -> suggest `username`
/// - Validation warnings for unresolved modules/types:
///   compares the unknown symbol against known module/type names
///
/// The general flow is:
/// 1. Take the bad input string from the user/model/template.
/// 2. Compare it against a list of known valid candidates.
/// 3. Compute Levenshtein distance for each candidate.
/// 4. Keep only close matches (`maxDistance`, default = 2).
/// 5. Sort by smallest distance and return the best matches.
///
/// In practice, this turns a plain failure like:
/// - `modifier not found`
///
/// into a more helpful message like:
/// - `"lowercas" not found — did you mean "lowercase"?`
///
/// This file also converts those matches into:
/// - human-readable error suffixes
/// - structured diagnostic suggestions for the debug UI
public enum Suggestions {
    /// Extracts the root symbol from a lookup query.
    ///
    /// Example:
    /// - `user.name` -> `user`
    ///
    /// This is useful when a nested lookup fails and we want to suggest the
    /// closest top-level symbol first.
    static func lookupQueryRoot(_ query: String) -> String {
        // For nested lookups like `user.nmae`, suggestion quality is better if we
        // compare only the root symbol first (`user`) instead of the whole dotted path.
        String(query.split(separator: ".", maxSplits: 1).first ?? Substring(query))
    }

    /// Returns the nearest typo-tolerant matches for a lookup query.
    ///
    /// How this works:
    /// 1. Lowercase the query and each candidate for case-insensitive comparison.
    /// 2. Compute Levenshtein distance from the query to every candidate.
    /// 3. Keep only candidates within `maxDistance`.
    /// 4. Sort by smallest distance first.
    /// 5. Return at most `maxResults` candidates.
    ///
    /// Example:
    /// - query: `lowercas`
    /// - candidates: [`lowercase`, `uppercase`, `trim`]
    /// - result: [`lowercase`]
    ///
    /// This is the core primitive used by the rest of this file. Higher-level
    /// helpers wrap these raw matches into:
    /// - user-facing strings
    /// - structured `DiagnosticSuggestion` values
    ///
    /// Notes:
    /// - A small `maxDistance` keeps suggestions relevant and avoids noisy guesses.
    /// - `maxResults` prevents huge candidate lists from becoming unreadable.
    public static func closestMatches(
        for query: String,
        in candidates: [String],
        maxDistance: Int = 2,
        maxResults: Int = 3
    ) -> [String] {
        let q = query.lowercased()
        var scored: [(String, Int)] = []

        for candidate in candidates {
            let dist = levenshtein(q, candidate.lowercased())
            if dist <= maxDistance {
                scored.append((candidate, dist))
            }
        }

        return scored
            .sorted { $0.1 < $1.1 }
            .prefix(maxResults)
            .map { $0.0 }
    }

    /// Builds a structured "did you mean?" suggestion from the nearest candidate matches.
    ///
    /// What this function does:
    /// 1. Calls `closestMatches(...)` to compute typo-near candidates using
    ///    Levenshtein distance.
    /// 2. Returns `nil` if no candidate is close enough.
    /// 3. Produces a `DiagnosticSuggestion` so the caller can use the result in:
    ///    - debug diagnostics
    ///    - structured Problems-panel payloads
    ///    - future quick-fix style UI actions
    ///
    /// Result shape:
    /// - If there is exactly one strong match:
    ///   - message: `did you mean 'username'?`
    ///   - replacement: `username`
    ///   - options: `[username]`
    /// - If there are multiple close matches:
    ///   - message: `did you mean one of: 'userName', 'username'?`
    ///   - replacement: `nil`
    ///   - options: all returned matches
    ///
    /// Why structured instead of only returning a string:
    /// - `message` is for display
    /// - `replacement` is useful if a future UI wants a one-click fix
    /// - `options` preserves the raw candidate list for richer tooling
    public static func didYouMeanSuggestion(for query: String, in candidates: [String]) -> DiagnosticSuggestion? {
        let matches = closestMatches(for: query, in: candidates)
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 {
            return DiagnosticSuggestion(
                kind: .didYouMean,
                message: "did you mean '\(matches[0])'?",
                replacement: matches[0],
                options: matches
            )
        }
        let quoted = matches.map { "'\($0)'" }.joined(separator: ", ")
        return DiagnosticSuggestion(
            kind: .didYouMean,
            message: "did you mean one of: \(quoted)?",
            options: matches
        )
    }

    /// Convenience wrapper that returns only the display message from
    /// `didYouMeanSuggestion(...)`.
    ///
    /// Use this when the caller only needs plain text, for example:
    /// - appending a suffix to an error message
    /// - logging a human-readable warning
    ///
    /// Use `didYouMeanSuggestion(...)` instead when the caller needs structured
    /// suggestion data such as:
    /// - a replacement value
    /// - the full option list
    /// - a `DiagnosticSuggestion` object for UI rendering
    public static func didYouMean(for query: String, in candidates: [String]) -> String? {
        didYouMeanSuggestion(for: query, in: candidates)?.message
    }

    /// Builds a structured list of suggestions for a failed symbol lookup.
    ///
    /// This is the main aggregation helper used by diagnostics and error builders.
    /// It can include two kinds of guidance:
    /// - a `didYouMean` suggestion for typo correction
    /// - an `availableOptions` suggestion listing valid known names
    ///
    /// Example output:
    /// - `[.didYouMean("did you mean 'username'?"), .availableOptions("variables in scope: username, userId")]`
    ///
    /// The result is structured so callers can:
    /// - render richer Problems-panel entries
    /// - serialize suggestions in diagnostics JSON
    /// - keep replacement/options metadata alongside the display text
    public static func lookupSuggestions(
        for query: String,
        in candidates: [String],
        availableOptionsLabel: String? = nil
    ) -> [DiagnosticSuggestion] {
        var suggestions: [DiagnosticSuggestion] = []
        if let hint = didYouMeanSuggestion(for: query, in: candidates) {
            suggestions.append(hint)
        }
        if let availableOptionsLabel {
            suggestions.append(availableOptionsSuggestion(candidates, label: availableOptionsLabel))
        }
        return suggestions
    }

    /// Formats structured lookup suggestions into a compact inline message suffix.
    ///
    /// This is mainly used for thrown parsing/evaluation errors where we want a
    /// single human-readable sentence instead of a structured diagnostics object.
    ///
    /// Example output:
    /// - ` — did you mean 'foo'?. available modifiers: foo, bar`
    ///
    /// Formatting rules:
    /// - if both a typo hint and available-options note exist, include both
    /// - if only one exists, emit only that one
    /// - if nothing useful exists, return an empty string
    public static func lookupMessageSuffix(
        for query: String,
        in candidates: [String],
        availableOptionsLabel: String? = nil
    ) -> String {
        let suggestions = lookupSuggestions(
            for: query,
            in: candidates,
            availableOptionsLabel: availableOptionsLabel
        )
        guard !suggestions.isEmpty else { return "" }

        let didYouMean = suggestions.first { $0.kind == .didYouMean }?.message
        let availableOptions = suggestions.first { $0.kind == .availableOptions }?.message

        switch (didYouMean, availableOptions) {
        case let (.some(hint), .some(options)):
            return " — \(hint). \(options)"
        case let (.some(hint), .none):
            return " — \(hint)"
        case let (.none, .some(options)):
            return ". \(options)"
        case (.none, .none):
            return ""
        }
    }

    /// Builds a complete lookup failure message by attaching suggestion guidance
    /// to a caller-provided base message.
    ///
    /// This helper keeps the calling sites simple:
    /// - the caller defines the primary failure sentence
    /// - this function appends any typo/available-options guidance consistently
    ///
    /// Example:
    /// - base: `Operator 'cntains' not found.`
    /// - result: `Operator 'cntains' not found. — did you mean 'contains'?. available operators: contains, equals`
    public static func lookupFailureMessage(
        _ baseMessage: String,
        for query: String,
        in candidates: [String],
        availableOptionsLabel: String? = nil
    ) -> String {
        baseMessage + lookupMessageSuffix(
            for: query,
            in: candidates,
            availableOptionsLabel: availableOptionsLabel
        )
    }

    /// Builds a parsing error for unresolved variable or property access.
    ///
    /// This helper is specialized for lookup failures in expressions like:
    /// - `usernme`
    /// - `account.emial`
    ///
    /// It:
    /// - preserves the user-facing base error text
    /// - suggests the closest in-scope root variable names
    /// - appends a visible "variables in scope" summary
    ///
    /// The returned error is already fully formatted and ready to throw.
    public static func variableOrPropertyNotFound(
        _ query: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> TemplateSoup_ParsingError {
        .variableOrPropertyNotFound(
            lookupFailureMessage(
                "Variable or property '\(query)' not found. Check spelling and scope.",
                for: lookupQueryRoot(query),
                in: candidates,
                availableOptionsLabel: "variables in scope"
            ),
            pInfo
        )
    }

    /// Builds a parsing error for unresolved operand in an expression.
    ///
    /// This helper is specialized for lookup failures in expressions like:
    /// - `usernme`
    /// - `account.emial`
    ///
    /// It:
    /// - preserves the user-facing base error text
    /// - suggests the closest in-scope root variable names
    /// - appends a visible "variables in scope" summary
    ///
    /// The returned error is already fully formatted and ready to throw.
    public static func expressionOperandNotFound(
        _ query: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> TemplateSoup_ParsingError {
        .expressionOperandNotFound(
            lookupFailureMessage(
                "Operand '\(query)' not found in expression. Check spelling and scope.",
                for: lookupQueryRoot(query),
                in: candidates,
                availableOptionsLabel: "variables in scope"
            ),
            pInfo
        )
    }

    /// Builds a parsing error for a missing template function.
    ///
    /// This is used when a function call in TemplateSoup/SoupyScript refers to a
    /// function name that does not exist. The resulting message includes:
    /// - the original failure
    /// - the nearest function-name suggestions
    /// - a compact list of known function names
    public static func templateFunctionNotFound(
        _ name: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> TemplateSoup_ParsingError {
        .templateFunctionNotFound(
            lookupFailureMessage(
                "Template function '\(name)' not found. Define it with :fn \(name) ... :end-fn before calling it.",
                for: name,
                in: candidates,
                availableOptionsLabel: "available template functions"
            ),
            pInfo
        )
    }

    /// Builds a parsing error for an unknown infix operator.
    ///
    /// This is the operator-specific equivalent of the generic lookup helpers.
    /// It packages a user-facing operator failure together with:
    /// - the nearest operator matches
    /// - a compact list of available operators
    public static func infixOperatorNotFound(
        _ name: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> TemplateSoup_ParsingError {
        .infixOperatorNotFound(
            lookupFailureMessage(
                "Operator '\(name)' not found.",
                for: name,
                in: candidates,
                availableOptionsLabel: "available operators"
            ),
            pInfo
        )
    }

    /// Builds a type-mismatch error when an operator exists by name but no registration
    /// matches the runtime LHS/RHS types. Lists the expected type pairs so the user can
    /// see what combinations are supported.
    public static func infixOperatorTypeMismatch(_ name: String, lhsType: String, rhsType: String, expectedPairs: [String], pInfo: ParsedInfo) -> TemplateSoup_ParsingError {
        let pairsStr = expectedPairs.joined(separator: ", ")
        return .infixOperatorCalledOnwrongLhsType(
            "Operator '\(name)' called with (\(lhsType), \(rhsType)). Registered type pairs: \(pairsStr)",
            lhsType, pInfo
        )
    }

    /// Builds a parsing error for an invalid wrapper/object property lookup.
    public static func invalidPropertyInCall(
        _ name: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> TemplateSoup_ParsingError {
        .invalidPropertyInCall(
            lookupFailureMessage(
                "Invalid property: '\(name)'",
                for: name,
                in: candidates,
                availableOptionsLabel: "available properties"
            ),
            pInfo
        )
    }

    /// Builds a parsing error when a referenced object type cannot be found.
    ///
    /// Generates a descriptive error message that includes "did you mean?" suggestions
    /// based on Levenshtein distance against the provided candidate type names.
    ///
    /// - Parameters:
    ///   - name: The unknown type name that was requested.
    ///   - candidates: A list of valid type names available in the current context.
    ///   - pInfo: Parsing context used to attach file and line number information.
    /// - Returns: A `.objectTypeNotFound` parsing error containing the formatted suggestion.
    public static func objectTypeNotFound(
        _ name: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> Model_ParsingError {
        .objectTypeNotFound(
            lookupFailureMessage(
                "Object type '\(name)' not found.",
                for: name,
                in: candidates,
                availableOptionsLabel: "known types"
            ),
            pInfo
        )
    }

    /// Builds a parsing error when a property is referenced on a type that doesn't define it.
    ///
    /// Generates a descriptive error message that includes "did you mean?" suggestions
    /// based on Levenshtein distance against the provided candidate properties.
    ///
    /// - Parameters:
    ///   - propertyName: The invalid property name that was requested.
    ///   - typeName: The name of the type being accessed.
    ///   - candidates: A list of valid property names available on the type.
    ///   - pInfo: Parsing context used to attach file and line number information.
    /// - Returns: A `.invalidPropertyInType` parsing error containing the formatted suggestion.
    public static func invalidPropertyInType(
        _ propertyName: String,
        typeName: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> Model_ParsingError {
        .invalidPropertyInType(
            lookupFailureMessage(
                "Property '\(propertyName)' does not exist on '\(typeName)'.",
                for: propertyName,
                in: candidates,
                availableOptionsLabel: "available properties"
            ),
            pInfo
        )
    }

    /// Builds a parsing error when an invalid property is referenced within an API definition block.
    ///
    /// Generates a descriptive error message that includes "did you mean?" suggestions
    /// based on Levenshtein distance against the provided candidate properties.
    ///
    /// - Parameters:
    ///   - propertyName: The invalid property name that was requested.
    ///   - line: The full line of text where the invalid property was used, for context.
    ///   - candidates: A list of valid property names available in the current context.
    ///   - pInfo: Parsing context used to attach file and line number information.
    /// - Returns: A `.invalidPropertyUsedInApi` parsing error containing the formatted suggestion.
    public static func invalidPropertyUsedInApi(
        _ propertyName: String,
        line: String,
        candidates: [String],
        pInfo: ParsedInfo
    ) -> Model_ParsingError {
        .invalidPropertyUsedInApi(
            lookupFailureMessage(
                "Invalid property '\(propertyName)' used in '\(line)'.",
                for: propertyName,
                in: candidates,
                availableOptionsLabel: "available properties"
            ),
            pInfo
        )
    }

    /// Builds a structured "available options" suggestion.
    ///
    /// This is used when we want to show the user the valid known values after a
    /// failed lookup, even if there is no strong typo match.
    ///
    /// Behavior:
    /// - if there are no options, returns `<label>: (none)`
    /// - if there are up to 8 options, lists them all
    /// - if there are more than 8, shows a short preview plus a `(+N more)` tail
    ///
    /// Returning a `DiagnosticSuggestion` instead of a string keeps the raw list
    /// available for structured UIs and future quick-fix interactions.
    public static func availableOptionsSuggestion(_ options: [String], label: String = "available") -> DiagnosticSuggestion {
        let sorted = options.sorted()
        if sorted.isEmpty {
            return DiagnosticSuggestion(
                kind: .availableOptions,
                message: "\(label): (none)",
                options: []
            )
        }
        if sorted.count <= 8 {
            return DiagnosticSuggestion(
                kind: .availableOptions,
                message: "\(label): \(sorted.joined(separator: ", "))",
                options: sorted
            )
        }
        let preview = sorted.prefix(8).joined(separator: ", ")
        return DiagnosticSuggestion(
            kind: .availableOptions,
            message: "\(label): \(preview) … (+\(sorted.count - 8) more)",
            options: sorted
        )
    }

    /// Convenience wrapper that returns only the display message from
    /// `availableOptionsSuggestion(...)`.
    ///
    /// Use this when the caller only needs a compact string to append to an error
    /// message or log line, rather than the full structured suggestion object.
    public static func availableOptions(_ options: [String], label: String = "available") -> String {
        availableOptionsSuggestion(options, label: label).message
    }

    // MARK: - Levenshtein distance (iterative, O(m*n) time, O(min(m,n)) space)

    /// Computes classic Levenshtein edit distance between two strings.
    ///
    /// Distance = minimum number of single-character edits needed to turn `a` into `b`.
    /// Allowed edit operations:
    /// - insertion
    /// - deletion
    /// - substitution
    ///
    /// Examples:
    /// - `lowercas` -> `lowercase` = 1 insertion
    /// - `usernme` -> `username` = 1 insertion
    /// - `modul` -> `module` = 1 insertion
    /// - `usrname` -> `username` = 1 insertion
    ///
    /// Implementation notes:
    /// - Uses dynamic programming
    /// - `prev` stores the previous DP row
    /// - `curr` stores the current DP row being computed
    /// - We only keep two rows at a time to reduce memory usage
    ///
    /// DP intuition:
    /// - If characters match, carry forward the diagonal value
    /// - Otherwise take the cheapest of:
    ///   - delete  (`prev[j]`)
    ///   - insert  (`curr[j - 1]`)
    ///   - replace (`prev[j - 1]`)
    ///   and add 1 for the current edit
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        // Base row: distance from empty prefix of `a` to each prefix of `b`.
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            // Distance from first `i` chars of `a` to empty prefix of `b`
            // is `i` deletions.
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    // Same character: no new edit needed.
                    curr[j] = prev[j - 1]
                } else {
                    // One edit plus the best of:
                    // - delete from `a`
                    // - insert into `a`
                    // - replace current character
                    curr[j] = 1 + Swift.min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            // Move current row into previous row for the next iteration.
            swap(&prev, &curr)
        }
        // Final cell = full-string edit distance.
        return prev[n]
    }
}
