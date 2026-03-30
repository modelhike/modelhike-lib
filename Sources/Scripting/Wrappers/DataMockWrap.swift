//
//  Mocking_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor Mocking_Wrap : DynamicMemberLookup {
    public private(set) var item: MockData_Generator
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = MockingProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(propname,
                candidates: MockingProperty.allCases.map(\.rawValue), pInfo: pInfo
            )
        }
        return switch key {
        case .objectId: item.randomObjectId_MongoDb()
        }
    }
    
    public init(_ item: MockData_Generator) {
        self.item = item
    }
    
    public init() {
        self.item = MockData_Generator()
    }
}

// MARK: - Mock data property keys (template-facing raw strings)

private enum MockingProperty: String, CaseIterable {
    case objectId = "object-id"
}
