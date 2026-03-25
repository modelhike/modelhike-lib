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
