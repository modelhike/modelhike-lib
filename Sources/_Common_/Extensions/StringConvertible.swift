//
//  StringConvertible.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol StringConvertible: Sendable {
    func toString() -> String
}

extension Int : StringConvertible {
    public func toString() -> String {
        return "\(self)"
    }
    
}

extension String : StringConvertible {
    public func toString() -> String {
        return self
    }
    
}

public typealias StringConvertibleBuilder = ResultBuilder<StringConvertible>
