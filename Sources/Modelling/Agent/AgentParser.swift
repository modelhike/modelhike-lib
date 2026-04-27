//
//  AgentParser.swift
//  ModelHike
//

import Foundation

public enum AgentParser {
    public static func canParseModule(parser lineParser: LineParser) async -> Bool {
        guard await ModuleParser.canParse(parser: lineParser) else { return false }
        let line = await lineParser.currentLine()
        let underline = await lineParser.nextLine()
        return headerHasAttribute("agent", line: line) && underline.hasOnly(ModelConstants.AgentUnderlineChar)
    }

    public static func canParseSubAgent(parser lineParser: LineParser) async -> Bool {
        guard await SubModuleParser.canParse(parser: lineParser) else { return false }
        let line = await lineParser.currentLine()
        let underline = await lineParser.nextLine()
        return headerHasAttribute("sub-agent", line: line) && underline.hasOnly(ModelConstants.AgentUnderlineChar)
    }

    public static func parseModule(parser: LineParser, with ctx: LoadContext, pending: ParserUtil.PendingMetadata? = nil, kind: AgentComponentKind) async throws -> C4Component? {
        let headerLine = await parser.currentLine()
        let module = kind == .agent
            ? try await ModuleParser.parse(parser: parser, with: ctx, pending: pending)
            : try await SubModuleParser.parse(parser: parser, with: ctx, pending: pending)
        guard let module else { return nil }
        let header = parseHeader(fromAgentFenceLine: headerLine)
        let agent = AgentObject(name: header?.name ?? module.givenname, componentKind: kind)
        if let header {
            await ExtendedDSLParserSupport.populateHeaderMetadata(for: agent, header: header, pending: pending)
        }
        await module.appendAttached(agent)
        await parser.skipLine()
        return module
    }

    public static func isAgentComponent(_ component: C4Component) async -> Bool {
        await agentObject(in: component) != nil
    }

    public static func agentObject(in component: C4Component) async -> AgentObject? {
        for attached in await component.attached {
            if let agent = attached as? AgentObject {
                return agent
            }
        }
        return nil
    }

    public static func canParsePrompt(parser lineParser: LineParser) async -> Bool {
        (await lineParser.currentLine()).trim().hasPrefix("```system-prompt")
    }

    public static func parsePrompt(parser: LineParser, with pInfo: ParsedInfo, into agent: AgentObject) async throws {
        let opening = pInfo.line.trim()
        let condition = opening.remainingLine(after: "```system-prompt").trim().nonEmpty
        await parser.skipLine()
        var body: [String] = []
        while await parser.linesRemaining {
            let line = await parser.currentLine()
            if line.trim() == "```" {
                await parser.skipLine()
                await agent.append(prompt: AgentPrompt(kind: "system-prompt", condition: condition, body: body, pInfo: pInfo))
                return
            }
            body.append(line)
            await parser.skipLine()
        }
        throw Model_ParsingError.invalidAgentLine(pInfo)
    }

    public static func canParseTool(parser lineParser: LineParser) async -> Bool {
        guard await DomainObjectParser.canParse(parser: lineParser) else { return false }
        let header = await lineParser.currentLine()
        return !(header.contains("(knowledge"))
    }

    public static func parseTool(parser: LineParser, with pInfo: ParsedInfo, into agent: AgentObject, pending: ParserUtil.PendingMetadataBlock? = nil) async throws -> Bool {
        guard let header = ExtendedDSLParserSupport.parseHeader(from: await parser.currentLine()) else { return false }
        let kind = resourceKind(from: header.attributeString)
        var tool = AgentTool(name: header.name, resourceKind: kind, descriptionLines: [], method: nil, directives: [], prompts: [], delegations: [], pInfo: pInfo)
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
            let trimmed = lineInfo.line.trim()

            if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                tool.descriptionLines.append(trimmed.remainingLine(after: ModelConstants.Member_Description).trim())
                await parser.skipLine()
                continue
            }
            if let directive = ExtendedDSLParserSupport.parseDirectiveLine(trimmed, pInfo: lineInfo) {
                tool.directives.append(directive)
                await parser.skipLine()
                continue
            }
            if trimmed.hasPrefix("```skill-prompt") || trimmed.hasPrefix("```prompt") {
                tool.prompts.append(try await parseInlinePrompt(parser: parser, pInfo: lineInfo))
                continue
            }
            let scoped = ExtendedDSLParserSupport.scopeDepthAndText(trimmed)
            if scoped.depth > 0, let delegation = parseDelegation(scoped.text, pInfo: lineInfo) {
                tool.delegations.append(delegation)
                await parser.skipLine()
                continue
            }
            if lineInfo.firstWord == ModelConstants.AttachedSection {
                break
            }
            if await MethodObject.canParse(parser: parser) {
                let methodPending = pending?.isEmpty == false ? pending : nil
                tool.method = try await MethodObject.parse(pInfo: lineInfo, pendingMetadataBlock: methodPending)
                continue
            }
            let isKnownTopLevelStart = await ExtendedDSLParserSupport.isKnownTopLevelStart(parser: parser)
            let isPromptStart = await canParsePrompt(parser: parser)
            if isKnownTopLevelStart || isPromptStart {
                break
            }
            if await DomainObjectParser.canParse(parser: parser) {
                break
            }

