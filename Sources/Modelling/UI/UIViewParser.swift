//
//  UIViewParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum UIViewParser {
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        let nextLine = await lineParser.nextLine()
        return nextLine.has(prefix: ModelConstants.UIViewFenceChar, filler: ModelConstants.UIViewUnderlineChar, suffix: ModelConstants.UIViewFenceChar)
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> UIView? {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return nil }
        try await pInfo.ctx.events.onParse(objectName: header.name, with: pInfo)

        let item = UIView(name: header.name, sourceLocation: SourceLocation(from: pInfo))
        await ExtendedDSLParserSupport.populateHeaderMetadata(for: item, header: header, pending: pending)
        await parser.skipLine(by: 2)

        var inActions = false

       while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() {
                await parser.skipLine()
                continue
            }
            guard let lineInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }
            let trimmed = await parser.currentLine()
            if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                await ParserUtil.appendConsumedDescriptionLines(from: parser, to: item)
                continue
            }
            if let directive = ExtendedDSLParserSupport.parseDirectiveLine(lineInfo.line, pInfo: lineInfo) {
                await item.append(directive: directive)
                await parser.skipLine()
                continue
            }

            let isTopLevelStart = await ExtendedDSLParserSupport.isKnownTopLevelStart(parser: parser)
            if await parseBodyLine(lineInfo, into: item, inActions: &inActions, allowContinuation: !isTopLevelStart) {
                await parser.skipLine()
                continue
            }

            if try await lineInfo.tryParseAttachedSections(with: item) { continue }

            if isTopLevelStart { break }

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "UI View")
            await parser.skipLine()
        }

        return item
    }

    private static func parseBodyLine(_ pInfo: ParsedInfo, into item: UIView, inActions: inout Bool, allowContinuation: Bool) async -> Bool {
        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        let text = scoped.text
        if text.isEmpty { return false }

        if text == "# Actions" {
            inActions = true
            return true
        }

        if text == "#" {
            inActions = false
            return true
        }

        if inActions, text.hasPrefix("##") {
            await item.append(action: UIActionHandler(trigger: text.dropFirstWord(), lines: [], pInfo: pInfo))
            return true
        }

        if inActions, scoped.depth > 0 || inActions && allowContinuation {
            await item.appendLineToLastAction(DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo))
            return true
        }

        if text.hasSuffix(":"), !text.contains("=>") {
            await item.append(section: UIViewSection(name: String(text.dropLast()).trim(), controls: [], pInfo: pInfo))
            return true
        }

        if let slot = parseSlot(text, pInfo: pInfo) {
            await item.append(slot: slot)
            return true
        }

        let hasSlotContinuationTarget = allowContinuation ? await item.slots.isNotEmpty : false
        if scoped.depth > 0 || hasSlotContinuationTarget {
            await item.appendDirectiveToLastSlot(DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo))
            return true
        }

        if let binding = parseBinding(text, pInfo: pInfo) {
            await item.append(binding: binding)
            return true
        }

        return false
    }

    private static func parseSlot(_ text: String, pInfo: ParsedInfo) -> UIViewSlot? {
        guard text.hasPrefix("* "), text.contains("@\"") else { return nil }
        let rest = text.remainingLine(after: "*")
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let name = String(parts[0]).trim()
        guard let firstQuote = text.firstIndex(of: "\""), let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") else { return nil }
        let reference = String(text[text.index(after: firstQuote)..<secondQuote])
        return UIViewSlot(name: name, reference: reference, directives: [], pInfo: pInfo)
    }

    private static func parseBinding(_ text: String, pInfo: ParsedInfo) -> UIViewBinding? {
        let required: RequiredKind
        let rest: String
        if text.hasPrefix("* ") {
            required = .yes
            rest = text.remainingLine(after: "*")
        } else if text.hasPrefix("- ") || text.hasPrefix("_ ") {
            required = .no
            rest = String(text.dropFirst()).trim()
        } else if text.hasPrefix(". ") {
            required = .no
            rest = text.remainingLine(after: ".")
        } else if text.hasPrefix("+ ") {
            required = .no
            rest = text.remainingLine(after: "+")
        } else if text.hasPrefix("= ") {
            required = .no
            rest = text.remainingLine(after: "=")
        } else {
            return nil
        }

        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let name = parts.first.map { String($0).trim() } ?? rest.trim()
        let typeName = parts.count == 2 ? String(parts[1]).trim().nonEmpty : nil
        return UIViewBinding(name: name, typeName: typeName, required: required, pInfo: pInfo)
    }
}
