//
//  PrintableParser.swift
//  ModelHike
//

import Foundation

public enum PrintableParser {
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        let nextLine = await lineParser.nextLine()
        return nextLine.has(prefix: ModelConstants.PrintableFenceChar, filler: ModelConstants.PrintableUnderlineChar, suffix: ModelConstants.PrintableFenceChar)
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> PrintableObject? {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return nil }
        try await pInfo.ctx.events.onParse(objectName: header.name, with: pInfo)

        let item = PrintableObject(name: header.name, sourceLocation: SourceLocation(from: pInfo))
        await ExtendedDSLParserSupport.populateHeaderMetadata(for: item, header: header, pending: pending)
        if let bound = header.attributeString {
            await item.setBoundObjects(ExtendedDSLParserSupport.splitCommaList(bound))
        }
        await parser.skipLine(by: 2)

        var currentBlock: String?

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
            if await parseBodyLine(lineInfo, into: item, currentBlock: &currentBlock, allowContinuation: !isTopLevelStart) {
                await parser.skipLine()
                continue
            }

            if isTopLevelStart { break }

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "Printable")
            await parser.skipLine()
        }

        await validate(item, pInfo: pInfo)
        return item
    }

    private static func parseBodyLine(_ pInfo: ParsedInfo, into item: PrintableObject, currentBlock: inout String?, allowContinuation: Bool) async -> Bool {
        let rawText = pInfo.line.trim()
        if rawText.hasPrefix("|> IF") {
            await item.append(conditional: PrintableConditional(condition: rawText.remainingLine(after: "|> IF"), pInfo: pInfo))
            return true
        }

        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        let text = scoped.text
        if text.isEmpty { return false }

        if text == "header:" {
            currentBlock = "header"
            return true
        }

        if text == "footer:" {
            currentBlock = "footer"
            return true
        }

        if text.hasPrefix("section "), text.hasSuffix(":") || text.contains(":") {
            currentBlock = "section"
            await item.append(section: parseSection(text, pInfo: pInfo))
            return true
        }

        if text.hasPrefix("|> IF") {
            await item.append(conditional: PrintableConditional(condition: text.remainingLine(after: "|> IF"), pInfo: pInfo))
            return true
        }

        if text == "end" {
            return true
        }

        if text.hasPrefix("pageBreak:") {
            await item.append(pageBreak: PrintablePageBreak(rule: text.remainingLine(after: "pageBreak:"), pInfo: pInfo))
            return true
        }

        if text.hasPrefix("table:") {
            await item.appendTableToLastSection(PrintableTable(source: text.remainingLine(after: "table:"), columns: [], pInfo: pInfo))
            return true
        }

        if text.hasPrefix("column:") {
            guard let column = parseColumn(text, pInfo: pInfo) else { return false }
            await item.appendColumnToLastTable(column)
            return true
        }

        if text == "footer-row:" {
            currentBlock = "section"
            return true
        }

        if scoped.depth > 0 || allowContinuation && currentBlock != nil {
            let line = DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo)
            switch currentBlock {
            case "header": await item.appendHeaderRow(line)
            case "footer": await item.appendFooterRow(line)
            default: await item.appendRowToLastSection(line)
            }
            return true
        }

        return false
    }

    private static func parseSection(_ text: String, pInfo: ParsedInfo) -> PrintableSection {
        let withoutPrefix = text.hasPrefix("section ") ? text.remainingLine(after: "section") : text
        let parts = withoutPrefix.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var name = parts.first.map(String.init) ?? withoutPrefix
        let layout = extractAttributeSuffix(from: &name)
        return PrintableSection(name: name.trim(), layout: layout, rows: [], tables: [], pInfo: pInfo)
    }

    private static func parseColumn(_ text: String, pInfo: ParsedInfo) -> PrintableTableColumn? {
        let remainder = text.remainingLine(after: "column:")
        let parts = Self.split(remainder, by: "->")
        guard parts.count >= 2 else { return nil }
        return PrintableTableColumn(title: parts[0].trim(), binding: parts[1].trim(), pInfo: pInfo)
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

    private static func extractAttributeSuffix(from text: inout String) -> String? {
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), close > open else { return nil }
        let value = String(text[text.index(after: open)..<close]).trim()
        text.removeSubrange(open...close)
        return value.nonEmpty
    }

    private static func validate(_ item: PrintableObject, pInfo: ParsedInfo) async {
        if await item.outputFormats.isEmpty {
            await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Printable has no @ output:: directive", pInfo: pInfo)
        }
    }
}