            await ExtendedDSLParserSupport.warnUnrecognized(lineInfo, in: "Agent")
            await parser.skipLine()
        }

        await agent.append(tool: tool)
        return true
    }

    public static func parseAgentSection(parser: LineParser, with pInfo: ParsedInfo, into agent: AgentObject) async throws -> Bool {
        guard pInfo.firstWord == ModelConstants.AttachedSection else { return false }
        let sectionName = pInfo.line.dropFirstWord().trim()
        guard ["slash commands", "guardrails"].contains(sectionName.lowercased()) else { return false }
        await parser.skipLine()
        var lines: [DSLBodyLine] = []
        while await parser.linesRemaining {
            guard let lineInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }
            if lineInfo.firstWord == ModelConstants.AttachedSection {
                if lineInfo.line.secondWord() == nil {
                    await parser.skipLine()
                }
                break
            }
            let scoped = ExtendedDSLParserSupport.scopeDepthAndText(lineInfo.line)
            lines.append(DSLBodyLine(text: scoped.text, depth: scoped.depth, pInfo: lineInfo))
            await parser.skipLine()
        }
        await agent.append(section: AgentSection(name: sectionName, lines: lines, pInfo: pInfo))
        return true
    }

    public static func parseDelegation(_ text: String, pInfo: ParsedInfo) -> AgentDelegation? {
        let keyword = text.firstWord() ?? ""
        guard ["decide", "run", "source", "mcp", "invoke"].contains(keyword) else { return nil }
        var target: String?
        if let firstQuote = text.firstIndex(of: "\""), let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") {
            target = String(text[text.index(after: firstQuote)..<secondQuote])
        }
        let resultParts = split(text, by: "->")
        let result = resultParts.count >= 2 ? resultParts[1].trim().nonEmpty : nil
        let beforeResult = resultParts.first ?? text
        let args = beforeResult.contains("with") ? beforeResult.remainingLine(after: "with").trim().nonEmpty : nil
        return AgentDelegation(keyword: keyword, target: target, arguments: args, result: result, raw: text, pInfo: pInfo)
    }

    private static func parseHeader(fromAgentFenceLine line: String) -> ExtendedDSLHeader? {
        var innerLine = line.dropFirstAndLastWords()
        let inlineDescription = ParserUtil.extractInlineDescription(from: &innerLine)
        guard let match = innerLine.wholeMatch(of: ModelRegEx.moduleName_Capturing) else { return nil }
        let (_, name, attributeString, technicalString, tagString) = match.output
        return ExtendedDSLHeader(name: name.trim(), attributeString: attributeString, technicalString: technicalString, tagString: tagString, inlineDescription: inlineDescription)
    }

    private static func headerHasAttribute(_ attribute: String, line: String) -> Bool {
        guard let header = parseHeader(fromAgentFenceLine: line), let attributeString = header.attributeString else { return false }
        return ExtendedDSLParserSupport.splitCommaList(attributeString).contains(attribute)
    }

    private static func resourceKind(from attributeString: String?) -> AgentResourceKind {
        let attrs = attributeString.map(ExtendedDSLParserSupport.splitCommaList) ?? []
        if attrs.contains("skill") { return .skill }
        if attrs.contains("mcp-server") { return .mcpServer }
        return .tool
    }

    private static func parseInlinePrompt(parser: LineParser, pInfo: ParsedInfo) async throws -> AgentPrompt {
        let opening = pInfo.line.trim()
        let kind = opening.firstWord()?.removingPrefix("```") ?? "prompt"
        let condition = opening.dropFirstWord().trim().nonEmpty
        await parser.skipLine()
        var body: [String] = []
        while await parser.linesRemaining {
            let line = await parser.currentLine()
            if line.trim() == "```" {
                await parser.skipLine()
                return AgentPrompt(kind: kind, condition: condition, body: body, pInfo: pInfo)
            }
            body.append(line)
            await parser.skipLine()
        }
        throw Model_ParsingError.invalidAgentLine(pInfo)
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
}
