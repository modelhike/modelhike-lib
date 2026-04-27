//
//  ConfigParser.swift
//  ModelHike
//

import Foundation

public enum ConfigParser {
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        if let nextFirstWord = await lineParser.nextLine().firstWord() {
            return nextFirstWord.hasOnly(ModelConstants.ConfigUnderlineChar)
        }
        return false
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> ConfigObject? {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return nil }
        try await pInfo.ctx.events.onParse(objectName: header.name, with: pInfo)

        let item = ConfigObject(name: header.name, sourceLocation: SourceLocation(from: pInfo))
        await ExtendedDSLParserSupport.populateHeaderMetadata(for: item, header: header, pending: pending)
        if let attr = header.attributeString {
            await item.setConfigKind(ExtendedDSLParserSupport.splitCommaList(attr).first)
        }
        await parser.skipLine(by: 2)

        var currentGroup: String?

        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() {
                await parser.skipLine()
                continue
            }
            guard let lineInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }
            if try await lineInfo.tryParseAttachedSections(with: item) { continue }
            if let directive = ExtendedDSLParserSupport.parseDirectiveLine(lineInfo.line, pInfo: lineInfo) {
                await item.append(directive: directive)
                await parser.skipLine()
                continue
            }

            let isTopLevelStart = await ExtendedDSLParserSupport.isKnownTopLevelStart(parser: parser)
            if await parseBodyLine(lineInfo, into: item, currentGroup: &currentGroup, allowContinuation: !isTopLevelStart) {
                await parser.skipLine()
                continue
            }

            if isTopLevelStart { break }

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "Config")
            await parser.skipLine()
        }

        await validate(item, pInfo: pInfo)
        return item
    }

    private static func parseBodyLine(_ pInfo: ParsedInfo, into item: ConfigObject, currentGroup: inout String?, allowContinuation: Bool) async -> Bool {
        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        let text = scoped.text
        if text.isEmpty { return false }

        if text.hasSuffix(":"), !text.contains("="), !text.contains("->") {
            currentGroup = String(text.dropLast()).trim()
            await item.append(group: ConfigGroup(name: currentGroup ?? "", properties: [], pInfo: pInfo))
            return true
        }

        if let property = parseProperty(text, depth: scoped.depth, pInfo: pInfo) {
            if scoped.depth > 0 || allowContinuation && currentGroup != nil {
                await item.appendPropertyToLastGroup(property)
            } else {
                await item.append(property: property)
            }
            return true
        }

        return false
    }

    private static func parseProperty(_ text: String, depth: Int, pInfo: ParsedInfo) -> ConfigProperty? {
        if text.contains("=") {
            let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return ConfigProperty(key: String(parts[0]).trim(), value: String(parts[1]).trim(), depth: depth, pInfo: pInfo)
        }
        if text.contains("->") {
            let parts = Self.split(text, by: "->")
            guard parts.count >= 2 else { return nil }
            return ConfigProperty(key: parts[0].trim(), value: parts.dropFirst().joined(separator: "->").trim(), depth: depth, pInfo: pInfo)
        }
        if text.contains(":") {
            let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return ConfigProperty(key: String(parts[0]).trim(), value: String(parts[1]).trim(), depth: depth, pInfo: pInfo)
        }
        return nil
    }

    private static func split(_ text: String, by separator: String) -> [String] {
        var result: [String] = []
        var remainder = text
        while let range = remainder.range(of: separator) {
            result.append(String(remainder[..<range.lowerBound]))
            remainder = String(remainder[range.upperBound...])
        }
        result.append(remainder)
        return result
    }

    private static func validate(_ item: ConfigObject, pInfo: ParsedInfo) async {
        if await item.configKind == nil {
            await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Config object has no kind in header attributes, e.g. (calendar)", pInfo: pInfo)
        }
    }
}
