//
//  CodeLogicParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// Parses fenced logic blocks from a `LineParser` into a `CodeLogic` tree.
///
/// Logic is written inside a fenced block, similar to Markdown code fences:
///
/// ```
/// ~~~                           ← opening fence (optional for setext methods)
/// return x                      ← depth-1 line statement
/// |> IF condition               ← depth-1 block opener
/// | return amount               ← depth-2 line statement (child of IF)
/// | |> FOR items                ← depth-2 block opener
/// | | return item               ← depth-3 line statement (child of FOR)
/// |> ELSE                       ← depth-1 block opener (sibling of IF)
/// | return default              ← depth-2 line statement
/// ~~~                           ← closing fence
/// ```
///
/// **Depth rules inside the fence:**
/// - Block openers (`|> KEYWORD`) — `N ≥ 1` pipes then `>` then the keyword; tree depth = N.
/// - Line statements (no `>`)    — `N ≥ 0` pipes then the keyword; tree depth = N + 1.
/// - Block keyword case is flexible (IF / if / If all parse to `.if`).
///
/// Parsing stops when the closing ` ``` ` is encountered, at a recognised DSL-element
/// prefix character (`*`, `-`, `_`, `@`, `#`, `~`, `+`, `=`), or at end of input.
public enum CodeLogicParser {

    // MARK: - Public constants

    /// Backtick fence used by tilde-prefix methods (` ``` ` — opening required, closing required).
    public static let fenceDelimiter = "```"

    /// Single-quote fence, an alternative for tilde-prefix methods (`'''` — opening required, closing required).
    public static let singleQuoteFenceDelimiter = "'''"

    /// Double-quote fence, an alternative for tilde-prefix methods (`"""` — opening required, closing required).
    public static let doubleQuoteFenceDelimiter = "\"\"\""

    /// Tilde fence used by setext methods (`~~~` — opening optional, closing required).
    public static let setextFenceDelimiter = "---"

    /// Returns the fence delimiter to use for closing if `line` is a recognised tilde-style
    /// opening fence, otherwise `nil`.
    ///
    /// A valid opening fence is a line consisting entirely of `` ` ``, `'`, or `"` characters,
    /// with a minimum length of 3. Any repetition count of 3 or more is accepted
    /// (e.g. ```` ``` ````, ```` ```` ````, `''''`, `"""""` are all valid).
    /// The returned value is the exact (trimmed) line content, so the closing fence
    /// must match the opening fence character-for-character.
    public static func tildeFenceDelimiter(for line: String) -> String? {
        let trimmed = line.trim()
        guard trimmed.count >= 3 else { return nil }
        if trimmed.hasOnly("`") { return trimmed }
        if trimmed.hasOnly("'") { return trimmed }
        if trimmed.hasOnly("\"") { return trimmed }
        return nil
    }

    // MARK: - Public API

    /// Parses a raw logic string (already inside a fence) into a `CodeLogic` tree.
    ///
    /// Convenience entry-point for quick parsing and tests — the input is treated as if it were
    /// already between the opening and closing fences. No fence delimiter is expected.
    public static func parse(dslString: String, context: LoadContext, pInfo: ParsedInfo) async throws -> CodeLogic? {
        let parser = LineParserDuringLoad(
            string: dslString,
            identifier: pInfo.identifier,
            isStatementsPrefixedWithKeyword: false,
            with: context
        )
        return try await parseFenced(from: parser, pInfo: pInfo)
    }

