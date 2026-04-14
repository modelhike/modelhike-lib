//
//  VirtualGroupParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//
//  Parses a virtual-group block inside a system body:
//
//      +--- Infrastructure #tier=data -- Core data tier      ← opening fence
//      |                                                      ← empty body line
//      | + Payments Service                                   ← container ref
//      |                                                      ← empty body line
//      | PostgreSQL [database]                                ← infra node
//      | +++++++++++++++++++++
//      | host = db.internal
//      |
//      | +--- Cache Layer                                     ← nested group
//      | | Redis [cache]
//      | | +++++++++++++++
//      | | host = redis.internal
//      | +---                                                 ← nested close
//      |
//      +---                                                   ← closing fence
//
//  Opening fence: `+---` followed by one or more non-whitespace characters (the name).
//  Closing fence: `+---` followed by nothing (or only whitespace).
//  Body lines:    any line whose trimmed form starts with `|`.
//
//  When parsing the body, the leading `|` (and one optional space) is stripped and
//  the remaining content is interpreted exactly as a system body line — container
//  refs, infra nodes, and nested virtual groups.  Nesting works because a stripped
//  body line that starts with `+---` is itself a group opener, and a stripped
//  `| item` becomes `item` for the inner group's body.
//

import Foundation

public enum VirtualGroupParser {

    // MARK: - Fence helpers

    /// `+--- Group Name` — has non-empty content after the fence token.
    public static func isOpeningFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(ModelConstants.VirtualGroupFence) else { return false }
        let rest = trimmed.dropFirst(ModelConstants.VirtualGroupFence.count)
            .trimmingCharacters(in: .whitespaces)
        return rest.isNotEmpty
    }

    /// `+---` alone — nothing after the fence token.
    public static func isClosingFence(_ line: String) -> Bool {
        return line.trimmingCharacters(in: .whitespaces) == ModelConstants.VirtualGroupFence
    }

    // MARK: - canParse

    /// Returns `true` when the current parser line is a virtual-group opening fence.
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        return isOpeningFence(await lineParser.currentLine())
    }

    // MARK: - parse

    /// Parses the full virtual-group block (opening fence + body + closing fence).
    /// The parser must be positioned on the opening `+--- Name` line on entry.
    /// On return the parser is positioned on the first line after the closing `+---`
    /// (or at EOF if no closing fence was found).
    public static func parse(parser: LineParser, with ctx: LoadContext) async throws -> VirtualGroup? {
        let openingLine = await parser.currentLine()
        let afterFence = String(
            openingLine.trimmingCharacters(in: .whitespaces)
                .dropFirst(ModelConstants.VirtualGroupFence.count)
        ).trimmingCharacters(in: .whitespaces)

        var headerLine = afterFence
        let inlineDesc = ParserUtil.extractInlineDescription(from: &headerLine)

        // Extract name + optional tags from the header segment.
        let groupName: String
        let tags: [Tag]
        let technical: [TechnicalImplication]
        if let match = headerLine.wholeMatch(of: ModelRegEx.containerName_Capturing) {
            let (_, name, _, techStr, tagStr) = match.output
            groupName = name
            technical = techStr.map { ParserUtil.technicalImplicationNotes(from: $0) } ?? []
            tags = tagStr.map { ParserUtil.parseTags(from: $0) } ?? []
        } else {
            // Fallback for names that fail the standard regex (e.g. digit-first names).
            let (n, tagStr) = ParserUtil.extractNameAndTagString(from: headerLine)
            groupName = n
            technical = []
            tags = tagStr.map { ParserUtil.parseTags(from: $0) } ?? []
        }

        guard groupName.isNotEmpty else { return nil }

        var group = VirtualGroup(givenname: groupName, description: inlineDesc, tags: tags, technicalImplications: technical)
        await parser.skipLine() // consume the opening fence line

        // Collect body lines (each must start with `|`) until the closing `+---`.
        var bodyLines: [String] = []
        while await parser.linesRemaining {
            let raw = await parser.currentLine()
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if isClosingFence(trimmed) {
                await parser.skipLine()
                break
            }

            guard trimmed.hasPrefix(ModelConstants.VirtualGroupBodyPrefix) else {
                // Malformed — a non-`|` line that is not the closing fence.
                ctx.debugLog.recordDiagnostic(
                    .warning,
                    code: .w621,
                    "Virtual group '\(group.givenname)': unexpected line '\(trimmed)' — expected a '|' body line or '+---' closing fence.",
                    source: SourceLocation(fileIdentifier: await parser.identifier, lineNo: await parser.curLineNoForDisplay, lineContent: trimmed)
                )
                break
            }

            // Strip `| ` or bare `|`.
            let stripped = trimmed.hasPrefix("| ")
                ? String(trimmed.dropFirst(2))
                : String(trimmed.dropFirst(1))
            bodyLines.append(stripped)
            await parser.skipLine()
        }

        // Parse the stripped body lines with a sub-parser using the same body logic.
        let subParser = LineParserDuringLoad(
            lines: bodyLines,
            identifier: "\(await parser.identifier)/group-\(group.name)",
            isStatementsPrefixedWithKeyword: true,
            with: ctx,
            autoIncrementLineNoForEveryLoop: false
        )
        try await parseGroupBody(parser: subParser, into: &group, with: ctx)

        return group
    }

    // MARK: - Body parsing

    /// Parses the stripped body lines of a virtual group, populating container refs,
    /// infra nodes, and nested sub-groups.  Uses the same logic as `SystemParser`'s
    /// body loop so that all element types work identically inside groups.
    private static func parseGroupBody(parser: LineParser, into group: inout VirtualGroup, with ctx: LoadContext) async throws {
        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() { await parser.skipLine(); continue }

            let trimmed = await parser.currentLine()

            // Nested virtual group.
            if isOpeningFence(trimmed) {
                if let nested = try await parse(parser: parser, with: ctx) {
                    group.appendSubGroup(nested)
                }
                continue
            }

            guard let pInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }

            // Container reference: `+ Name`
            if pInfo.firstWord == ModelConstants.Container_Member {
                let rest = pInfo.line
                    .remainingLine(after: ModelConstants.Container_Member)
                    .trimmingCharacters(in: .whitespaces)
                if rest.isNotEmpty {
                    group.appendRef(rest)
                }
                await parser.skipLine()
                continue
            }

            // Infra node: setext `++++` header.
            if await InfraNodeParser.canParse(parser: parser) {
                if let node = await InfraNodeParser.parse(parser: parser) {
                    group.appendInfraNode(node)
                } else {
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: .w620,
                        "Infra node header '\(pInfo.line.trim())' inside group '\(group.givenname)' could not be parsed.",
                        pInfo: pInfo
                    )
                    await parser.skipLine()
                }
                continue
            }

            // Unrecognised line — skip silently.
            await parser.skipLine()
        }
    }
}
