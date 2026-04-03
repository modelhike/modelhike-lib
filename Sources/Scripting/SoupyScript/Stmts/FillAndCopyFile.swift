//
//  FillAndCopyFileStmt.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation
import RegexBuilder

public struct FillAndCopyFileStmt: LineTemplateStmt, CustomDebugStringConvertible {
    public var state: LineTemplateStmtState
    
    static let START_KEYWORD = "fill-and-copy-file"

    public private(set) var FromFile: String = ""
    public private(set) var ToFile: String = ""
    
    nonisolated(unsafe)
    static let stmtRegex = Regex {
        START_KEYWORD
        
        OneOrMore(.whitespace)
        Capture {
            CommonRegEx.validStringValue
        } transform: { String($0) }
        OneOrMore(.whitespace)
        
        Optionally {
            "to"
            OneOrMore(.whitespace)
            Capture {
                CommonRegEx.validStringValue
            } transform: { String($0) }
        }
        
        CommonRegEx.comments
    }
    
   public mutating func matchLine(line: String) throws -> Bool {
        guard let match = line.wholeMatch(of: Self.stmtRegex) else { return false }
        
        let (_, fromValue, toValue) = match.output
        
        self.FromFile = fromValue
        self.ToFile = toValue ?? fromValue
        
        return true
    }
    
    public func execute(with ctx: Context) async throws -> String? {
        guard let context = ctx as? GenerationContext else { return nil }
        guard FromFile.isNotEmpty else { return nil }
        
        if await ctx.workingDirectoryString.isEmpty {
            throw TemplateSoup_EvaluationError.workingDirectoryNotSet(pInfo)
        }
        
        guard let fromFile = try? await ctx.evaluate(value: FromFile, with: pInfo) as? String
        else {
            let candidates = await ctx.variables.keySnapshot
            throw Suggestions.variableOrPropertyNotFound(FromFile, candidates: candidates, pInfo: pInfo)
        }

        try await context.fileGenerator.setRelativePath(ctx.workingDirectoryString)
        
        if ToFile.isEmpty {
            let fileName = fromFile
            
            await ctx.debugLog.generatingFile(fileName)
            if let _ = try await context.fileGenerator.fillPlaceholdersAndCopyFile(fileName, with: pInfo) {
                //file generated successfully
            } else {
                await ctx.debugLog.fileNotGenerated(fileName)
            }
        } else {
            let rawToValue = try await ctx.evaluate(value: ToFile, with: pInfo)
            guard let toFile = rawToValue as? String else {
                let actualType = runtimeTypeName(of: rawToValue)
                throw TemplateSoup_EvaluationError.invalidFileSystemPath(
                    operation: "fill-and-copy-file",
                    argument: "to",
                    expression: ToFile,
                    actualType: actualType,
                    pInfo
                )
            }
            await ctx.debugLog.generatingFile(toFile)
            if let _ = try await context.fileGenerator.fillPlaceholdersAndCopyFile(fromFile, to: toFile, with: pInfo) {
                //file generated successfully
            } else {
                await ctx.debugLog.fileNotGenerated(toFile)
            }
        }
        
        return nil
    }
    
    public var debugDescription: String {
        let str =  """
        FILL AND COPY stmt (level: \(pInfo.level))
        - from: \(self.FromFile)
        - to: \(self.ToFile)
        
        """
                
        return str
    }
    
    public init(_ pInfo: ParsedInfo) {
        state = LineTemplateStmtState(keyword: Self.START_KEYWORD, pInfo: pInfo)
    }
    
    static let register = LineTemplateStmtConfig(keyword: START_KEYWORD) {pInfo in FillAndCopyFileStmt(pInfo) }
}