    /// Reads lines from `parser` as fenced logic content and returns a `CodeLogic` tree.
    ///
    /// Call this **after** the opening fence has already been consumed (or immediately after the
    /// setext underline, since setext methods have no opening fence — logic starts implicitly).
    ///
    /// - Parameter closingFence: The delimiter that ends the logic block.
    ///   Use `fenceDelimiter` (` ``` `) for tilde-prefix methods and
    ///   `setextFenceDelimiter` (`---`) for setext methods.
    ///
    /// Terminates on:
    /// - A line equal to `closingFence` — consumed and parsing ends successfully.
    /// - A line whose first non-whitespace character is a recognised DSL prefix
    ///   (`*`, `-`, `_`, `@`, `#`, `~`, `+`, `=`) — not consumed, returns what was parsed.
    /// - End of input — returns what was parsed.
    public static func parseFenced(from parser: any LineParser, pInfo: ParsedInfo, closingFence: String = fenceDelimiter) async throws -> CodeLogic? {
        var rawLines: [ParsedLogicLine] = []
        var precededBySeparator = false

        while await parser.linesRemaining {
            let line = await parser.currentLine()
            let lineNo = await parser.curLineNoForDisplay

            // Closing fence — consume and stop
            if line == closingFence {
                await parser.skipLine()
                break
            }

            // Blank lines inside a fence are preserved as separators between parsed statements.
            if line.isEmpty {
                precededBySeparator = true
                await parser.skipLine()
                continue
            }

            if let parsed = parseLine(line, lineNo: lineNo, precededBySeparator: precededBySeparator) {
                rawLines.append(parsed)
                precededBySeparator = false
            } else if isSeparatorLine(line) {
                precededBySeparator = true
            }
            await parser.skipLine()
        }

        guard rawLines.isNotEmpty else { return nil }

        let stream = LineStream(rawLines)
        return CodeLogic(statements: try await buildStatements(from: stream, baseDepth: 1, pInfo: pInfo))
    }

    // MARK: - Line parsing

    /// Flat representation of a single parsed logic line before tree assembly.
    private struct ParsedLogicLine {
        let depth: Int
        let keyword: String
        let expression: String
        let rawLine: String
        let lineNo: Int
        let precededBySeparator: Bool
    }

    /// Parses a single line of fenced logic content.
    ///
    /// **Block openers** — `|> KEYWORD expression` (pipes, then `>`, then the keyword in any case):
    /// - `|> IF condition`   depth-1 block opener
    /// - `||> FOR item in x` depth-2 block opener
    /// - `| |> WHILE cond`   depth-2 (spaces between pipes allowed)
    /// - Require `N ≥ 1` pipes; `depth = N`.
    ///
    /// **Line statements** — `keyword expression` with optional leading pipes:
    /// - `return x`          depth-1 (N=0)
    /// - `|return x`         depth-2 (N=1)
    /// - `| return x`        depth-2 (space after pipe allowed)
    /// - `depth = N + 1`.
    private static func parseLine(_ line: String, lineNo: Int, precededBySeparator: Bool) -> ParsedLogicLine? {
        let originalLine = line
        var line = line

        // Count depth pipes, allowing optional spaces between them for readability.
        // "|> IF", "| |> FOR", "||> WHILE" are all valid.
        var N = 0
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "|" {
                N += 1
                i = line.index(after: i)
            } else if c == " " || c == "\t" {
                i = line.index(after: i)
            } else {
                break
            }
        }
        line = String(line[i...])

        // Prefix-only lines like `|` / `||` are treated as scoped blank separators.
        guard line.isNotEmpty else { return nil }

        // Block opener: "> KEYWORD expression"
        let isBlock = line.hasPrefix(">")
        if isBlock { guard N >= 1 else { return nil } }

        let content = isBlock ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
        let parts   = content.splitOnFirstWhitespace()
        let firstWord = parts.first.lowercased()
        let depth     = isBlock ? N : N + 1

        // Bare `key = value` lines inside parameter blocks (path>, body>, metadata>, NOTIFY DATA, …)
        // must stay as `assign` even when `key` matches a pipe-gutter keyword (e.g. `priority`,
        // `channel`, `data`) so gRPC/HTTP metadata fields and similar KV lines keep working.
        if !isBlock && parts.second.hasPrefix("=") {
            return ParsedLogicLine(depth: depth, keyword: "assign", expression: content, rawLine: originalLine, lineNo: lineNo, precededBySeparator: precededBySeparator)
        }

        if CodeLogicStmtKind(rawValue: firstWord) == nil {
            if isBlock {
                // Unknown block opener (e.g. |> CUSTOM expr): keep as .unknown, expression only.
                return ParsedLogicLine(depth: depth, keyword: firstWord, expression: parts.second, rawLine: originalLine, lineNo: lineNo, precededBySeparator: precededBySeparator)
            } else if parts.second.hasPrefix("=") {
                // Bare "key = value" line inside parameter blocks (path>, body>, params>, etc.)
                // Rewrite as assign so parseKV can extract the pair.
                return ParsedLogicLine(depth: depth, keyword: "assign", expression: content, rawLine: originalLine, lineNo: lineNo, precededBySeparator: precededBySeparator)
            } else {
                // Raw text line (sql>, raw>, note> bodies) — preserve full content as expression.
                return ParsedLogicLine(depth: depth, keyword: "unknown", expression: content, rawLine: originalLine, lineNo: lineNo, precededBySeparator: precededBySeparator)
            }
        }

