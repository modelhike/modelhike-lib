//
//  HierarchyObject.swift
//  ModelHike
//

import Foundation

public enum HierarchyDirection: String, Sendable {
    case up
    case down
    case none
}

public struct HierarchyDirective: Sendable {
    public let name: String
    public let value: String
    public let depth: Int
    public let pInfo: ParsedInfo
}

public struct HierarchyOperation: Sendable {
    public let name: String
    public var descriptionLines: [String]
    public var directives: [HierarchyDirective]
    public let pInfo: ParsedInfo

    public var direction: String? { directiveValue("direction") }
    public var includeSelf: String? { directiveValue("include-self") }
    public var returns: String? { directiveValue("returns") }
    public var aggregate: String? { directiveValue("aggregate") }
    public var multiply: String? { directiveValue("multiply") }
    public var filter: String? { directiveValue("filter") }
    public var orderBy: String? { directiveValue("order-by") }
    public var projectedAs: String? { directiveValue("as") }
    public var format: String? { directiveValue("format") }
    public var groupBy: String? { directiveValue("group-by") }
    public var action: String? { directiveValue("action") }
    public var validate: String? { directiveValue("validate") }

    private func directiveValue(_ name: String) -> String? {
        directives.last { $0.name == name }?.value
    }
}

public actor HierarchyObject: Artifact {
    public let attribs = Attributes()
    public let tags = Tags()
    public let annotations = Annotations()

    public let givenname: String
    public let name: String
    public let dataType: ArtifactKind = .hierarchy
    public let ownerName: String
    public let sectionName: String
    public private(set) var operations: [HierarchyOperation] = []

    public init(owner: CodeObject, sectionName: String) async {
        self.ownerName = await owner.name
        self.sectionName = sectionName
        self.givenname = "\(await owner.givenname) \(sectionName)"
        self.name = "\(await owner.name)\(sectionName.normalizeForVariableName())"
    }

    public func append(operation: HierarchyOperation) {
        operations.append(operation)
    }

    public func appendDirectiveToLastOperation(_ directive: HierarchyDirective) {
        guard operations.isNotEmpty else { return }
        operations[operations.count - 1].directives.append(directive)
    }

    public func appendDescriptionToLastOperation(_ description: String) {
        guard operations.isNotEmpty else { return }
        operations[operations.count - 1].descriptionLines.append(description)
    }

    public var debugDescription: String {
        get async {
            "\(name) : hierarchy operations=\(operations.count)"
        }
    }
}
