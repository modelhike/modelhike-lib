//
//  ExtendedDSLCommon.swift
//  ModelHike
//

import Foundation

public struct DSLDirective: Sendable {
    public let name: String
    public let value: String
    public let pInfo: ParsedInfo

    public init(name: String, value: String, pInfo: ParsedInfo) {
        self.name = name.trim()
        self.value = value.trim()
        self.pInfo = pInfo
    }
}

public struct DSLBodyLine: Sendable {
    public let text: String
    public let depth: Int
    public let pInfo: ParsedInfo

    public init(text: String, depth: Int, pInfo: ParsedInfo) {
        self.text = text
        self.depth = depth
        self.pInfo = pInfo
    }
}

public struct ExtendedDSLHeader: Sendable {
    public let name: String
    public let attributeString: String?
    public let technicalString: String?
    public let tagString: String?
    public let inlineDescription: String?
}

public enum ExtendedDSLParserSupport {
    public static func parseHeader(from line: String) -> ExtendedDSLHeader? {
        var headerLine = line
        let inlineDescription = ParserUtil.extractInlineDescription(from: &headerLine)
        guard let match = headerLine.wholeMatch(of: ModelRegEx.className_Capturing) else { return nil }
        let (_, name, attributeString, technicalString, tagString) = match.output
        return ExtendedDSLHeader(
            name: name.trim(),
            attributeString: attributeString,
            technicalString: technicalString,
            tagString: tagString,
            inlineDescription: inlineDescription
        )
    }

    public static func populateHeaderMetadata(for item: any HasAttributes_Actor & HasTags_Actor & HasTechnicalImplications_Actor & HasDescription_Actor, header: ExtendedDSLHeader, pending: ParserUtil.PendingMetadata?) async {
        await ParserUtil.appendDescription(pending?.description, to: item)
        await ParserUtil.appendDescription(header.inlineDescription, to: item)
        if let attributeString = header.attributeString {
            await ParserUtil.populateAttributes(for: item, from: attributeString)
        }
        if let technicalString = header.technicalString {
            await ParserUtil.populateTechnicalImplications(for: item, from: technicalString)
        }
        if let tagString = header.tagString {
            await ParserUtil.populateTags(for: item, from: tagString)
        }
    }

    public static func isKnownTopLevelStart(parser: LineParser) async -> Bool {
        if await ContainerParser.canParse(parser: parser) { return true }
        if await ModuleParser.canParse(parser: parser) { return true }
        if await SubModuleParser.canParse(parser: parser) { return true }
        if await DomainObjectParser.canParse(parser: parser) { return true }
        if await DtoObjectParser.canParse(parser: parser) { return true }
        if await UIViewParser.canParse(parser: parser) { return true }
        if await FlowParser.canParse(parser: parser) { return true }
        if await RulesParser.canParse(parser: parser) { return true }
        if await PrintableParser.canParse(parser: parser) { return true }
        if await ConfigParser.canParse(parser: parser) { return true }
        return false
    }

    public static func parseDirectiveLine(_ line: String, pInfo: ParsedInfo) -> DSLDirective? {
        let trimmed = line.trim()
        guard trimmed.hasPrefix(ModelConstants.Annotation_Start) else { return nil }
        let remainder = trimmed.dropFirst().trim()
        let parts = remainder.split(separator: ModelConstants.Annotation_Split, maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return DSLDirective(name: String(parts[0]), value: String(parts[1]), pInfo: pInfo)
    }

    public static func scopeDepthAndText(_ line: String) -> (depth: Int, text: String) {
        let trimmed = line.trim()
        var depth = 0
        var remaining = trimmed
        while remaining.hasPrefix(ModelConstants.VirtualGroupBodyPrefix) {
            depth += 1
            remaining = String(remaining.dropFirst()).trim()
        }
        return (depth, remaining)
    }

    public static func splitCommaList(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: true).map { String($0).trim() }.filter(\.isNotEmpty)
    }

    public static func warnUnrecognized(_ pInfo: ParsedInfo, in block: String) async {
        await pInfo.ctx.debugLog.recordDiagnostic(
            .warning,
            code: .w620,
            "Unrecognized line in \(block): \(pInfo.line)",
            pInfo: pInfo
        )
    }
}
