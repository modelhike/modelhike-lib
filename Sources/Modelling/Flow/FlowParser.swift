//
//  FlowParser.swift
//  ModelHike
//

import Foundation

public enum FlowParser {
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        if let nextFirstWord = await lineParser.nextLine().firstWord() {
            return nextFirstWord.hasOnly(ModelConstants.FlowUnderlineChar)
        }
        return false
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> FlowObject? {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return nil }
        try await pInfo.ctx.events.onParse(objectName: header.name, with: pInfo)

        let item = FlowObject(name: header.name, sourceLocation: SourceLocation(from: pInfo))
        await ExtendedDSLParserSupport.populateHeaderMetadata(for: item, header: header, pending: pending)
        await parser.skipLine(by: 2)

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
            if await parseBodyLine(lineInfo, into: item, allowContinuation: !isTopLevelStart) {
                await parser.skipLine()
                continue
            }

            if isTopLevelStart { break }

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "Flow")
            await parser.skipLine()
        }

        await item.finalizeMode()
        await validate(item, pInfo: pInfo)
        return item
    }

    private static func parseBodyLine(_ pInfo: ParsedInfo, into item: FlowObject, allowContinuation: Bool) async -> Bool {
        let rawText = pInfo.line.trim()
        if rawText.hasPrefix("|> IF") || rawText.hasPrefix("|> ELSEIF") || rawText.hasPrefix("|> ELSE") {
            await item.append(branch: parseBranch(rawText, depth: 0, pInfo: pInfo))
            return true
        }

        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        let text = scoped.text
        if text.isEmpty { return false }

        if text.hasPrefix("state ") {
            await item.append(state: FlowState(name: text.remainingLine(after: "state").trim(), actions: [], isTerminal: false, pInfo: pInfo))
            return true
        }

        if text.hasPrefix("\\__ ") || text.hasPrefix("[*] ") || text.contains(" --> [*]") {
            guard let transition = parseTransition(text, pInfo: pInfo) else { return false }
            await item.append(transition: transition)
            return true
        }

        if let participant = parseParticipant(text, pInfo: pInfo) {
            await item.append(participant: participant)
            return true
        }

        if let message = parseMessage(text, pInfo: pInfo) {
            await item.append(message: message)
            return true
        }

        if let wait = parseWait(text, pInfo: pInfo) {
            await item.append(wait: wait)
            return true
        }

        if let call = parseCall(text, pInfo: pInfo) {
            await item.append(call: call)
            return true
        }

        if text.hasPrefix("return ") {
            await item.append(returnLine: DSLBodyLine(text: text.remainingLine(after: "return"), depth: scoped.depth, pInfo: pInfo))
            return true
        }

        if text.hasPrefix("==>") {
            await item.append(step: FlowStep(title: text.remainingLine(after: "==>"), pInfo: pInfo))
            return true
        }

        if text.hasPrefix("---") {
            await item.append(parallelRegion: FlowParallelRegion(name: parseParallelRegionName(text), actions: [], pInfo: pInfo))
            return true
        }

        if text.hasPrefix("|> IF") || text.hasPrefix("|> ELSEIF") || text.hasPrefix("|> ELSE") || text == "end" {
            await item.append(branch: parseBranch(text, depth: scoped.depth, pInfo: pInfo))
            return true
        }

        let hasContinuationTarget = allowContinuation ? await hasContinuationTarget(in: item) : false
        if scoped.depth > 0 || hasContinuationTarget {
            let action = FlowAction(text: text, depth: scoped.depth, pInfo: pInfo)
            await item.appendDirectiveToLastWait(DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo))
            await item.appendActionToLastState(action)
            await item.appendActionToLastTransition(action)
            await item.appendActionToLastParallelRegion(action)
            return true
        }

        return false
    }

    private static func hasContinuationTarget(in item: FlowObject) async -> Bool {
        if await item.states.isNotEmpty { return true }
        if await item.transitions.isNotEmpty { return true }
        if await item.waits.isNotEmpty { return true }
        if await item.parallelRegions.isNotEmpty { return true }
        return false
    }

    private static func parseParticipant(_ text: String, pInfo: ParsedInfo) -> FlowParticipant? {
        guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return nil }
        let name = String(text[text.index(after: text.startIndex)..<close]).trim()
        let after = String(text[text.index(after: close)...]).trim()
        guard after.hasPrefix("as ") else { return nil }
        return FlowParticipant(name: name, kind: after.remainingLine(after: "as"), pInfo: pInfo)
    }

    private static func parseTransition(_ text: String, pInfo: ParsedInfo) -> FlowTransition? {
        var working = text.hasPrefix("\\__") ? text.remainingLine(after: "\\__") : text
        let guardExpression = extractBalanced(from: &working, open: "{", close: "}")
        let eventSplit = working.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let route = eventSplit.first.map { String($0).trim() } ?? ""
        var eventText = eventSplit.count == 2 ? String(eventSplit[1]).trim() : ""
        let roles = extractBalanced(from: &eventText, open: "[", close: "]").map(ExtendedDSLParserSupport.splitCommaList) ?? []
        let event = eventText.trim().nonEmpty
        let arrowSplit = Self.split(route, by: "->")
        guard arrowSplit.count >= 2 else { return nil }
        return FlowTransition(
            from: arrowSplit[0].trim(),
            to: arrowSplit[1].trim(),
            event: event,
            guardExpression: guardExpression,
            roles: roles,
            actions: [],
            pInfo: pInfo
        )
    }

    private static func parseMessage(_ text: String, pInfo: ParsedInfo) -> FlowMessage? {
        for arrow in [FlowMessageArrow.async, .sync, .response] {
            guard let range = text.range(of: arrow.rawValue) else { continue }
            let from = String(text[..<range.lowerBound]).trim()
            let afterArrow = String(text[range.upperBound...]).trim()
            let parts = afterArrow.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            return FlowMessage(from: from, to: String(parts[0]).trim(), arrow: arrow, call: String(parts[1]).trim(), pInfo: pInfo)
        }
        return nil
    }

    private static func parseWait(_ text: String, pInfo: ParsedInfo) -> FlowWait? {
        guard text.hasPrefix("wait ") else { return nil }
        let remainder = text.remainingLine(after: "wait")
        let resultSplit = Self.split(remainder, by: "->")
        let lhs = resultSplit.first?.trim() ?? ""
        let result = resultSplit.count >= 2 ? resultSplit[1].trim().nonEmpty : nil
        let parts = lhs.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return FlowWait(participant: String(parts[0]).trim(), task: String(parts[1]).trim(), result: result, directives: [], pInfo: pInfo)
    }

    private static func parseCall(_ text: String, pInfo: ParsedInfo) -> FlowCall? {
        guard text.hasPrefix("run @\"") || text.hasPrefix("decide @\"") || text.hasPrefix("generate @\"") else { return nil }
        let kind = text.firstWord() ?? ""
        guard let firstQuote = text.firstIndex(of: "\"") else { return nil }
        guard let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") else { return nil }
        let target = String(text[text.index(after: firstQuote)..<secondQuote])
        let afterTarget = String(text[text.index(after: secondQuote)...]).trim()
        let resultParts = Self.split(afterTarget, by: "->")
        let args = (resultParts.first ?? "").replacingOccurrences(of: "with", with: "").trim().nonEmpty
        let result = resultParts.count >= 2 ? resultParts[1].trim().nonEmpty : nil
        return FlowCall(kind: kind, target: target, arguments: args, result: result, pInfo: pInfo)
    }

    private static func parseParallelRegionName(_ text: String) -> String? {
        let trimmed = text.trim()
        guard trimmed != "---" else { return nil }
        return trimmed.replacingOccurrences(of: "---", with: "").trim().nonEmpty
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

    private static func parseBranch(_ text: String, depth: Int, pInfo: ParsedInfo) -> FlowBranch {
        if text == "end" { return FlowBranch(keyword: "end", condition: nil, depth: depth, pInfo: pInfo) }
        let keyword = text.hasPrefix("|> ELSEIF") ? "elseif" : text.hasPrefix("|> ELSE") ? "else" : "if"
        let condition = text.replacingOccurrences(of: "|> ELSEIF", with: "")
            .replacingOccurrences(of: "|> IF", with: "")
            .replacingOccurrences(of: "|> ELSE", with: "")
            .trim()
            .nonEmpty
        return FlowBranch(keyword: keyword, condition: condition, depth: depth, pInfo: pInfo)
    }

    private static func extractBalanced(from text: inout String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open), let end = text[start...].firstIndex(of: close), end > start else { return nil }
        let value = String(text[text.index(after: start)..<end]).trim()
        text.removeSubrange(start...end)
        return value
    }

    private static func validate(_ item: FlowObject, pInfo: ParsedInfo) async {
        let states = await item.states.map(\.name)
        let transitions = await item.transitions
        if states.isNotEmpty {
            var hasInitial = false
            for transition in transitions {
                if transition.from == "[*]" {
                    hasInitial = true
                    break
                }
            }
            if !hasInitial {
                await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Flow has states but no initial [*] transition", pInfo: pInfo)
            }
            let known = Set(states + ["CURRENT", "self", "[*]", "history", "[H]", "[H*]"])
            for transition in transitions {
                if !known.contains(transition.from) {
                    await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Transition references unknown source state '\(transition.from)'", pInfo: transition.pInfo)
                }
                if !known.contains(transition.to) {
                    await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Transition references unknown target state '\(transition.to)'", pInfo: transition.pInfo)
                }
            }
        }
    }
}
