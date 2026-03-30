//
//  RuntimeTypeName.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

@inlinable
public func runtimeTypeName(of value: Any) -> String {
    String(describing: Swift.type(of: value))
}

@inlinable
public func runtimeTypeName(of value: Any?) -> String {
    guard let value else { return "nil" }
    return runtimeTypeName(of: value)
}

@inlinable
public func runtimeTypeName(of type: any Any.Type) -> String {
    String(describing: type)
}

@inlinable
public func runtimeType(of value: Sendable?) -> any Any.Type {
    guard let value else { return type(of: Optional<Any>.none as Any) }
    return type(of: value)
}
