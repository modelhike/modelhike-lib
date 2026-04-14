//
//  DtoObjectParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum DtoObjectParser {
    // Dto Object starting should be of the format:
    //
    // class name (attributes)
    // /======/
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        let nextLine = await lineParser.nextLine()
        if nextLine.has(prefix: "/", filler: ModelConstants.NameUnderlineChar, suffix: "/") {
            return true
        }
        
        return false
    }
    
    public static func parse(parser: LineParser, with pInfo: ParsedInfo, pending: ParserUtil.PendingMetadata? = nil) async throws -> DtoObject? {
        var line = await parser.currentLine()
        let inlineDesc = ParserUtil.extractInlineDescription(from: &line)
        
        guard let match = line.wholeMatch(of: ModelRegEx.className_Capturing)                                                                                  else { return nil }
        
        let (_, className, attributeString, technicalString, tagString) = match.output
        
        try await pInfo.ctx.events.onParse(objectName: className, with: pInfo)

        let item = DtoObject(name: className.trim(), sourceLocation: SourceLocation(from: pInfo))
        await ParserUtil.appendDescription(pending?.description, to: item)
        await ParserUtil.appendDescription(inlineDesc, to: item)

        //check if has attributes
        if let attributeString = attributeString {
            await ParserUtil.populateAttributes(for: item, from: attributeString)
        }

        if let technicalString = technicalString {
            await ParserUtil.populateTechnicalImplications(for: item, from: technicalString)
        }
        
        //check if has tags
        if let tagString = tagString {
            await ParserUtil.populateTags(for: item, from: tagString)
        }
        
        await parser.skipLine(by: 2)//skip class name and underline
        
        var pendingMetadataBlock = ParserUtil.PendingMetadataBlock()

        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() { await parser.skipLine(); continue }

            if await ParserUtil.consumePendingMetadataBlockLines(from: parser, into: &pendingMetadataBlock) {
                continue
            }

            // Method check before humane-comment: signatures look like plain identifiers
            if await MethodObject.canParse(parser: parser) {
                guard let methodPInfo = await parser.currentParsedInfo(level: 0) else {
                    await parser.skipLine(); continue
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

            guard let pInfo = await parser.currentParsedInfo(level: 0) else { await parser.skipLine(); continue }
            if await parser.isCurrentLineHumaneComment(pInfo) { await parser.skipLine(); continue }

            let trimmed = await parser.currentLine()
            if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                await ParserUtil.appendConsumedDescriptionLines(from: parser, toLastRecognizedMember: await item.members.last, orOwner: item)
                continue
            }

            if DerivedProperty.canParse(firstWord: pInfo.firstWord) {
                if let prop = try await DerivedProperty.parse(pInfo: pInfo) {
                    await item.append(prop)
                    continue
                } else {
                    let msg = pInfo.line
                    throw Model_ParsingError.invalidDerivedProperty(msg, pInfo)
                }
            }
            
            if try await pInfo.tryParseAnnotations(with: item) {
                continue
            }
            
            if try await pInfo.tryParseAttachedSections(with: item) {
                continue
            }
            
            //nothing can be recognised by this
            break
        }
        
        return item
    }

}
