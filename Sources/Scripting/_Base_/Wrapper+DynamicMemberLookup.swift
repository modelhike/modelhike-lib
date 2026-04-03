//
//  DynamicMemberLookup.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Template dynamic property access. Conformers may be actors or classes (e.g. ``ForLoop_Wrap``).
public protocol DynamicMemberLookup: Sendable {
    func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable?
    func hasSettable(property propname: String) async -> Bool
    //func setValueOf(property propname: String, value: Any, with pInfo: ParsedInfo) throws -> Bool
}

public extension DynamicMemberLookup {
    func hasSettable(property propname: String) async -> Bool {
        return false
    }
    
    func setValueOf(property propname: String, value: Sendable?, with pInfo: ParsedInfo) async throws {
        throw ParsingError.featureNotImplementedYet(pInfo)
        //RuntimeReflection.setValue(value, forProperty: propname, in: &self)
    }
}

public protocol ObjectWrapper : DynamicMemberLookup, HasAsyncAttributes, SendableDebugStringConvertible, Actor {
    
}