        return ParsedLogicLine(depth: depth, keyword: firstWord, expression: parts.second, rawLine: originalLine, lineNo: lineNo, precededBySeparator: precededBySeparator)
    }

    // MARK: - Tree assembly

    private final class LineStream: @unchecked Sendable {
        private let lines: [ParsedLogicLine]
        private var index: Int = 0

        var current: ParsedLogicLine? { index < lines.count ? lines[index] : nil }

        init(_ lines: [ParsedLogicLine]) { self.lines = lines }
        func advance() { index += 1 }
    }

    private static func buildStatements(from stream: LineStream, baseDepth: Int, pInfo: ParsedInfo) async throws -> [CodeLogicStmt] {
        var result: [CodeLogicStmt] = []

        while let line = stream.current, line.depth == baseDepth {
            stream.advance()

            let kind = CodeLogicStmtKind.parse(line.keyword)

            // Depth+1 children — for control-flow blocks and leaf sub-blocks (params>, sql>, etc.)
            var children: [CodeLogicStmt] = (stream.current?.depth ?? 0) > baseDepth
                ? try await buildStatements(from: stream, baseDepth: stream.current!.depth, pInfo: pInfo)
                : []

            // Some blocks own same-depth continuation lines directly from the stream:
            // parts (`where>`, `headers>`, `let>`, ...) and branch blocks (`elseif>`, `catch>`, `case>`, ...).
            let ownership = CodeLogicStmt.blockOwnership(for: kind)
            let ownedSameDepthKinds = ownership.partKinds.union(ownership.branchKinds)
            if ownedSameDepthKinds.isNotEmpty {
                while let next = stream.current,
                      next.depth == baseDepth,
                      !next.precededBySeparator,
                      ownedSameDepthKinds.contains(CodeLogicStmtKind.parse(next.keyword)) {
                    stream.advance()
                    let childKind = CodeLogicStmtKind.parse(next.keyword)
                    let grandchildren: [CodeLogicStmt] = (stream.current?.depth ?? 0) > baseDepth
                        ? try await buildStatements(from: stream, baseDepth: stream.current!.depth, pInfo: pInfo)
                        : []
                    children.append(CodeLogicStmt(kind: childKind, expression: next.expression,
                                                  children: grandchildren))
                }

                if let next = stream.current,
                   next.depth == baseDepth,
                   !next.precededBySeparator {
                    let nextKind = CodeLogicStmtKind.parse(next.keyword)
                    if nextKind != .unknown, !ownedSameDepthKinds.contains(nextKind) {
                        let ownedKinds = ownedSameDepthKinds.map(\.keyword).sorted().joined(separator: ", ")
                        let nextPInfo = await ParsedInfo(
                            parser: pInfo.parser,
                            line: next.rawLine,
                            lineNo: next.lineNo,
                            level: pInfo.level,
                            firstWord: next.keyword
                        )
                        throw Model_ParsingError.invalidCodeLogicStatement(
                            "'\(kind.keyword)' does not own same-depth keyword '\(next.keyword)'. Insert a blank line before '\(next.keyword)' to start a new sibling block. If this is nested inside another block, use that parent scope's blank-line prefix. Owned continuations: [\(ownedKinds)].",
                            nextPInfo
                        )
                    }
                }
            }

            result.append(CodeLogicStmt(kind: kind, expression: line.expression, children: children))
        }

        return result
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "|" || c == " " || c == "\t" {
                i = line.index(after: i)
            } else {
                break
            }
        }
        return String(line[i...]).isEmpty
    }
}

// MARK: - String helper

private extension String {
    func splitOnFirstWhitespace() -> (first: String, second: String) {
        guard let range = rangeOfCharacter(from: .whitespaces) else {
            return (self, "")
        }
        let first = String(self[startIndex..<range.lowerBound])
        let second = String(self[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (first, second)
    }
}
