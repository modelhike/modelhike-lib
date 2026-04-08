//
//  AnnounceStmt.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation
import RegexBuilder

public struct AnnounceStmt: LineTemplateStmt {
    public var state: LineTemplateStmtState

    static let START_KEYWORD = "announce"

    public private(set) var Expression: String = ""

    nonisolated(unsafe)
    private static let stmtRegex = Regex {
        START_KEYWORD
        OneOrMore(.whitespace)
        Capture {
            CommonRegEx.anything
        } transform: {
            String($0)
        }
        ZeroOrMore(.whitespace)

        CommonRegEx.comments
    }

    public mutating func matchLine(line: String) throws -> Bool {
        guard let match = line.wholeMatch(of: Self.stmtRegex) else { return false }

        let (_, expn) = match.output

        self.Expression = expn

        return true
    }

    public func execute(with ctx: Context) async throws -> String? {
        guard Expression.isNotEmpty else { return nil }
        let debugLog = await ctx.debugLog

        let value: String
        if let expn = try? await ctx.evaluate(value: Expression, with: pInfo) {
            value = "🔈 \(expn)"
        } else {
            value = "🔈🎈[Line no: \(lineNo)] - nothing to announce"
        }

        debugLog.pipelineProgress(value)
        // Emit to debug timeline so announce output is visible in the debug console
        debugLog.recordEvent(.announce(value: value))
        return nil
    }

    public var debugDescription: String { get async {
        let str = """
            ANNOUNCE stmt (level: \(pInfo.level))
            - expn: \(self.Expression)
            
            """
        
        return str
    }}

    public init(_ pInfo: ParsedInfo) {
        state = LineTemplateStmtState(keyword: Self.START_KEYWORD, pInfo: pInfo)
    }

    static let register = LineTemplateStmtConfig(keyword: START_KEYWORD) { pInfo in
        AnnounceStmt(pInfo)
    }
}
