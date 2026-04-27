//
//  HierarchyObjectWrap.swift
//  ModelHike
//

import Foundation

public actor HierarchyObject_Wrap: ObjectWrapper {
    public let item: HierarchyObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = HierarchyObjectProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(propname, candidates: HierarchyObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .owner: await item.ownerName
        case .section: await item.sectionName
        case .operations: await item.operations
        case .hasOperations: await item.operations.isNotEmpty
        }
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: HierarchyObject) {
        self.item = item
    }
}

private enum HierarchyObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case owner
    case section
    case operations
    case hasOperations = "has-operations"
}
