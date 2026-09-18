//
//  ImportFileStmt.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation
import RegexBuilder

/// `import-file "templateName"` — compiles and executes a template purely to register its
/// `func`/`end-func` definitions (which happens at parse time) so later `call` statements
/// elsewhere can use them. Unlike `render-file`, no output file is written and the rendered
/// content is discarded; there is no `as "..."` clause because there is nothing to name.
public struct ImportFileStmt: LineTemplateStmt, CallStackable, CustomDebugStringConvertible {
    public var state: LineTemplateStmtState

    static let START_KEYWORD = "import-file"

    public private(set) var FromTemplate: String = ""

    nonisolated(unsafe)
        static let stmtRegex = Regex {
            START_KEYWORD

            OneOrMore(.whitespace)
            Capture {
                CommonRegEx.validStringValue
            } transform: {
                String($0)
            }

            CommonRegEx.comments
        }

    public mutating func matchLine(line: String) throws -> Bool {
        guard let match = line.wholeMatch(of: Self.stmtRegex) else { return false }

        let (_, fromTemplate) = match.output
        self.FromTemplate = fromTemplate

        return true
    }

    public func execute(with ctx: Context) async throws -> String? {
        guard let context = ctx as? GenerationContext else { return nil }
        guard FromTemplate.isNotEmpty else { return nil }

        guard
            let fromTemplate = try? await ctx.evaluate(value: FromTemplate, with: pInfo) as? String
        else {
            let candidates = await ctx.variables.keySnapshot
            throw Suggestions.variableOrPropertyNotFound(
                FromTemplate, candidates: candidates, pInfo: pInfo)
        }

        await ctx.pushCallStack(self)
        try await context.fileGenerator.importFile(fromTemplate, with: pInfo)
        await ctx.popCallStack()

        return nil
    }

    public var debugDescription: String {
        """
        IMPORT FILE stmt (level: \(pInfo.level))
        - template: \(self.FromTemplate)

        """
    }

    public var callStackItem: CallStackItem { CallStackItem(self, pInfo: pInfo) }

    public init(_ pInfo: ParsedInfo) {
        state = LineTemplateStmtState(keyword: Self.START_KEYWORD, pInfo: pInfo)
    }

    static let register = LineTemplateStmtConfig(keyword: START_KEYWORD) { pInfo in
        ImportFileStmt(pInfo)
    }
}
