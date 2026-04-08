//
//  FrontMatter.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
import Foundation

// Live `FrontMatter` keeps original parser-backed behavior.
// `CachedTemplateFrontMatter` is the parse-once snapshot used by cached template rendering.

struct CachedTemplateFrontMatter: Sendable {
    let identifier: String
    let lines: [String]

    func withIdentifier(_ identifier: String?) -> CachedTemplateFrontMatter {
        guard let identifier, identifier != self.identifier else {
            return self
        }

        return CachedTemplateFrontMatter(identifier: identifier, lines: lines)
    }

    static func split(contents: String, identifier: String) -> (frontMatter: CachedTemplateFrontMatter?, body: String) {
        let sourceLines = contents.splitIntoLines()
        guard let firstLine = sourceLines.first, firstLine.hasOnly(TemplateConstants.frontMatterIndicator) else {
            return (nil, contents)
        }

        var frontMatterLines: [String] = []
        var closingFenceIndex: Int?
        for index in sourceLines.indices.dropFirst() {
            let line = sourceLines[index]
            if line.hasOnly(TemplateConstants.frontMatterIndicator) {
                closingFenceIndex = index
                break
            }
            frontMatterLines.append(line)
        }

        let body: String
        if let closingFenceIndex {
            body = sourceLines.dropFirst(closingFenceIndex + 1).joined(separator: String.newLine)
        } else {
            body = ""
        }

        return (Self(identifier: identifier, lines: frontMatterLines), body)
    }

    func simpleValues() -> [String: String] {
        var values: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: Character(TemplateConstants.frontMatterSplit), maxSplits: 1)
            if parts.count == 2 {
                values[String(parts[0]).trim()] = String(parts[1]).trim()
            }
        }
        return values
    }
}

public struct FrontMatter: Sendable {
    private let lines: [String]
    private let parser: LineParser
    private let ctx: Context
    private var pInfo: ParsedInfo

    private var cachedSnapshot: CachedTemplateFrontMatter {
        CachedTemplateFrontMatter(identifier: pInfo.identifier, lines: lines)
    }

    @discardableResult
    public init(lineParser: LineParser, with context: Context) async throws {
        parser = lineParser
        ctx = context

        await lineParser.skipLine()
        self.lines = await lineParser.parseLinesTill(lineHasOnly: TemplateConstants.frontMatterIndicator)
        await lineParser.skipLine()

        self.pInfo = await ParsedInfo.dummy(line: "FrontMatter", identifier: lineParser.identifier, with: context)
    }

    @discardableResult
    public init?(in contents: String, filename: String, with context: GenerationContext) async throws {
        let lineParser = LineParserDuringGeneration(
            string: contents, identifier: filename, isStatementsPrefixedWithKeyword: true,
            with: context)

        parser = lineParser
        ctx = context

        let curLine = await lineParser.currentLine()

        if curLine.hasOnly(TemplateConstants.frontMatterIndicator) {
            await lineParser.skipLine()
            self.lines = await lineParser.parseLinesTill(lineHasOnly: TemplateConstants.frontMatterIndicator)
            await lineParser.skipLine()

            self.pInfo = await ParsedInfo.dummy(line: "FrontMatter", identifier: await lineParser.identifier, with: context)
        } else {
            return nil
        }
    }

    // MARK: Live parser-backed API

    // Keeps the original best-effort behavior: malformed lines return `nil`.
    public func hasDirective(_ directive: String) async -> ParsedInfo? {
        do {
            let directiveString = "/\(directive)"
            if let rhs = try self.rhs(for: directiveString) {
                return await ParsedInfo(parser: parser, line: rhs, lineNo: -1, level: 0, firstWord: directiveString)
            }

            return nil
        } catch {
            return nil
        }
    }

    public func evalDirective(_ directive: String, pInfo: ParsedInfo) async throws -> Any? {
        try await Self.evalDirective(directive, in: cachedSnapshot, pInfo: pInfo)
    }

    public func bodyAfterFrontMatter() async -> String {
        await parser.getRemainingLinesAsString()
    }

    public mutating func processVariables() async throws {
        var index = 1 // front matter starts after the separator (---) line

        for line in lines {
            pInfo.setLineInfo(line: line, lineNo: index)
            let (lhs, rhs) = try FrontMatterParsing.splitKeyValue(line, pInfo: pInfo)
            if let firstChar = lhs.first {
                switch firstChar {
                case "/":
                    try await FrontMatterParsing.applySlashDirective(lhs: lhs, rhs: rhs, identifier: await parser.identifier, pInfo: pInfo, with: ctx)
                default:
                    await ctx.variables.set(lhs, value: rhs)
                }
            }
            index += 1
        }
    }

    public func rhs(for lhsValueToCheck: String, defaultValue: String) -> String {
        if let rhs = try? rhs(for: lhsValueToCheck) {
            return rhs
        } else {
            return defaultValue
        }
    }

    public func rhs(for lhsValueToCheck: String) throws -> String? {
        var index = 1 // front matter starts after the separator (---) line
        var pInfo2 = pInfo
        for line in lines {
            pInfo2.setLineInfo(line: line, lineNo: index)
            let (lhs, rhs) = try FrontMatterParsing.splitKeyValue(line, pInfo: pInfo2)
            if lhs == lhsValueToCheck {
                return rhs
            }
            index += 1
        }

        return nil
    }

