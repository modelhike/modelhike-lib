//
//  ConsoleLogStmt.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation
import RegexBuilder

public struct ConsoleLogStmt: LineTemplateStmt, CustomDebugStringConvertible {
    public var state: LineTemplateStmtState
    
    static let START_KEYWORD = "console-log"

    public private(set) var Expression: String = ""
    
    nonisolated(unsafe)
    static let stmtRegex = Regex {
        START_KEYWORD
        OneOrMore(.whitespace)
        Capture {
            CommonRegEx.anything
        } transform: { String($0) }
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
        
        var logValue = "🏷️🎈[Line no: \(lineNo)] - nothing to show"
        
        //see if it is an object
        if let expn = try? await ctx.evaluate(value: Expression, with: pInfo) {
            if expn is String {
                logValue = "🏷️ [Line \(lineNo)] \(expn)"
            } else if let obj = deepUnwrap(expn) {
                if let debugInfo = obj as? CustomDebugStringConvertible {
                    logValue = "🏷️ [Line \(lineNo)] \(debugInfo.debugDescription)"
                } else {
                    logValue = "🏷️ [Line \(lineNo)] \(obj)"
                }
            }
        } else if let expn = try? await ctx.evaluate(expression: Expression, with: pInfo) {
            logValue = "🏷️ [Line \(lineNo)] \(expn)"
        }
        
        print(logValue)
        // Emit to debug console so console-log output appears in the event timeline
        await ctx.debugLog.recordEvent(.consoleLog(
            value: logValue,
            source: SourceLocation(fileIdentifier: pInfo.identifier, lineNo: pInfo.lineNo,
                                   lineContent: pInfo.line, level: pInfo.level)
        ))
        return nil
    }
    
    public var debugDescription: String {
        let str =  """
        CONSOLE LOG stmt (level: \(pInfo.level))
        - expn: \(self.Expression)
        
        """
                
        return str
    }
    
    public init(_ pInfo: ParsedInfo) {
        state = LineTemplateStmtState(keyword: Self.START_KEYWORD, pInfo: pInfo)

    }
    
    static let register = LineTemplateStmtConfig(keyword: START_KEYWORD) {pInfo in ConsoleLogStmt(pInfo) }
}


