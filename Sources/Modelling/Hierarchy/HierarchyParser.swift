//
//  HierarchyParser.swift
//  ModelHike
//

import Foundation

public enum HierarchyParser {
    public static func parseAttachedLine(for obj: CodeObject, section: AttachedSection, with pInfo: ParsedInfo) async throws {
        let scoped = ExtendedDSLParserSupport.scopeDepthAndText(pInfo.line)
        await section.append(bodyLine: DSLBodyLine(text: scoped.text, depth: scoped.depth, pInfo: pInfo))

        let hierarchy = await hierarchyObject(for: obj, section: section)
        let text = scoped.text
        guard text.isNotEmpty else {
            await pInfo.parser.skipLine()
            return
        }

        if text.hasPrefix(ModelConstants.Member_Description), !text.hasOnly("-") {
            await hierarchy.appendDescriptionToLastOperation(text.remainingLine(after: ModelConstants.Member_Description).trim())
            await pInfo.parser.skipLine()
            return
        }

        if scoped.depth == 0 {
            guard text.hasSuffix(":") else { throw Model_ParsingError.invalidHierarchyLine(pInfo) }
            let operationName = String(text.dropLast()).trim()
            guard operationName.isNotEmpty else { throw Model_ParsingError.invalidHierarchyLine(pInfo) }
            await hierarchy.append(operation: HierarchyOperation(name: operationName, descriptionLines: [], directives: [], pInfo: pInfo))
            await pInfo.parser.skipLine()
            return
        }

        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { throw Model_ParsingError.invalidHierarchyLine(pInfo) }
        let name = String(parts[0]).trim()
        let value = String(parts[1]).trim()
        guard Self.directiveNames.contains(name), value.isNotEmpty else { throw Model_ParsingError.invalidHierarchyLine(pInfo) }
        await hierarchy.appendDirectiveToLastOperation(HierarchyDirective(name: name, value: value, depth: scoped.depth, pInfo: pInfo))
        await pInfo.parser.skipLine()
    }

    private static func hierarchyObject(for obj: CodeObject, section: AttachedSection) async -> HierarchyObject {
        for attached in await obj.attached {
            if let hierarchy = attached as? HierarchyObject {
                return hierarchy
            }
        }
        let hierarchy = await HierarchyObject(owner: obj, sectionName: section.givenname)
        await obj.appendAttached(hierarchy)
        return hierarchy
    }

    private static let directiveNames: Set<String> = [
        "action",
        "aggregate",
        "as",
        "direction",
        "filter",
        "format",
        "group-by",
        "include-self",
        "max-depth",
        "multiply",
        "order-by",
        "returns",
        "validate"
    ]
}