    public static func simpleParse(contents: String) -> (values: [String: String], body: String) {
        let lines = contents.splitIntoLines()
        var values: [String: String] = [:]
        var fenceCount = 0

        for (index, line) in lines.enumerated() {
            if line.hasOnly(TemplateConstants.frontMatterIndicator) {
                fenceCount += 1
                if fenceCount == 2 {
                    let body = lines.dropFirst(index + 1).joined(separator: String.newLine)
                    return (values, body)
                }
                continue
            }

            if fenceCount == 1 {
                let parts = line.split(separator: Character(TemplateConstants.frontMatterSplit), maxSplits: 1)
                if parts.count == 2 {
                    values[String(parts[0]).trim()] = String(parts[1]).trim()
                }
            }
        }

        return ([:], contents)
    }

    // Cached-path parity with the legacy live API: malformed front matter is
    // treated as "directive not found" here and will surface later when the
    // full front matter is processed during actual template execution.
    // When `sourceContents` is provided, the returned `ParsedInfo` carries a real
    // `LineParser` backed by the template source (matching the old live path).
    static func hasDirective(_ directive: String, in cached: CachedTemplateFrontMatter, with ctx: Context, sourceContents: String? = nil) async -> ParsedInfo? {
        do {
            let directiveString = "/\(directive)"
            guard let rhs = try await FrontMatterParsing.rhs(for: directiveString, in: cached, with: ctx) else {
                return nil
            }

            if let sourceContents, let genCtx = ctx as? GenerationContext {
                let parser = LineParserDuringGeneration(string: sourceContents, identifier: cached.identifier, isStatementsPrefixedWithKeyword: true, with: genCtx)
                return await ParsedInfo(parser: parser, line: rhs, lineNo: -1, level: 0, firstWord: directiveString)
            }

            var pInfo = await ParsedInfo.dummy(line: rhs, identifier: cached.identifier, with: ctx)
            pInfo.firstWord(directiveString)
            return pInfo
        } catch {
            return nil
        }
    }

    /// - Throws: Same as ``hasDirective`` plus evaluation errors from the RHS.
    static func evalDirective(_ directive: String, in cached: CachedTemplateFrontMatter, pInfo: ParsedInfo) async throws -> Any? {
        let directiveString = "/\(directive)"
        if let rhs = try FrontMatterParsing.rhs(for: directiveString, in: cached, basePInfo: pInfo) {
            return try await ContentHandler.eval(line: rhs, pInfo: pInfo)
        }
        return nil
    }

    /// - Throws: ``FrontMatterParsing/splitKeyValue`` and ``FrontMatterParsing/applySlashDirective``.
    static func processVariables(in cached: CachedTemplateFrontMatter, with ctx: Context) async throws {
        var lineNo = 1
        for line in cached.lines {
            var linePInfo = await ParsedInfo.dummy(line: line, identifier: cached.identifier, with: ctx)
            linePInfo.setLineInfo(line: line, lineNo: lineNo)

            let (lhs, rhs) = try FrontMatterParsing.splitKeyValue(line, pInfo: linePInfo)
            if let firstChar = lhs.first {
                switch firstChar {
                case "/":
                    try await FrontMatterParsing.applySlashDirective(lhs: lhs, rhs: rhs, identifier: cached.identifier, pInfo: linePInfo, with: ctx)
                default:
                    await ctx.variables.set(lhs, value: rhs)
                }
            }

            lineNo += 1
        }
    }
}

// MARK: - Private parsing and directive semantics

private enum FrontMatterParsing {
    static func rhs(for lhsValueToCheck: String, in cached: CachedTemplateFrontMatter, basePInfo: ParsedInfo) throws -> String? {
        var linePInfo = basePInfo
        var lineNo = 1
        for line in cached.lines {
            linePInfo.setLineInfo(line: line, lineNo: lineNo)
            let (lhs, rhs) = try splitKeyValue(line, pInfo: linePInfo)
            if lhs == lhsValueToCheck {
                return rhs
            }
            lineNo += 1
        }
        return nil
    }

    static func rhs(for lhsValueToCheck: String, in cached: CachedTemplateFrontMatter, with ctx: Context) async throws -> String? {
        let basePInfo = await ParsedInfo.dummy(line: "FrontMatter", identifier: cached.identifier, with: ctx)
        return try rhs(for: lhsValueToCheck, in: cached, basePInfo: basePInfo)
    }

    /// - Throws: `TemplateSoup_ParsingError.invalidFrontMatter` when the line has no `:` separator (or not exactly one split).
    static func splitKeyValue(_ line: String, pInfo: ParsedInfo) throws -> (lhs: String, rhs: String) {
        let split = line.split(separator: TemplateConstants.frontMatterSplit, maxSplits: 1, omittingEmptySubsequences: true)
        if split.count == 2 {
            return (String(split[0]).trim(), String(split[1]).trim())
        }
        throw TemplateSoup_ParsingError.invalidFrontMatter(line, pInfo)
    }

    /// - Throws: `ParserDirective.excludeFile` if `/include-if` is false; `ParsingError.unrecognisedParsingDirective` for unknown `/…`; errors from ``Context/evaluateCondition``.
    static func applySlashDirective(lhs: String, rhs: String, identifier: String, pInfo: ParsedInfo, with ctx: Context) async throws {
        let directiveName = lhs.dropFirst().lowercased()

        switch directiveName {
        case ParserDirective.includeIf:
            let result = try await ctx.evaluateCondition(expression: rhs, with: pInfo)
            if !result {
                throw ParserDirective.excludeFile(identifier)
            }
        case ParserDirective.includeFor:
            break
        case ParserDirective.outputFilename:
            break
        default:
            throw ParsingError.unrecognisedParsingDirective(String(directiveName), pInfo)
        }
    }
}
