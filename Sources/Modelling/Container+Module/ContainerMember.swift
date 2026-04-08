//
//  ContainerMember.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor ContainerModuleMember: Artifact {
    let sourceLocation: SourceLocation
    public var attribs = Attributes()
    public var tags = Tags()
    public var annotations = Annotations()

    public let name: String
    public let givenname: String
    public let dataType: ArtifactKind = .container

    public var comment: String?

    public func hasAttrib(_ name: String) async -> Bool {
        return await attribs.has(name)
    }

    public func hasAttrib(_ name: AttributeNamePresets) async -> Bool {
        return await hasAttrib(name.rawValue)
    }

    static func parse(with pctx: ParsedInfo) async throws -> ContainerModuleMember? {
        let originalLine = pctx.line
        let firstWord = pctx.firstWord

        let line = originalLine.remainingLine(after: firstWord)  //remove first word

        guard let match = line.wholeMatch(of: ModelRegEx.container_Member_Capturing) else {
            return nil
        }

        let (_, moduleName, attributeString, tagString) = match.output
        let modulename = moduleName.trim()

        let module = ContainerModuleMember(
            named: modulename, sourceLocation: SourceLocation(from: pctx))

        //check if has attributes
        if let attributeString = attributeString {
            await ParserUtil.populateAttributes(for: module, from: attributeString)
        }

        //check if has tags
        if let tagString = tagString {
            await ParserUtil.populateTags(for: module, from: tagString)
        }

        await pctx.parser.skipLine()

        return module
    }

    public static func canParse(firstWord: String) -> Bool {
        switch firstWord {
        case ModelConstants.Container_Member: return true
        default:
            return false
        }
    }

    public var debugDescription: String {
        get async {
            var str = """
                \(self.name)
                """
            str += .newLine

            return str
        }
    }

    init(named name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.name = name.normalizeForVariableName()
        self.givenname = name
    }

}
