//
//  UIViewParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum UIViewParser {
    // UI View starting should be of the format:
    //
    // ui view name (attributes)
    // ~~~~~~~~~~~~~~
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        if let nextFirstWord = await lineParser.nextLine().firstWord() {
            if nextFirstWord.hasOnly(ModelConstants.UIViewUnderlineChar) {
                return true
            }
        }

        return false
    }

    public static func parse(parser: LineParser, with ctx: LoadContext, pending: ParserUtil.PendingMetadata? = nil) async throws -> UIView? {
        var line = await parser.currentLine()
        let inlineDesc = ParserUtil.extractInlineDescription(from: &line)

        guard let match = line.wholeMatch(of: ModelRegEx.uiviewName_Capturing)                                                                                  else { return nil }

        let (_, className, attributeString, tagString) = match.output

        guard let pctx = await parser.currentParsedInfo(level : 0) else { await parser.skipLine(); return nil }

        let item = UIView(name: className.trim(), sourceLocation: SourceLocation(from: pctx))
        await ParserUtil.appendDescription(pending?.description, to: item)
        await ParserUtil.appendDescription(inlineDesc, to: item)

        //check if has attributes
        if let attributeString = attributeString {
            await ParserUtil.populateAttributes(for: item, from: attributeString)
        }

        //check if has tags
        if let tagString = tagString {
            await ParserUtil.populateTags(for: item, from: tagString)
        }

        await parser.skipLine(by: 2)//skip class name and underline

        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() { await parser.skipLine(); continue }

            let trimmed = await parser.currentLine()
            if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                await ParserUtil.appendConsumedDescriptionLines(from: parser, to: item)
                continue
            }

            guard let pctx = await parser.currentParsedInfo(level : 0) else { await parser.skipLine(); continue }

            if try await pctx.tryParseAnnotations(with: item) {
                continue
            }

            if try await pctx.tryParseAttachedSections(with: item) {
                continue
            }

            //nothing can be recognised by this
            break
        }

        return item
    }
}
