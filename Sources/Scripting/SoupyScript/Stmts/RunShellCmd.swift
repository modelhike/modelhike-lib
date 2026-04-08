//
//  RunShellCmdStmt.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation
import RegexBuilder

public struct RunShellCmdStmt: LineTemplateStmt, CustomDebugStringConvertible {
    public var state: LineTemplateStmtState

    static let START_KEYWORD = "run-shell-cmd"

    public private(set) var CommandToRun: String = ""

    nonisolated(unsafe)
        static let stmtRegex = Regex {
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

        self.CommandToRun = expn

        return true
    }

    public func execute(with ctx: Context) async throws -> String? {
        guard CommandToRun.isNotEmpty else { return nil }
        let debugLog = await ctx.debugLog

        if await ctx.workingDirectoryString.isEmpty {
            throw TemplateSoup_EvaluationError.workingDirectoryNotSet(pInfo)
        }

        #if os(macOS)
            debugLog.pipelineProgress("⚙️  Running the shell command...")
            let fullPath = await ctx.config.output.path / ctx.workingDirectoryString
            let options = Shell.Options(workingDirectory: fullPath.string)
            let result = Shell.execute(command: CommandToRun, options: options)

            if result.failed {
                if let stderr = result.stderr, stderr.isNotEmpty {
                    debugLog.pipelineError(stderr)
                    debugLog.pipelineError("")
                }
                debugLog.pipelineError("❌ Failed to finish the shell command.")
            } else {
                if let stdout = result.stdout, stdout.isNotEmpty {
                    debugLog.pipelineProgress(stdout)
                    debugLog.pipelineProgress("")
                }

                debugLog.pipelineProgress("✅ Finished the shell command...")
            }
        #else
            debugLog.pipelineError("⚠️ Shell commands are not supported on this platform.")
            debugLog.pipelineError("❌ Command not executed: \(CommandToRun)")
        #endif

        return nil
    }

    public var debugDescription: String {
        let str = """
            RUN SHELL CMD stmt (level: \(pInfo.level))
            - expn: \(self.CommandToRun)

            """

        return str
    }

    public init(_ pInfo: ParsedInfo) {
        state = LineTemplateStmtState(keyword: Self.START_KEYWORD, pInfo: pInfo)
    }

    static let register = LineTemplateStmtConfig(keyword: START_KEYWORD) { pInfo in
        RunShellCmdStmt(pInfo)
    }
}
