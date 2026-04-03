//
//  DomainObjectParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public enum DomainObjectParser {
    // Domain Object starting should be of the format:
    //
    // class name (attributes)
    // ===
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        if let nextFirstWord = await lineParser.nextLine().firstWord() {
            if nextFirstWord.hasOnly(ModelConstants.NameUnderlineChar) {
                return true
            }
        }

        return false
    }

    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> DomainObject? {
        var headerLine = await parser.currentLine()
        let inlineClassDesc = ParserUtil.extractInlineDescription(from: &headerLine)
        guard let match = headerLine.wholeMatch(of: ModelRegEx.className_Capturing) else { return nil }

        let (_, className, attributeString, tagString) = match.output

        try await pInfo.ctx.events.onParse(objectName: className, with: pInfo)

        let item = DomainObject(name: className.trim())
        await ParserUtil.appendDescription(pending?.description, to: item)
        await ParserUtil.appendDescription(inlineClassDesc, to: item)

        //check if has attributes
        if let attributeString = attributeString {
            await ParserUtil.populateAttributes(for: item, from: attributeString)
        }

        //check if has tags
        if let tagString = tagString {
            await ParserUtil.populateTags(for: item, from: tagString)
        }

        await parser.skipLine(by: 2)  //skip class name and underline

        var pendingMetadataBlock = ParserUtil.PendingMetadataBlock()

        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() {
                await parser.skipLine()
                continue
            }

            if await ParserUtil.consumePendingMetadataBlockLines(from: parser, into: &pendingMetadataBlock) {
                continue
            }

            let trimmed = await parser.currentLine()
            if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                await ParserUtil.appendConsumedDescriptionLines(from: parser, toLastRecognizedMember: await item.members.last, orOwner: item)
                continue
            }

            // Method check before humane-comment: signatures look like plain identifiers
            if await MethodObject.canParse(parser: parser) {
                guard let methodPInfo = await parser.currentParsedInfo(level: 0) else {
                    await parser.skipLine()
                    continue
                }
                let passPending = pendingMetadataBlock.isEmpty ? nil : pendingMetadataBlock
                pendingMetadataBlock.clear()
                if let method = try await MethodObject.parse(pInfo: methodPInfo, pendingMetadataBlock: passPending) {
                    await ParserUtil.appendConsumedDescriptionLines(from: parser, to: method)
                    await item.append(method)
                    continue
                } else {
                    throw Model_ParsingError.invalidMethodLine(methodPInfo)
                }
            }

            guard let bodyInfo = await parser.currentParsedInfo(level: 0) else {
                await parser.skipLine()
                continue
            }
            if await parser.isCurrentLineHumaneComment(bodyInfo) {
                await parser.skipLine()
                continue
            }  //humane comment

            if bodyInfo.firstWord == ModelConstants.Member_Calculated, ParserUtil.isNamedConstraintEqualsLine(line: bodyInfo.line, firstWord: bodyInfo.firstWord) {
                if let constraint = try await ParserUtil.parseNamedConstraint(from: bodyInfo, parser: parser) {
                    await item.namedConstraints.add(constraint)
                    continue
                }
            }

            if Property.canParse(firstWord: bodyInfo.firstWord) {
                if let prop = try await Property.parse(pInfo: bodyInfo) {
                    await ParserUtil.appendConsumedDescriptionLines(from: parser, to: prop)
                    await item.append(prop)
                    continue
                } else {
                    throw Model_ParsingError.invalidPropertyLine(bodyInfo)
                }
            }

            if try await bodyInfo.tryParseAnnotations(with: item) {
                continue
            }

            if try await bodyInfo.tryParseAttachedSections(with: item) {
                continue
            }

            //nothing can be recognised by this
            break
        }

        return item
    }

}
