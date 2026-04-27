//
//  RulesParser.swift
//  ModelHike
//

import Foundation

public enum RulesParser {
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        if let nextFirstWord = await lineParser.nextLine().firstWord() {
            return nextFirstWord.hasOnly(ModelConstants.RulesUnderlineChar)
        }
        return false
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> RulesObject? {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return nil }
        try await pInfo.ctx.events.onParse(objectName: header.name, with: pInfo)

        let item = RulesObject(name: header.name, sourceLocation: SourceLocation(from: pInfo))
        await ExtendedDSLParserSupport.populateHeaderMetadata(for: item, header: header, pending: pending)
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

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "Rules")
            await parser.skipLine()
        }

        await validate(item)
        return item
    }

    private static func parseBodyLine(_ pInfo: ParsedInfo, into item: RulesObject, currentBlock: inout String?, allowContinuation: Bool) async -> Bool {
        let rawText = pInfo.line.trim()
        if rawText.hasPrefix("||") {
            await parseTableLine(rawText, pInfo: pInfo, into: item)
            return true
        }

        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        let text = scoped.text
        if text.isEmpty { return false }

        if text.hasPrefix("rule ") {
            currentBlock = "rule"
            await item.append(rule: ConditionalRule(name: text.remainingLine(after: "rule"), whenClauses: [], thenClauses: [], pInfo: pInfo))
            return true
        }

        if text.hasPrefix("score ") {
            currentBlock = "score"
            await item.append(score: ScoreRule(name: text.remainingLine(after: "score"), clauses: [], pInfo: pInfo))
            return true
        }

        if text.hasPrefix("classify ") {
            currentBlock = "classify"
            await item.append(classification: ClassificationRule(outputName: text.remainingLine(after: "classify"), clauses: [], pInfo: pInfo))
            return true
        }

        if text == "filter" {
            currentBlock = "filter"
            return true
        }

        if text == "rank" {
            currentBlock = "rank"
            return true
        }

        if text.hasPrefix("limit:") {
            await item.setLimit(text.remainingLine(after: "limit:"))
            return true
        }

        if text.hasPrefix("constraint ") {
            currentBlock = "constraint"
            await item.append(constraint: ConstraintRule(name: text.remainingLine(after: "constraint"), whenClauses: [], rejectClauses: [], pInfo: pInfo))
            return true
        }

        if text.hasPrefix("decide @\"") {
            guard let call = parseCompositionCall(text, pInfo: pInfo) else { return false }
            await item.append(compositionCall: call)
            return true
        }

        if text.hasPrefix("=") {
            currentBlock = "formula"
            await item.append(formula: parseFormula(text, pInfo: pInfo))
            return true
        }

        if isDecisionTreeLine(text) {
            await item.append(treeNode: parseTreeNode(text, pInfo: pInfo))
            return true
        }

        if scoped.depth > 0 || text.hasPrefix("|>") || text == "end" || allowContinuation && currentBlock != nil {
            let line = DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo)
            switch currentBlock {
            case "rule": await item.appendLineToLastConditional(line)
            case "score": await item.appendLineToLastScore(line)
            case "classify": await item.appendLineToLastClassification(line)
            case "filter": await item.appendFilterClause(line)
            case "rank": await item.appendRankClause(line)
            case "formula": await item.appendLineToLastFormula(line)
            case "constraint": await item.appendLineToLastConstraint(line)
            default: await item.append(assignment: line)
            }
            return true
        }

        if text.contains("=") {
            await item.append(assignment: DSLBodyLine(text: text, depth: scoped.depth, pInfo: pInfo))
            return true
        }

        return false
    }

    private static func parseTableLine(_ text: String, pInfo: ParsedInfo, into item: RulesObject) async {
        var sides: [String] = []
        for side in Self.split(text, by: "||") {
            let trimmed = side.trim()
            if trimmed.isNotEmpty { sides.append(trimmed) }
        }
        guard sides.count == 2 else {
            await ExtendedDSLParserSupport.warnUnrecognized(pInfo, in: "Rules decision table")
            return
        }
        let left = parseTableCells(sides[0])
        let right = parseTableCells(sides[1])
        let allCells = left + right
        let isSeparator = allCells.allSatisfy { $0.replacingOccurrences(of: "-", with: "").trim().isEmpty }
        if isSeparator { return }

        let table = await item.decisionTable
        if table.inputColumns.isEmpty && table.outputColumns.isEmpty {
            await item.appendTableHeader(inputColumns: left, outputColumns: right)
        } else {
            let expected = table.inputColumns.count + table.outputColumns.count
            if allCells.count != expected {
                await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Decision table row has \(allCells.count) cells but expected \(expected)", pInfo: pInfo)
            }
            await item.append(tableRow: DecisionTableRow(cells: allCells, pInfo: pInfo))
        }
    }

    private static func parseTableCells(_ text: String) -> [String] {
        text.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trim() }.filter(\.isNotEmpty)
    }

    private static func isDecisionTreeLine(_ text: String) -> Bool {
        text.hasPrefix("├──") || text.hasPrefix("└──") || text.hasPrefix("+--") || text.hasPrefix("\\--")
    }

    private static func parseTreeNode(_ text: String, pInfo: ParsedInfo) -> DecisionTreeNode {
        let trimmed = text.trim()
        let isCondition = trimmed.contains("[")
        let depth = trimmed.prefix { $0 == "│" || $0 == " " || $0 == "|" }.count / 4
        let normalized = trimmed
            .replacingOccurrences(of: "├──", with: "")
            .replacingOccurrences(of: "└──", with: "")
            .replacingOccurrences(of: "+--", with: "")
            .replacingOccurrences(of: "\\--", with: "")
            .replacingOccurrences(of: "[", with: "")
            .trim()
        return DecisionTreeNode(conditionOrAction: normalized, isCondition: isCondition, depth: depth, pInfo: pInfo)
    }

    private static func parseFormula(_ text: String, pInfo: ParsedInfo) -> FormulaRule {
        let remainder = text.remainingLine(after: "=")
        let parts = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            return FormulaRule(name: String(parts[0]).trim(), typeName: String(parts[1]).trim(), clauses: [], pInfo: pInfo)
        }
        return FormulaRule(name: remainder.trim(), typeName: nil, clauses: [], pInfo: pInfo)
    }

    private static func parseCompositionCall(_ text: String, pInfo: ParsedInfo) -> RuleCompositionCall? {
        guard let firstQuote = text.firstIndex(of: "\"") else { return nil }
        guard let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") else { return nil }
        let target = String(text[text.index(after: firstQuote)..<secondQuote])
        let afterTarget = String(text[text.index(after: secondQuote)...]).trim()
        let resultParts = Self.split(afterTarget, by: "->")
        let args = (resultParts.first ?? "").replacingOccurrences(of: "with", with: "").trim().nonEmpty
        let result = resultParts.count >= 2 ? resultParts[1].trim().nonEmpty : nil
        return RuleCompositionCall(target: target, arguments: args, result: result, pInfo: pInfo)
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

    private static func validate(_ item: RulesObject) async {
        let inputs = await item.inputs
        let outputs = await item.outputs
        let pInfo = await item.directives.first?.pInfo
        if inputs.isEmpty, let pInfo {
            await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Rules block has no @ input:: directive", pInfo: pInfo)
        }
        if outputs.isEmpty, let pInfo {
            await pInfo.ctx.debugLog.recordDiagnostic(.warning, code: .w620, "Rules block has no @ output:: directive", pInfo: pInfo)
        }
    }
}
