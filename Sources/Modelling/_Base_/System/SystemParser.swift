//
//  SystemParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//
//  Parses the system-level fence block:
//
//      * * * * * * * * * * * * * * * * * * *    ← opening title fence
//      My System Name (attributes) #tags
//      * * * * * * * * * * * * * * * * * * *    ← closing title fence / body starts here
//
//      + Container A                             ← container reference (resolved during load)
//      + Container B
//
//      PostgreSQL [database] #primary-db         ← infra node (setext header)
//      +++++++++++++++++++++++++++++++++
//      host = db.internal
//      port = 5432
//
//      +--- Infrastructure                       ← virtual group opening fence
//      |                                         ← body line (empty)
//      | + Auth Service                          ← container ref inside group
//      | Redis [cache]                           ← infra node inside group
//      | +++++++++++++++
//      | host = redis.internal
//      | +--- Nested Group                       ← nested virtual group
//      | | + Billing Service
//      | +---                                    ← nested group close
//      +---                                      ← virtual group closing fence
//
//      * * * * * * * * * * * * * * * * * * *    ← end of system body (consumed)
//

import Foundation

public enum SystemParser {

    // MARK: - Fence detection

    /// Returns `true` when `line` is a valid system fence — three or more space-separated
    /// `*` characters on an otherwise empty line, e.g. `* * * * *`.
    public static func isAsterismLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isNotEmpty else { return false }
        let parts = trimmed.components(separatedBy: " ")
        guard parts.count >= ModelConstants.SystemFenceMinCount else { return false }
        return parts.allSatisfy { $0 == ModelConstants.SystemFenceChar }
    }

    // MARK: - canParse

    /// Returns `true` when the current line is an asterism fence and two lines ahead is
    /// also an asterism fence — confirming the three-line system header is present.
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        let currentLine = await lineParser.currentLine()
        guard isAsterismLine(currentLine) else { return false }
        let nameCandidate = await lineParser.lookAheadLine(by: 1)
        let trimmedName = nameCandidate.trimmingCharacters(in: .whitespaces)
        guard trimmedName.isNotEmpty else { return false }
        guard !isAsterismLine(trimmedName) else { return false }  // name line must not itself be a fence
        let closingFence = await lineParser.lookAheadLine(by: 2)
        return isAsterismLine(closingFence)
    }

    // MARK: - parse

    /// Parses a system block and returns the populated `C4System`.
    ///
    /// Expects the parser positioned on the opening asterism line.
    /// Reads the body — `+` container references and infra-node blocks — until the
    /// closing body asterism (or end of file). The closing asterism is consumed.
    public static func parse(
        parser: LineParser, with ctx: LoadContext, pending: ParserUtil.PendingMetadata? = nil
    ) async throws -> C4System? {
        await parser.skipLine()  // skip opening asterism

        var nameLine = await parser.currentLine()
        let inlineDesc = ParserUtil.extractInlineDescription(from: &nameLine)

        guard let match = nameLine.wholeMatch(of: ModelRegEx.containerName_Capturing) else {
            return nil
        }

        let (_, systemName, attributeString, tagString) = match.output
        let item = await C4System(name: systemName)

        await ParserUtil.appendDescription(pending?.description, to: item)
        await ParserUtil.appendDescription(inlineDesc, to: item)
        if let attributeString {
            await ParserUtil.populateAttributes(for: item, from: attributeString)
        }
        if let tagString {
            await ParserUtil.populateTags(for: item, from: tagString)
        }

        await parser.skipLine()  // skip system name line
        await parser.skipLine()  // skip closing title asterism

        // Read the system body until the closing body asterism or end of file.
        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() {
                await parser.skipLine()
                continue
            }

            let currentLine = await parser.currentLine()
            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

            // Closing body asterism — consume it and stop.
            if isAsterismLine(trimmed) {
                await parser.skipLine()
                break
            }

            guard let pInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }
            if await parser.isCurrentLineHumaneComment(pInfo) {
                await parser.skipLine()
                continue
            }

            // `+ Container Name` — store as unresolved reference.
            if pInfo.firstWord == ModelConstants.Container_Member {
                let rest = pInfo.line.remainingLine(after: ModelConstants.Container_Member)
                    .trimmingCharacters(in: .whitespaces)
                if rest.isNotEmpty {
                    await item.appendUnresolvedRef(rest)
                }
                await parser.skipLine()
                continue
            }

            // Virtual group — `+--- Group Name … +---`.
            if await VirtualGroupParser.canParse(parser: parser) {
                if let group = try await VirtualGroupParser.parse(parser: parser, with: ctx) {
                    await item.appendGroup(group)
                }
                continue
            }

            // Infra node — setext header with `++++` underline.
            if await InfraNodeParser.canParse(parser: parser) {
                if let node = await InfraNodeParser.parse(parser: parser) {
                    await item.appendInfraNode(node)
                } else {
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: .w620,
                        "Infra node header '\(pInfo.line.trim())' could not be parsed — name must start with a letter. Expected: 'Name [type] #tags -- description' followed by a '++++' underline.",
                        pInfo: pInfo
                    )
                    await parser.skipLine()
                }
                continue
            }

            // Unrecognised line inside system body — skip silently.
            await parser.skipLine()
        }

        return item
    }
}
